const std = @import("std");
const pubkey = @import("../pubkey/pubkey.zig");
const Pubkey = pubkey.Pubkey;
const syscalls = @import("../syscalls.zig");
const ProgramError = @import("../program_error.zig").ProgramError;

/// Maximum number of bytes a program may add to an account during a single instruction
pub const MAX_PERMITTED_DATA_INCREASE: usize = 1_024 * 10;

/// Maximum number of accounts that a transaction can process
pub const MAX_TX_ACCOUNTS: usize = 254; // u8::MAX - 1

/// Non-duplicated account marker
pub const NON_DUP_MARKER: u8 = 0b11111111;

/// Account data structure as serialized by Solana runtime
/// This matches the exact layout used in solana-program-sdk-zig
/// Total size: 88 bytes
pub const AccountData = extern struct {
    duplicate_index: u8,
    is_signer: u8,
    is_writable: u8,
    is_executable: u8,
    original_data_len: u32,
    id: Pubkey,
    owner_id: Pubkey,
    lamports: u64,
    data_len: u64,

    comptime {
        if (@sizeOf(AccountData) != 88) {
            @compileError("AccountData must be 88 bytes");
        }
        if (@alignOf(AccountData) != 8) {
            @compileError("AccountData must be 8-byte aligned");
        }
    }
};

/// Raw account info structure as it appears in the input buffer
/// This is what we need to pass to CPI - with pointers to Pubkeys
pub const RawAccountInfo = extern struct {
    id: *const Pubkey,
    lamports: *align(1) u64,  // Unaligned pointer from input buffer
    data_len: u64,
    data: [*]u8,
    owner_id: *const Pubkey,
    rent_epoch: u64,
    is_signer: u8,
    is_writable: u8,
    is_executable: u8,
};

