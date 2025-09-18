const std = @import("std");

/// Solana program error codes
pub const ProgramError = error{
    // Standard errors (0-12)
    CustomError, // 0 TODO:(how to handle custom errors with string information)
    InvalidArgument, // 1
    InvalidInstructionData, // 2
    InvalidAccountData, // 3
    AccountDataTooSmall, // 4
    InsufficientFunds, // 5
    IncorrectProgramId, // 6
    MissingRequiredSignature, // 7
    AccountAlreadyInitialized, // 8
    UninitializedAccount, // 9
    UnbalancedInstruction, // 10
    ModifiedProgramId, // 11
    ExternalAccountLamportSpend, // 12

    // Additional errors (13-22)
    ExternalAccountDataModified, // 13
    ReadonlyLamportChange, // 14
    ReadonlyDataModified, // 15
    DuplicateAccountIndex, // 16
    ExecutableModified, // 17
    RentEpochModified, // 18
    NotEnoughAccountKeys, // 19
    AccountDataSizeChanged, // 20
    AccountNotExecutable, // 21
    AccountBorrowFailed, // 22

    // More errors (23-48)
    AccountBorrowOutstanding, // 23
    DuplicateAccountOutOfSync, // 24
    Custom, // 25 TODO:(how to handle custom errors with string information)
    InvalidError, // 26
    ExecutableDataModified, // 27
    ExecutableLamportChange, // 28
    ExecutableAccountNotRentExempt, // 29
    UnsupportedSysvar, // 30
    IllegalOwner, // 31
    MaxAccountsDataAllocationsExceeded, // 32
    MaxAccountsExceeded, // 33
    MaxInstructionTraceLengthExceeded, // 34
    BuiltinProgramsMustConsumeComputeUnits, // 35
    InvalidAccountOwner, // 36
    ArithmeticOverflow, // 37
    Immutable, // 38
    IncorrectAuthority, // 39
    BorshIoError, // 40
    AccountNotRentExempt, // 41
    InvalidAccountOwner2, // 42
    InvalidSeeds, // 43
    AddWithOverflow, // 44
    InvalidProgramExecutable, // 45
    AccountNotSigner, // 46
    AccountNotWritable, // 47
    IllegalRealloc, // 48

    // Additional custom errors
    AlreadyBorrowed,
    AlreadyBorrowedMut,
    BorrowLimitExceeded,
    InvalidPubkey,
    InvalidPubkeyLength,
    InvalidDataLength,
    BufferTooSmall,
    ExceedsMaxDataIncrease,
    SeedTooLong,
    NoProgramAddressFound,
    InvalidPDA,
    UnknownInstruction,
};

/// Success code
pub const SUCCESS: u64 = 0;

/// Convert error to u64 code for syscalls
pub fn toErrorCode(err: ProgramError) u64 {
    return switch (err) {
        error.CustomError => 0,
        error.InvalidArgument => 1,
        error.InvalidInstructionData => 2,
        error.InvalidAccountData => 3,
        error.AccountDataTooSmall => 4,
        error.InsufficientFunds => 5,
        error.IncorrectProgramId => 6,
        error.MissingRequiredSignature => 7,
        error.AccountAlreadyInitialized => 8,
        error.UninitializedAccount => 9,
        error.UnbalancedInstruction => 10,
        error.ModifiedProgramId => 11,
        error.ExternalAccountLamportSpend => 12,
        error.ExternalAccountDataModified => 13,
        error.ReadonlyLamportChange => 14,
        error.ReadonlyDataModified => 15,
        error.DuplicateAccountIndex => 16,
        error.ExecutableModified => 17,
        error.RentEpochModified => 18,
        error.NotEnoughAccountKeys => 19,
        error.AccountDataSizeChanged => 20,
        error.AccountNotExecutable => 21,
        error.AccountBorrowFailed => 22,
        error.AccountBorrowOutstanding => 23,
        error.DuplicateAccountOutOfSync => 24,
        error.Custom => 25,
        error.InvalidError => 26,
        error.ExecutableDataModified => 27,
        error.ExecutableLamportChange => 28,
        error.ExecutableAccountNotRentExempt => 29,
        error.UnsupportedSysvar => 30,
        error.IllegalOwner => 31,
        error.MaxAccountsDataAllocationsExceeded => 32,
        error.MaxAccountsExceeded => 33,
        error.MaxInstructionTraceLengthExceeded => 34,
        error.BuiltinProgramsMustConsumeComputeUnits => 35,
        error.InvalidAccountOwner => 36,
        error.ArithmeticOverflow => 37,
        error.Immutable => 38,
        error.IncorrectAuthority => 39,
        error.BorshIoError => 40,
        error.AccountNotRentExempt => 41,
        error.InvalidAccountOwner2 => 42,
        error.InvalidSeeds => 43,
        error.AddWithOverflow => 44,
        error.InvalidProgramExecutable => 45,
        error.AccountNotSigner => 46,
        error.AccountNotWritable => 47,
        error.IllegalRealloc => 48,

        // Custom errors start at 1000
        error.AlreadyBorrowed => 1000,
        error.AlreadyBorrowedMut => 1001,
        error.BorrowLimitExceeded => 1002,
        error.InvalidPubkey => 1003,
        error.InvalidPubkeyLength => 1004,
        error.InvalidDataLength => 1005,
        error.BufferTooSmall => 1006,
        error.ExceedsMaxDataIncrease => 1007,
        error.SeedTooLong => 1008,
        error.NoProgramAddressFound => 1009,
        error.InvalidPDA => 1010,
        error.UnknownInstruction => 1011,
    };
}

