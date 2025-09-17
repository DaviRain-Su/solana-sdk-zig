const std = @import("std");
const base58 = @import("base58");
const bpf = @import("bpf.zig");
const log = @import("log.zig");
const syscalls = @import("syscalls.zig");
const ProgramError = @import("program_error.zig").ProgramError;

const BASE58_ENDEC = base58.Table.BITCOIN;

/// Maximum string length of a base58 encoded pubkey
pub const MAX_BASE58_LEN = base58.encodedMaxSize(PUBKEY_BYTES);
pub const Base58String = std.BoundedArray(u8, MAX_BASE58_LEN);

/// The size of a public key in bytes
pub const PUBKEY_BYTES: usize = 32;

/// Maximum length of derived Pubkey seed
pub const MAX_SEED_LEN: usize = 32;

/// Maximum number of seeds
pub const MAX_SEEDS: usize = 16;

/// The marker used to derive program derived addresses
pub const PDA_MARKER: []const u8 = "ProgramDerivedAddress";

pub const ProgramDerivedAddress = struct {
    address: Pubkey,
    bump_seed: [1]u8,
};

/// A Solana public key - 32 bytes
pub const Pubkey = extern struct {
    bytes: [PUBKEY_BYTES]u8,

    /// Size of a Pubkey
    pub const SIZE: usize = PUBKEY_BYTES;

    pub const max_num_seeds: usize = 16;
    pub const max_seed_length: usize = 32;

    /// Default pubkey - all zeros
    pub const ZEROES = Pubkey{ .bytes = .{0} ** PUBKEY_BYTES };

    pub fn fromPublicKey(public_key: *const std.crypto.sign.Ed25519.PublicKey) Pubkey {
        return Pubkey.fromBytes(public_key);
    }

    /// Create a Pubkey from a byte array
    pub fn fromBytes(bytes: [PUBKEY_BYTES]u8) Pubkey {
        return .{ .bytes = bytes };
    }

    pub fn comptimeFromBase58(comptime encoded: []const u8) Pubkey {
        comptime {
            return Pubkey.fromBytes(base58.bitcoin.comptimeDecode(encoded));
        }
    }

    pub fn comptimeCreateProgramAddress(comptime seeds: anytype, comptime program_id: Pubkey) Pubkey {
        comptime {
            return Pubkey.createProgramAddress(seeds, program_id) catch |err| {
                @compileError("Failed to create program address: " ++ @errorName(err));
            };
        }
    }

    pub fn comptimeFindProgramAddress(comptime seeds: anytype, comptime program_id: Pubkey) ProgramDerivedAddress {
        comptime {
            return Pubkey.findProgramAddress(seeds, program_id) catch |err| {
                @compileError("Failed to find program address: " ++ @errorName(err));
            };
        }
    }

    pub fn initRandom(random: std.Random) Pubkey {
        var bytes: [SIZE]u8 = undefined;
        random.bytes(&bytes);
        return .{ .bytes = bytes };
    }

    /// Create a Pubkey from a byte slice
    pub fn fromSlice(slice: []const u8) !Pubkey {
        if (slice.len != PUBKEY_BYTES) {
            return error.InvalidPubkeyLength;
        }
        var bytes: [PUBKEY_BYTES]u8 = undefined;
        @memcpy(&bytes, slice);
        return .{ .bytes = bytes };
    }

    /// Create a Pubkey from a base58 encoded string
    pub fn fromString(str: []const u8) !Pubkey {
        var bytes: [PUBKEY_BYTES]u8 = undefined;
        const len = try BASE58_ENDEC.decode(&bytes, str);
        if (len != PUBKEY_BYTES) {
            return error.InvalidPubkey;
        }
        return .{ .bytes = bytes };
    }

    /// Convert Pubkey to base58 encoded string
    pub fn toString(self: Pubkey, buf: []u8) ![]const u8 {
        if (buf.len < MAX_BASE58_LEN) {
            return error.BufferTooSmall;
        }
        const len = BASE58_ENDEC.encode(buf, &self.bytes);
        return buf[0..len];
    }

    /// Convert Pubkey to base58 string (allocates)
    pub fn toStringAlloc(self: Pubkey, allocator: std.mem.Allocator) ![]u8 {
        return try BASE58_ENDEC.encodeAlloc(allocator, &self.bytes);
    }

    pub fn base58String(self: Pubkey) Base58String {
        return BASE58_ENDEC.encodeArray(SIZE, self.bytes);
    }

    /// Format for printing (implements std.fmt)
    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const str = self.base58String();
        try writer.writeAll(str.constSlice());
    }

    pub fn jsonStringify(self: Pubkey, write_stream: anytype) !void {
        try write_stream.write(self.base58String().slice());
    }

    pub fn jsonParse(
        _: std.mem.Allocator,
        source: anytype,
        _: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!Pubkey {
        return switch (try source.next()) {
            .string => |str| parseRuntime(str) catch error.UnexpectedToken,
            else => error.UnexpectedToken,
        };
    }

    pub fn jsonParseFromValue(
        _: std.mem.Allocator,
        source: std.json.Value,
        _: std.json.ParseOptions,
    ) std.json.ParseFromValueError!Pubkey {
        return switch (source) {
            .string => |str| parseRuntime(str) catch |err| switch (err) {
                error.InvalidPubkey => error.InvalidCharacter,
                error.InvalidLength => error.LengthMismatch,
            },
            else => error.UnexpectedToken,
        };
    }

    pub fn indexIn(self: Pubkey, pubkeys: []const Pubkey) ?usize {
        return for (pubkeys, 0..) |candidate, index| {
            if (self.equals(&candidate)) break index;
        } else null;
    }

    pub fn order(self: Pubkey, other: Pubkey) std.math.Order {
        return for (self.bytes, other.bytes) |a_byte, b_byte| {
            if (a_byte > b_byte) break .gt;
            if (a_byte < b_byte) break .lt;
        } else .eq;
    }

    /// Check if two pubkeys are equal - optimized version
    pub fn equals(self: *const Pubkey, other: *const Pubkey) bool {
        const xx: @Vector(SIZE, u8) = self.bytes;
        const yy: @Vector(SIZE, u8) = other.bytes;
        return @reduce(.And, xx == yy);
    }

    pub fn isZeroed(self: *const Pubkey) bool {
        return self.equals(&ZEROES);
    }

    pub inline fn parse(comptime str: []const u8) Pubkey {
        comptime {
            return parseRuntime(str) catch @compileError("failed to parse pubkey");
        }
    }

    pub fn parseRuntime(str: []const u8) error{ InvalidLength, InvalidPubkey }!Pubkey {
        if (str.len > MAX_BASE58_LEN) return error.InvalidLength;
        var encoded: std.BoundedArray(u8, MAX_BASE58_LEN) = .{};
        encoded.appendSliceAssumeCapacity(str);

        if (@inComptime()) @setEvalBranchQuota(str.len * str.len * str.len);
        const decoded = BASE58_ENDEC.decodeBounded(MAX_BASE58_LEN, encoded) catch {
            return error.InvalidPubkey;
        };

        if (decoded.len != SIZE) return error.InvalidLength;
        return .{ .bytes = decoded.constSlice()[0..SIZE].* };
    }

    /// Check if pubkey is on the ed25519 curve
    pub fn isOnCurve(self: Pubkey) bool {
        const Y = std.crypto.ecc.Curve25519.Fe.fromBytes(self.bytes);
        const Z = std.crypto.ecc.Curve25519.Fe.one;
        const YY = Y.sq();
        const u = YY.sub(Z);
        const v = YY.mul(std.crypto.ecc.Curve25519.Fe.edwards25519d).add(Z);
        if (sqrtRatioM1(u, v) != 1) {
            return false;
        }
        return true;
    }

    fn sqrtRatioM1(u: std.crypto.ecc.Curve25519.Fe, v: std.crypto.ecc.Curve25519.Fe) u32 {
        const v3 = v.sq().mul(v); // v^3
        const x = v3.sq().mul(u).mul(v).pow2523().mul(v3).mul(u); // uv^3(uv^7)^((q-5)/8)
        const vxx = x.sq().mul(v); // vx^2
        const m_root_check = vxx.sub(u); // vx^2-u
        const p_root_check = vxx.add(u); // vx^2+u
        const has_m_root = m_root_check.isZero();
        const has_p_root = p_root_check.isZero();
        return @intFromBool(has_m_root) | @intFromBool(has_p_root);
    }

    pub fn createProgramAddress(seeds: anytype, program_id: Pubkey) !Pubkey {
        if (seeds.len > Pubkey.max_num_seeds) {
            return error.MaxSeedLengthExceeded;
        }

        comptime var seeds_index = 0;
        inline while (seeds_index < seeds.len) : (seeds_index += 1) {
            if (@as([]const u8, seeds[seeds_index]).len > Pubkey.max_seed_length) {
                return error.MaxSeedLengthExceeded;
            }
        }

        var address: Pubkey = undefined;

        if (bpf.is_bpf_program) {
            const Syscall = struct {
                extern fn sol_create_program_address(
                    seeds_ptr: [*]const []const u8,
                    seeds_len: u64,
                    program_id_ptr: *const Pubkey,
                    address_ptr: *Pubkey,
                ) callconv(.C) u64;
            };

            var seeds_array: [seeds.len][]const u8 = undefined;
            inline for (seeds, 0..) |seed, i| seeds_array[i] = seed;

            const result = Syscall.sol_create_program_address(
                &seeds_array,
                seeds.len,
                &program_id,
                &address,
            );
            if (result != 0) {
                log.print("failed to create program address with seeds {any} and program id {}: error code {}", .{
                    seeds,
                    program_id,
                    result,
                });
                return error.Unexpected;
            }

            return address;
        }

        @setEvalBranchQuota(100_000_000);

        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        comptime var i = 0;
        inline while (i < seeds.len) : (i += 1) {
            hasher.update(seeds[i]);
        }
        hasher.update(&program_id.bytes);
        hasher.update("ProgramDerivedAddress");
        hasher.final(&address.bytes);

        if (address.isOnCurve()) {
            return error.InvalidSeeds;
        }

        return address;
    }

    /// Find a valid program address and bump seed
    pub fn findProgramAddress(seeds: anytype, program_id: Pubkey) !ProgramDerivedAddress {
        var pda: ProgramDerivedAddress = undefined;

        if (comptime bpf.is_bpf_program) {
            const Syscall = struct {
                extern fn sol_try_find_program_address(
                    seeds_ptr: [*]const []const u8,
                    seeds_len: u64,
                    program_id_ptr: *const Pubkey,
                    address_ptr: *Pubkey,
                    bump_seed_ptr: *u8,
                ) callconv(.C) u64;
            };

            var seeds_array: [seeds.len][]const u8 = undefined;

            comptime var seeds_index = 0;
            inline while (seeds_index < seeds.len) : (seeds_index += 1) {
                const Seed = @TypeOf(seeds[seeds_index]);
                if (comptime Seed == Pubkey) {
                    seeds_array[seeds_index] = &seeds[seeds_index].bytes;
                } else {
                    seeds_array[seeds_index] = seeds[seeds_index];
                }
            }

            const result = Syscall.sol_try_find_program_address(
                &seeds_array,
                seeds.len,
                &program_id,
                &pda.address,
                &pda.bump_seed[0],
            );
            if (result != 0) {
                log.print("failed to find program address given seeds {any} and program id {}: error code {}", .{
                    seeds,
                    program_id,
                    result,
                });
                return error.Unexpected;
            }

            return pda;
        }

        var seeds_with_bump: [seeds.len + 1][]const u8 = undefined;

        comptime var seeds_index = 0;
        inline while (seeds_index < seeds.len) : (seeds_index += 1) {
            const Seed = @TypeOf(seeds[seeds_index]);
            if (comptime Seed == Pubkey) {
                seeds_with_bump[seeds_index] = &seeds[seeds_index].bytes;
            } else {
                seeds_with_bump[seeds_index] = seeds[seeds_index];
            }
        }

        pda.bump_seed[0] = 255;
        seeds_with_bump[seeds.len] = &pda.bump_seed;

        while (pda.bump_seed[0] >= 0) : (pda.bump_seed[0] -= 1) {
            pda = ProgramDerivedAddress{
                .address = Pubkey.createProgramAddress(&seeds_with_bump, program_id) catch {
                    if (pda.bump_seed[0] == 0) {
                        return error.NoViableBumpSeed;
                    }
                    continue;
                },
                .bump_seed = pda.bump_seed,
            };

            break;
        }

        return pda;
    }
};