/// AccountInfo - The primary interface for account access
/// This struct provides a view into account data with methods for safe access
pub const AccountInfo = struct {
    /// Pointer to the raw account data (may be dummy in fast mode)
    data_ptr: *align(8) AccountData,

    /// Pointer to the actual data buffer
    data_buffer: [*]u8,

    /// Direct pointer to RawAccountInfo for CPI and optimized access
    /// When non-null, this is used instead of data_ptr for key/owner access
    raw_ptr: ?*const RawAccountInfo = null,

    /// Create AccountInfo from a pointer to AccountData
    pub fn fromDataPtr(ptr: *align(8) AccountData, data_buffer: [*]u8) AccountInfo {
        return .{
            .data_ptr = ptr,
            .data_buffer = data_buffer,
            .raw_ptr = null,
        };
    }

    /// Create AccountInfo with raw pointer for optimization
    pub fn fromDataPtrWithRaw(ptr: *align(8) AccountData, data_buffer: [*]u8, raw: *const RawAccountInfo) AccountInfo {
        return .{
            .data_ptr = ptr,
            .data_buffer = data_buffer,
            .raw_ptr = raw,
        };
    }

    /// Get the account's public key
    pub inline fn key(self: *const AccountInfo) *const Pubkey {
        // Use raw_ptr if available (avoids copy)
        if (self.raw_ptr) |raw| {
            return raw.id;
        }
        return &self.data_ptr.id;
    }

    /// Get lamports (read-only)
    pub inline fn getLamports(self: *const AccountInfo) u64 {
        return self.data_ptr.lamports;
    }

    /// Get mutable lamports pointer (requires writable)
    pub fn getLamportsMut(self: *AccountInfo) !*u64 {
        if (!self.isWritable()) {
            return error.AccountNotWritable;
        }
        return &self.data_ptr.lamports;
    }

    /// Get the owner public key
    pub inline fn owner(self: *const AccountInfo) *const Pubkey {
        // Use raw_ptr if available (avoids copy)
        if (self.raw_ptr) |raw| {
            return raw.owner_id;
        }
        return &self.data_ptr.owner_id;
    }

    /// Assign new owner (requires writable)
    pub fn assign(self: *AccountInfo, new_owner: *const Pubkey) !void {
        if (!self.isWritable()) {
            return error.AccountNotWritable;
        }
        self.data_ptr.owner_id = new_owner.*;
    }

    /// Get account data as slice
    pub fn getData(self: *const AccountInfo) []const u8 {
        return self.data_buffer[0..self.data_ptr.data_len];
    }

    /// Get mutable account data (requires writable)
    pub fn getDataMut(self: *AccountInfo) ![]u8 {
        if (!self.isWritable()) {
            return error.AccountNotWritable;
        }
        return self.data_buffer[0..self.data_ptr.data_len];
    }

    /// Check if account is writable
    pub inline fn isWritable(self: *const AccountInfo) bool {
        return self.data_ptr.is_writable != 0;
    }

    /// Check if account is executable
    pub inline fn isExecutable(self: *const AccountInfo) bool {
        return self.data_ptr.is_executable != 0;
    }

    /// Check if account is signer
    pub inline fn isSigner(self: *const AccountInfo) bool {
        return self.data_ptr.is_signer != 0;
    }

    /// Get data length
    pub inline fn dataLen(self: *const AccountInfo) u64 {
        return self.data_ptr.data_len;
    }

    /// Get original data length before any realloc
    pub inline fn originalDataLen(self: *const AccountInfo) u32 {
        return self.data_ptr.original_data_len;
    }

    /// Reallocate account data
    pub fn realloc(self: *AccountInfo, new_len: usize, zero_init: bool) !void {
        if (!self.isWritable()) {
            return error.AccountNotWritable;
        }

        const old_len = self.data_ptr.data_len;

        // Check maximum increase
        if (new_len > old_len) {
            const increase = new_len - old_len;
            if (increase > MAX_PERMITTED_DATA_INCREASE) {
                return error.ExceedsMaxDataIncrease;
            }
        }

        // Update length
        self.data_ptr.data_len = new_len;

        // Zero new memory if requested
        if (zero_init and new_len > old_len) {
            const new_data = self.data_buffer[old_len..new_len];
            @memset(new_data, 0);
        }
    }

    /// Set executable flag (requires writable)
    pub fn setExecutable(self: *AccountInfo, exe: bool) !void {
        if (!self.isWritable()) {
            return error.AccountNotWritable;
        }
        self.data_ptr.is_executable = if (exe) 1 else 0;
    }

    /// Check if this account's key matches the provided key
    pub inline fn keyEquals(self: *const AccountInfo, other: *const Pubkey) bool {
        return self.key().equals(other);
    }

    /// Check if this account is owned by the provided program
    pub inline fn isOwnedBy(self: *const AccountInfo, program_id: *const Pubkey) bool {
        return self.owner().equals(program_id);
    }

    /// Verify this account is a signer
    pub inline fn verifySigner(self: *const AccountInfo) !void {
        if (!self.isSigner()) {
            return error.MissingRequiredSignature;
        }
    }

    /// Verify this account is writable
    pub inline fn verifyWritable(self: *const AccountInfo) !void {
        if (!self.isWritable()) {
            return error.AccountNotWritable;
        }
    }

    /// Transfer lamports from this account to another
    pub fn transferLamports(self: *AccountInfo, to: *AccountInfo, amount: u64) !void {
        if (!self.isWritable() or !to.isWritable()) {
            return error.AccountNotWritable;
        }

        const from_lamports = try self.getLamportsMut();
        const to_lamports = try to.getLamportsMut();

        if (from_lamports.* < amount) {
            return error.InsufficientFunds;
        }

        from_lamports.* -= amount;
        to_lamports.* += amount;
    }

    /// Zero-copy cast data to a type
    pub inline fn dataAs(self: *const AccountInfo, comptime T: type) !*align(1) const T {
        const data_slice = self.getData();
        if (data_slice.len < @sizeOf(T)) {
            return error.InvalidDataLength;
        }
        return @ptrCast(@alignCast(data_slice.ptr));
    }

    /// Zero-copy cast mutable data to a type
    pub inline fn dataMutAs(self: *AccountInfo, comptime T: type) !*align(1) T {
        const data_slice = try self.getDataMut();
        if (data_slice.len < @sizeOf(T)) {
            return error.InvalidDataLength;
        }
        return @ptrCast(@alignCast(data_slice.ptr));
    }

    /// Zero-copy deserialize account data to packed struct
    pub inline fn unpack(self: *const AccountInfo, comptime T: type) !*align(1) const T {
        if (@typeInfo(T) != .@"struct") {
            @compileError("unpack requires a struct type");
        }
        return self.dataAs(T);
    }

    /// Zero-copy deserialize mutable account data to packed struct
    pub inline fn unpackMut(self: *AccountInfo, comptime T: type) !*align(1) T {
        if (@typeInfo(T) != .@"struct") {
            @compileError("unpack requires a struct type");
        }
        return self.dataMutAs(T);
    }

    /// Get duplicate index (0xFF if not a duplicate)
    pub inline fn duplicateIndex(self: *const AccountInfo) u8 {
        return self.data_ptr.duplicate_index;
    }

    /// Check if this is a duplicate account
    pub inline fn isDuplicate(self: *const AccountInfo) bool {
        return self.data_ptr.duplicate_index != NON_DUP_MARKER;
    }
};

