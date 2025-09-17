const std = @import("std");
const Pubkey = @import("pubkey/pubkey.zig").Pubkey;

/// Maximum number of bytes a program may add to an account during a single instruction
pub const MAX_PERMITTED_DATA_INCREASE: usize = 1_024 * 10;

/// Maximum number of accounts that a transaction can process
pub const MAX_TX_ACCOUNTS: usize = 254; // u8::MAX - 1

/// Non-duplicated account marker
pub const NON_DUP_MARKER: u8 = 0b11111111;

/// Borrow state masks for account data and lamports
pub const BorrowState = struct {
    /// Check if account is borrowed (any type)
    pub const BORROWED: u8 = 0b11111111;

    /// Check if account is mutably borrowed
    pub const MUTABLY_BORROWED: u8 = 0b10001000;

    /// Lamports mutable borrow flag position
    pub const LAMPORTS_MUT_FLAG: u8 = 0b10000000;

    /// Data mutable borrow flag position
    pub const DATA_MUT_FLAG: u8 = 0b00001000;

    /// Lamports immutable borrow count mask
    pub const LAMPORTS_IMMUT_MASK: u8 = 0b01110000;

    /// Data immutable borrow count mask
    pub const DATA_IMMUT_MASK: u8 = 0b00000111;
};

/// Raw account data structure - matches Rust layout exactly
pub const Account = extern struct {
    /// Borrow state for lamports and data
    /// Bit layout:
    /// - Bit 7: lamports mutable borrow flag (1 = available, 0 = borrowed)
    /// - Bits 6-4: lamports immutable borrow count (7 to 0)
    /// - Bit 3: data mutable borrow flag (1 = available, 0 = borrowed)
    /// - Bits 2-0: data immutable borrow count (7 to 0)
    borrow_state: u8,

    /// Whether transaction was signed by this account
    is_signer: u8,

    /// Whether account is writable
    is_writable: u8,

    /// Whether this account represents a program
    executable: u8,

    /// Original data length delta (used for resizing)
    resize_delta: i32,

    /// Public key of the account
    key: Pubkey,

    /// Program that owns this account
    owner: Pubkey,

    /// Number of lamports in the account
    lamports: u64,

    /// Length of data in bytes
    data_len: usize,

    /// On-chain data pointer
    data: [*]u8,

    /// Padding for alignment
    padding_0: usize,

    /// Epoch at which account will next owe rent
    rent_epoch: u64,
};

