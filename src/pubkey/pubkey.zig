const std = @import("std");
const base58 = @import("base58");
const bpf = @import("../bpf.zig");
const log = @import("../log.zig");
const syscalls = @import("../syscalls.zig");
const ProgramError = @import("../program_error.zig").ProgramError;

// Re-export submodules
pub const extensions = @import("extensions.zig");
pub const hasher = @import("hasher.zig");
pub const errors = @import("error.zig");

// Re-export common system program IDs from extensions
pub const SYSTEM_PROGRAM_ID = extensions.SYSTEM_PROGRAM_ID;
pub const TOKEN_PROGRAM_ID = extensions.TOKEN_PROGRAM_ID;
pub const ASSOCIATED_TOKEN_PROGRAM_ID = extensions.ASSOCIATED_TOKEN_PROGRAM_ID;
pub const RENT_SYSVAR_ID = extensions.RENT_SYSVAR_ID;
pub const CLOCK_SYSVAR_ID = extensions.CLOCK_SYSVAR_ID;
pub const STAKE_PROGRAM_ID = extensions.STAKE_PROGRAM_ID;
pub const VOTE_PROGRAM_ID = extensions.VOTE_PROGRAM_ID;
pub const BPF_LOADER_PROGRAM_ID = extensions.BPF_LOADER_PROGRAM_ID;
pub const BPF_UPGRADEABLE_LOADER_PROGRAM_ID = extensions.BPF_UPGRADEABLE_LOADER_PROGRAM_ID;

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
        return Pubkey.fromBytes(public_key.bytes);
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

    /// Create a Pubkey with a seed (matching Rust's create_with_seed)
    pub fn createWithSeed(
        self: Pubkey,
        seed: []const u8,
        owner: *const Pubkey,
    ) !Pubkey {
        // Check seed length
        if (seed.len > MAX_SEED_LEN) {
            return error.MaxSeedLengthExceeded;
        }

        // Check for illegal owner (PDA marker check)
        const owner_bytes = owner.bytes;
        if (owner_bytes.len >= PDA_MARKER.len) {
            const slice = owner_bytes[owner_bytes.len - PDA_MARKER.len ..];
            if (std.mem.eql(u8, slice, PDA_MARKER)) {
                return error.IllegalOwner;
            }
        }

        // Hash the components using SHA256
        var h = std.crypto.hash.sha2.Sha256.init(.{});
        h.update(&self.bytes);
        h.update(seed);
        h.update(&owner.bytes);
        var result: [32]u8 = undefined;
        h.final(&result);
        return Pubkey.fromBytes(result);
    }

    /// Create a unique Pubkey for testing (matching Rust's new_unique)
    var unique_counter = std.atomic.Value(u32).init(1);

    pub fn newUnique() Pubkey {
        const counter = unique_counter.fetchAdd(1, .monotonic);
        var bytes: [32]u8 = undefined;

        // Use big-endian to ensure ordering (like Rust version)
        std.mem.writeInt(u32, bytes[0..4], counter, .big);

        // Fill rest with pseudo-random data based on counter
        var prng = std.Random.DefaultPrng.init(counter);
        const random = prng.random();
        random.bytes(bytes[4..]);

        return Pubkey.fromBytes(bytes);
    }

    /// Get bytes array (matching Rust's to_bytes)
    pub fn toBytes(self: Pubkey) [32]u8 {
        return self.bytes;
    }

    /// Get reference to bytes array (matching Rust's as_array)
    pub fn asArray(self: *const Pubkey) *const [32]u8 {
        return &self.bytes;
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
        const seeds_info = @typeInfo(@TypeOf(seeds));

        // Handle both tuples (comptime known) and slices (runtime)
        const is_tuple = seeds_info == .@"struct" and seeds_info.@"struct".is_tuple;

        if (is_tuple) {
            // Comptime path for tuples
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

            var h = std.crypto.hash.sha2.Sha256.init(.{});
            comptime var i = 0;
            inline while (i < seeds.len) : (i += 1) {
                h.update(seeds[i]);
            }
            h.update(&program_id.bytes);
            h.update("ProgramDerivedAddress");
            h.final(&address.bytes);

            if (address.isOnCurve()) {
                return error.InvalidSeeds;
            }

            return address;
        } else {
            // Runtime path for slices
            if (seeds.len > Pubkey.max_num_seeds) {
                return error.MaxSeedLengthExceeded;
            }

            for (seeds) |seed| {
                if (seed.len > Pubkey.max_seed_length) {
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

                const result = Syscall.sol_create_program_address(
                    seeds.ptr,
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

            var h = std.crypto.hash.sha2.Sha256.init(.{});
            for (seeds) |seed| {
                h.update(seed);
            }
            h.update(&program_id.bytes);
            h.update("ProgramDerivedAddress");
            h.final(&address.bytes);

            if (address.isOnCurve()) {
                return error.InvalidSeeds;
            }

            return address;
        }
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

test "createWithSeed" {
    const testing = std.testing;

    const base = Pubkey.ZEROES;
    const owner = SYSTEM_PROGRAM_ID;

    // Test valid seed
    const addr1 = try base.createWithSeed("test-seed", &owner);
    _ = addr1;

    // Test empty seed
    const addr2 = try base.createWithSeed("", &owner);
    _ = addr2;

    // Test max length seed
    const max_seed = "a" ** 32;
    const addr3 = try base.createWithSeed(max_seed, &owner);
    _ = addr3;

    // Test seed too long
    const long_seed = "a" ** 33;
    const result = base.createWithSeed(long_seed, &owner);
    try testing.expectError(error.MaxSeedLengthExceeded, result);
}

test "newUnique generates different addresses" {
    const testing = std.testing;

    const addr1 = Pubkey.newUnique();
    const addr2 = Pubkey.newUnique();
    const addr3 = Pubkey.newUnique();

    try testing.expect(!addr1.equals(&addr2));
    try testing.expect(!addr2.equals(&addr3));
    try testing.expect(!addr1.equals(&addr3));
}

test "createProgramAddress" {
    const testing = std.testing;
    const program_id = BPF_UPGRADEABLE_LOADER_PROGRAM_ID;

    // Test with valid seeds
    const seeds = .{ "vault", &[_]u8{1} };
    const pda = try Pubkey.createProgramAddress(seeds, program_id);

    // Test that PDA is off curve
    try testing.expect(!pda.isOnCurve());

    // Test with max seeds
    const max_seeds = .{ &[_]u8{1}, &[_]u8{2}, &[_]u8{3}, &[_]u8{4}, &[_]u8{5}, &[_]u8{6}, &[_]u8{7}, &[_]u8{8}, &[_]u8{9}, &[_]u8{10}, &[_]u8{11}, &[_]u8{12}, &[_]u8{13}, &[_]u8{14}, &[_]u8{15}, &[_]u8{16} };
    const pda2 = try Pubkey.createProgramAddress(max_seeds, program_id);
    _ = pda2;
}

test "findProgramAddress" {
    const testing = std.testing;
    const program_id = BPF_UPGRADEABLE_LOADER_PROGRAM_ID;

    const seeds = .{ "Lil'", "Bits" };
    const pda_result = try Pubkey.findProgramAddress(seeds, program_id);

    // Verify that the bump seed generates the same address
    const seeds_with_bump = .{ "Lil'", "Bits", &[_]u8{pda_result.bump_seed[0]} };
    const pda_verify = try Pubkey.createProgramAddress(seeds_with_bump, program_id);

    try testing.expect(pda_result.address.equals(&pda_verify));
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
