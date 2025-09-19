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
const msg = solana.msg;

/// System Program ID - use const for pointer stability
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
    /// Minimal CPI test
    MinimalTest = 4,
    /// Debug CPI test
    DebugTest = 5,

    pub fn fromU8(byte: u8) ?CpiExampleInstruction {
        return switch (byte) {
            0 => .TransferSol,
            1 => .CreatePdaAccount,
            2 => .TransferFromPda,
            4 => .MinimalTest,
            5 => .DebugTest,
            else => null,
        };
    }
};

/// Main processing function
pub fn process_instruction(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    instruction_data: []const u8,
) ProgramResult {
    msg.msg("CPI Example Program - Entry Point");

    // Parse instruction
    if (instruction_data.len == 0) {
        return ProgramError.InvalidInstructionData;
    }

    const instruction = CpiExampleInstruction.fromU8(instruction_data[0]) orelse {
        msg.msgf("Unknown instruction: {}", .{instruction_data[0]});
        return ProgramError.InvalidInstructionData;
    };

    switch (instruction) {
        .TransferSol => return transferSol(program_id, accounts, instruction_data[1..]),
        .CreatePdaAccount => return createPdaAccount(program_id, accounts, instruction_data[1..]),
        .TransferFromPda => return transferFromPda(program_id, accounts, instruction_data[1..]),
        .MinimalTest => return minimalTest(program_id, accounts, instruction_data[1..]),
        .DebugTest => return debugTest(program_id, accounts, instruction_data[1..]),
    }
}

/// Minimal CPI test - just try to invoke with empty instruction
fn minimalTest(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    data: []const u8,
) ProgramResult {
    _ = program_id;
    _ = data;

    msg.msg("Minimal CPI Test");

    if (accounts.len < 2) {
        return ProgramError.NotEnoughAccountKeys;
    }

    // Create the simplest possible instruction
    const empty_data = [_]u8{};
    const empty_accounts = [_]AccountMeta{};

    // Create instruction pointing to System Program
    const ix = Instruction.from(.{
        .program_id = &SYSTEM_PROGRAM_ID,
        .accounts = &empty_accounts,
        .data = &empty_data,
    });

    msg.msg("Calling CPI with empty instruction");

    // Try to invoke with no accounts
    const empty_account_infos = [_]AccountInfo{};
    try ix.invoke(&empty_account_infos);

    msg.msg("Minimal CPI test successful!");
    return;
}

/// Debug CPI test - test with just System Program account
fn debugTest(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    data: []const u8,
) ProgramResult {
    _ = program_id;
    _ = data;

    msg.msg("Debug CPI Test - Testing transfer between accounts");

    // Now let's test a transfer instruction properly
    // But first test with a simple no-account instruction
    msg.msg("Testing CPI with proper transfer instruction");

    if (accounts.len < 2) {
        msg.msg("Need at least 2 accounts for transfer test");
        return ProgramError.NotEnoughAccountKeys;
    }

    const from_account = &accounts[0];
    const to_account = &accounts[1];

    // Create stable pointers
    const from_key = &from_account.data_ptr.id;
    const to_key = &to_account.data_ptr.id;

    // Create a local copy of system program ID to ensure stable pointer
    var local_system_program = SYSTEM_PROGRAM_ID;

    // Skip empty test since System Program rejects empty data
    // msg.msg("Test 1: Empty instruction");
    // var empty_data = [_]u8{};
    // const empty_accounts = [_]AccountMeta{};

    // const empty_ix = Instruction.from(.{
    //     .program_id = &local_system_program,
    //     .accounts = &empty_accounts,
    //     .data = &empty_data,
    // });

    // const empty_account_infos = [_]AccountInfo{};
    // try empty_ix.invoke(&empty_account_infos);
    // msg.msg("✓ Empty CPI succeeded (System Program returns success for empty)");

    // Second test: Transfer with proper accounts
    msg.msg("Test 2: Transfer instruction with accounts");
    var ix_accounts = [_]AccountMeta{
        .{ .pubkey = from_key, .is_writable = true, .is_signer = true },
        .{ .pubkey = to_key, .is_writable = true, .is_signer = false },
    };

    // System transfer data (1 lamport)
    var ix_data: [12]u8 = undefined;
    std.mem.writeInt(u32, ix_data[0..4], 2, .little); // Transfer = 2
    std.mem.writeInt(u64, ix_data[4..12], 1, .little); // 1 lamport

    const transfer_ix = Instruction.from(.{
        .program_id = &local_system_program,
        .accounts = &ix_accounts,
        .data = &ix_data,
    });

    msg.msg("Invoking transfer with account infos");
    // Pass all accounts available to us
    if (accounts.len < 3) {
        msg.msg("Need 3 accounts: from, to, system_program");
        return ProgramError.NotEnoughAccountKeys;
    }
    try transfer_ix.invoke(accounts);
    msg.msg("✓ Transfer CPI succeeded!");

    msg.msg("Debug CPI test completed successfully!");
    return;
}

