/// Hello World Solana Program
///
/// A simple Solana program demonstrating basic functionality using Solana SDK Zig
const std = @import("std");
const solana = @import("solana_sdk_zig");

const Pubkey = solana.Pubkey;
const AccountInfo = solana.AccountInfo;
const ProgramResult = solana.ProgramResult;
const ProgramError = solana.ProgramError;
const msg = solana.msg;

/// Instruction enum for our program
const HelloInstruction = enum(u8) {
    /// Initialize a new greeting account
    Initialize = 0,
    /// Update the greeting message
    UpdateGreeting = 1,
    /// Say hello - logs the current greeting
    SayHello = 2,

    pub fn fromU8(byte: u8) ?HelloInstruction {
        return switch (byte) {
            0 => .Initialize,
            1 => .UpdateGreeting,
            2 => .SayHello,
            else => null,
        };
    }
};

/// Account data structure for storing greeting
const GreetingAccount = extern struct {
    /// Magic number to identify initialized accounts
    magic: u32,
    /// Counter for number of greetings
    greeting_count: u32,
    /// The greeting message (max 32 bytes)
    message: [32]u8,

    const MAGIC: u32 = 0xDEADBEEF;

    pub fn isInitialized(self: *const GreetingAccount) bool {
        return self.magic == MAGIC;
    }

    pub fn init() GreetingAccount {
        var account = GreetingAccount{
            .magic = MAGIC,
            .greeting_count = 0,
            .message = [_]u8{0} ** 32,
        };
        const default_msg = "Hello, Solana!";
        @memcpy(account.message[0..default_msg.len], default_msg);
        return account;
    }

    pub fn getMessage(self: *const GreetingAccount) []const u8 {
        // Find the null terminator or use full buffer
        for (self.message, 0..) |byte, i| {
            if (byte == 0) {
                return self.message[0..i];
            }
        }
        return &self.message;
    }
};

/// Main processing function for our program
pub fn process_instruction(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    instruction_data: []const u8,
) ProgramResult {
    msg.msg("Hello World Program - Entry Point");

    // Parse instruction type
    if (instruction_data.len == 0) {
        msg.msg("Error: No instruction data provided");
        return ProgramError.InvalidInstructionData;
    }

    const instruction = HelloInstruction.fromU8(instruction_data[0]) orelse {
        msg.msgf("Error: Unknown instruction: {}", .{instruction_data[0]});
        return ProgramError.InvalidInstructionData;
    };

    msg.msgf("Processing instruction: {}", .{instruction});

    // Dispatch to appropriate handler
    return switch (instruction) {
        .Initialize => processInitialize(program_id, accounts),
        .UpdateGreeting => processUpdateGreeting(program_id, accounts, instruction_data[1..]),
        .SayHello => processSayHello(accounts),
    };
}

/// Initialize a new greeting account
fn processInitialize(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
) ProgramResult {
    msg.msg("Initializing greeting account");

    if (accounts.len < 1) {
        msg.msg("Error: Initialize requires at least 1 account");
        return ProgramError.NotEnoughAccountKeys;
    }

    var account = &accounts[0];

    // Verify the account is owned by this program
    if (!account.owner().equals(program_id)) {
        msg.msg("Error: Account not owned by this program");
        return ProgramError.IncorrectProgramId;
    }

    // Check that the account is writable
    if (!account.isWritable()) {
        msg.msg("Error: Account must be writable");
        return ProgramError.InvalidAccountData;
    }

    // Check that the account is a signer
    if (!account.isSigner()) {
        msg.msg("Error: Account must be a signer");
        return ProgramError.MissingRequiredSignature;
    }

    // Check account has enough space
    const required_space = @sizeOf(GreetingAccount);
    const account_data = account.getData();
    if (account_data.len < required_space) {
        msg.msgf("Error: Account too small. Need {} bytes, got {}", .{ required_space, account_data.len });
        return ProgramError.AccountDataTooSmall;
    }

    // Get mutable data
    const data = account.getDataMut() catch {
        msg.msg("Error: Failed to get mutable account data");
        return ProgramError.AccountBorrowFailed;
    };

    // Cast to our account structure
    const greeting_account = @as(*GreetingAccount, @ptrCast(@alignCast(data.ptr)));

    // Check if already initialized
    if (greeting_account.isInitialized()) {
        msg.msg("Error: Account already initialized");
        return ProgramError.AccountAlreadyInitialized;
    }

    // Initialize the account
    greeting_account.* = GreetingAccount.init();

    msg.msg("Successfully initialized greeting account");
    msg.msgf("Default message: {s}", .{greeting_account.getMessage()});

    return;
}

