/// Hello World Solana Program Example
///
/// This demonstrates the basic structure of a Solana program using Pinocchio-Zig
const std = @import("std");
const pinocchio = @import("pinocchio");

const Pubkey = pinocchio.Pubkey;
const AccountInfo = pinocchio.AccountInfo;
const ProgramResult = pinocchio.ProgramResult;
const ProgramError = pinocchio.ProgramError;
const msg = pinocchio.msg;

/// Main processing function for our program
pub fn process_instruction(
    program_id: *const Pubkey,
    accounts: []const AccountInfo,
    instruction_data: []const u8,
) ProgramResult {
    // Log a hello message
    msg.msg("Hello, Solana from Zig!");

    // Log program ID
    msg.msgf("Program ID: {}", .{program_id});

    // Log number of accounts
    msg.msgf("Number of accounts: {}", .{accounts.len});

    // Log each account
    for (accounts, 0..) |account, i| {
        msg.msgf("Account {}: {}", .{ i, account.key });
        msg.msgf("  Owner: {}", .{account.owner});
        msg.msgf("  Lamports: {}", .{account.lamports.*});
        msg.msgf("  Data len: {}", .{account.data_len});
        msg.msgf("  Signer: {}", .{account.is_signer});
        msg.msgf("  Writable: {}", .{account.is_writable});
    }

    // Log instruction data
    msg.msgf("Instruction data length: {}", .{instruction_data.len});
    if (instruction_data.len > 0) {
        msg.msgHex("Instruction data", instruction_data);
    }

    // Process different instruction types based on first byte
    if (instruction_data.len > 0) {
        const instruction_type = instruction_data[0];

        switch (instruction_type) {
            0 => {
                msg.msg("Processing Initialize instruction");
                return processInitialize(accounts);
            },
            1 => {
                msg.msg("Processing Transfer instruction");
                if (instruction_data.len < 9) {
                    msg.msg("Error: Transfer requires 8 bytes for amount");
                    return .{ .Err = ProgramError.InvalidInstructionData };
                }
                const amount = std.mem.readInt(u64, instruction_data[1..9], .little);
                return processTransfer(accounts, amount);
            },
            2 => {
                msg.msg("Processing Close instruction");
                return processClose(accounts);
            },
            else => {
                msg.msgf("Unknown instruction type: {}", .{instruction_type});
                return .{ .Err = ProgramError.InvalidInstructionData };
            },
        }
    }

    // Success
    msg.msg("Hello World program executed successfully!");
    return .Success;
}

/// Initialize a new account
fn processInitialize(accounts: []const AccountInfo) ProgramResult {
    if (accounts.len < 1) {
        msg.msg("Initialize requires at least 1 account");
        return .{ .Err = ProgramError.NotEnoughAccountKeys };
    }

    const account = &accounts[0];

    // Check that the account is writable
    if (!account.is_writable) {
        msg.msg("Account must be writable");
        return .{ .Err = ProgramError.InvalidAccountData };
    }

    // Check that the account is a signer
    if (!account.is_signer) {
        msg.msg("Account must be a signer");
        return .{ .Err = ProgramError.MissingRequiredSignature };
    }

    // Initialize account data (if it has space)
    if (account.data_len > 0) {
        // Write a magic number to indicate initialization
        if (account.data_len >= 4) {
            const data = account.data_slice_mut();
            data[0] = 0xDE;
            data[1] = 0xAD;
            data[2] = 0xBE;
            data[3] = 0xEF;
            msg.msg("Account initialized with magic number");
        }
    }

    msg.msg("Initialize completed successfully");
    return .Success;
}

/// Transfer lamports between accounts
fn processTransfer(accounts: []const AccountInfo, amount: u64) ProgramResult {
    if (accounts.len < 2) {
        msg.msg("Transfer requires at least 2 accounts");
        return .{ .Err = ProgramError.NotEnoughAccountKeys };
    }

    const from = &accounts[0];
    const to = &accounts[1];

    // Check from account is signer
    if (!from.is_signer) {
        msg.msg("From account must be a signer");
        return .{ .Err = ProgramError.MissingRequiredSignature };
    }

    // Check both accounts are writable
    if (!from.is_writable or !to.is_writable) {
        msg.msg("Both accounts must be writable");
        return .{ .Err = ProgramError.InvalidAccountData };
    }

    // Check sufficient balance
    if (from.lamports.* < amount) {
        msg.msgf("Insufficient balance: {} < {}", .{ from.lamports.*, amount });
        return .{ .Err = ProgramError.InsufficientFunds };
    }

    // Perform transfer
    from.lamports.* -= amount;
    to.lamports.* += amount;

    msg.msgf("Transferred {} lamports", .{amount});
    return .Success;
}

/// Close an account and transfer remaining lamports
fn processClose(accounts: []const AccountInfo) ProgramResult {
    if (accounts.len < 2) {
        msg.msg("Close requires at least 2 accounts");
        return .{ .Err = ProgramError.NotEnoughAccountKeys };
    }

    const account_to_close = &accounts[0];
    const destination = &accounts[1];

    // Check account to close is signer and writable
    if (!account_to_close.is_signer) {
        msg.msg("Account to close must be a signer");
        return .{ .Err = ProgramError.MissingRequiredSignature };
    }

    if (!account_to_close.is_writable or !destination.is_writable) {
        msg.msg("Both accounts must be writable");
        return .{ .Err = ProgramError.InvalidAccountData };
    }

    // Transfer all lamports
    const lamports = account_to_close.lamports.*;
    destination.lamports.* += lamports;
    account_to_close.lamports.* = 0;

    // Clear account data
    const data = account_to_close.data_slice_mut();
    @memset(data, 0);

    msg.msgf("Closed account, transferred {} lamports", .{lamports});
    return .Success;
}

// Declare the program entrypoint
comptime {
    pinocchio.declareEntrypoint(process_instruction);
}

// ============================================================================
// Alternative: Using Context-based entrypoint
// ============================================================================

/// Alternative processor using Context directly
pub fn process_with_context(ctx: *pinocchio.Context) ProgramResult {
    msg.msg("Hello from context-based processor!");

    // Access program ID
    msg.msgf("Program ID: {}", .{ctx.program_id});

    // Access accounts
    const accounts = ctx.getAccounts();
    msg.msgf("Number of accounts: {}", .{accounts.len});

    // Access instruction data
    msg.msgf("Instruction data length: {}", .{ctx.data.len});

    // You can also find specific accounts
    if (accounts.len > 0) {
        const first_key = accounts[0].key;
        if (ctx.findAccount(first_key)) |found| {
            msg.msg("Found first account in context");
            _ = found;
        }
    }

    return .Success;
}

// To use the context-based entrypoint instead, uncomment this:
// comptime {
//     pinocchio.declareEntrypointWithContext(process_with_context);
// }