const Error = error{ InvalidBytesLength, InvalidEncodedLength, InvalidEncodedValue };

/// System program ID
pub const SYSTEM_PROGRAM_ID = Pubkey{
    .bytes = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
};

/// Token program ID
pub const TOKEN_PROGRAM_ID = Pubkey{
    .bytes = .{
        6,  221, 246, 225, 215, 101, 161, 147, 217, 203, 225, 70,  206, 235, 121, 172,
        28, 180, 133, 237, 95,  91,  55,  145, 58,  140, 245, 133, 126, 255, 0,   169,
    },
};

/// Associated token program ID
pub const ASSOCIATED_TOKEN_PROGRAM_ID = Pubkey{
    .bytes = .{
        140, 151, 37,  143, 78,  36, 137, 241, 187, 61,  16,  41,  20,  142, 13, 131, 11,
        90,  19,  153, 218, 255, 16, 132, 4,   142, 123, 216, 219, 233, 248, 89,
    },
};

/// Sysvar IDs
pub const SYSVAR_CLOCK_ID = Pubkey{
    .bytes = .{
        6,   167, 213, 23,  24,  199, 116, 201, 40,  86, 99, 152, 105, 29, 94, 182,
        139, 94,  184, 163, 155, 75,  109, 92,  115, 85, 91, 33,  0,   0,  0,  0,
    },
};