/// Iterator for parsing multiple accounts from entrypoint input
pub const AccountIterator = struct {
    /// Raw input buffer from entrypoint
    input: [*]const u8,
    /// Current offset in buffer
    offset: usize,
    /// Number of accounts remaining
    remaining: usize,
    /// Array to track parsed accounts for duplicates
    accounts: []AccountInfo,
    /// Current account index
    current_index: usize,
    /// Buffer for aligned account data
    aligned_buffer: []AccountData,

    /// Initialize iterator
    pub fn init(input: [*]const u8, num_accounts: usize, accounts_buffer: []AccountInfo, aligned_buffer: []AccountData) AccountIterator {
        return .{
            .input = input,
            .offset = 1, // Skip the account count byte
            .remaining = num_accounts,
            .accounts = accounts_buffer,
            .current_index = 0,
            .aligned_buffer = aligned_buffer,
        };
    }

    /// Get next account
    pub fn next(self: *AccountIterator) ?AccountInfo {
        if (self.remaining == 0) return null;

        // Read duplicate marker
        const dup_marker = self.input[self.offset];
        self.offset += 1;

        if (dup_marker != NON_DUP_MARKER) {
            // This is a duplicate, return the original
            const dup_index = dup_marker;
            self.remaining -= 1;
            if (dup_index < self.current_index) {
                return self.accounts[dup_index];
            }
            return null; // Invalid duplicate index
        }

        // Parse new account - copy to aligned memory
        const account_data_ptr = @as(*align(1) const AccountData, @ptrCast(self.input + self.offset));
        self.offset += @sizeOf(AccountData);

        // Copy to aligned buffer
        if (self.current_index < self.aligned_buffer.len) {
            self.aligned_buffer[self.current_index] = account_data_ptr.*;
        }

        // Get data buffer pointer (follows AccountData)
        const data_buffer = @as([*]u8, @ptrCast(@constCast(self.input + self.offset)));
        self.offset += account_data_ptr.data_len;

        // Create AccountInfo using aligned data
        const account = AccountInfo.fromDataPtr(&self.aligned_buffer[self.current_index], data_buffer);

        // Store for potential duplicates
        if (self.current_index < self.accounts.len) {
            self.accounts[self.current_index] = account;
            self.current_index += 1;
        }

        self.remaining -= 1;
        return account;
    }

    /// Skip n accounts
    pub fn skip(self: *AccountIterator, n: usize) void {
        var i: usize = 0;
        while (i < n and self.remaining > 0) : (i += 1) {
            _ = self.next();
        }
    }
};

/// Container for parsed accounts and their aligned data
pub const ParsedAccounts = struct {
    accounts: []AccountInfo,
    aligned_data: []AccountData,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ParsedAccounts) void {
        self.allocator.free(self.accounts);
        self.allocator.free(self.aligned_data);
    }
};

/// Parse accounts from entrypoint input
pub fn parseAccounts(input: [*]const u8, allocator: std.mem.Allocator) !ParsedAccounts {
    // First byte is the number of accounts
    const num_accounts = input[0];

    // Allocate space for accounts and aligned data
    const accounts = try allocator.alloc(AccountInfo, num_accounts);
    errdefer allocator.free(accounts);

    const aligned_buffer = try allocator.alloc(AccountData, num_accounts);
    errdefer allocator.free(aligned_buffer);

    // Create iterator
    var iter = AccountIterator.init(input, num_accounts, accounts, aligned_buffer);

    // Parse all accounts
    var i: usize = 0;
    while (iter.next()) |account| : (i += 1) {
        accounts[i] = account;
    }

    return ParsedAccounts{
        .accounts = accounts[0..i],
        .aligned_data = aligned_buffer,
        .allocator = allocator,
    };
}

