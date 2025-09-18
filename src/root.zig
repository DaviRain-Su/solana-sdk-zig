/// Pinocchio-Zig: Zero-dependency, zero-copy Solana program framework for Zig
///
/// A lightweight alternative to solana-program, inspired by anza-xyz/pinocchio
const std = @import("std");

// Core modules
pub const pubkey = @import("pubkey/pubkey.zig");
pub const account_info = @import("account_info/account_info.zig");
pub const instruction = @import("instruction.zig");
pub const program_error = @import("program_error.zig");
pub const syscalls = @import("syscalls.zig");
pub const bpf = @import("bpf.zig");
pub const log = @import("log.zig");

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
pub const SYSVAR_CLOCK_ID = pubkey.CLOCK_SYSVAR_ID;
pub const SYSVAR_RENT_ID = pubkey.RENT_SYSVAR_ID;
pub const SYSVAR_INSTRUCTIONS_ID = pubkey.extensions.SYSVAR_PROGRAM_ID;

// Helper functions
pub const toErrorCode = program_error.toErrorCode;
pub const resultToU64 = program_error.resultToU64;
pub const fromAccount = account_info.fromAccount;

// Re-export log functions
pub const msg = log.msg;
pub const print = log.print;

// Re-export syscall helpers
pub const sha256 = syscalls.sha256;
pub const keccak256 = syscalls.keccak256;
pub const blake3 = syscalls.blake3;
pub const poseidon = syscalls.poseidon;
pub const secp256k1Recover = syscalls.secp256k1Recover;
pub const getRemainingComputeUnits = syscalls.getRemainingComputeUnits;
pub const getStackHeight = syscalls.getStackHeight;
pub const setReturnData = syscalls.setReturnData;
pub const getReturnData = syscalls.getReturnData;

// Re-export BPF loader program IDs
pub const BPF_LOADER_DEPRECATED_PROGRAM_ID = bpf.bpf_loader_deprecated_program_id;
pub const BPF_LOADER_PROGRAM_ID = bpf.bpf_loader_program_id;
pub const BPF_UPGRADEABLE_LOADER_PROGRAM_ID = bpf.bpf_upgradeable_loader_program_id;

// Re-export pubkey extensions
pub const createWithSeed = pubkey.extensions.createWithSeed;
pub const tryFindProgramAddress = pubkey.extensions.tryFindProgramAddress;
pub const newUnique = pubkey.extensions.newUnique;
pub const isOnCurve = pubkey.extensions.isOnCurve;

// Re-export hasher for HashMap with Pubkey keys
pub const PubkeyHashContext = pubkey.hasher.PubkeyHashContext;
pub const AddressHasherBuilder = pubkey.hasher.AddressHasherBuilder;

test "pinocchio exports" {
    // Test that all exports are available
    _ = Pubkey;
    _ = AccountInfo;
    _ = Instruction;
    _ = ProgramError;
    _ = ProgramResult;
    _ = SUCCESS;
}
