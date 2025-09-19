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
            const msg = @import("../msg/msg.zig");
            const RawAccountInfo = @import("../account_info/account_info.zig").RawAccountInfo;

            // Use the original account pointers if available
            // Otherwise fall back to creating CPI accounts
            var has_original = true;
            for (account_infos) |*info| {
                if (info.original_account_ptr == null) {
                    has_original = false;
                    break;
                }
            }

            if (has_original and account_infos.len > 0) {
                // All accounts have original pointers - use them directly
                // Get the first original account pointer
                const first_raw = @as(*const RawAccountInfo, @ptrCast(@alignCast(account_infos[0].original_account_ptr.?)));
                const seeds_ptr = if (signer_seeds.len > 0) signer_seeds.ptr else null;

                msg.msgf("Using original account pointers at 0x{x}, len={}", .{@intFromPtr(first_raw), account_infos.len});
                msg.msgf("  First account id ptr: 0x{x}", .{@intFromPtr(first_raw.id)});

                return switch (sol_invoke_signed_c(self, @ptrCast(first_raw), account_infos.len, seeds_ptr, signer_seeds.len)) {
                    0 => {},
                    else => |err| {
                        msg.msgf("CPI failed with error: {}", .{err});
                        return error.CrossProgramInvocationFailed;
                    },
                };
            } else if (account_infos.len > 0) {
                // Fallback: create CPI accounts (less likely to work)
                msg.msg("WARNING: No original account pointers, creating CPI accounts");

                var cpi_accounts: [32]CPIAccountInfo = undefined;
                for (account_infos, 0..) |*info, i| {
                    const data = info.data_ptr;
                    cpi_accounts[i] = CPIAccountInfo{
                        .id = &data.id,
                        .lamports = @ptrCast(&data.lamports),  // Cast to unaligned pointer
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
                return switch (sol_invoke_signed_c(self, @ptrCast(&cpi_accounts[0]), account_infos.len, seeds_ptr, signer_seeds.len)) {
                    0 => {},
                    else => |err| {
                        msg.msgf("CPI failed with error: {}", .{err});
                        return error.CrossProgramInvocationFailed;
                    },
                };
            } else {
                // No accounts
                var dummy: u8 = 0;
                return switch (sol_invoke_signed_c(self, @ptrCast(&dummy), 0, null, 0)) {
                    0 => {},
                    else => |err| {
                        msg.msgf("CPI failed with error: {}", .{err});
                        return error.CrossProgramInvocationFailed;
                    },
                };
            }
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

    const meta1 = AccountMeta.readOnly(key, true);
    try std.testing.expect(meta1.is_signer);
    try std.testing.expect(!meta1.is_writable);

    const meta2 = AccountMeta.writable(key, false);
    try std.testing.expect(!meta2.is_signer);
    try std.testing.expect(meta2.is_writable);
}

test "instruction creation" {
    const program = Pubkey.ZEROES;
    const accounts = [_]AccountMeta{
        AccountMeta.writable(Pubkey.ZEROES, true),
        AccountMeta.readOnly(Pubkey.ZEROES, false),
    };
    const data = [_]u8{ 1, 2, 3, 4 };

    const ix = Instruction.init(program, &accounts, &data);

    try std.testing.expectEqual(program, ix.program_id);
    try std.testing.expectEqual(@as(usize, 2), ix.accounts.len);
    try std.testing.expectEqual(@as(usize, 4), ix.data.len);
}
