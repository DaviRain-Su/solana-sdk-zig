/// Benchmark program to analyze CU bottlenecks
const std = @import("std");
const solana = @import("solana_sdk_zig");

const Pubkey = solana.Pubkey;
const AccountInfo = solana.AccountInfo;
const ProgramResult = solana.ProgramResult;
const ProgramError = solana.ProgramError;

/// Test 0: Empty program - measure pure entrypoint overhead
pub fn empty_processor(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    instruction_data: []const u8,
) ProgramResult {
    _ = program_id;
    _ = accounts;
    _ = instruction_data;
    return;
}

/// Test 1: Minimal account access - measure AccountInfo overhead
pub fn account_access_processor(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    instruction_data: []const u8,
) ProgramResult {
    _ = program_id;
    _ = instruction_data;

    // Just access first account's key
    if (accounts.len > 0) {
        const key = accounts[0].key();
        _ = key;
    }
    return;
}

/// Test 2: PDA derivation only - no CPI
pub fn pda_only_processor(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    instruction_data: []const u8,
) ProgramResult {
    _ = accounts;

    if (instruction_data.len == 0) {
        return ProgramError.InvalidInstructionData;
    }

    // Just derive PDA, no verification or CPI
    const seed = "You pass butter";
    const bump_seed = [_]u8{instruction_data[0]};
    const seeds = [_][]const u8{ seed, &bump_seed };

    const pda = try Pubkey.findProgramAddress(&seeds, program_id.*);
    _ = pda;

    return;
}

/// Test 3: Build instruction only - no invoke
pub fn build_ix_only_processor(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    instruction_data: []const u8,
) ProgramResult {
    _ = program_id;

    if (accounts.len < 1 or instruction_data.len == 0) {
        return ProgramError.InvalidInstructionData;
    }

    // Build instruction but don't invoke
    const SYSTEM_PROGRAM_BYTES = [_]u8{0} ** 32;
    const SYSTEM_PROGRAM_ID = Pubkey.fromBytes(SYSTEM_PROGRAM_BYTES);

    const allocated_key = accounts[0].key();
    const ix_accounts = [_]solana.AccountMeta{
        .{ .pubkey = allocated_key, .is_writable = true, .is_signer = true },
    };

    var ix_data: [12]u8 = undefined;
    std.mem.writeInt(u32, ix_data[0..4], 8, .little);
    std.mem.writeInt(u64, ix_data[4..12], 42, .little);

    const allocate_ix = solana.Instruction.from(.{
        .program_id = &SYSTEM_PROGRAM_ID,
        .accounts = &ix_accounts,
        .data = &ix_data,
    });
    _ = allocate_ix;

    return;
}

/// Main processor - switch based on instruction type
pub fn process_instruction(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    instruction_data: []const u8,
) ProgramResult {
    if (instruction_data.len == 0) {
        return ProgramError.InvalidInstructionData;
    }

    // First byte is test type, second byte is data (if needed)
    const test_type = instruction_data[0];
    const data = if (instruction_data.len > 1) instruction_data[1..] else &[_]u8{};

    return switch (test_type) {
        0 => empty_processor(program_id, accounts, data),
        1 => account_access_processor(program_id, accounts, data),
        2 => pda_only_processor(program_id, accounts, data),
        3 => build_ix_only_processor(program_id, accounts, data),
        else => ProgramError.InvalidInstructionData,
    };
}

// Export entrypoint
comptime {
    solana.entrypoint.declareEntrypoint(process_instruction);
}