pub const SYSVAR_RENT_ID = Pubkey{
    .bytes = .{
        6,   167, 213, 23, 25, 44,  86, 142, 224, 138, 132, 95, 115, 210, 151, 136,
        207, 3,   92,  49, 69, 178, 26, 179, 68,  216, 6,   46, 169, 64,  0,   0,
    },
};

pub const SYSVAR_INSTRUCTIONS_ID = Pubkey{
    .bytes = .{
        6,   167, 213, 23, 25,  47,  10, 175, 198, 242, 101, 227, 251, 119, 204, 122,
        218, 130, 197, 41, 208, 190, 59, 19,  110, 45,  0,   85,  32,  0,   0,   0,
    },
};

test "pubkey display" {
    //std.debug.print("key: {}\n", .{TOKEN_PROGRAM_ID});
    //std.debug.print("key: {}\n", .{SYSVAR_CLOCK_ID});
    //std.debug.print("key: {}\n", .{SYSTEM_PROGRAM_ID});
    //std.debug.print("key: {}\n", .{ASSOCIATED_TOKEN_PROGRAM_ID});
    //std.debug.print("key: {}\n", .{SYSVAR_INSTRUCTIONS_ID});
    //std.debug.print("key: {}\n", .{SYSVAR_RENT_ID});
}

