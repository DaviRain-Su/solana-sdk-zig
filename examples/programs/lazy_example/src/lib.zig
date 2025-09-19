/// Lazy Entrypoint Example - Demonstrates lazy account parsing
///
/// This example shows how lazy parsing can reduce CU consumption
/// by only parsing accounts that are actually used
const std = @import("std");
const solana = @import("solana_sdk_zig");

const Pubkey = solana.Pubkey;
const LazyAccountIter = solana.LazyAccountIter;
const ProgramResult = solana.ProgramResult;
const ProgramError = solana.ProgramError;
const msg = solana.msg;

/// Instruction types
const Instruction = enum(u8) {
    /// Process only first and last account
    ProcessFirstAndLast = 0,
    /// Skip middle accounts
    SkipMiddleAccounts = 1,
    /// Find specific account by key
    FindAccount = 2,
    /// Process all accounts (worst case for lazy)
    ProcessAll = 3,
};

/// Main lazy processing function
pub fn process_instruction_lazy(
    program_id: *const Pubkey,
    accounts: *LazyAccountIter,
    instruction_data: []const u8,
) ProgramResult {
    msg.msg("Lazy Example - Entry Point");

    if (instruction_data.len == 0) {
        msg.msg("Error: No instruction data provided");
        return ProgramError.InvalidInstructionData;
    }

    msg.msgf("Instruction data length: {}, first byte: {}", .{ instruction_data.len, instruction_data[0] });

    const instruction_byte = instruction_data[0];
    if (instruction_byte > 3) {
        msg.msgf("Error: Invalid instruction byte: {}", .{instruction_byte});
        return ProgramError.InvalidInstructionData;
    }

    const instruction = @as(Instruction, @enumFromInt(instruction_byte));
    msg.msgf("Processing instruction: {}", .{instruction});

    return switch (instruction) {
        .ProcessFirstAndLast => processFirstAndLast(program_id, accounts),
        .SkipMiddleAccounts => skipMiddleAccounts(program_id, accounts),
        .FindAccount => findAccount(program_id, accounts, instruction_data[1..]),
        .ProcessAll => processAll(program_id, accounts),
    };
}

/// Process only first and last account (best case for lazy)
fn processFirstAndLast(
    program_id: *const Pubkey,
    accounts: *LazyAccountIter,
) ProgramResult {
    _ = program_id;

    msg.msg(">>> ProcessFirstAndLast called");

    // Get first account
    const first = (try accounts.next()) orelse {
        msg.msg("No accounts provided");
        return ProgramError.NotEnoughAccountKeys;
    };

    msg.msgf("First account key: {}", .{first.key});
    msg.msgf("First account lamports: {}", .{first.getLamports()});

    // Count remaining accounts
    const remaining = accounts.remaining();
    if (remaining == 0) {
        msg.msg("Only one account provided");
        return;
    }

    // Skip all middle accounts (huge CU saving!)
    accounts.skip(remaining - 1);

    // Get last account
    const last = (try accounts.next()) orelse {
        return ProgramError.InvalidArgument;
    };

    msg.msgf("Last account key: {}", .{last.key});
    msg.msgf("Last account lamports: {}", .{last.getLamports()});

    msg.msg("Successfully processed first and last accounts");
    return;
}

/// Skip middle accounts demonstration
fn skipMiddleAccounts(
    program_id: *const Pubkey,
    accounts: *LazyAccountIter,
) ProgramResult {
    _ = program_id;

    msg.msg("Processing every other account");

    var count: usize = 0;
    while (try accounts.next()) |account| {
        msg.msgf("Processing account {}: {}", .{ count, account.key });
        count += 1;

        // Skip next account
        accounts.skip(1);
    }

    msg.msgf("Processed {} accounts (skipped {} accounts)", .{ count, count });
    return;
}

/// Find specific account by key (early exit benefit)
fn findAccount(
    program_id: *const Pubkey,
    accounts: *LazyAccountIter,
    data: []const u8,
) ProgramResult {
    _ = program_id;

    if (data.len < 32) {
        return ProgramError.InvalidInstructionData;
    }

    const target_key = @as(*const Pubkey, @ptrCast(@alignCast(data.ptr)));
    msg.msgf("Looking for account: {}", .{target_key});

    // Peek at keys without full parsing
    var index: usize = 0;
    while (try accounts.peekKey()) |key| {
        if (key.equals(target_key)) {
            msg.msgf("Found account at index {}", .{index});

            // Now parse the full account
            const account = (try accounts.next()).?;
            msg.msgf("Account lamports: {}", .{account.getLamports()});
            msg.msgf("Account is signer: {}", .{account.isSigner()});

            // Early exit - remaining accounts not parsed!
            return;
        }

        // Skip this account
        accounts.skip(1);
        index += 1;
    }

    msg.msg("Account not found");
    return ProgramError.InvalidAccountData;
}

/// Process all accounts (worst case, but still optimized)
fn processAll(
    program_id: *const Pubkey,
    accounts: *LazyAccountIter,
) ProgramResult {
    _ = program_id;

    msg.msg("Processing all accounts");

    var total_lamports: u64 = 0;
    var count: usize = 0;

    while (try accounts.next()) |account| {
        total_lamports += account.getLamports();
        count += 1;
    }

    msg.msgf("Processed {} accounts, total lamports: {}", .{ count, total_lamports });
    return;
}

// Export lazy entrypoint
comptime {
    solana.declareLazyEntrypoint(process_instruction_lazy);
}