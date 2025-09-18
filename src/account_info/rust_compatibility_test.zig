// Test that Zig can parse Rust-generated serialized account data
const std = @import("std");
const account_info = @import("account_info.zig");
const AccountInfo = account_info.AccountInfo;
const AccountData = account_info.AccountData;
const AccountIterator = account_info.AccountIterator;
const ParsedAccounts = account_info.ParsedAccounts;
const parseAccounts = account_info.parseAccounts;
const NON_DUP_MARKER = account_info.NON_DUP_MARKER;
const pubkey = @import("../pubkey/pubkey.zig");
const Pubkey = pubkey.Pubkey;

test "parse Rust empty data accounts" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Read the Rust-generated file
    const file = try std.fs.cwd().openFile("test_data/empty_data_accounts.bin", .{});
    defer file.close();

    const file_content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(file_content);

    // Parse the accounts
    var parsed = try parseAccounts(file_content.ptr, allocator);
    defer parsed.deinit();

    // Verify we have 2 accounts
    try testing.expectEqual(@as(usize, 2), parsed.accounts.len);

    // First account has empty data
    try testing.expectEqual(@as(u64, 0), parsed.accounts[0].dataLen());
    try testing.expectEqual(@as(usize, 0), parsed.accounts[0].getData().len);
    try testing.expect(parsed.accounts[0].isSigner());
    try testing.expect(parsed.accounts[0].isWritable());
    try testing.expectEqual(@as(u64, 1000), parsed.accounts[0].getLamports());

    // Second account has data
    try testing.expectEqual(@as(u64, 4), parsed.accounts[1].dataLen());
    const data = parsed.accounts[1].getData();
    try testing.expectEqual(@as(usize, 4), data.len);
    for (data) |byte| {
        try testing.expectEqual(@as(u8, 0xFF), byte);
    }
    try testing.expect(!parsed.accounts[1].isSigner());
    try testing.expect(!parsed.accounts[1].isWritable());
    try testing.expect(parsed.accounts[1].isExecutable());
    try testing.expectEqual(@as(u64, 2000), parsed.accounts[1].getLamports());
}

test "parse Rust Solana format single account" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Read the Solana runtime format file
    const file = try std.fs.cwd().openFile("test_data/solana_single_account.bin", .{});
    defer file.close();

    const file_content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(file_content);

    // Parse the accounts
    var parsed = try parseAccounts(file_content.ptr, allocator);
    defer parsed.deinit();

    // Verify we have 1 account
    try testing.expectEqual(@as(usize, 1), parsed.accounts.len);

    // Verify account properties
    const acc = parsed.accounts[0];
    try testing.expect(acc.isSigner());
    try testing.expect(acc.isWritable());
    try testing.expect(!acc.isExecutable());
    try testing.expectEqual(@as(u64, 1000), acc.getLamports());
    try testing.expectEqual(@as(u64, 10), acc.dataLen());

    // Verify account data contains 0xAA bytes
    const data = acc.getData();
    try testing.expectEqual(@as(usize, 10), data.len);
    for (data) |byte| {
        try testing.expectEqual(@as(u8, 0xAA), byte);
    }
}

test "parse Rust Solana format actual AccountInfo" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Read the file created from actual AccountInfo instances
    const file = try std.fs.cwd().openFile("test_data/solana_actual_accountinfo.bin", .{});
    defer file.close();

    const file_content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(file_content);

    // Parse the accounts
    var parsed = try parseAccounts(file_content.ptr, allocator);
    defer parsed.deinit();

    // Verify we have 2 accounts
    try testing.expectEqual(@as(usize, 2), parsed.accounts.len);

    // Verify first account - created with AccountInfo::new
    const acc1 = parsed.accounts[0];
    try testing.expect(acc1.isSigner());
    try testing.expect(acc1.isWritable());
    try testing.expect(!acc1.isExecutable());
    try testing.expectEqual(@as(u64, 1000), acc1.getLamports());
    try testing.expectEqual(@as(u64, 10), acc1.dataLen());

    // Verify data is all 0xAA
    const data1 = acc1.getData();
    for (data1) |byte| {
        try testing.expectEqual(@as(u8, 0xAA), byte);
    }

    // Verify second account - created with AccountInfo::new
    const acc2 = parsed.accounts[1];
    try testing.expect(!acc2.isSigner());
    try testing.expect(!acc2.isWritable());
    try testing.expect(acc2.isExecutable());
    try testing.expectEqual(@as(u64, 2000), acc2.getLamports());
    try testing.expectEqual(@as(u64, 20), acc2.dataLen());

    // Verify data is all 0xBB
    const data2 = acc2.getData();
    for (data2) |byte| {
        try testing.expectEqual(@as(u8, 0xBB), byte);
    }
}

