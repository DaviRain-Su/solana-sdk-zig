/// CPI Example - Demonstrates Cross-Program Invocation
///
/// This example shows how to:
/// 1. Create instructions for other programs
/// 2. Invoke other programs using CPI
/// 3. Use invoke_signed for PDA signing
const std = @import("std");
const solana = @import("solana_sdk_zig");

const Pubkey = solana.Pubkey;
const AccountInfo = solana.AccountInfo;
const ProgramResult = solana.ProgramResult;
const ProgramError = solana.ProgramError;
const Instruction = solana.Instruction;
const AccountMeta = solana.AccountMeta;
// Remove msg to reduce CU consumption
// const msg = solana.msg;

/// System Program ID
const SYSTEM_PROGRAM_BYTES = [_]u8{0} ** 32;
const SYSTEM_PROGRAM_ID = Pubkey.fromBytes(SYSTEM_PROGRAM_BYTES);

/// Instruction enum for our program
const CpiExampleInstruction = enum(u8) {
    /// Transfer SOL using CPI to System Program
    TransferSol = 0,
    /// Create a PDA-owned account
    CreatePdaAccount = 1,
    /// Transfer from PDA using invoke_signed
    TransferFromPda = 2,
};

/// Main processing function
pub fn process_instruction(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    instruction_data: []const u8,
) ProgramResult {
    // Skip logging to reduce CU

    // Parse instruction
    if (instruction_data.len == 0) {
        return ProgramError.InvalidInstructionData;
    }

    const instruction = std.meta.intToEnum(CpiExampleInstruction, instruction_data[0]) catch {
        return ProgramError.InvalidInstructionData;
    };

    return switch (instruction) {
        .TransferSol => transferSol(program_id, accounts, instruction_data[1..]),
        .CreatePdaAccount => createPdaAccount(program_id, accounts, instruction_data[1..]),
        .TransferFromPda => transferFromPda(program_id, accounts, instruction_data[1..]),
    };
}

/// Transfer SOL using System Program CPI
fn transferSol(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    data: []const u8,
) ProgramResult {
    _ = program_id;

    // Skip logging to reduce CU

    // Expected accounts:
    // 0. From account (signer, writable)
    // 1. To account (writable)
    // 2. System Program
    if (accounts.len < 3) {
        return ProgramError.NotEnoughAccountKeys;
    }

    const from_account = &accounts[0];
    const to_account = &accounts[1];
    const system_program = &accounts[2];

    // Parse lamports amount from data (8 bytes)
    if (data.len < 8) {
        return ProgramError.InvalidInstructionData;
    }
    const lamports = std.mem.readInt(u64, data[0..8], .little);

    // Verify system program
    if (!system_program.key().equals(&SYSTEM_PROGRAM_ID)) {
        return ProgramError.IncorrectProgramId;
    }

    // Best optimization: Use account data pointers
    const from_key = &from_account.data_ptr.id;
    const to_key = &to_account.data_ptr.id;

    // Optimized: Stack-allocated instruction components
    const ix_accounts = [_]AccountMeta{
        .{ .pubkey = from_key, .is_writable = true, .is_signer = true },
        .{ .pubkey = to_key, .is_writable = true, .is_signer = false },
    };

    // Optimized: Compact instruction data
    const ix_data = [_]u8{
        2, 0, 0, 0, // Transfer discriminator (little-endian u32)
    } ++ std.mem.toBytes(std.mem.nativeToLittle(u64, lamports));

    const transfer_ix = Instruction.from(.{
        .program_id = &SYSTEM_PROGRAM_ID,
        .accounts = &ix_accounts,
        .data = &ix_data,
    });

    // Optimized: Direct invoke with minimal accounts
    try transfer_ix.invoke(accounts[0..3]);

    // Transfer successful
    return;
}

