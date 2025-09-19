/// Rosetta-compatible CPI implementation
/// This exactly matches solana-program-rosetta/cpi logic for accurate benchmarking
const std = @import("std");
const solana = @import("solana_sdk_zig");

const Pubkey = solana.Pubkey;
const AccountInfo = solana.AccountInfo;
const ProgramResult = solana.ProgramResult;
const ProgramError = solana.ProgramError;
const Instruction = solana.Instruction;
const AccountMeta = solana.AccountMeta;

/// System Program ID
const SYSTEM_PROGRAM_BYTES = [_]u8{0} ** 32;
const SYSTEM_PROGRAM_ID = Pubkey.fromBytes(SYSTEM_PROGRAM_BYTES);

/// Amount of bytes to allocate (matching Rosetta)
const SIZE: u64 = 42;

/// Main processing function - matches Rosetta's process_instruction
pub fn process_instruction(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    instruction_data: []const u8,
) ProgramResult {
    // Validate we have the minimum accounts
    if (accounts.len < 2) {
        return ProgramError.NotEnoughAccountKeys;
    }

    // Get accounts (matching Rosetta's next_account_info pattern)
    const allocated_info = &accounts[0];
    const system_program_info = &accounts[1];

    // Skip system program verification to save CU
    _ = system_program_info;

    // Check instruction data has bump seed
    if (instruction_data.len == 0) {
        return ProgramError.InvalidInstructionData;
    }

    // Derive expected PDA address using create_program_address (matching Rosetta exactly)
    const seed = "You pass butter";
    const bump_seed = [_]u8{instruction_data[0]};
    const seeds = [_][]const u8{ seed, &bump_seed };

    const expected_allocated_key = Pubkey.createProgramAddress(&seeds, program_id.*) catch {
        return ProgramError.InvalidSeeds;
    };

    // Verify the allocated account key matches expected PDA (matching Rosetta)
    if (!allocated_info.key().equals(&expected_allocated_key)) {
        return ProgramError.InvalidArgument;
    }

    // Build allocate instruction (system program instruction 8)
    const allocated_key = allocated_info.key();
    const ix_accounts = [_]AccountMeta{
        .{ .pubkey = allocated_key, .is_writable = true, .is_signer = true },
    };

    // Allocate instruction data: [8, 0, 0, 0] + space (8 bytes)
    var ix_data: [12]u8 = undefined;
    std.mem.writeInt(u32, ix_data[0..4], 8, .little); // Allocate = 8
    std.mem.writeInt(u64, ix_data[4..12], SIZE, .little);

    const allocate_ix = Instruction.from(.{
        .program_id = &SYSTEM_PROGRAM_ID,
        .accounts = &ix_accounts,
        .data = &ix_data,
    });

    // Invoke with PDA as signer (matching invoke_signed in Rosetta)
    const signer_seeds = [_][]const u8{ seed, &bump_seed };
    try allocate_ix.invoke_signed(
        accounts[0..1], // Only pass the allocated account
        &[_][]const []const u8{&signer_seeds},
    );

    return;
}

// Export entrypoint
comptime {
    solana.entrypoint.declareEntrypoint(process_instruction);
}