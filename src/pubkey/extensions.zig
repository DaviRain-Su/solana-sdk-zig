/// Extended functionality for Pubkey
/// This file implements additional features from Rust's Address/Pubkey
const std = @import("std");
const Pubkey = @import("pubkey.zig").Pubkey;
const syscalls = @import("../syscalls.zig");
const bpf = @import("../bpf.zig");

/// Error types matching Rust's AddressError
pub const AddressError = error{
    MaxSeedLengthExceeded,
    InvalidSeeds,
    IllegalOwner,
};

/// PDA marker constant
pub const PDA_MARKER: []const u8 = "ProgramDerivedAddress";

/// Create a Pubkey with a seed
/// This matches Rust's create_with_seed function
pub fn createWithSeed(
    base: *const Pubkey,
    seed: []const u8,
    owner: *const Pubkey,
) AddressError!Pubkey {
    // Check seed length
    if (seed.len > Pubkey.max_seed_length) {
        return AddressError.MaxSeedLengthExceeded;
    }

    // Check for illegal owner (PDA marker check)
    const owner_bytes = owner.bytes;
    if (owner_bytes.len >= PDA_MARKER.len) {
        const slice = owner_bytes[owner_bytes.len - PDA_MARKER.len..];
        if (std.mem.eql(u8, slice, PDA_MARKER)) {
            return AddressError.IllegalOwner;
        }
    }

    // Use SHA256 to hash the components
    if (bpf.is_bpf_program) {
        // Use syscall on BPF
        var result: [32]u8 = undefined;
        syscalls.sha256(base.bytes ++ seed ++ owner.bytes, &result);
        return Pubkey.fromBytes(result);
    } else {
        // Use standard library implementation for testing
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(&base.bytes);
        hasher.update(seed);
        hasher.update(&owner.bytes);
        var result: [32]u8 = undefined;
        hasher.final(&result);
        return Pubkey.fromBytes(result);
    }
}

/// Create a unique Pubkey for testing
/// This is useful for generating test addresses
var unique_counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(1);

pub fn newUnique() Pubkey {
    const counter = unique_counter.fetchAdd(1, .monotonic);
    var bytes: [32]u8 = undefined;

    // Use big-endian to ensure ordering
    std.mem.writeInt(u32, bytes[0..4], counter, .big);

    // Fill rest with pseudo-random data based on counter
    var prng = std.Random.DefaultPrng.init(counter);
    const random = prng.random();
    random.bytes(bytes[4..]);

    return Pubkey.fromBytes(bytes);
}

/// Additional helper methods for Pubkey
pub fn toBytes(self: Pubkey) [32]u8 {
    return self.bytes;
}

pub fn asArray(self: *const Pubkey) *const [32]u8 {
    return &self.bytes;
}

/// Try to find a program address and bump seed
/// Returns null if no valid address is found within 256 iterations
pub fn tryFindProgramAddress(
    seeds: []const []const u8,
    program_id: *const Pubkey,
) ?struct { pubkey: Pubkey, bump: u8 } {
    var bump: u8 = 255;
    while (true) {
        const bump_seed = [_]u8{bump};

        // Create seeds array with bump
        var seeds_with_bump: [16][]const u8 = undefined;
        if (seeds.len >= seeds_with_bump.len) return null;

        for (seeds, 0..) |seed, i| {
            seeds_with_bump[i] = seed;
        }
        seeds_with_bump[seeds.len] = &bump_seed;

        const seeds_final = seeds_with_bump[0..seeds.len + 1];

        // Try to create program address
        const result = Pubkey.createProgramAddress(seeds_final, program_id.*);
        if (result) |pubkey| {
            return .{ .pubkey = pubkey, .bump = bump };
        } else |_| {
            // Continue searching
        }

        if (bump == 0) break;
        bump -= 1;
    }

    return null;
}

/// Check if a pubkey is on the ed25519 curve
/// This is an important validation for PDAs which must be off-curve
pub fn isOnCurve(pubkey: *const Pubkey) bool {
    // Delegate to the Pubkey's isOnCurve method
    return pubkey.isOnCurve();
}

/// Log a pubkey to the console (for debugging in BPF programs)
pub fn log(pubkey: *const Pubkey) void {
    if (bpf.is_bpf_program) {
        // Use syscall to log the pubkey
        syscalls.sol_log_pubkey(&pubkey.bytes);
    } else {
        // For testing, don't print to avoid test output issues
        // Just validate that the pubkey can be converted to string
        var buf: [64]u8 = undefined;
        _ = pubkey.toString(&buf) catch {};
    }
}

