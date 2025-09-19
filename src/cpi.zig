/// Cross-Program Invocation (CPI) support
///
/// This module provides functions for invoking other Solana programs
const std = @import("std");
const syscalls = @import("syscalls.zig");
const Pubkey = @import("pubkey/pubkey.zig").Pubkey;
const account_info = @import("account_info/account_info.zig");
const AccountInfo = account_info.AccountInfo;
const AccountData = account_info.AccountData;
const instruction_mod = @import("instruction/instruction.zig");
const Instruction = instruction_mod.Instruction;
const AccountMeta = instruction_mod.AccountMeta;
const ProgramError = @import("program_error.zig").ProgramError;
const fromErrorCode = @import("program_error.zig").fromErrorCode;
const msg = @import("msg/msg.zig");

/// Maximum depth for cross-program invocations
pub const MAX_CPI_DEPTH = 4;

/// Maximum number of account infos per CPI
pub const MAX_CPI_ACCOUNTS = 32;

/// Maximum instruction data size for CPI
pub const MAX_CPI_DATA_SIZE = 10240; // 10KB

/// Rust-compatible StableVec format
const StableVec = extern struct {
    addr: u64,  // Pointer as u64
    cap: u64,   // Capacity
    len: u64,   // Length
};

/// Rust-compatible instruction for sol_invoke_signed_rust
/// This matches the format expected by Rust's CPI implementation
const StableInstruction = extern struct {
    accounts: StableVec,     // StableVec<AccountMeta>
    data: StableVec,         // StableVec<u8>
    program_id: Pubkey,      // Inline Pubkey, not pointer
};

/// C-compatible instruction for syscall
/// This matches the format expected by sol_invoke_signed_c
const CInstruction = extern struct {
    program_id: *const Pubkey,
    accounts: [*]const AccountMeta,
    accounts_len: u64,
    data: [*]const u8,
    data_len: u64,
};


// Note: AccountMeta now has inline Pubkey values
// This ensures the data is self-contained when passed to CPI


/// Invoke a cross-program invocation
pub fn invoke(
    instruction: *const Instruction,
    account_infos: []const AccountInfo,
) !void {
    return invoke_signed(instruction, account_infos, &[_][]const []const u8{});
}

/// Invoke a cross-program invocation with signer seeds (for PDAs)
pub fn invoke_signed(
    instruction: *const Instruction,
    account_infos: []const AccountInfo,
    signer_seeds: []const []const []const u8,
) !void {
    // Validate inputs
    if (account_infos.len > MAX_CPI_ACCOUNTS) {
        return error.TooManyAccounts;
    }
    if (instruction.data.len > MAX_CPI_DATA_SIZE) {
        return error.InstructionDataTooLarge;
    }

    // Debug logging
    msg.msgf("CPI: Invoking program {}", .{instruction.program_id});
    msg.msgf("  Instruction has {} accounts", .{instruction.accounts.len});
    msg.msgf("  Passing {} account infos", .{account_infos.len});
    msg.msgf("  Data len: {}", .{instruction.data.len});
    msg.msgf("  Signers: {}", .{signer_seeds.len});

    if (comptime !@import("bpf.zig").is_solana) {
        return; // Mock success in test environment
    }

    // Simply delegate to the Instruction's invoke_signed method
    try instruction.invoke_signed(account_infos, signer_seeds);
}

/// Serialized instruction for syscall
const SerializedInstruction = struct {
    buffer: [256]u8,  // Reduced from 1024 to save stack space
    len: usize,

    pub fn ptr(self: *const SerializedInstruction) *const u8 {
        return &self.buffer[0];
    }

    pub fn deinit(self: *const SerializedInstruction) void {
        // No-op for stack allocation
        _ = self;
    }
};

/// Serialize an instruction for the syscall
fn serializeInstruction(ix: *const Instruction) !SerializedInstruction {
    var result = SerializedInstruction{
        .buffer = undefined,
        .len = 0,
    };

    var offset: usize = 0;

    // Program ID (32 bytes)
    @memcpy(result.buffer[offset .. offset + 32], &ix.program_id.bytes);
    offset += 32;

    // Number of accounts (u64)
    const num_accounts = @as(u64, ix.accounts.len);
    @memcpy(result.buffer[offset .. offset + 8], std.mem.asBytes(&num_accounts));
    offset += 8;

    // Account metas
    for (ix.accounts) |meta| {
        // Pubkey (32 bytes)
        @memcpy(result.buffer[offset .. offset + 32], &meta.pubkey.bytes);
        offset += 32;

        // Flags (is_signer, is_writable)
        result.buffer[offset] = @as(u8, @intFromBool(meta.is_signer));
        offset += 1;
        result.buffer[offset] = @as(u8, @intFromBool(meta.is_writable));
        offset += 1;
    }

    // Data length (u64)
    const data_len = @as(u64, ix.data.len);
    @memcpy(result.buffer[offset .. offset + 8], std.mem.asBytes(&data_len));
    offset += 8;

    // Data
    @memcpy(result.buffer[offset .. offset + ix.data.len], ix.data);
    offset += ix.data.len;

    result.len = offset;
    return result;
}

