const std = @import("std");
const Pubkey = @import("pubkey.zig").Pubkey;

/// Account metadata for instructions
pub const AccountMeta = extern struct {
    /// Public key of the account
    pubkey: Pubkey,

    /// Is the account a signer
    is_signer: bool,

    /// Is the account writable
    is_writable: bool,

    /// Create a new AccountMeta
    pub fn init(pubkey: Pubkey, is_signer: bool, is_writable: bool) AccountMeta {
        return .{
            .pubkey = pubkey,
            .is_signer = is_signer,
            .is_writable = is_writable,
        };
    }

    /// Create a read-only account meta
    pub fn readOnly(pubkey: Pubkey, is_signer: bool) AccountMeta {
        return init(pubkey, is_signer, false);
    }

    /// Create a writable account meta
    pub fn writable(pubkey: Pubkey, is_signer: bool) AccountMeta {
        return init(pubkey, is_signer, true);
    }
};

/// Instruction data for cross-program invocation
pub const Instruction = struct {
    /// Program ID of the instruction
    program_id: Pubkey,

    /// Accounts involved in the instruction
    accounts: []const AccountMeta,

    /// Instruction data
    data: []const u8,

    /// Create a new instruction
    pub fn init(
        program_id: Pubkey,
        accounts: []const AccountMeta,
        data: []const u8,
    ) Instruction {
        return .{
            .program_id = program_id,
            .accounts = accounts,
            .data = data,
        };
    }
};

/// Compiled instruction for efficient processing
pub const CompiledInstruction = extern struct {
    /// Index of the program account in the transaction
    program_id_index: u8,

    /// Indexes of accounts in the transaction
    accounts: [*]const u8,
    accounts_len: u16,

    /// Instruction data
    data: [*]const u8,
    data_len: u16,

    /// Get accounts as slice
    pub fn accountsSlice(self: *const CompiledInstruction) []const u8 {
        return self.accounts[0..self.accounts_len];
    }

    /// Get data as slice
    pub fn dataSlice(self: *const CompiledInstruction) []const u8 {
        return self.data[0..self.data_len];
    }
};

/// Helper to build instructions
pub const InstructionBuilder = struct {
    accounts: std.ArrayList(AccountMeta),
    data: std.ArrayList(u8),
    program_id: Pubkey,

    pub fn init(allocator: std.mem.Allocator, program_id: Pubkey) InstructionBuilder {
        return .{
            .accounts = std.ArrayList(AccountMeta).init(allocator),
            .data = std.ArrayList(u8).init(allocator),
            .program_id = program_id,
        };
    }

    pub fn deinit(self: *InstructionBuilder) void {
        self.accounts.deinit();
        self.data.deinit();
    }

    pub fn addAccount(self: *InstructionBuilder, meta: AccountMeta) !void {
        try self.accounts.append(meta);
    }

    pub fn addData(self: *InstructionBuilder, bytes: []const u8) !void {
        try self.data.appendSlice(bytes);
    }

    pub fn build(self: *InstructionBuilder) Instruction {
        return Instruction.init(
            self.program_id,
            self.accounts.items,
            self.data.items,
        );
    }
};

test "account meta creation" {
    const key = Pubkey.default;

    const meta1 = AccountMeta.readOnly(key, true);
    try std.testing.expect(meta1.is_signer);
    try std.testing.expect(!meta1.is_writable);

    const meta2 = AccountMeta.writable(key, false);
    try std.testing.expect(!meta2.is_signer);
    try std.testing.expect(meta2.is_writable);
}

test "instruction creation" {
    const program = Pubkey.default;
    const accounts = [_]AccountMeta{
        AccountMeta.writable(Pubkey.default, true),
        AccountMeta.readOnly(Pubkey.default, false),
    };
    const data = [_]u8{ 1, 2, 3, 4 };

    const ix = Instruction.init(program, &accounts, &data);

    try std.testing.expectEqual(program, ix.program_id);
    try std.testing.expectEqual(@as(usize, 2), ix.accounts.len);
    try std.testing.expectEqual(@as(usize, 4), ix.data.len);
}