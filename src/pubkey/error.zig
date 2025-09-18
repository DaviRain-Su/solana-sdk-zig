const std = @import("std");
const ProgramError = @import("../program_error.zig").ProgramError;

/// Error types for address operations
pub const PubkeyError = error{
    /// Length of the seed is too long for address generation
    MaxSeedLengthExceeded,
    /// Provided seeds do not result in a valid address
    InvalidSeeds,
    /// Provided owner is not allowed
    IllegalOwner,
    /// No viable bump seed found for address generation
    NoViableBumpSeed,
};

/// Parse errors for address strings
pub const ParsePubkeyError = error{
    /// Length of the public key is invalid
    InvalidPubkeyLength,
    /// String is the wrong size
    WrongSize,
    /// Invalid Base58 string
    Invalid,
};

/// Convert AddressError to u64 error code
pub fn pubkeyErrorToU64(err: PubkeyError) u64 {
    return switch (err) {
        PubkeyError.MaxSeedLengthExceeded => 0,
        PubkeyError.InvalidSeeds => 1,
        PubkeyError.IllegalOwner => 2,
        PubkeyError.NoViableBumpSeed => 3,
    };
}

/// Convert u64 to AddressError
pub fn u64ToPubkeyError(code: u64) PubkeyError {
    return switch (code) {
        0 => PubkeyError.MaxSeedLengthExceeded,
        1 => PubkeyError.InvalidSeeds,
        2 => PubkeyError.IllegalOwner,
        else => @panic("Invalid error code, Is not a valid PubkeyError"),
    };
}

/// Convert AddressError to ProgramError
pub fn addressErrorToProgramError(err: PubkeyError) ProgramError {
    return switch (err) {
        PubkeyError.MaxSeedLengthExceeded => ProgramError.MaxSeedLengthExceeded,
        PubkeyError.InvalidSeeds => ProgramError.InvalidSeeds,
        PubkeyError.IllegalOwner => ProgramError.IllegalOwner,
        PubkeyError.NoViableBumpSeed => ProgramError.InvalidError, // TODO: Implement error handling for NoViableBumpSeed
    };
}

/// Format error message for display
pub fn formatPubkeyError(err: PubkeyError) []const u8 {
    return switch (err) {
        PubkeyError.MaxSeedLengthExceeded => "Length of the seed is too long for address generation",
        PubkeyError.InvalidSeeds => "Provided seeds do not result in a valid address",
        PubkeyError.IllegalOwner => "Provided owner is not allowed",
        PubkeyError.NoViableBumpSeed => "No viable bump seed found for address generation",
    };
}

/// Format parse error message for display
pub fn formatParsePubkeyError(err: ParsePubkeyError) []const u8 {
    return switch (err) {
        ParsePubkeyError.WrongSize => "String is the wrong size",
        ParsePubkeyError.Invalid => "Invalid Base58 string",
        ParsePubkeyError.InvalidPubkeyLength => "Invalid public key length",
    };
}

test "error conversions" {
    const testing = std.testing;

    // Test AddressError to u64 conversion
    try testing.expectEqual(@as(u64, 0), pubkeyErrorToU64(error.MaxSeedLengthExceeded));
    try testing.expectEqual(@as(u64, 1), pubkeyErrorToU64(error.InvalidSeeds));
    try testing.expectEqual(@as(u64, 2), pubkeyErrorToU64(error.IllegalOwner));

    // Test u64 to AddressError conversion
    try testing.expectEqual(error.MaxSeedLengthExceeded, u64ToPubkeyError(0));
    try testing.expectEqual(error.InvalidSeeds, u64ToPubkeyError(1));
    try testing.expectEqual(error.IllegalOwner, u64ToPubkeyError(2));

    // Test that invalid code panics (can't test panic in unit tests, so skip this)
}

test "error messages" {
    const testing = std.testing;

    // Test error message formatting
    const msg1 = formatPubkeyError(PubkeyError.MaxSeedLengthExceeded);
    try testing.expect(std.mem.indexOf(u8, msg1, "seed is too long") != null);

    const msg3 = formatPubkeyError(PubkeyError.NoViableBumpSeed);
    try testing.expect(std.mem.indexOf(u8, msg3, "No viable bump seed found for address generation") != null);

    const msg4 = formatPubkeyError(PubkeyError.InvalidSeeds);
    try testing.expect(std.mem.indexOf(u8, msg4, "Provided seeds do not result in a valid address") != null);

    const msg5 = formatPubkeyError(PubkeyError.IllegalOwner);
    try testing.expect(std.mem.indexOf(u8, msg5, "Provided owner is not allowed") != null);
}