test "parse Rust Solana format with duplicates" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Read the Solana format file with duplicates
    const file = try std.fs.cwd().openFile("test_data/solana_accounts_with_duplicates.bin", .{});
    defer file.close();

    const file_content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(file_content);

    // Test with iterator for duplicate handling
    var accounts_buffer: [10]AccountInfo = undefined;
    var aligned_buffer: [10]AccountData = undefined;
    var iter = AccountIterator.init(file_content.ptr, 5, &accounts_buffer, &aligned_buffer);

    // Account 0: Original
    const acc0 = iter.next();
    try testing.expect(acc0 != null);
    try testing.expect(acc0.?.isSigner());
    try testing.expect(acc0.?.isWritable());
    try testing.expectEqual(@as(u64, 1000), acc0.?.getLamports());

    // Account 1: Original
    const acc1 = iter.next();
    try testing.expect(acc1 != null);
    try testing.expect(!acc1.?.isSigner());
    try testing.expect(acc1.?.isWritable());
    try testing.expect(acc1.?.isExecutable());
    try testing.expectEqual(@as(u64, 2000), acc1.?.getLamports());

    // Account 2: Duplicate of account 0
    const acc2 = iter.next();
    try testing.expect(acc2 != null);
    try testing.expectEqual(@as(u64, 1000), acc2.?.getLamports());

    // Account 3: Original
    const acc3 = iter.next();
    try testing.expect(acc3 != null);
    try testing.expect(acc3.?.isSigner());
    try testing.expect(!acc3.?.isWritable());
    try testing.expectEqual(@as(u64, 3000), acc3.?.getLamports());

    // Account 4: Duplicate of account 1
    const acc4 = iter.next();
    try testing.expect(acc4 != null);
    try testing.expectEqual(@as(u64, 2000), acc4.?.getLamports());
}

test "verify Rust AccountData structure size" {
    const testing = std.testing;

    // Verify that our AccountData matches the Rust structure
    try testing.expectEqual(@as(usize, 88), @sizeOf(AccountData));
    try testing.expectEqual(@as(usize, 8), @alignOf(AccountData));

    // Verify field offsets match what Rust generates
    const dummy = AccountData{
        .duplicate_index = 0,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
        .original_data_len = 0,
        .id = Pubkey.ZEROES,
        .owner_id = Pubkey.ZEROES,
        .lamports = 0,
        .data_len = 0,
    };

    const base = @intFromPtr(&dummy);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(&dummy.duplicate_index) - base);
    try testing.expectEqual(@as(usize, 1), @intFromPtr(&dummy.is_signer) - base);
    try testing.expectEqual(@as(usize, 2), @intFromPtr(&dummy.is_writable) - base);
    try testing.expectEqual(@as(usize, 3), @intFromPtr(&dummy.is_executable) - base);
    try testing.expectEqual(@as(usize, 4), @intFromPtr(&dummy.original_data_len) - base);
    try testing.expectEqual(@as(usize, 8), @intFromPtr(&dummy.id) - base);
    try testing.expectEqual(@as(usize, 40), @intFromPtr(&dummy.owner_id) - base);
    try testing.expectEqual(@as(usize, 72), @intFromPtr(&dummy.lamports) - base);
    try testing.expectEqual(@as(usize, 80), @intFromPtr(&dummy.data_len) - base);

    // Print debug info based on environment or build mode
    const builtin = @import("builtin");
    var should_print = !builtin.is_test;

    // Check build option in test mode
    if (builtin.is_test) {
        const build_options = @import("build_options");
        should_print = build_options.show_test_output;
    }

    if (should_print) {
        std.debug.print("\n=== Rust Compatibility Test ===\n", .{});
        std.debug.print("✓ AccountData size: {} bytes (matches Rust)\n", .{@sizeOf(AccountData)});
        std.debug.print("✓ AccountData alignment: {} bytes (matches Rust)\n", .{@alignOf(AccountData)});
        std.debug.print("✓ All field offsets match Rust layout\n", .{});
    }
}