/// Convert u64 code to error (for testing/debugging)
pub fn fromErrorCode(code: u64) ?ProgramError {
    return switch (code) {
        0 => error.CustomError,
        1 => error.InvalidArgument,
        2 => error.InvalidInstructionData,
        3 => error.InvalidAccountData,
        4 => error.AccountDataTooSmall,
        5 => error.InsufficientFunds,
        6 => error.IncorrectProgramId,
        7 => error.MissingRequiredSignature,
        8 => error.AccountAlreadyInitialized,
        9 => error.UninitializedAccount,
        10 => error.UnbalancedInstruction,
        11 => error.ModifiedProgramId,
        12 => error.ExternalAccountLamportSpend,
        13 => error.ExternalAccountDataModified,
        14 => error.ReadonlyLamportChange,
        15 => error.ReadonlyDataModified,
        16 => error.DuplicateAccountIndex,
        17 => error.ExecutableModified,
        18 => error.RentEpochModified,
        19 => error.NotEnoughAccountKeys,
        20 => error.AccountDataSizeChanged,
        21 => error.AccountNotExecutable,
        22 => error.AccountBorrowFailed,
        23 => error.AccountBorrowOutstanding,
        24 => error.DuplicateAccountOutOfSync,
        25 => error.Custom,
        26 => error.InvalidError,
        27 => error.ExecutableDataModified,
        28 => error.ExecutableLamportChange,
        29 => error.ExecutableAccountNotRentExempt,
        30 => error.UnsupportedSysvar,
        31 => error.IllegalOwner,
        32 => error.MaxAccountsDataAllocationsExceeded,
        33 => error.MaxAccountsExceeded,
        34 => error.MaxInstructionTraceLengthExceeded,
        35 => error.BuiltinProgramsMustConsumeComputeUnits,
        36 => error.InvalidAccountOwner,
        37 => error.ArithmeticOverflow,
        38 => error.Immutable,
        39 => error.IncorrectAuthority,
        40 => error.BorshIoError,
        41 => error.AccountNotRentExempt,
        42 => error.InvalidAccountOwner2,
        43 => error.InvalidSeeds,
        44 => error.AddWithOverflow,
        45 => error.InvalidProgramExecutable,
        46 => error.AccountNotSigner,
        47 => error.AccountNotWritable,
        48 => error.IllegalRealloc,
        1000 => error.AlreadyBorrowed,
        1001 => error.AlreadyBorrowedMut,
        1002 => error.BorrowLimitExceeded,
        1003 => error.InvalidPubkey,
        1004 => error.InvalidPubkeyLength,
        1005 => error.InvalidDataLength,
        1006 => error.BufferTooSmall,
        1007 => error.ExceedsMaxDataIncrease,
        1008 => error.SeedTooLong,
        1009 => error.NoProgramAddressFound,
        1010 => error.InvalidPDA,
        1011 => error.UnknownInstruction,
        else => null,
    };
}

/// Program result type
pub const ProgramResult = ProgramError!void;

/// Helper to convert result to u64 for entrypoint return
pub inline fn resultToU64(result: ProgramResult) u64 {
    if (result) |_| {
        return SUCCESS;
    } else |err| {
        return toErrorCode(err);
    }
}

test "error code conversion" {
    try std.testing.expectEqual(@as(u64, 0), toErrorCode(error.CustomError));
    try std.testing.expectEqual(@as(u64, 7), toErrorCode(error.MissingRequiredSignature));
    try std.testing.expectEqual(@as(u64, 1000), toErrorCode(error.AlreadyBorrowed));

    try std.testing.expectEqual(@as(?ProgramError, error.CustomError), fromErrorCode(0));
    try std.testing.expectEqual(@as(?ProgramError, error.MissingRequiredSignature), fromErrorCode(7));
    try std.testing.expectEqual(@as(?ProgramError, null), fromErrorCode(999));
}

test "result conversion" {
    const ok_result: ProgramResult = {};
    try std.testing.expectEqual(@as(u64, SUCCESS), resultToU64(ok_result));

    const err_result: ProgramResult = error.InvalidArgument;
    try std.testing.expectEqual(@as(u64, 1), resultToU64(err_result));
}