/// Common System Program IDs
pub const SYSTEM_PROGRAM_ID = Pubkey.parse("11111111111111111111111111111111");
pub const TOKEN_PROGRAM_ID = Pubkey.parse("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
pub const ASSOCIATED_TOKEN_PROGRAM_ID = Pubkey.parse("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL");
pub const RENT_SYSVAR_ID = Pubkey.parse("SysvarRent111111111111111111111111111111111");
pub const CLOCK_SYSVAR_ID = Pubkey.parse("SysvarC1ock11111111111111111111111111111111");
pub const STAKE_PROGRAM_ID = Pubkey.parse("Stake11111111111111111111111111111111111111");
pub const VOTE_PROGRAM_ID = Pubkey.parse("Vote111111111111111111111111111111111111111");
pub const BPF_LOADER_PROGRAM_ID = Pubkey.parse("BPFLoader2111111111111111111111111111111111");
pub const BPF_UPGRADEABLE_LOADER_PROGRAM_ID = Pubkey.parse("BPFLoaderUpgradeab1e11111111111111111111111");

/// More system program IDs
pub const STAKE_CONFIG_PROGRAM_ID = Pubkey.parse("StakeConfig11111111111111111111111111111111");
pub const SYSTEM_INSTRUCTION_PROGRAM_ID = SYSTEM_PROGRAM_ID;
pub const FEATURE_PROGRAM_ID = Pubkey.parse("Feature111111111111111111111111111111111111");
pub const CONFIG_PROGRAM_ID = Pubkey.parse("Config1111111111111111111111111111111111111");
pub const SYSVAR_PROGRAM_ID = Pubkey.parse("Sysvar1111111111111111111111111111111111111");

test "createWithSeed basic" {
    const testing = std.testing;

    const base = Pubkey.ZEROES;
    const owner = SYSTEM_PROGRAM_ID;

    // Test valid seed
    const addr1 = try createWithSeed(&base, "test-seed", &owner);
    _ = addr1;

    // Test empty seed
    const addr2 = try createWithSeed(&base, "", &owner);
    _ = addr2;

    // Test max length seed
    const max_seed = "a" ** 32;
    const addr3 = try createWithSeed(&base, max_seed, &owner);
    _ = addr3;

    // Test seed too long
    const long_seed = "a" ** 33;
    const result = createWithSeed(&base, long_seed, &owner);
    try testing.expectError(AddressError.MaxSeedLengthExceeded, result);
}

test "newUnique generates different addresses" {
    const testing = std.testing;

    const addr1 = newUnique();
    const addr2 = newUnique();
    const addr3 = newUnique();

    try testing.expect(!addr1.equals(&addr2));
    try testing.expect(!addr2.equals(&addr3));
    try testing.expect(!addr1.equals(&addr3));

    // Check that counter is incrementing
    const bytes1 = addr1.bytes;
    const bytes2 = addr2.bytes;
    const counter1 = std.mem.readInt(u32, bytes1[0..4], .big);
    const counter2 = std.mem.readInt(u32, bytes2[0..4], .big);
    try testing.expect(counter2 > counter1);
}

test "system program IDs are valid" {
    const testing = std.testing;

    // Just verify they compile and are valid pubkeys
    try testing.expectEqual(@as(usize, 32), SYSTEM_PROGRAM_ID.bytes.len);
    try testing.expectEqual(@as(usize, 32), TOKEN_PROGRAM_ID.bytes.len);
    try testing.expectEqual(@as(usize, 32), ASSOCIATED_TOKEN_PROGRAM_ID.bytes.len);
}

test "tryFindProgramAddress" {
    const testing = std.testing;

    const program_id = Pubkey.newUnique();
    const seeds = [_][]const u8{"test"};

    // Should find a valid PDA
    const result = tryFindProgramAddress(&seeds, &program_id);
    try testing.expect(result != null);

    if (result) |pda| {
        // Verify the found PDA is valid
        const seeds_with_bump = [_][]const u8{ "test", &[_]u8{pda.bump} };
        const recreated = try Pubkey.createProgramAddress(&seeds_with_bump, program_id);
        try testing.expect(pda.pubkey.equals(&recreated));

        // PDA should be off-curve
        try testing.expect(!isOnCurve(&pda.pubkey));
    }
}

test "isOnCurve" {
    const testing = std.testing;

    // Regular pubkeys are usually on curve
    // PDAs are off curve
    const program_id = SYSTEM_PROGRAM_ID;
    const seeds = [_][]const u8{"off-curve"};

    // Find a PDA (which should be off-curve)
    if (tryFindProgramAddress(&seeds, &program_id)) |pda| {
        try testing.expect(!isOnCurve(&pda.pubkey));
    }

    // System program ID might be on curve (it's a special case)
    // We can't guarantee this without checking the actual key
    _ = isOnCurve(&SYSTEM_PROGRAM_ID);
}

test "log function" {
    // Just test that it compiles and runs
    const key = Pubkey.newUnique();
    log(&key);
}