test "pubkey equals" {
    const key1 = Pubkey.fromBytes(.{1} ** 32);
    const key2 = Pubkey.fromBytes(.{1} ** 32);
    const key3 = Pubkey.fromBytes(.{2} ** 32);

    try std.testing.expect(key1.equals(&key2));
    try std.testing.expect(!key1.equals(&key3));
}

test "pubkey from slice" {
    const bytes = [_]u8{3} ** 32;
    const key = try Pubkey.fromSlice(&bytes);

    try std.testing.expect(key.bytes[0] == 3);
    try std.testing.expect(key.bytes[31] == 3);
}

test "pubkey is zeroes" {
    const key = Pubkey.ZEROES;

    try std.testing.expect(key.bytes[0] == 0);
    try std.testing.expect(key.bytes[31] == 0);
}

test "pubkey fromBytes and equals" {
    const bytes1 = [_]u8{42} ** 32;
    const bytes2 = [_]u8{42} ** 32;
    const bytes3 = [_]u8{24} ** 32;

    const key1 = Pubkey.fromBytes(bytes1);
    const key2 = Pubkey.fromBytes(bytes2);
    const key3 = Pubkey.fromBytes(bytes3);

    try std.testing.expect(key1.equals(&key2));
    try std.testing.expect(!key1.equals(&key3));
}