/// Account information with safe accessors
pub const AccountInfo = struct {
    /// Pointer to the raw account data
    account: *Account,

    /// Get account public key
    pub inline fn key(self: *const AccountInfo) *const Pubkey {
        return &self.account.key;
    }

    /// Get account owner
    pub inline fn owner(self: *const AccountInfo) *const Pubkey {
        return &self.account.owner;
    }

    /// Check if account is signer
    pub inline fn isSigner(self: *const AccountInfo) bool {
        return self.account.is_signer != 0;
    }

    /// Check if account is writable
    pub inline fn isWritable(self: *const AccountInfo) bool {
        return self.account.is_writable != 0;
    }

    /// Check if account is executable
    pub inline fn isExecutable(self: *const AccountInfo) bool {
        return self.account.executable != 0;
    }

    /// Get rent epoch
    pub inline fn rentEpoch(self: *const AccountInfo) u64 {
        return self.account.rent_epoch;
    }

    /// Try to borrow lamports for reading
    pub fn tryBorrowLamports(self: *const AccountInfo) !u64 {
        const state = @atomicLoad(u8, &self.account.borrow_state, .acquire);

        // Check if mutably borrowed
        if ((state & BorrowState.LAMPORTS_MUT_FLAG) == 0) {
            return error.AlreadyBorrowedMut;
        }

        // Check if we can add another immutable borrow
        const immut_count = (state & BorrowState.LAMPORTS_IMMUT_MASK) >> 4;
        if (immut_count == 0) {
            return error.BorrowLimitExceeded;
        }

        return self.account.lamports;
    }

    /// Try to borrow lamports for writing
    pub fn tryBorrowMutLamports(self: *AccountInfo) !*u64 {
        if (!self.isWritable()) {
            return error.AccountNotWritable;
        }

        const state = @atomicLoad(u8, &self.account.borrow_state, .acquire);

        // Check if already borrowed (mutable or immutable)
        if ((state & BorrowState.LAMPORTS_MUT_FLAG) == 0) {
            return error.AlreadyBorrowedMut;
        }

        const immut_count = (state & BorrowState.LAMPORTS_IMMUT_MASK) >> 4;
        if (immut_count < 7) {
            return error.AlreadyBorrowed;
        }

        // Mark as mutably borrowed
        const new_state = state & ~BorrowState.LAMPORTS_MUT_FLAG;
        _ = @cmpxchgWeak(u8, &self.account.borrow_state, state, new_state, .release, .acquire);

        return &self.account.lamports;
    }

    /// Get data as slice (read-only)
    pub fn data(self: *const AccountInfo) []const u8 {
        return self.account.data[0..self.account.data_len];
    }

    /// Try to borrow data for reading
    pub fn tryBorrowData(self: *const AccountInfo) ![]const u8 {
        const state = @atomicLoad(u8, &self.account.borrow_state, .acquire);

        // Check if mutably borrowed
        if ((state & BorrowState.DATA_MUT_FLAG) == 0) {
            return error.AlreadyBorrowedMut;
        }

        // Check if we can add another immutable borrow
        const immut_count = state & BorrowState.DATA_IMMUT_MASK;
        if (immut_count == 0) {
            return error.BorrowLimitExceeded;
        }

        return self.account.data[0..self.account.data_len];
    }

    /// Try to borrow data for writing
    pub fn tryBorrowMutData(self: *AccountInfo) ![]u8 {
        if (!self.isWritable()) {
            return error.AccountNotWritable;
        }

        const state = @atomicLoad(u8, &self.account.borrow_state, .acquire);

        // Check if already borrowed (mutable or immutable)
        if ((state & BorrowState.DATA_MUT_FLAG) == 0) {
            return error.AlreadyBorrowedMut;
        }

        const immut_count = state & BorrowState.DATA_IMMUT_MASK;
        if (immut_count < 7) {
            return error.AlreadyBorrowed;
        }

        // Mark as mutably borrowed
        const new_state = state & ~BorrowState.DATA_MUT_FLAG;
        _ = @cmpxchgWeak(u8, &self.account.borrow_state, state, new_state, .release, .acquire);

        return self.account.data[0..self.account.data_len];
    }

    /// Reallocate account data
    pub fn realloc(self: *AccountInfo, new_len: usize, zero_init: bool) !void {
        if (!self.isWritable()) {
            return error.AccountNotWritable;
        }

        const old_len = self.account.data_len;

        // Check maximum increase
        if (new_len > old_len) {
            const increase = new_len - old_len;
            if (increase > MAX_PERMITTED_DATA_INCREASE) {
                return error.ExceedsMaxDataIncrease;
            }
        }

        // Update length
        self.account.data_len = new_len;

        // Update resize delta
        const original_len = @as(isize, @intCast(old_len)) - @as(isize, @intCast(self.account.resize_delta));
        self.account.resize_delta = @as(i32, @intCast(@as(isize, @intCast(new_len)) - original_len));

        // Zero new memory if requested
        if (zero_init and new_len > old_len) {
            const new_data = self.account.data[old_len..new_len];
            @memset(new_data, 0);
        }
    }

    /// Assign a new owner to the account
    pub fn assignOwner(self: *AccountInfo, new_owner: *const Pubkey) !void {
        if (!self.isWritable()) {
            return error.AccountNotWritable;
        }
        self.account.owner = new_owner.*;
    }

    /// Set account as executable
    pub fn setExecutable(self: *AccountInfo, executable: bool) !void {
        if (!self.isWritable()) {
            return error.AccountNotWritable;
        }
        self.account.executable = if (executable) 1 else 0;
    }

    /// Zero-copy cast data to a type
    pub fn dataAs(self: *const AccountInfo, comptime T: type) !*align(1) const T {
        const data_slice = self.data();
        if (data_slice.len < @sizeOf(T)) {
            return error.InvalidDataLength;
        }
        return @ptrCast(@alignCast(data_slice.ptr));
    }

    /// Zero-copy cast mutable data to a type
    pub fn dataMutAs(self: *AccountInfo, comptime T: type) !*align(1) T {
        const data_slice = try self.tryBorrowMutData();
        if (data_slice.len < @sizeOf(T)) {
            return error.InvalidDataLength;
        }
        return @ptrCast(@alignCast(data_slice.ptr));
    }
};

/// Helper to create AccountInfo from raw account pointer
pub fn fromAccount(account: *Account) AccountInfo {
    return AccountInfo{ .account = account };
}

test "account info basic operations" {
    var raw_account = Account{
        .borrow_state = NON_DUP_MARKER,
        .is_signer = 1,
        .is_writable = 1,
        .executable = 0,
        .resize_delta = 0,
        .key = Pubkey.ZEROES,
        .owner = Pubkey.ZEROES,
        .lamports = 1000,
        .data_len = 100,
        .data = @ptrFromInt(0x1000), // Mock pointer
        .padding_0 = 0,
        .rent_epoch = 0,
    };

    const info = fromAccount(&raw_account);

    try std.testing.expect(info.isSigner());
    try std.testing.expect(info.isWritable());
    try std.testing.expect(!info.isExecutable());

    const lamports = try info.tryBorrowLamports();
    try std.testing.expectEqual(@as(u64, 1000), lamports);
}