/// Create a test AccountInfo for unit testing
pub fn createTestAccountInfo(
    allocator: std.mem.Allocator,
    id: *const Pubkey,
    owner_id: *const Pubkey,
    lamports_value: u64,
    data_buffer: []u8,
    is_signer_flag: bool,
    is_writable_flag: bool,
    is_executable_flag: bool,
) !AccountInfo {
    const account_data = try allocator.create(AccountData);
    account_data.* = .{
        .duplicate_index = NON_DUP_MARKER,
        .is_signer = if (is_signer_flag) 1 else 0,
        .is_writable = if (is_writable_flag) 1 else 0,
        .is_executable = if (is_executable_flag) 1 else 0,
        .original_data_len = @intCast(data_buffer.len),
        .id = id.*,
        .owner_id = owner_id.*,
        .lamports = lamports_value,
        .data_len = data_buffer.len,
    };

    return AccountInfo.fromDataPtr(account_data, data_buffer.ptr);
}

test "AccountInfo basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const id = Pubkey.ZEROES;
    const owner_id = pubkey.SYSTEM_PROGRAM_ID;
    var data_buffer: [100]u8 = undefined;

    const info = try createTestAccountInfo(
        allocator,
        &id,
        &owner_id,
        1000,
        &data_buffer,
        true, // is_signer
        true, // is_writable
        false, // is_executable
    );
    defer allocator.destroy(info.data_ptr);

    try testing.expect(info.isSigner());
    try testing.expect(info.isWritable());
    try testing.expect(!info.isExecutable());
    try testing.expectEqual(@as(u64, 1000), info.getLamports());

    // Test key operations
    try testing.expect(info.keyEquals(&Pubkey.ZEROES));
    try testing.expect(info.isOwnedBy(&pubkey.SYSTEM_PROGRAM_ID));

    // Test verification functions
    try info.verifySigner();
    try info.verifyWritable();
}

test "AccountInfo zero-copy data access" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestStruct = packed struct {
        magic: u32,
        value: u64,
        flag: u8,
    };

    const id = Pubkey.ZEROES;
    const owner_id = pubkey.SYSTEM_PROGRAM_ID;

    var test_data: [@sizeOf(TestStruct)]u8 align(@alignOf(TestStruct)) = undefined;
    const test_struct = @as(*TestStruct, @ptrCast(@alignCast(&test_data)));
    test_struct.magic = 0xDEADBEEF;
    test_struct.value = 42;
    test_struct.flag = 1;

    var info = try createTestAccountInfo(
        allocator,
        &id,
        &owner_id,
        0,
        &test_data,
        false, // is_signer
        true, // is_writable
        false, // is_executable
    );
    defer allocator.destroy(info.data_ptr);

    // Test zero-copy read
    const read_struct = try info.unpack(TestStruct);
    try testing.expectEqual(@as(u32, 0xDEADBEEF), read_struct.magic);
    try testing.expectEqual(@as(u64, 42), read_struct.value);
    try testing.expectEqual(@as(u8, 1), read_struct.flag);

    // Test zero-copy write
    const write_struct = try info.unpackMut(TestStruct);
    write_struct.value = 100;

    // Verify change
    const verify_struct = try info.unpack(TestStruct);
    try testing.expectEqual(@as(u64, 100), verify_struct.value);
}

test "AccountInfo lamports transfer" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const from_id = Pubkey.ZEROES;
    const to_id = Pubkey.newUnique();
    const owner_id = pubkey.SYSTEM_PROGRAM_ID;

    var from_data: [0]u8 = undefined;
    var to_data: [0]u8 = undefined;

    var from_info = try createTestAccountInfo(
        allocator,
        &from_id,
        &owner_id,
        1000,
        &from_data,
        true, // is_signer
        true, // is_writable
        false, // is_executable
    );
    defer allocator.destroy(from_info.data_ptr);

    var to_info = try createTestAccountInfo(
        allocator,
        &to_id,
        &owner_id,
        500,
        &to_data,
        false, // is_signer
        true, // is_writable
        false, // is_executable
    );
    defer allocator.destroy(to_info.data_ptr);

    // Transfer 250 lamports
    try from_info.transferLamports(&to_info, 250);

    try testing.expectEqual(@as(u64, 750), from_info.getLamports());
    try testing.expectEqual(@as(u64, 750), to_info.getLamports());

    // Test insufficient funds
    const result = from_info.transferLamports(&to_info, 1000);
    try testing.expectError(error.InsufficientFunds, result);
}

