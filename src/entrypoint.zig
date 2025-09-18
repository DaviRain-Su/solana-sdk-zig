/// Standard entrypoint for Solana programs
///
/// This module provides the standard entrypoint implementation,
/// parsing all accounts upfront like Rust's `entrypoint!` macro
const std = @import("std");
const account_info = @import("account_info/account_info.zig");
const pubkey = @import("pubkey/pubkey.zig");
const program_error = @import("program_error.zig");
const msg = @import("msg/msg.zig");

const AccountInfo = account_info.AccountInfo;
const AccountData = account_info.AccountData;
const Pubkey = pubkey.Pubkey;
const ProgramError = program_error.ProgramError;
const ProgramResult = program_error.ProgramResult;

/// Maximum number of accounts that can be passed to a program
/// Note: Reduced from 64 to 16 to fit within Solana's stack limit
pub const MAX_ACCOUNTS = 16;

/// Process instruction function type
pub const ProcessInstruction = fn (
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    instruction_data: []const u8,
) ProgramResult;

/// Raw input parser - parses the input buffer from Solana runtime
pub fn parseInput(input: [*]const u8) struct {
    accounts: []AccountInfo,
    num_accounts: usize,
    instruction_data: []const u8,
    program_id: *const Pubkey,
} {
    var offset: usize = 0;

    // Read number of accounts (u64)
    const num_accounts = @as(*const u64, @ptrCast(@alignCast(input + offset))).*;
    offset += 8;

    // We'll store account infos in a static buffer
    // In a real implementation, these would be allocated properly
    var accounts_buf: [MAX_ACCOUNTS]AccountInfo = undefined;
    var account_data_buf: [MAX_ACCOUNTS]AccountData = undefined;

    // Parse each account
    for (0..num_accounts) |i| {
        const is_duplicate = input[offset];
        offset += 1;

        if (is_duplicate != 0) {
            // This is a duplicate account
            const duplicate_index = input[offset];
            offset += 1;

            // Copy the reference
            accounts_buf[i] = accounts_buf[duplicate_index];
            account_data_buf[i] = account_data_buf[duplicate_index];
        } else {
            // Parse full account info
            var acc_data = &account_data_buf[i];

            // Flags
            acc_data.is_signer = input[offset];
            offset += 1;
            acc_data.is_writable = input[offset];
            offset += 1;
            acc_data.is_executable = input[offset];
            offset += 1;

            // Original data length (4 bytes)
            acc_data.original_data_len = @as(*const u32, @ptrCast(@alignCast(input + offset))).*;
            offset += 4;

            // Pubkey (32 bytes)
            acc_data.id = @as(*const Pubkey, @ptrCast(@alignCast(input + offset))).*;
            offset += 32;

            // Owner (32 bytes)
            acc_data.owner_id = @as(*const Pubkey, @ptrCast(@alignCast(input + offset))).*;
            offset += 32;

            // Lamports (8 bytes)
            acc_data.lamports = @as(*const u64, @ptrCast(@alignCast(input + offset))).*;
            offset += 8;

            // Data length (8 bytes)
            acc_data.data_len = @as(*const u64, @ptrCast(@alignCast(input + offset))).*;
            offset += 8;

            // Data pointer - this points to the actual data
            const data_ptr = @as([*]u8, @ptrFromInt(@intFromPtr(input + offset)));
            offset += acc_data.data_len;

            // Padding to 8-byte alignment
            const padding = (8 - (acc_data.data_len % 8)) % 8;
            offset += padding;

            // Skip rent epoch for now (8 bytes)
            offset += 8;

            // Mark as not duplicate
            acc_data.duplicate_index = 0xFF;

            // Create AccountInfo
            accounts_buf[i] = AccountInfo.fromDataPtr(acc_data, data_ptr);
        }
    }

    // Parse instruction data length
    const data_len = @as(*const u64, @ptrCast(@alignCast(input + offset))).*;
    offset += 8;

    // Get instruction data slice
    const instruction_data = input[offset .. offset + data_len];
    offset += data_len;

    // Parse program ID
    const program_id = @as(*const Pubkey, @ptrCast(@alignCast(input + offset)));

    return .{
        .accounts = accounts_buf[0..num_accounts],
        .num_accounts = num_accounts,
        .instruction_data = instruction_data,
        .program_id = program_id,
    };
}

/// Declare a standard entrypoint for a Solana program
///
/// Example:
/// ```zig
/// const entrypoint = @import("pinocchio").entrypoint;
///
/// pub fn process_instruction(
///     program_id: *const Pubkey,
///     accounts: []const AccountInfo,
///     instruction_data: []const u8,
/// ) ProgramResult {
///     // Your program logic here
///     return .Success;
/// }
///
/// // Create and export the entrypoint
/// comptime {
///     entrypoint.declareEntrypoint(process_instruction);
/// }
/// ```
pub fn declareEntrypoint(comptime process_instruction: ProcessInstruction) void {
    const S = struct {
        pub export fn entrypoint(input: [*]const u8) callconv(.C) u64 {
            // Parse the input
            const parsed = parseInput(input);

            // Call the user's process instruction function
            const result = process_instruction(
                parsed.program_id,
                parsed.accounts,
                parsed.instruction_data,
            );

            // Convert result to u64
            return program_error.resultToU64(result);
        }
    };
    _ = &S.entrypoint; // Force the export
}