/// Create a PDA-owned account
fn createPdaAccount(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    data: []const u8,
) ProgramResult {
    // Skip logging to reduce CU

    // Expected accounts:
    // 0. Payer account (signer, writable)
    // 1. PDA account (writable)
    // 2. System Program
    if (accounts.len < 3) {
        return ProgramError.NotEnoughAccountKeys;
    }

    const payer = &accounts[0];
    const pda_account = &accounts[1];

    // Parse space from data (8 bytes)
    if (data.len < 8) {
        return ProgramError.InvalidInstructionData;
    }
    const space = std.mem.readInt(u64, data[0..8], .little);

    // Derive PDA using the SDK function
    const seed = "vault";
    const seeds = [_][]const u8{seed};

    // Skip logging to reduce CU
    const pda_result = try Pubkey.findProgramAddress(&seeds, program_id.*);
    // Skip logging to reduce CU

    // Verify PDA matches
    if (!pda_account.key().equals(&pda_result.address)) {
        // PDA mismatch
        return ProgramError.InvalidSeeds;
    }

    const bump = pda_result.bump_seed[0];

    // Calculate minimum rent (simplified - should use rent sysvar)
    const lamports = 1_000_000;

    // Create account instruction
    const payer_key = &payer.data_ptr.id;
    const pda_key = &pda_account.data_ptr.id;

    var ix_accounts = [_]AccountMeta{
        .{ .pubkey = payer_key, .is_writable = true, .is_signer = true },
        .{ .pubkey = pda_key, .is_writable = true, .is_signer = true },
    };

    // System create_account instruction data:
    // [u32 discriminator][u64 lamports][u64 space][32 bytes owner]
    var ix_data: [52]u8 = undefined;
    std.mem.writeInt(u32, ix_data[0..4], 0, .little); // CreateAccount = 0
    std.mem.writeInt(u64, ix_data[4..12], lamports, .little);
    std.mem.writeInt(u64, ix_data[12..20], space, .little);
    @memcpy(ix_data[20..52], &program_id.bytes);

    const create_ix = Instruction.from(.{
        .program_id = &SYSTEM_PROGRAM_ID,
        .accounts = &ix_accounts,
        .data = &ix_data,
    });

    // Invoke with PDA signer
    const signer_seeds = [_][]const u8{ seed, &[_]u8{bump} };
    try create_ix.invoke_signed(
        accounts[0..3],
        &[_][]const []const u8{&signer_seeds},
    );

    // PDA account created
    return;
}

/// Transfer from PDA using invoke_signed
fn transferFromPda(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    data: []const u8,
) ProgramResult {
    // Skip logging to reduce CU

    // Expected accounts:
    // 0. PDA account (writable)
    // 1. To account (writable)
    // 2. System Program
    if (accounts.len < 3) {
        return ProgramError.NotEnoughAccountKeys;
    }

    const pda_account = &accounts[0];
    const to_account = &accounts[1];

    // Parse lamports amount from data (8 bytes)
    if (data.len < 8) {
        return ProgramError.InvalidInstructionData;
    }
    const lamports = std.mem.readInt(u64, data[0..8], .little);

    // Derive PDA and verify
    const seed = "vault";
    const seeds = [_][]const u8{seed};
    const pda_result = try Pubkey.findProgramAddress(&seeds, program_id.*);

    if (!pda_account.key().equals(&pda_result.address)) {
        // PDA mismatch
        return ProgramError.InvalidSeeds;
    }

    const bump = pda_result.bump_seed[0];

    // Get stable pointers to pubkeys
    const pda_key = &pda_account.data_ptr.id;
    const to_key = &to_account.data_ptr.id;

    // Create transfer instruction
    var ix_accounts = [_]AccountMeta{
        .{ .pubkey = pda_key, .is_writable = true, .is_signer = true },
        .{ .pubkey = to_key, .is_writable = true, .is_signer = false },
    };

    // System transfer data
    var ix_data: [12]u8 = undefined;
    std.mem.writeInt(u32, ix_data[0..4], 2, .little); // Transfer = 2
    std.mem.writeInt(u64, ix_data[4..12], lamports, .little);

    const transfer_ix = Instruction.from(.{
        .program_id = &SYSTEM_PROGRAM_ID,
        .accounts = &ix_accounts,
        .data = &ix_data,
    });

    // Invoke with PDA as signer
    const signer_seeds = [_][]const u8{ seed, &[_]u8{bump} };
    try transfer_ix.invoke_signed(
        accounts[0..3],
        &[_][]const []const u8{&signer_seeds},
    );

    // Transfer from PDA successful
    return;
}

// ============================================================================
// Helper functions
// ============================================================================


// Export entrypoint
comptime {
    solana.entrypoint.declareEntrypoint(process_instruction);
}