test "AccountData size and alignment" {
    const testing = std.testing;

    // Verify AccountData is 88 bytes with 8-byte alignment
    try testing.expectEqual(@as(usize, 88), @sizeOf(AccountData));
    try testing.expectEqual(@as(usize, 8), @alignOf(AccountData));

    // Verify field offsets
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
}

test "AccountIterator basic iteration" {
    const testing = std.testing;

    // Create mock serialized input with proper alignment
    var buffer: [1024]u8 align(@alignOf(AccountData)) = undefined;
    var offset: usize = 0;

    // Number of accounts
    buffer[offset] = 3;
    offset += 1;

    // First account (non-duplicate)
    buffer[offset] = NON_DUP_MARKER;
    offset += 1;

    const account1_data = AccountData{
        .duplicate_index = NON_DUP_MARKER,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
        .original_data_len = 10,
        .id = Pubkey.ZEROES,
        .owner_id = pubkey.SYSTEM_PROGRAM_ID,
        .lamports = 1000,
        .data_len = 10,
    };
    @memcpy(buffer[offset..][0..@sizeOf(AccountData)], std.mem.asBytes(&account1_data));
    offset += @sizeOf(AccountData);
    // Account data
    @memset(buffer[offset..][0..10], 0xAA);
    offset += 10;

    // Second account (non-duplicate)
    buffer[offset] = NON_DUP_MARKER;
    offset += 1;

    const account2_data = AccountData{
        .duplicate_index = NON_DUP_MARKER,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 1,
        .original_data_len = 20,
        .id = Pubkey.newUnique(),
        .owner_id = pubkey.SYSTEM_PROGRAM_ID,
        .lamports = 500,
        .data_len = 20,
    };
    @memcpy(buffer[offset..][0..@sizeOf(AccountData)], std.mem.asBytes(&account2_data));
    offset += @sizeOf(AccountData);
    // Account data
    @memset(buffer[offset..][0..20], 0xBB);
    offset += 20;

    // Third account (duplicate of first)
    buffer[offset] = 0; // Duplicate marker
    offset += 1;

    // Allocate space for tracking accounts
    var accounts_buffer: [10]AccountInfo = undefined;
    var aligned_buffer: [10]AccountData = undefined;

    // Create iterator
    var iter = AccountIterator.init(&buffer, 3, &accounts_buffer, &aligned_buffer);

    // First account
    const acc1 = iter.next();
    try testing.expect(acc1 != null);
    try testing.expect(acc1.?.isSigner());
    try testing.expect(acc1.?.isWritable());
    try testing.expect(!acc1.?.isExecutable());
    try testing.expectEqual(@as(u64, 1000), acc1.?.getLamports());
    try testing.expectEqual(@as(u64, 10), acc1.?.dataLen());

    // Second account
    const acc2 = iter.next();
    try testing.expect(acc2 != null);
    try testing.expect(!acc2.?.isSigner());
    try testing.expect(!acc2.?.isWritable());
    try testing.expect(acc2.?.isExecutable());
    try testing.expectEqual(@as(u64, 500), acc2.?.getLamports());
    try testing.expectEqual(@as(u64, 20), acc2.?.dataLen());

    // Third account (duplicate of first)
    const acc3 = iter.next();
    try testing.expect(acc3 != null);
    try testing.expect(acc3.?.isSigner());
    try testing.expect(acc3.?.isWritable());
    try testing.expectEqual(@as(u64, 1000), acc3.?.getLamports());

    // No more accounts
    const acc4 = iter.next();
    try testing.expect(acc4 == null);
}

test "AccountIterator skip functionality" {
    const testing = std.testing;

    // Create mock serialized input with 5 accounts
    var buffer: [1024]u8 align(@alignOf(AccountData)) = undefined;
    var offset: usize = 0;

    // Number of accounts
    buffer[offset] = 5;
    offset += 1;

    // Add 5 non-duplicate accounts
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        buffer[offset] = NON_DUP_MARKER;
        offset += 1;

        const account_data = AccountData{
            .duplicate_index = NON_DUP_MARKER,
            .is_signer = if (i == 0) 1 else 0,
            .is_writable = 1,
            .is_executable = 0,
            .original_data_len = 5,
            .id = Pubkey.ZEROES,
            .owner_id = pubkey.SYSTEM_PROGRAM_ID,
            .lamports = 100 * (i + 1),
            .data_len = 5,
        };
        @memcpy(buffer[offset..][0..@sizeOf(AccountData)], std.mem.asBytes(&account_data));
        offset += @sizeOf(AccountData);
        @memset(buffer[offset..][0..5], @intCast(i));
        offset += 5;
    }

    var accounts_buffer: [10]AccountInfo = undefined;
    var aligned_buffer: [10]AccountData = undefined;
    var iter = AccountIterator.init(&buffer, 5, &accounts_buffer, &aligned_buffer);

    // Skip first 2 accounts
    iter.skip(2);
    try testing.expectEqual(@as(usize, 3), iter.remaining);

    // Get third account
    const acc3 = iter.next();
    try testing.expect(acc3 != null);
    try testing.expectEqual(@as(u64, 300), acc3.?.getLamports());

    // Skip next account
    iter.skip(1);

    // Get fifth account
    const acc5 = iter.next();
    try testing.expect(acc5 != null);
    try testing.expectEqual(@as(u64, 500), acc5.?.getLamports());

    // No more accounts
    try testing.expect(iter.next() == null);
}

