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

/// Input parser - optimized to avoid unnecessary copies
pub fn parseInput(
    input: [*]const u8,
    accounts_buf: *[MAX_ACCOUNTS]AccountInfo,
    raw_accounts_buf: *[MAX_ACCOUNTS]account_info.RawAccountInfo,
) struct {
    accounts: []AccountInfo,
    num_accounts: usize,
    instruction_data: []const u8,
    program_id: *const Pubkey,
} {
    var offset: usize = 0;

    // Read number of accounts
    const num_accounts = std.mem.readInt(u64, input[offset..][0..8], .little);
    offset += 8;

    // Parse accounts - skip AccountData entirely!
    for (0..num_accounts) |i| {
        const dup_info = input[offset];
        offset += 1;

        if (dup_info != 0xFF) {
            // Duplicate
            offset += 7;
            accounts_buf[i] = accounts_buf[dup_info];
            raw_accounts_buf[i] = raw_accounts_buf[dup_info];
        } else {
            const account_ptr = input + offset;

            // Ultra-minimal parsing - only read what's absolutely needed
            const data_len = std.mem.readInt(u64, account_ptr[79..87], .little);
            const data_ptr = @as([*]u8, @constCast(account_ptr + 87));

            // Debug: Log the raw bytes
            // msg.msgf("Raw bytes [0-3]: {} {} {} {}", .{account_ptr[0], account_ptr[1], account_ptr[2], account_ptr[3]});

            // Create RawAccountInfo with lazy pointer calculations
            raw_accounts_buf[i] = account_info.RawAccountInfo{
                .id = @ptrCast(account_ptr + 7),
                .lamports = @ptrCast(@constCast(account_ptr + 71)),
                .data_len = data_len,
                .data = data_ptr,
                .owner_id = @ptrCast(account_ptr + 39),
                .rent_epoch = 0,
                .is_signer = account_ptr[0],
                .is_writable = account_ptr[1],
                .is_executable = account_ptr[2],
            };

            // Create minimal AccountInfo with raw pointer
            accounts_buf[i] = AccountInfo{
                .data_ptr = @ptrFromInt(8), // Aligned dummy pointer
                .data_buffer = data_ptr,
                .raw_ptr = &raw_accounts_buf[i],
            };

            // Skip to next account
            offset += 87 + data_len + ACCOUNT_DATA_PADDING + 8;
            offset = (offset + 7) & ~@as(usize, 7);
        }
    }

    // Parse instruction data
    const data_len = std.mem.readInt(u64, input[offset..][0..8], .little);
    offset += 8;
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
/// Uses fast parsing that avoids AccountData creation for optimal performance
///
/// Example:
/// ```zig
/// const entrypoint = @import("solana_sdk_zig").entrypoint;
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
            // Fast path: no AccountData buffer for optimal CU usage
            var accounts_buf: [MAX_ACCOUNTS]AccountInfo = undefined;
            var raw_accounts_buf: [MAX_ACCOUNTS]account_info.RawAccountInfo = undefined;

            // Parse with optimized parser that avoids copying
            const parsed = parseInput(input, &accounts_buf, &raw_accounts_buf);

            // Direct call
            const result = process_instruction(
                parsed.program_id,
                parsed.accounts,
                parsed.instruction_data,
            );

            return program_error.resultToU64(result);
        }
    };
    _ = &S.entrypoint;
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
    var input_buffer = [_]u8{0} ** 20000;
    var offset: usize = 0;

    // Number of accounts (u64) = 1
    const num_accounts: u64 = 1;
    @memcpy(input_buffer[offset .. offset + 8], std.mem.asBytes(&num_accounts));
    offset += 8;

    // Account 0 - not a duplicate (0xFF marker)
    input_buffer[offset] = 0xFF;
    offset += 1;

    // Build account in the format parseInput expects (87 bytes before data)
    const account_start = offset;

    // [0]: is_signer
    input_buffer[account_start + 0] = 1;

    // [1]: is_writable
    input_buffer[account_start + 1] = 1;

    // [2]: is_executable
    input_buffer[account_start + 2] = 0;

    // [3]: unused/padding
    input_buffer[account_start + 3] = 0;

    // [4-6]: padding (3 bytes)
    // Already zero from initialization

    // [7-38]: Pubkey (32 bytes)
    const test_pubkey = Pubkey.fromBytes([_]u8{1} ** 32);
    @memcpy(input_buffer[account_start + 7 .. account_start + 39], &test_pubkey.bytes);

    // [39-70]: Owner (32 bytes)
    const owner_pubkey = Pubkey.fromBytes([_]u8{2} ** 32);
    @memcpy(input_buffer[account_start + 39 .. account_start + 71], &owner_pubkey.bytes);

    // [71-78]: Lamports (8 bytes)
    const lamports: u64 = 1000;
    @memcpy(input_buffer[account_start + 71 .. account_start + 79], std.mem.asBytes(&lamports));

    // [79-86]: Data length (8 bytes)
    const data_len: u64 = 10;
    @memcpy(input_buffer[account_start + 79 .. account_start + 87], std.mem.asBytes(&data_len));

    // [87+]: Data
    for (0..10) |i| {
        input_buffer[account_start + 87 + i] = @as(u8, @intCast(i * 2));
    }

    offset = account_start + 87 + 10; // Account header + data

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
    var raw_accounts_buf: [MAX_ACCOUNTS]account_info.RawAccountInfo = undefined;

    // Parse the input
    const parsed = parseInput(&input_buffer, &accounts_buf, &raw_accounts_buf);

    // Check if parsing succeeded at all
    if (parsed.num_accounts == 0) {
        std.debug.print("ERROR: No accounts parsed\n", .{});
        return error.TestFailed;
    }

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
