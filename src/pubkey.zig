const std = @import("std");
const base58 = @import("base58");

/// Maximum string length of a base58 encoded pubkey
pub const MAX_BASE58_LEN = base58.encodedMaxSize(PUBKEY_BYTES);

/// The size of a public key in bytes
pub const PUBKEY_BYTES: usize = 32;

/// A Solana public key - 32 bytes
pub const Pubkey = extern struct {
    bytes: [PUBKEY_BYTES]u8,

    /// Size of a Pubkey
    pub const SIZE: usize = PUBKEY_BYTES;

    /// Default pubkey - all zeros
    pub const default = Pubkey{ .bytes = .{0} ** PUBKEY_BYTES };

    /// Create a Pubkey from a byte array
    pub fn fromBytes(bytes: [PUBKEY_BYTES]u8) Pubkey {
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
        const table = base58.Table.BITCOIN;
        const len = try table.decode(&bytes, str);
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
        const table = base58.Table.BITCOIN;
        const len = table.encode(buf, &self.bytes);
        return buf[0..len];
    }

    /// Convert Pubkey to base58 string (allocates)
    pub fn toStringAlloc(self: Pubkey, allocator: std.mem.Allocator) ![]u8 {
        const table = base58.Table.BITCOIN;
        return try table.encodeAlloc(allocator, &self.bytes);
    }

    /// Format for printing (implements std.fmt)
    pub fn format(
        self: Pubkey,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        var buf: [MAX_BASE58_LEN]u8 = undefined;
        const str = self.toString(&buf) catch return writer.writeAll("InvalidPubkey");
        try writer.writeAll(str);
    }

    /// Check if two pubkeys are equal - optimized version
    pub inline fn equals(self: Pubkey, other: Pubkey) bool {
        // Cast to u64 arrays for faster comparison
        const self_u64 = @as(*const [4]u64, @ptrCast(@alignCast(&self.bytes)));
        const other_u64 = @as(*const [4]u64, @ptrCast(@alignCast(&other.bytes)));

        return self_u64[0] == other_u64[0] and
            self_u64[1] == other_u64[1] and
            self_u64[2] == other_u64[2] and
            self_u64[3] == other_u64[3];
    }

    /// Check if pubkey is on the ed25519 curve
    pub fn isOnCurve(self: Pubkey) bool {
        // TODO: Implement ed25519 curve check if needed
        _ = self;
        return true;
    }

    /// Find a valid program address and bump seed
    pub fn findProgramAddress(
        seeds: []const []const u8,
        program_id: *const Pubkey,
    ) !struct { pubkey: Pubkey, bump: u8 } {
        var bump: u8 = 255;

        while (true) : (bump -= 1) {
            var seeds_with_bump = try std.BoundedArray([]const u8, 17).init(0);
            for (seeds) |seed| {
                try seeds_with_bump.append(seed);
            }

            var bump_seed = [_]u8{bump};
            try seeds_with_bump.append(&bump_seed);

            const maybe_pda = try createProgramAddress(seeds_with_bump.slice(), program_id);
            if (maybe_pda) |pda| {
                return .{ .pubkey = pda, .bump = bump };
            }

            if (bump == 0) break;
        }

        return error.NoProgramAddressFound;
    }

    /// Create a program address (PDA) from seeds and program_id
    pub fn createProgramAddress(
        seeds: []const []const u8,
        program_id: *const Pubkey,
    ) !?Pubkey {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});

        // Hash all seeds
        for (seeds) |seed| {
            if (seed.len > 32) return error.SeedTooLong;
            hasher.update(seed);
        }

        // Add program id
        hasher.update(&program_id.bytes);

        // Add PDA marker
        hasher.update("ProgramDerivedAddress");

        var hash: [32]u8 = undefined;
        hasher.final(&hash);

        const pda = Pubkey{ .bytes = hash };

        // Check if the result is on the ed25519 curve
        // If it is, it's not a valid PDA
        if (pda.isOnCurve()) {
            return null;
        }

        return pda;
    }
};

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
    //std.debug.print("key1: {}\nkey2: {}\nkey3: {}\n", .{ key1, key2, key3 });
    try std.testing.expect(key1.equals(key2));
    try std.testing.expect(!key1.equals(key3));
}

test "pubkey from slice" {
    const bytes = [_]u8{3} ** 32;
    const key = try Pubkey.fromSlice(&bytes);
    //std.debug.print("key: {}\n", .{key});
    try std.testing.expect(key.bytes[0] == 3);
    try std.testing.expect(key.bytes[31] == 3);
}

test "pubkey default" {
    const key = Pubkey.default;
    //std.debug.print("key: {}\n", .{key});
    try std.testing.expect(key.bytes[0] == 0);
    try std.testing.expect(key.bytes[31] == 0);
}