test "parseAccounts function" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create mock serialized input
    var buffer: [512]u8 align(@alignOf(AccountData)) = undefined;
    var offset: usize = 0;

    // Number of accounts
    buffer[offset] = 2;
    offset += 1;

    // First account
    buffer[offset] = NON_DUP_MARKER;
    offset += 1;

    const account1_data = AccountData{
        .duplicate_index = NON_DUP_MARKER,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
        .original_data_len = 8,
        .id = Pubkey.ZEROES,
        .owner_id = pubkey.SYSTEM_PROGRAM_ID,
        .lamports = 2000,
        .data_len = 8,
    };
    @memcpy(buffer[offset..][0..@sizeOf(AccountData)], std.mem.asBytes(&account1_data));
    offset += @sizeOf(AccountData);
    @memset(buffer[offset..][0..8], 0xFF);
    offset += 8;

    // Second account
    buffer[offset] = NON_DUP_MARKER;
    offset += 1;

    const account2_data = AccountData{
        .duplicate_index = NON_DUP_MARKER,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 1,
        .original_data_len = 4,
        .id = Pubkey.newUnique(),
        .owner_id = pubkey.SYSTEM_PROGRAM_ID,
        .lamports = 3000,
        .data_len = 4,
    };
    @memcpy(buffer[offset..][0..@sizeOf(AccountData)], std.mem.asBytes(&account2_data));
    offset += @sizeOf(AccountData);
    @memset(buffer[offset..][0..4], 0xEE);

    // Parse accounts
    var parsed = try parseAccounts(&buffer, allocator);
    defer parsed.deinit();

    try testing.expectEqual(@as(usize, 2), parsed.accounts.len);

    // Verify first account
    try testing.expect(parsed.accounts[0].isSigner());
    try testing.expect(parsed.accounts[0].isWritable());
    try testing.expectEqual(@as(u64, 2000), parsed.accounts[0].getLamports());
    try testing.expectEqual(@as(u64, 8), parsed.accounts[0].dataLen());

    // Verify second account
    try testing.expect(!parsed.accounts[1].isSigner());
    try testing.expect(parsed.accounts[1].isWritable());
    try testing.expect(parsed.accounts[1].isExecutable());
    try testing.expectEqual(@as(u64, 3000), parsed.accounts[1].getLamports());
    try testing.expectEqual(@as(u64, 4), parsed.accounts[1].dataLen());
}

test "AccountInfo realloc functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const id = Pubkey.ZEROES;
    const owner_id = pubkey.SYSTEM_PROGRAM_ID;
    var data_buffer: [1024]u8 = undefined;

    var info = try createTestAccountInfo(
        allocator,
        &id,
        &owner_id,
        1000,
        data_buffer[0..100],
        false,
        true, // is_writable
        false,
    );
    defer allocator.destroy(info.data_ptr);

    // Initial data length
    try testing.expectEqual(@as(u64, 100), info.dataLen());
    try testing.expectEqual(@as(u32, 100), info.originalDataLen());

    // Grow the account
    try info.realloc(200, true);
    try testing.expectEqual(@as(u64, 200), info.dataLen());
    try testing.expectEqual(@as(u32, 100), info.originalDataLen()); // Original doesn't change

    // Verify zero initialization
    const data = info.getData();
    var i: usize = 100;
    while (i < 200) : (i += 1) {
        try testing.expectEqual(@as(u8, 0), data[i]);
    }

    // Shrink the account
    try info.realloc(50, false);
    try testing.expectEqual(@as(u64, 50), info.dataLen());

    // Test max increase limit
    const result = info.realloc(50 + MAX_PERMITTED_DATA_INCREASE + 1, false);
    try testing.expectError(error.ExceedsMaxDataIncrease, result);

    // Test non-writable account
    info.data_ptr.is_writable = 0;
    const result2 = info.realloc(100, false);
    try testing.expectError(error.AccountNotWritable, result2);
}