/// Update the greeting message
fn processUpdateGreeting(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    new_message: []const u8,
) ProgramResult {
    msg.msg("Updating greeting message");

    if (accounts.len < 1) {
        msg.msg("Error: UpdateGreeting requires at least 1 account");
        return ProgramError.NotEnoughAccountKeys;
    }

    var account = &accounts[0];

    // Verify ownership
    if (!account.owner().equals(program_id)) {
        msg.msg("Error: Account not owned by this program");
        return ProgramError.IncorrectProgramId;
    }

    // Check writable
    if (!account.isWritable()) {
        msg.msg("Error: Account must be writable");
        return ProgramError.InvalidAccountData;
    }

    // Check signer
    if (!account.isSigner()) {
        msg.msg("Error: Account must be a signer");
        return ProgramError.MissingRequiredSignature;
    }

    // Get mutable data
    const data = account.getDataMut() catch {
        msg.msg("Error: Failed to get mutable account data");
        return ProgramError.AccountBorrowFailed;
    };

    // Cast to account structure
    const greeting_account = @as(*GreetingAccount, @ptrCast(@alignCast(data.ptr)));

    // Check initialized
    if (!greeting_account.isInitialized()) {
        msg.msg("Error: Account not initialized");
        return ProgramError.UninitializedAccount;
    }

    // Validate new message length
    if (new_message.len > 32) {
        msg.msgf("Error: Message too long. Max 32 bytes, got {}", .{new_message.len});
        return ProgramError.InvalidInstructionData;
    }

    // Clear old message
    @memset(&greeting_account.message, 0);

    // Copy new message
    if (new_message.len > 0) {
        @memcpy(greeting_account.message[0..new_message.len], new_message);
    }

    // Increment greeting count
    greeting_account.greeting_count += 1;

    msg.msgf("Updated message to: {s}", .{greeting_account.getMessage()});
    msg.msgf("Total updates: {}", .{greeting_account.greeting_count});

    return;
}

/// Say hello - logs the current greeting
fn processSayHello(accounts: []AccountInfo) ProgramResult {
    msg.msg("Saying hello!");

    if (accounts.len < 1) {
        // No account provided, just say generic hello
        msg.msg("Hello, Solana from Zig!");
        msg.msg("No greeting account provided, using default message");
        return;
    }

    const account = &accounts[0];
    const account_data = account.getData();

    // Check if we have enough data for a greeting account
    if (account_data.len < @sizeOf(GreetingAccount)) {
        msg.msg("Hello, Solana from Zig!");
        msg.msg("Account too small to contain greeting data");
        return;
    }

    // Try to read greeting account
    const greeting_account = @as(*const GreetingAccount, @ptrCast(@alignCast(account_data.ptr)));

    if (greeting_account.isInitialized()) {
        // Use stored greeting
        msg.msgf("Greeting: {s}", .{greeting_account.getMessage()});
        msg.msgf("This greeting has been updated {} times", .{greeting_account.greeting_count});

        // Show account details
        msg.msgf("Account owner: {}", .{account.owner()});
        msg.msgf("Account lamports: {}", .{account.getLamports()});
    } else {
        // Account not initialized, use default
        msg.msg("Hello, Solana from Zig!");
        msg.msg("(Account not initialized with greeting data)");
    }

    return;
}

// Declare the program entrypoint
comptime {
    solana.declareEntrypoint(process_instruction);
}

// ============================================================================
// Tests
// ============================================================================

test "GreetingAccount initialization" {
    const testing = std.testing;

    var account = GreetingAccount.init();
    try testing.expect(account.isInitialized());
    try testing.expectEqual(@as(u32, 0), account.greeting_count);
    try testing.expectEqualStrings("Hello, Solana!", account.getMessage());
}

test "GreetingAccount message update" {
    const testing = std.testing;

    var account = GreetingAccount.init();

    // Update message
    const new_msg = "Zig rocks!";
    @memset(&account.message, 0);
    @memcpy(account.message[0..new_msg.len], new_msg);
    account.greeting_count += 1;

    try testing.expectEqualStrings("Zig rocks!", account.getMessage());
    try testing.expectEqual(@as(u32, 1), account.greeting_count);
}

test "HelloInstruction parsing" {
    const testing = std.testing;

    try testing.expectEqual(HelloInstruction.Initialize, HelloInstruction.fromU8(0));
    try testing.expectEqual(HelloInstruction.UpdateGreeting, HelloInstruction.fromU8(1));
    try testing.expectEqual(HelloInstruction.SayHello, HelloInstruction.fromU8(2));
    try testing.expectEqual(@as(?HelloInstruction, null), HelloInstruction.fromU8(99));
}