/// Transfer SOL using System Program CPI
fn transferSol(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    data: []const u8,
) ProgramResult {
    _ = program_id;

    msg.msg("Processing TransferSol instruction");

    if (accounts.len < 3) {
        return ProgramError.NotEnoughAccountKeys;
    }

    const from_account = &accounts[0];
    const to_account = &accounts[1];
    const system_program = &accounts[2];

    // Debug log account states
    msg.msgf("From account: signer={}, writable={}", .{from_account.isSigner(), from_account.isWritable()});
    msg.msgf("To account: signer={}, writable={}", .{to_account.isSigner(), to_account.isWritable()});
    msg.msgf("System program: signer={}, writable={}", .{system_program.isSigner(), system_program.isWritable()});

    // Parse lamports amount from data (8 bytes)
    if (data.len < 8) {
        return ProgramError.InvalidInstructionData;
    }
    const lamports = std.mem.readInt(u64, data[0..8], .little);

    msg.msgf("Transferring {} lamports", .{lamports});

    // Verify system program
    if (!system_program.key().equals(&SYSTEM_PROGRAM_ID)) {
        msg.msg("Invalid system program");
        return ProgramError.IncorrectProgramId;
    }

    // Get stable pointers to pubkeys from account data
    const from_key = &from_account.data_ptr.id;
    const to_key = &to_account.data_ptr.id;

    msg.msgf("From key ptr: 0x{x}, value: {}", .{@intFromPtr(from_key), from_key.*});
    msg.msgf("To key ptr: 0x{x}, value: {}", .{@intFromPtr(to_key), to_key.*});

    // Create a local copy of system program ID to ensure stable pointer
    var local_system_program = SYSTEM_PROGRAM_ID;

    // Create instruction with stable program ID pointer
    var ix_accounts = [_]AccountMeta{
        .{ .pubkey = from_key, .is_writable = true, .is_signer = true },
        .{ .pubkey = to_key, .is_writable = true, .is_signer = false },
    };

    // System transfer data
    var ix_data: [12]u8 = undefined;
    std.mem.writeInt(u32, ix_data[0..4], 2, .little); // Transfer = 2
    std.mem.writeInt(u64, ix_data[4..12], lamports, .little);

    const transfer_ix = Instruction.from(.{
        .program_id = &local_system_program,
        .accounts = &ix_accounts,
        .data = &ix_data,
    });

    // Debug log the instruction details
    msg.msgf("System program ID ptr: 0x{x}", .{@intFromPtr(&local_system_program)});
    msg.msgf("ix_accounts ptr: 0x{x}", .{@intFromPtr(&ix_accounts)});
    msg.msgf("ix_data ptr: 0x{x}", .{@intFromPtr(&ix_data)});
    for (ix_accounts, 0..) |meta, i| {
        msg.msgf("AccountMeta[{}]: pubkey_ptr=0x{x}, signer={}, writable={}", .{
            i, @intFromPtr(meta.pubkey), meta.is_signer, meta.is_writable
        });
    }

    // Invoke System Program - pass all accounts including System Program
    msg.msg("Invoking System Program transfer");
    // Pass all accounts: from, to, and System Program
    // Even though System Program is in program_id, it might need to be in accounts too
    try transfer_ix.invoke(accounts[0..3]);

    msg.msg("Transfer successful!");
    return;
}