/// Helper macro-like function for simple entrypoint declaration
pub inline fn entrypoint(comptime process_instruction: ProcessInstruction) void {
    declareEntrypoint(process_instruction);
}

// ============================================================================
// Utility functions
// ============================================================================

/// No-op processor for testing
pub fn noOpProcessor(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    instruction_data: []const u8,
) ProgramResult {
    _ = program_id;
    _ = accounts;
    _ = instruction_data;
    return;
}

// ============================================================================
// Tests
// ============================================================================

test "basic entrypoint parsing" {
    const testing = std.testing;

    // Create a mock input buffer
    var input_buffer = [_]u8{0} ** 512;
    var offset: usize = 0;

    // Number of accounts (u64) = 1
    const num_accounts: u64 = 1;
    @memcpy(input_buffer[offset .. offset + 8], std.mem.asBytes(&num_accounts));
    offset += 8;

    // Account 0 - not a duplicate
    input_buffer[offset] = 0;
    offset += 1;

    // Account flags
    input_buffer[offset] = 1; // is_signer
    offset += 1;
    input_buffer[offset] = 1; // is_writable
    offset += 1;
    input_buffer[offset] = 0; // executable
    offset += 1;

    // Original data length (u32)
    const orig_data_len: u32 = 100;
    @memcpy(input_buffer[offset .. offset + 4], std.mem.asBytes(&orig_data_len));
    offset += 4;

    // Pubkey (32 bytes)
    const test_pubkey = Pubkey.fromBytes([_]u8{1} ** 32);
    @memcpy(input_buffer[offset .. offset + 32], &test_pubkey.bytes);
    offset += 32;

    // Owner (32 bytes)
    const owner_pubkey = Pubkey.fromBytes([_]u8{2} ** 32);
    @memcpy(input_buffer[offset .. offset + 32], &owner_pubkey.bytes);
    offset += 32;

    // Lamports (u64)
    const lamports: u64 = 1000;
    @memcpy(input_buffer[offset .. offset + 8], std.mem.asBytes(&lamports));
    offset += 8;

    // Data length (u64)
    const data_len: u64 = 10;
    @memcpy(input_buffer[offset .. offset + 8], std.mem.asBytes(&data_len));
    offset += 8;

    // Data (10 bytes)
    for (0..10) |i| {
        input_buffer[offset + i] = @as(u8, @intCast(i * 2));
    }
    offset += 10;

    // Padding to 8-byte alignment
    offset += 6; // (8 - (10 % 8)) = 6

    // Rent epoch (u64)
    const rent_epoch: u64 = 100;
    @memcpy(input_buffer[offset .. offset + 8], std.mem.asBytes(&rent_epoch));
    offset += 8;

    // Instruction data length (u64)
    const ix_data_len: u64 = 4;
    @memcpy(input_buffer[offset .. offset + 8], std.mem.asBytes(&ix_data_len));
    offset += 8;

    // Instruction data (4 bytes)
    input_buffer[offset] = 0xAA;
    input_buffer[offset + 1] = 0xBB;
    input_buffer[offset + 2] = 0xCC;
    input_buffer[offset + 3] = 0xDD;
    offset += 4;

    // Program ID (32 bytes)
    const program_pubkey = Pubkey.fromBytes([_]u8{3} ** 32);
    @memcpy(input_buffer[offset .. offset + 32], &program_pubkey.bytes);

    // Parse the input
    const parsed = parseInput(&input_buffer);

    // Verify parsing
    try testing.expectEqual(@as(usize, 1), parsed.num_accounts);
    try testing.expectEqual(@as(usize, 1), parsed.accounts.len);

    const acc = &parsed.accounts[0];
    try testing.expect(acc.isSigner());
    try testing.expect(acc.isWritable());
    try testing.expect(!acc.isExecutable());
    try testing.expectEqual(@as(u64, 1000), acc.getLamports());

    try testing.expectEqual(@as(usize, 4), parsed.instruction_data.len);
    try testing.expectEqual(@as(u8, 0xAA), parsed.instruction_data[0]);

    try testing.expect(parsed.program_id.equals(&program_pubkey));
}

test "entrypoint macro usage" {
    // This just tests that the macro compiles
    const S = struct {
        fn process(
            program_id: *const Pubkey,
            accounts: []AccountInfo,
            data: []const u8,
        ) ProgramResult {
            _ = program_id;
            _ = accounts;
            _ = data;
            return;
        }
    };

    // This would normally be at module level
    comptime {
        entrypoint(S.process);
    }
}