/// Serialized account infos for syscall
const SerializedAccountInfos = struct {
    buffer: [1024]u8,  // Reduced from 4096 to save stack space
    len: usize,

    pub fn ptr(self: *const SerializedAccountInfos) *const u8 {
        return &self.buffer[0];
    }

    pub fn deinit(self: *const SerializedAccountInfos) void {
        // No-op for stack allocation
        _ = self;
    }
};

/// Serialize account infos for the syscall
fn serializeAccountInfos(
    account_infos: []const AccountInfo,
    account_metas: []const AccountMeta,
) !SerializedAccountInfos {
    var result = SerializedAccountInfos{
        .buffer = undefined,
        .len = 0,
    };

    // Validate that we have matching accounts
    if (account_infos.len < account_metas.len) {
        return error.MissingAccounts;
    }

    var offset: usize = 0;

    // Serialize each account info
    for (account_infos) |info| {
        // TODO: Match account info with corresponding meta
        // This requires proper account matching logic

        // For now, serialize the basic account info structure
        // This is a simplified version - real implementation needs
        // to match Solana's exact serialization format

        // Pubkey
        @memcpy(result.buffer[offset .. offset + 32], &info.key().bytes);
        offset += 32;

        // Owner
        @memcpy(result.buffer[offset .. offset + 32], &info.owner().bytes);
        offset += 32;

        // Lamports (u64)
        const lamports = info.getLamports();
        @memcpy(result.buffer[offset .. offset + 8], std.mem.asBytes(&lamports));
        offset += 8;

        // Data length (u64)
        const data = info.getData();
        const data_len = @as(u64, data.len);
        @memcpy(result.buffer[offset .. offset + 8], std.mem.asBytes(&data_len));
        offset += 8;

        // Note: Actual data pointer is passed separately in real CPI
    }

    result.len = offset;
    return result;
}

/// Helper to create a simple transfer instruction
pub fn createTransferInstruction(
    from: *const Pubkey,
    to: *const Pubkey,
    lamports: u64,
) Instruction {
    // System program ID
    const system_program_id = Pubkey.fromBytes([_]u8{0} ** 32);

    // Create account metas
    const accounts = [_]AccountMeta{
        AccountMeta.writable(from.*, true), // From account (signer, writable)
        AccountMeta.writable(to.*, false), // To account (writable)
    };

    // Serialize transfer instruction data
    // System program transfer instruction: [4-byte discriminator][8-byte lamports]
    var data: [12]u8 = undefined;
    // Transfer discriminator = 2
    @memcpy(data[0..4], &[_]u8{ 2, 0, 0, 0 });
    @memcpy(data[4..12], std.mem.asBytes(&lamports));

    return Instruction{
        .program_id = system_program_id,
        .accounts = &accounts,
        .data = &data,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "create transfer instruction" {
    const from = Pubkey.fromBytes([_]u8{1} ** 32);
    const to = Pubkey.fromBytes([_]u8{2} ** 32);
    const lamports: u64 = 1000;

    const ix = createTransferInstruction(&from, &to, lamports);

    try std.testing.expectEqual(@as(usize, 2), ix.accounts.len);
    try std.testing.expectEqual(@as(usize, 12), ix.data.len);
    try std.testing.expect(ix.accounts[0].is_signer);
    try std.testing.expect(ix.accounts[0].is_writable);
    try std.testing.expect(!ix.accounts[1].is_signer);
    try std.testing.expect(ix.accounts[1].is_writable);
}

test "invoke mock in test environment" {
    const from = Pubkey.fromBytes([_]u8{1} ** 32);
    const to = Pubkey.fromBytes([_]u8{2} ** 32);

    const ix = createTransferInstruction(&from, &to, 1000);

    // This should succeed in test environment (mocked)
    try invoke(&ix, &[_]AccountInfo{});
}
