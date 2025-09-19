const std = @import("std");
const Pubkey = @import("../pubkey/pubkey.zig").Pubkey;

/// Account metadata for instructions
/// Must match the layout expected by Solana runtime
pub const AccountMeta = extern struct {
    /// Pointer to public key of the account
    pubkey: *const Pubkey,

    /// Is the account writable
    is_writable: bool,

    /// Is the account a signer
    is_signer: bool,

    /// Create a read-only account meta
    pub fn readOnly(pubkey: *const Pubkey, is_signer: bool) AccountMeta {
        return .{
            .pubkey = pubkey,
            .is_writable = false,
            .is_signer = is_signer,
        };
    }

    /// Create a writable account meta
    pub fn writable(pubkey: *const Pubkey, is_signer: bool) AccountMeta {
        return .{
            .pubkey = pubkey,
            .is_writable = true,
            .is_signer = is_signer,
        };
    }
};

/// Instruction data for cross-program invocation - extern struct for C ABI
pub const Instruction = extern struct {
    /// Program ID of the instruction
    program_id: *const Pubkey,

    /// Accounts involved in the instruction
    accounts: [*]const AccountMeta,
    accounts_len: usize,

    /// Instruction data
    data: [*]const u8,
    data_len: usize,

    /// Declare syscall directly in the struct like solana-program-sdk-zig
    extern fn sol_invoke_signed_c(
        instruction: *const Instruction,
        account_infos: *const anyopaque,  // Will be cast from AccountInfo array
        account_infos_len: usize,
        signer_seeds: ?[*]const []const []const u8,
        signer_seeds_len: usize,
    ) callconv(.C) u64;

    /// Create a new instruction
    pub fn init(
        program_id: Pubkey,
        accounts: []const AccountMeta,
        data: []const u8,
    ) Instruction {
        return .{
            .program_id = &program_id,
            .accounts = accounts.ptr,
            .accounts_len = accounts.len,
            .data = data.ptr,
            .data_len = data.len,
        };
    }

    /// Create from parameters (like solana-program-sdk-zig)
    pub fn from(params: struct {
        program_id: *const Pubkey,
        accounts: []const AccountMeta,
        data: []const u8,
    }) Instruction {
        return .{
            .program_id = params.program_id,
            .accounts = params.accounts.ptr,
            .accounts_len = params.accounts.len,
            .data = params.data.ptr,
            .data_len = params.data.len,
        };
    }

    /// CPI Account Info structure that matches runtime expectations
    /// MUST have pointers to Pubkeys, not inline values
    /// NO duplicate_index field!
    /// Note: This is now only used as a fallback when original pointers aren't available
    const CPIAccountInfo = extern struct {
        id: *const Pubkey,
        lamports: *align(1) u64,  // May be unaligned from input buffer
        data_len: u64,
        data: [*]u8,
        owner_id: *const Pubkey,
        rent_epoch: u64,
        is_signer: u8,
        is_writable: u8,
        is_executable: u8,
    };

    /// Invoke this instruction (CPI)
    pub fn invoke(self: *const Instruction, account_infos: []const AccountInfo) !void {
        return invoke_signed(self, account_infos, &.{});
    }

    /// Invoke this instruction with signer seeds (for PDAs)
    pub fn invoke_signed(
        self: *const Instruction,
        account_infos: []const AccountInfo,
        signer_seeds: []const []const []const u8,
    ) !void {
        if (comptime @import("../bpf.zig").is_solana) {
            const RawAccountInfo = @import("../account_info/account_info.zig").RawAccountInfo;

            // Fast path: use original account pointers if available
            if (account_infos.len > 0 and account_infos[0].original_account_ptr != null) {
                // Direct CPI using original pointers - minimal overhead
                const first_raw = @as(*const RawAccountInfo, @ptrCast(@alignCast(account_infos[0].original_account_ptr.?)));
                const seeds_ptr = if (signer_seeds.len > 0) signer_seeds.ptr else null;

                const result = sol_invoke_signed_c(self, @ptrCast(first_raw), account_infos.len, seeds_ptr, signer_seeds.len);
                if (result != 0) return error.CrossProgramInvocationFailed;
                return;
            }

            // Fallback path: create CPI accounts (slower)
            if (account_infos.len > 0) {
                var cpi_accounts: [32]CPIAccountInfo = undefined;
                for (account_infos, 0..) |*info, i| {
                    const data = info.data_ptr;
                    cpi_accounts[i] = CPIAccountInfo{
                        .id = &data.id,
                        .lamports = @ptrCast(&data.lamports),
                        .data_len = data.data_len,
                        .data = info.data_buffer,
                        .owner_id = &data.owner_id,
                        .rent_epoch = 0,
                        .is_signer = data.is_signer,
                        .is_writable = data.is_writable,
                        .is_executable = data.is_executable,
                    };
                }

                const seeds_ptr = if (signer_seeds.len > 0) signer_seeds.ptr else null;
                const result = sol_invoke_signed_c(self, @ptrCast(&cpi_accounts[0]), account_infos.len, seeds_ptr, signer_seeds.len);
                if (result != 0) return error.CrossProgramInvocationFailed;
                return;
            }

            // No accounts case
            var dummy: u8 = 0;
            const result = sol_invoke_signed_c(self, @ptrCast(&dummy), 0, null, 0);
            if (result != 0) return error.CrossProgramInvocationFailed;
        }
        return; // Mock success in test
    }
};

// Import AccountInfo for CPI methods
const AccountInfo = @import("../account_info/account_info.zig").AccountInfo;

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
    const key = Pubkey.ZEROES;

    const meta1 = AccountMeta.readOnly(&key, true);
    try std.testing.expect(meta1.is_signer);
    try std.testing.expect(!meta1.is_writable);

    const meta2 = AccountMeta.writable(&key, false);
    try std.testing.expect(!meta2.is_signer);
    try std.testing.expect(meta2.is_writable);
}

test "instruction creation" {
    const program = Pubkey.ZEROES;
    const key1 = Pubkey.ZEROES;
    const key2 = Pubkey.ZEROES;
    const accounts = [_]AccountMeta{
        AccountMeta.writable(&key1, true),
        AccountMeta.readOnly(&key2, false),
    };
    const data = [_]u8{ 1, 2, 3, 4 };

    const ix = Instruction.from(.{
        .program_id = &program,
        .accounts = &accounts,
        .data = &data,
    });

    try std.testing.expectEqual(program, ix.program_id.*);
    try std.testing.expectEqual(@as(usize, 2), ix.accounts_len);
    try std.testing.expectEqual(@as(usize, 4), ix.data_len);
}
