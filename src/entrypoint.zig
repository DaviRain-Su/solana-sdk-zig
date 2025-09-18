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

/// Account data padding - Solana adds 10KB padding after account data
pub const ACCOUNT_DATA_PADDING = 10 * 1024;

/// Process instruction function type
pub const ProcessInstruction = fn (
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    instruction_data: []const u8,
) ProgramResult;

/// Raw input parser - parses the input buffer from Solana runtime
pub fn parseInput(
    input: [*]const u8,
    accounts_buf: *[MAX_ACCOUNTS]AccountInfo,
    account_data_buf: *[MAX_ACCOUNTS]AccountData,
) struct {
    accounts: []AccountInfo,
    num_accounts: usize,
    instruction_data: []const u8,
    program_id: *const Pubkey,
} {
    var offset: usize = 0;

    // Read number of accounts (u64) - unaligned read
    const num_accounts = std.mem.readInt(u64, input[offset..][0..8], .little);
    offset += 8;

    // Parse each account
    for (0..num_accounts) |i| {
        const dup_info = input[offset];
        offset += 1;

        if (dup_info != 0xFF) {
            // This is a duplicate account
            offset += 7; // padding
            accounts_buf[i] = accounts_buf[dup_info];
            account_data_buf[i] = account_data_buf[dup_info];
        } else {
            // Parse account info
            const is_signer = input[offset];
            offset += 1;
            const is_writable = input[offset];
            offset += 1;
            const is_executable = input[offset];
            offset += 1;

            // Original data length (4 bytes) - skip padding
            const original_data_len = std.mem.readInt(u32, input[offset..][0..4], .little);
            offset += 4;

            // Pubkey (32 bytes)
            const key = @as(*align(1) const Pubkey, @ptrCast(input + offset));
            offset += 32;

            // Owner (32 bytes)
            const owner = @as(*align(1) const Pubkey, @ptrCast(input + offset));
            offset += 32;

            // Lamports (8 bytes)
            const lamports = std.mem.readInt(u64, input[offset..][0..8], .little);
            offset += 8;

            // Data length (8 bytes)
            const data_len = std.mem.readInt(u64, input[offset..][0..8], .little);
            offset += 8;

            // Data pointer
            const data_ptr = @as([*]u8, @constCast(input + offset));

            // Skip data + padding + rent epoch
            offset += data_len + ACCOUNT_DATA_PADDING + @sizeOf(u64);

            // Align to BPF_ALIGN_OF_U128 (8 bytes)
            const alignment_offset = @intFromPtr(input + offset) & 7;
            if (alignment_offset != 0) {
                offset += 8 - alignment_offset;
            }

            // Store account data
            account_data_buf[i] = AccountData{
                .duplicate_index = 0xFF,
                .is_signer = is_signer,
                .is_writable = is_writable,
                .is_executable = is_executable,
                .original_data_len = original_data_len,
                .id = key.*,
                .owner_id = owner.*,
                .lamports = lamports,
                .data_len = data_len,
            };

            // Create AccountInfo
            accounts_buf[i] = AccountInfo.fromDataPtr(&account_data_buf[i], data_ptr);
        }
    }

    // Parse instruction data length - unaligned read
    const data_len = std.mem.readInt(u64, input[offset..][0..8], .little);
    offset += 8;

    // Get instruction data slice
    const instruction_data = input[offset .. offset + data_len];
    offset += data_len;

    // Parse program ID
    const program_id = @as(*align(1) const Pubkey, @ptrCast(input + offset));

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
            // Allocate buffers on the stack of the entrypoint function
            var accounts_buf: [MAX_ACCOUNTS]AccountInfo = undefined;
            var account_data_buf: [MAX_ACCOUNTS]AccountData = undefined;

            // Parse the input
            const parsed = parseInput(input, &accounts_buf, &account_data_buf);

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

    // Create a mock input buffer (needs to be large enough for ACCOUNT_DATA_PADDING)
    var input_buffer = [_]u8{0} ** (512 + ACCOUNT_DATA_PADDING);
    var offset: usize = 0;

    // Number of accounts (u64) = 1
    const num_accounts: u64 = 1;
    @memcpy(input_buffer[offset .. offset + 8], std.mem.asBytes(&num_accounts));
    offset += 8;

    // Account 0 - not a duplicate (0xFF marker)
    input_buffer[offset] = 0xFF;
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

    // Account data padding (10KB)
    offset += ACCOUNT_DATA_PADDING;

    // Rent epoch (u64)
    const rent_epoch: u64 = 100;
    @memcpy(input_buffer[offset .. offset + 8], std.mem.asBytes(&rent_epoch));
    offset += 8;

    // Align to 8-byte boundary
    const alignment_offset = @intFromPtr(&input_buffer[offset]) & 7;
    if (alignment_offset != 0) {
        offset += 8 - alignment_offset;
    }

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

    // Allocate buffers for parsing
    var accounts_buf: [MAX_ACCOUNTS]AccountInfo = undefined;
    var account_data_buf: [MAX_ACCOUNTS]AccountData = undefined;

    // Parse the input
    const parsed = parseInput(&input_buffer, &accounts_buf, &account_data_buf);

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