/// Create a PDA-owned account
fn createPdaAccount(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    data: []const u8,
) ProgramResult {
    msg.msg("Processing CreatePdaAccount instruction");

    if (accounts.len < 4) {
        return ProgramError.NotEnoughAccountKeys;
    }

    const payer = &accounts[0];
    const pda_account = &accounts[1];
    _ = &accounts[2]; // system_program - will be passed in slice
    const rent_sysvar = &accounts[3];

    _ = rent_sysvar; // Rent is handled by runtime now

    // Parse space from data (8 bytes)
    if (data.len < 8) {
        return ProgramError.InvalidInstructionData;
    }
    const space = std.mem.readInt(u64, data[0..8], .little);

    // Derive PDA
    const seed = "vault";
    const seeds = [_][]const u8{seed};
    const bump = try findProgramAddressBump(&seeds, program_id);

    // Verify PDA matches
    const expected_pda = try deriveProgramAddress(&seeds, bump, program_id);
    if (!pda_account.key().equals(&expected_pda)) {
        msg.msg("PDA mismatch");
        return ProgramError.InvalidSeeds;
    }

    msg.msgf("Creating PDA account with {} bytes", .{space});

    // Calculate minimum rent
    const lamports = 1_000_000; // Simplified - should calculate actual rent

    // Create account instruction
    const create_ix = createSystemCreateAccountInstruction(
        payer.key(),
        pda_account.key(),
        lamports,
        space,
        program_id,
    );

    // Invoke with PDA signer
    const signer_seeds = [_][]const u8{ seed, &[_]u8{bump} };
    msg.msg("Invoking System Program create_account with PDA signer");
    try create_ix.invoke_signed(
        accounts[0..3],  // Pass original slice
        &[_][]const []const u8{&signer_seeds},
    );

    msg.msg("PDA account created!");
    return;
}

/// Transfer from PDA using invoke_signed
fn transferFromPda(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    data: []const u8,
) ProgramResult {
    msg.msg("Processing TransferFromPda instruction");

    if (accounts.len < 3) {
        return ProgramError.NotEnoughAccountKeys;
    }

    const pda_account = &accounts[0];
    const to_account = &accounts[1];
    // System program account is passed but not needed for the instruction
    _ = &accounts[2];

    // Parse lamports amount from data (8 bytes)
    if (data.len < 8) {
        return ProgramError.InvalidInstructionData;
    }
    const lamports = std.mem.readInt(u64, data[0..8], .little);

    // Derive PDA and verify
    const seed = "vault";
    const seeds = [_][]const u8{seed};
    const bump = try findProgramAddressBump(&seeds, program_id);

    const expected_pda = try deriveProgramAddress(&seeds, bump, program_id);
    if (!pda_account.key().equals(&expected_pda)) {
        msg.msg("PDA mismatch");
        return ProgramError.InvalidSeeds;
    }

    msg.msgf("Transferring {} lamports from PDA", .{lamports});

    // Get stable pointers to pubkeys from account data
    const pda_key = &pda_account.data_ptr.id;
    const to_key = &to_account.data_ptr.id;

    // Create a local copy of system program ID to ensure stable pointer
    var local_system_program = SYSTEM_PROGRAM_ID;

    // Create instruction with stable program ID pointer
    var ix_accounts = [_]AccountMeta{
        .{ .pubkey = pda_key, .is_writable = true, .is_signer = true },
        .{ .pubkey = to_key, .is_writable = true, .is_signer = false },
    };

    // System transfer data
    var ix_data: [12]u8 = undefined;
    std.mem.writeInt(u32, ix_data[0..4], 2, .little); // Transfer = 2
    std.mem.writeInt(u64, ix_data[4..12], lamports, .little);

    const transfer_ix = Instruction.from(.{
        .program_id = &local_system_program,
        .accounts = &ix_accounts,
        .data = &ix_data,
    });

    // Invoke with PDA as signer
    const signer_seeds = [_][]const u8{ seed, &[_]u8{bump} };
    msg.msg("Invoking System Program transfer with PDA signer");
    try transfer_ix.invoke_signed(
        accounts[0..2],  // Pass original slice
        &[_][]const []const u8{&signer_seeds},
    );

    msg.msg("Transfer from PDA successful!");
    return;
}

// ============================================================================
// Helper functions
// ============================================================================