test "pubkey isZeroed" {
    const zero_key = Pubkey.ZEROES;
    const non_zero_key = Pubkey.fromBytes([_]u8{1} ** 32);

    try std.testing.expect(zero_key.isZeroed());
    try std.testing.expect(!non_zero_key.isZeroed());
}

test "pubkey order comparison" {
    const key1 = Pubkey.fromBytes([_]u8{1} ** 32);
    const key2 = Pubkey.fromBytes([_]u8{2} ** 32);
    const key3 = Pubkey.fromBytes([_]u8{1} ** 32);

    try std.testing.expectEqual(std.math.Order.lt, key1.order(key2));
    try std.testing.expectEqual(std.math.Order.gt, key2.order(key1));
    try std.testing.expectEqual(std.math.Order.eq, key1.order(key3));
}

test "pubkey base58 string conversion" {
    const key = Pubkey.fromBytes([_]u8{1} ** 32);

    // Test toString with buffer
    var buf: [MAX_BASE58_LEN]u8 = undefined;
    const str = try key.toString(&buf);
    try std.testing.expect(str.len > 0);
    try std.testing.expect(str.len <= MAX_BASE58_LEN);

    // Test parsing back from string
    const parsed = try Pubkey.fromString(str);
    try std.testing.expect(parsed.equals(&key));
}

test "pubkey toStringAlloc" {
    const allocator = std.testing.allocator;
    const key = Pubkey.fromBytes([_]u8{255} ** 32);

    const str = try key.toStringAlloc(allocator);
    defer allocator.free(str);

    try std.testing.expect(str.len > 0);
    try std.testing.expect(str.len <= MAX_BASE58_LEN);

    // Verify it can be parsed back
    const parsed = try Pubkey.fromString(str);
    try std.testing.expect(parsed.equals(&key));
}

test "pubkey fromString with invalid input" {
    // Test with invalid base58 characters
    const result1 = Pubkey.fromString("invalid!@#$");
    try std.testing.expectError(error.InvalidCharacter, result1);

    // Test with wrong length - this will actually decode to some bytes, just not 32
    // The base58 decode doesn't fail, but the length check does
    // Skip this specific test for now as it needs more investigation
    const result2 = Pubkey.fromString("111111111111111"); // Too short
    try std.testing.expectError(error.InvalidPubkey, result2);
}

test "pubkey indexIn" {
    const key1 = Pubkey.fromBytes([_]u8{1} ** 32);
    const key2 = Pubkey.fromBytes([_]u8{2} ** 32);
    const key3 = Pubkey.fromBytes([_]u8{3} ** 32);
    const key4 = Pubkey.fromBytes([_]u8{4} ** 32);

    const pubkeys = [_]Pubkey{ key1, key2, key3 };

    try std.testing.expectEqual(@as(?usize, 0), key1.indexIn(&pubkeys));
    try std.testing.expectEqual(@as(?usize, 1), key2.indexIn(&pubkeys));
    try std.testing.expectEqual(@as(?usize, 2), key3.indexIn(&pubkeys));
    try std.testing.expectEqual(@as(?usize, null), key4.indexIn(&pubkeys));
}

test "pubkey system program constants" {
    // Test that system program IDs are valid
    try std.testing.expect(SYSTEM_PROGRAM_ID.bytes[0] == 0);
    try std.testing.expect(SYSTEM_PROGRAM_ID.isZeroed());

    // Token program should not be zero
    try std.testing.expect(!TOKEN_PROGRAM_ID.isZeroed());
    try std.testing.expect(!ASSOCIATED_TOKEN_PROGRAM_ID.isZeroed());
}

test "pubkey format display" {
    const key = Pubkey.fromBytes([_]u8{1} ** 32);

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try stream.writer().print("{}", .{key});

    const output = stream.getWritten();
    try std.testing.expect(output.len > 0);
    try std.testing.expect(output.len <= MAX_BASE58_LEN);
}
