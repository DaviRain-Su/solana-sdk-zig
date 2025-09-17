const std = @import("std");
const ProgramError = @import("../program_error.zig").ProgramError;

/// Error types for address operations
pub const AddressError = error{
    /// Length of the seed is too long for address generation
    MaxSeedLengthExceeded,
    /// Provided seeds do not result in a valid address
    InvalidSeeds,
    /// Provided owner is not allowed
    IllegalOwner,
};

/// Parse errors for address strings
pub const ParseAddressError = error{
    /// String is the wrong size
    WrongSize,
    /// Invalid Base58 string
    Invalid,
};

/// Convert AddressError to u64 error code
pub fn addressErrorToU64(err: AddressError) u64 {
    return switch (err) {
        error.MaxSeedLengthExceeded => 0,
        error.InvalidSeeds => 1,
        error.IllegalOwner => 2,
    };
}

/// Convert u64 to AddressError
pub fn u64ToAddressError(code: u64) !AddressError {
    return switch (code) {
        0 => error.MaxSeedLengthExceeded,
        1 => error.InvalidSeeds,
        2 => error.IllegalOwner,
        else => error.InvalidErrorCode,
    };
}

/// Convert AddressError to ProgramError
pub fn addressErrorToProgramError(err: AddressError) ProgramError {
    return switch (err) {
        error.MaxSeedLengthExceeded => ProgramError.MaxSeedLengthExceeded,
        error.InvalidSeeds => ProgramError.InvalidSeeds,
        error.IllegalOwner => ProgramError.IllegalOwner,
    };
}

/// Format error message for display
pub fn formatAddressError(err: AddressError) []const u8 {
    return switch (err) {
        error.MaxSeedLengthExceeded => "Length of the seed is too long for address generation",
        error.InvalidSeeds => "Provided seeds do not result in a valid address",
        error.IllegalOwner => "Provided owner is not allowed",
    };
}

/// Format parse error message for display
pub fn formatParseError(err: ParseAddressError) []const u8 {
    return switch (err) {
        error.WrongSize => "String is the wrong size",
        error.Invalid => "Invalid Base58 string",
    };
}

test "error conversions" {
    const testing = std.testing;

    // Test AddressError to u64 conversion
    try testing.expectEqual(@as(u64, 0), addressErrorToU64(error.MaxSeedLengthExceeded));
    try testing.expectEqual(@as(u64, 1), addressErrorToU64(error.InvalidSeeds));
    try testing.expectEqual(@as(u64, 2), addressErrorToU64(error.IllegalOwner));

    // Test u64 to AddressError conversion
    try testing.expectEqual(error.MaxSeedLengthExceeded, try u64ToAddressError(0));
    try testing.expectEqual(error.InvalidSeeds, try u64ToAddressError(1));
    try testing.expectEqual(error.IllegalOwner, try u64ToAddressError(2));

    // Test invalid code
    try testing.expectError(error.InvalidErrorCode, u64ToAddressError(999));
}

test "error messages" {
    const testing = std.testing;

    // Test error message formatting
    const msg1 = formatAddressError(error.MaxSeedLengthExceeded);
    try testing.expect(std.mem.indexOf(u8, msg1, "seed is too long") != null);

    const msg2 = formatParseError(error.WrongSize);
    try testing.expect(std.mem.indexOf(u8, msg2, "wrong size") != null);
}
