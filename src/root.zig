/// Pinocchio-Zig: Zero-dependency, zero-copy Solana program framework for Zig
///
/// A lightweight alternative to solana-program, inspired by anza-xyz/pinocchio

const std = @import("std");

// Core types
pub const pubkey = @import("pubkey.zig");
pub const account_info = @import("account_info.zig");
pub const instruction = @import("instruction.zig");
pub const program_error = @import("program_error.zig");

// Re-export common types
pub const Pubkey = pubkey.Pubkey;
pub const AccountInfo = account_info.AccountInfo;
pub const Account = account_info.Account;
pub const AccountMeta = instruction.AccountMeta;
pub const Instruction = instruction.Instruction;
pub const CompiledInstruction = instruction.CompiledInstruction;
pub const ProgramError = program_error.ProgramError;
pub const ProgramResult = program_error.ProgramResult;

// Re-export commonly used constants
pub const SUCCESS = program_error.SUCCESS;
pub const MAX_TX_ACCOUNTS = account_info.MAX_TX_ACCOUNTS;
pub const MAX_PERMITTED_DATA_INCREASE = account_info.MAX_PERMITTED_DATA_INCREASE;

// Re-export system program IDs
pub const SYSTEM_PROGRAM_ID = pubkey.SYSTEM_PROGRAM_ID;
pub const TOKEN_PROGRAM_ID = pubkey.TOKEN_PROGRAM_ID;
pub const ASSOCIATED_TOKEN_PROGRAM_ID = pubkey.ASSOCIATED_TOKEN_PROGRAM_ID;

// Re-export sysvar IDs
pub const SYSVAR_CLOCK_ID = pubkey.SYSVAR_CLOCK_ID;
pub const SYSVAR_RENT_ID = pubkey.SYSVAR_RENT_ID;
pub const SYSVAR_INSTRUCTIONS_ID = pubkey.SYSVAR_INSTRUCTIONS_ID;

// Helper functions
pub const toErrorCode = program_error.toErrorCode;
pub const resultToU64 = program_error.resultToU64;
pub const fromAccount = account_info.fromAccount;

test "pinocchio exports" {
    // Test that all exports are available
    _ = Pubkey;
    _ = AccountInfo;
    _ = Instruction;
    _ = ProgramError;
    _ = ProgramResult;
    _ = SUCCESS;
}