test "AccountInfo duplicate detection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test non-duplicate account
    const id1 = Pubkey.ZEROES;
    const owner_id = pubkey.SYSTEM_PROGRAM_ID;
    var data_buffer: [10]u8 = undefined;

    const info1 = try createTestAccountInfo(
        allocator,
        &id1,
        &owner_id,
        1000,
        &data_buffer,
        false,
        true,
        false,
    );
    defer allocator.destroy(info1.data_ptr);

    try testing.expect(!info1.isDuplicate());
    try testing.expectEqual(NON_DUP_MARKER, info1.duplicateIndex());

    // Create a duplicate account manually
    const account_data = try allocator.create(AccountData);
    defer allocator.destroy(account_data);

    account_data.* = .{
        .duplicate_index = 3, // Duplicate of account at index 3
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
        .original_data_len = 0,
        .id = Pubkey.ZEROES,
        .owner_id = Pubkey.ZEROES,
        .lamports = 0,
        .data_len = 0,
    };

    const info2 = AccountInfo.fromDataPtr(account_data, undefined);
    try testing.expect(info2.isDuplicate());
    try testing.expectEqual(@as(u8, 3), info2.duplicateIndex());
}

test "AccountInfo owner assignment" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const id = Pubkey.ZEROES;
    const initial_owner = pubkey.SYSTEM_PROGRAM_ID;
    const new_owner = Pubkey.newUnique();
    var data_buffer: [10]u8 = undefined;

    var info = try createTestAccountInfo(
        allocator,
        &id,
        &initial_owner,
        1000,
        &data_buffer,
        false,
        true, // is_writable
        false,
    );
    defer allocator.destroy(info.data_ptr);

    // Initial owner
    try testing.expect(info.isOwnedBy(&pubkey.SYSTEM_PROGRAM_ID));

    // Assign new owner
    try info.assign(&new_owner);
    try testing.expect(info.isOwnedBy(&new_owner));
    try testing.expect(!info.isOwnedBy(&pubkey.SYSTEM_PROGRAM_ID));

    // Test non-writable account
    info.data_ptr.is_writable = 0;
    const another_owner = Pubkey.newUnique();
    const result = info.assign(&another_owner);
    try testing.expectError(error.AccountNotWritable, result);
}

test "AccountInfo executable flag" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const id = Pubkey.ZEROES;
    const owner_id = pubkey.SYSTEM_PROGRAM_ID;
    var data_buffer: [10]u8 = undefined;

    var info = try createTestAccountInfo(
        allocator,
        &id,
        &owner_id,
        1000,
        &data_buffer,
        false,
        true, // is_writable
        false, // not executable initially
    );
    defer allocator.destroy(info.data_ptr);

    // Initially not executable
    try testing.expect(!info.isExecutable());

    // Set executable
    try info.setExecutable(true);
    try testing.expect(info.isExecutable());

    // Unset executable
    try info.setExecutable(false);
    try testing.expect(!info.isExecutable());

    // Test non-writable account
    info.data_ptr.is_writable = 0;
    const result = info.setExecutable(true);
    try testing.expectError(error.AccountNotWritable, result);
}

test "AccountInfo data access edge cases" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const id = Pubkey.ZEROES;
    const owner_id = pubkey.SYSTEM_PROGRAM_ID;

    // Test with empty data
    var empty_data: [0]u8 = undefined;
    const info_empty = try createTestAccountInfo(
        allocator,
        &id,
        &owner_id,
        1000,
        &empty_data,
        false,
        true,
        false,
    );
    defer allocator.destroy(info_empty.data_ptr);

    try testing.expectEqual(@as(u64, 0), info_empty.dataLen());
    const empty_slice = info_empty.getData();
    try testing.expectEqual(@as(usize, 0), empty_slice.len);

    // Test with max size data
    var large_data: [MAX_PERMITTED_DATA_INCREASE]u8 = undefined;
    @memset(&large_data, 0x42);

    const info_large = try createTestAccountInfo(
        allocator,
        &id,
        &owner_id,
        1000,
        &large_data,
        false,
        true,
        false,
    );
    defer allocator.destroy(info_large.data_ptr);

    try testing.expectEqual(@as(u64, MAX_PERMITTED_DATA_INCREASE), info_large.dataLen());
    const large_slice = info_large.getData();
    try testing.expectEqual(MAX_PERMITTED_DATA_INCREASE, large_slice.len);
    try testing.expectEqual(@as(u8, 0x42), large_slice[0]);
    try testing.expectEqual(@as(u8, 0x42), large_slice[large_slice.len - 1]);
}