/// Create System Program transfer instruction with provided buffers
fn createSystemTransferInstruction(
    from: *const Pubkey,
    to: *const Pubkey,
    lamports: u64,
    accounts_buf: []AccountMeta,
    data_buf: []u8,
) Instruction {
    // Fill account metas into provided buffer with pointers
    accounts_buf[0] = .{
        .pubkey = from,  // Use pointer directly
        .is_writable = true,
        .is_signer = true,
    };
    accounts_buf[1] = .{
        .pubkey = to,  // Use pointer directly
        .is_writable = true,
        .is_signer = false,
    };

    // Debug verify account metas
    msg.msgf("Created account metas: from.is_signer={}, to.is_signer={}", .{accounts_buf[0].is_signer, accounts_buf[1].is_signer});
    msg.msgf("  accounts_buf[0].pubkey ptr: 0x{x}", .{@intFromPtr(accounts_buf[0].pubkey)});
    msg.msgf("  accounts_buf[1].pubkey ptr: 0x{x}", .{@intFromPtr(accounts_buf[1].pubkey)});

    // System transfer instruction data: [u32 discriminator][u64 lamports]
    std.mem.writeInt(u32, data_buf[0..4], 2, .little); // Transfer = 2
    std.mem.writeInt(u64, data_buf[4..12], lamports, .little);

    // Debug: Log the instruction data
    msg.msgf("Transfer instruction data: {} {} {} {} | {} {} {} {} {} {} {} {}", .{
        data_buf[0], data_buf[1], data_buf[2], data_buf[3],
        data_buf[4], data_buf[5], data_buf[6], data_buf[7],
        data_buf[8], data_buf[9], data_buf[10], data_buf[11],
    });

    // Use from() method with pointer to program ID
    const ix = Instruction.from(.{
        .program_id = &SYSTEM_PROGRAM_ID,
        .accounts = accounts_buf,
        .data = data_buf,
    });

    // Debug verify instruction accounts
    msg.msgf("Instruction accounts[0].is_signer={}, accounts[1].is_signer={}", .{
        accounts_buf[0].is_signer,
        accounts_buf[1].is_signer,
    });

    return ix;
}

/// Create System Program create_account instruction
fn createSystemCreateAccountInstruction(
    payer: *const Pubkey,
    new_account: *const Pubkey,
    lamports: u64,
    space: u64,
    owner: *const Pubkey,
) Instruction {
    const accounts = [_]AccountMeta{
        .{ .pubkey = payer, .is_writable = true, .is_signer = true },        // Payer (signer, writable)
        .{ .pubkey = new_account, .is_writable = true, .is_signer = true },  // New account (signer, writable)
    };

    // System create_account instruction data:
    // [u32 discriminator][u64 lamports][u64 space][32 bytes owner]
    var data: [52]u8 = undefined;
    std.mem.writeInt(u32, data[0..4], 0, .little); // CreateAccount = 0
    std.mem.writeInt(u64, data[4..12], lamports, .little);
    std.mem.writeInt(u64, data[12..20], space, .little);
    @memcpy(data[20..52], &owner.bytes);

    return Instruction.from(.{
        .program_id = &SYSTEM_PROGRAM_ID,
        .accounts = &accounts,
        .data = &data,
    });
}

/// Find PDA bump seed
fn findProgramAddressBump(
    seeds: []const []const u8,
    program_id: *const Pubkey,
) !u8 {
    var bump: u8 = 255;
    while (bump > 0) : (bump -= 1) {
        const pda = deriveProgramAddress(seeds, bump, program_id) catch continue;
        _ = pda;
        return bump;
    }
    return error.InvalidSeeds;
}

/// Derive program address
fn deriveProgramAddress(
    seeds: []const []const u8,
    bump: u8,
    program_id: *const Pubkey,
) !Pubkey {
    // Simplified PDA derivation
    // Real implementation would use proper hash function
    var result = Pubkey.ZEROES;

    // Mix seeds
    for (seeds) |seed| {
        for (seed, 0..) |byte, i| {
            result.bytes[i % 32] ^= byte;
        }
    }

    // Mix bump
    result.bytes[0] ^= bump;

    // Mix program ID
    for (program_id.bytes, 0..) |byte, i| {
        result.bytes[i] ^= byte;
    }

    return result;
}

// Export entrypoint
comptime {
    solana.entrypoint.declareEntrypoint(process_instruction);
}