test "AccountInfo complex duplicate scenario" {
    const testing = std.testing;

    // Create serialized input with multiple duplicates
    var buffer: [2048]u8 align(@alignOf(AccountData)) = undefined;
    var offset: usize = 0;

    // 5 accounts: [A, B, dup(A), C, dup(B)]
    buffer[offset] = 5;
    offset += 1;

    // Account A (index 0)
    buffer[offset] = NON_DUP_MARKER;
    offset += 1;
    const account_a = AccountData{
        .duplicate_index = NON_DUP_MARKER,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
        .original_data_len = 4,
        .id = Pubkey.ZEROES,
        .owner_id = pubkey.SYSTEM_PROGRAM_ID,
        .lamports = 1000,
        .data_len = 4,
    };
    @memcpy(buffer[offset..][0..@sizeOf(AccountData)], std.mem.asBytes(&account_a));
    offset += @sizeOf(AccountData);
    @memset(buffer[offset..][0..4], 0xAA);
    offset += 4;

    // Account B (index 1)
    buffer[offset] = NON_DUP_MARKER;
    offset += 1;
    const account_b = AccountData{
        .duplicate_index = NON_DUP_MARKER,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 1,
        .original_data_len = 4,
        .id = Pubkey.newUnique(),
        .owner_id = pubkey.SYSTEM_PROGRAM_ID,
        .lamports = 2000,
        .data_len = 4,
    };
    @memcpy(buffer[offset..][0..@sizeOf(AccountData)], std.mem.asBytes(&account_b));
    offset += @sizeOf(AccountData);
    @memset(buffer[offset..][0..4], 0xBB);
    offset += 4;

    // Duplicate of A (index 2)
    buffer[offset] = 0; // duplicate marker pointing to index 0
    offset += 1;

    // Account C (index 3)
    buffer[offset] = NON_DUP_MARKER;
    offset += 1;
    const account_c = AccountData{
        .duplicate_index = NON_DUP_MARKER,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
        .original_data_len = 4,
        .id = Pubkey.newUnique(),
        .owner_id = pubkey.SYSTEM_PROGRAM_ID,
        .lamports = 3000,
        .data_len = 4,
    };
    @memcpy(buffer[offset..][0..@sizeOf(AccountData)], std.mem.asBytes(&account_c));
    offset += @sizeOf(AccountData);
    @memset(buffer[offset..][0..4], 0xCC);
    offset += 4;

    // Duplicate of B (index 4)
    buffer[offset] = 1; // duplicate marker pointing to index 1
    offset += 1;

    var accounts_buffer: [10]AccountInfo = undefined;
    var aligned_buffer: [10]AccountData = undefined;
    var iter = AccountIterator.init(&buffer, 5, &accounts_buffer, &aligned_buffer);

    // Parse all accounts
    const acc0 = iter.next().?;
    const acc1 = iter.next().?;
    const acc2 = iter.next().?; // Duplicate of acc0
    const acc3 = iter.next().?;
    const acc4 = iter.next().?; // Duplicate of acc1

    // Verify accounts
    try testing.expectEqual(@as(u64, 1000), acc0.getLamports());
    try testing.expectEqual(@as(u64, 2000), acc1.getLamports());
    try testing.expectEqual(@as(u64, 1000), acc2.getLamports()); // Same as acc0
    try testing.expectEqual(@as(u64, 3000), acc3.getLamports());
    try testing.expectEqual(@as(u64, 2000), acc4.getLamports()); // Same as acc1

    // Verify duplicate flags
    try testing.expect(acc0.isSigner());
    try testing.expect(acc2.isSigner()); // Same as acc0
    try testing.expect(!acc1.isSigner());
    try testing.expect(!acc4.isSigner()); // Same as acc1
}

// Include Rust compatibility tests
test {
    _ = @import("rust_compatibility_test.zig");
}
