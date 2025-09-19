/// Lazy parsing entrypoint for Solana programs
///
/// This module provides a lazy parsing implementation that only parses accounts
/// when they are actually accessed, reducing CU consumption significantly
const std = @import("std");
const account_info = @import("account_info/account_info.zig");
const pubkey = @import("pubkey/pubkey.zig");
const program_error = @import("program_error.zig");
const msg = @import("msg/msg.zig");

const AccountInfo = account_info.AccountInfo;
const RawAccountInfo = account_info.RawAccountInfo;
const Pubkey = pubkey.Pubkey;
const ProgramError = program_error.ProgramError;
const ProgramResult = program_error.ProgramResult;

/// Account data padding - Solana adds 10KB padding after account data
pub const ACCOUNT_DATA_PADDING = 10 * 1024;

/// Lazily parsed account
pub const LazyAccount = struct {
    key: *const Pubkey,
    lamports: *u64,
    data: []u8,
    owner: *const Pubkey,
    is_signer: bool,
    is_writable: bool,
    is_executable: bool,

    pub fn getLamports(self: *const LazyAccount) u64 {
        return self.lamports.*;
    }

    pub fn isSigner(self: *const LazyAccount) bool {
        return self.is_signer;
    }

    pub fn isWritable(self: *const LazyAccount) bool {
        return self.is_writable;
    }
};

/// Iterator for lazy account access
pub const LazyAccountIter = struct {
    /// Raw input buffer from Solana runtime
    input: [*]const u8,
    /// Current offset in the input buffer
    offset: usize,
    /// Number of accounts remaining
    remaining_accounts: usize,
    /// Total number of accounts
    total_accounts: usize,
    /// Current account index
    current_index: usize,
    /// Storage for current account
    current_account: LazyAccount = undefined,

    /// Get next account (parses on demand)
    pub fn next(self: *LazyAccountIter) !?*const LazyAccount {
        if (self.remaining_accounts == 0) {
            return null;
        }

        // Check for duplicate account
        const dup_info = self.input[self.offset];
        self.offset += 1;

        if (dup_info != 0xFF) {
            // This is a duplicate account - skip for now
            self.offset += 7; // Skip padding
            self.remaining_accounts -= 1;
            self.current_index += 1;
            // Try next account
            return self.next();
        }

        // Parse the account
        const account_ptr = self.input + self.offset;

        // Read account fields (matching entrypoint.zig layout exactly)
        const is_signer = account_ptr[0] != 0;
        const is_writable = account_ptr[1] != 0;
        const is_executable = account_ptr[2] != 0;
        // Fields layout: flags(3) + padding(4) + key(32) + owner(32) + lamports(8) + data_len(8) = 87
        const account_key = @as(*const Pubkey, @ptrCast(@alignCast(account_ptr + 7)));
        const owner = @as(*const Pubkey, @ptrCast(@alignCast(account_ptr + 39)));
        const lamports_ptr = @as(*u64, @ptrCast(@alignCast(@constCast(account_ptr + 71))));
        const data_len = std.mem.readInt(u64, account_ptr[79..87], .little);

        // Data starts after the header
        const data = @as([*]u8, @constCast(account_ptr + 87));

        // Fill current account
        self.current_account = LazyAccount{
            .key = account_key,
            .lamports = lamports_ptr,
            .data = data[0..data_len],
            .owner = owner,
            .is_signer = is_signer,
            .is_writable = is_writable,
            .is_executable = is_executable,
        };

        // Skip to next account
        self.offset += 87 + data_len + ACCOUNT_DATA_PADDING + 8;
        self.offset = (self.offset + 7) & ~@as(usize, 7); // Align to 8 bytes

        self.remaining_accounts -= 1;
        self.current_index += 1;

        return &self.current_account;
    }

    /// Skip n accounts without parsing
    pub fn skip(self: *LazyAccountIter, n: usize) void {
        var to_skip = @min(n, self.remaining_accounts);

        while (to_skip > 0) : (to_skip -= 1) {
            // Check for duplicate
            const dup_info = self.input[self.offset];
            self.offset += 1;

            if (dup_info != 0xFF) {
                // Duplicate - just skip padding
                self.offset += 7;
            } else {
                // Full account - need to read data_len to know how much to skip
                // Account structure is 87 bytes header, data_len is at offset 79 from start of account
                // We already incremented offset by 1 for dup_info, so account starts at self.offset
                const data_len = std.mem.readInt(u64, self.input[self.offset + 78..][0..8], .little);
                // Skip: remaining 86 bytes of header + data + padding + rent_epoch
                self.offset += 86 + data_len + ACCOUNT_DATA_PADDING + 8;
                self.offset = (self.offset + 7) & ~@as(usize, 7); // Align to 8 bytes
            }

            self.remaining_accounts -= 1;
            self.current_index += 1;
        }
    }

    /// Peek at next account key without parsing full account
    pub fn peekKey(self: *LazyAccountIter) !?*const Pubkey {
        if (self.remaining_accounts == 0) {
            return null;
        }

        var temp_offset = self.offset;

        // Check for duplicate
        const dup_info = self.input[temp_offset];
        temp_offset += 1;

        if (dup_info != 0xFF) {
            // Duplicate - skip for now and try next
            self.offset += 8; // Skip dup info + padding
            self.remaining_accounts -= 1;
            self.current_index += 1;
            return self.peekKey();
        }

        // Key is at offset + 7 in the account structure
        return @as(*const Pubkey, @ptrCast(@alignCast(self.input + temp_offset + 7)));
    }

    /// Get remaining account count
    pub fn remaining(self: *const LazyAccountIter) usize {
        return self.remaining_accounts;
    }
};

/// Lazy process instruction function type
pub const LazyProcessInstruction = fn (
    program_id: *const Pubkey,
    accounts: *LazyAccountIter,
    instruction_data: []const u8,
) ProgramResult;

/// Declare a lazy entrypoint for a Solana program
///
/// Example:
/// ```zig
/// pub fn process_lazy(
///     program_id: *const Pubkey,
///     accounts: *LazyAccountIter,
///     instruction_data: []const u8,
/// ) ProgramResult {
///     // Only parse accounts you need
///     const payer = (try accounts.next()).?;
///     accounts.skip(2); // Skip unused accounts
///     const target = (try accounts.next()).?;
///     return;
/// }
///
/// comptime {
///     lazy_entrypoint.declareLazyEntrypoint(process_lazy);
/// }
/// ```
pub fn declareLazyEntrypoint(comptime process_instruction: LazyProcessInstruction) void {
    const S = struct {
        pub export fn entrypoint(input: [*]const u8) callconv(.C) u64 {
            var offset: usize = 0;

            // Read number of accounts
            const num_accounts = std.mem.readInt(u64, input[offset..][0..8], .little);
            offset += 8;

            // Early check: if instruction parsing fails, return immediately
            if (num_accounts > 64) {
                return 0x02; // InvalidInstructionData
            }

            // Create iterator
            var iter = LazyAccountIter{
                .input = input,
                .offset = offset,
                .remaining_accounts = num_accounts,
                .total_accounts = num_accounts,
                .current_index = 0,
            };

            // Calculate where instruction data starts without actually parsing accounts
            // This is much more efficient than using skip
            var data_offset = offset;
            for (0..num_accounts) |_| {
                const dup_info = input[data_offset];
                data_offset += 1;

                if (dup_info != 0xFF) {
                    // Duplicate account - just 8 bytes total
                    data_offset += 7;
                } else {
                    // Full account - read data_len to calculate size
                    const data_len = std.mem.readInt(u64, input[data_offset + 78..][0..8], .little);
                    data_offset += 86 + data_len + ACCOUNT_DATA_PADDING + 8;
                    data_offset = (data_offset + 7) & ~@as(usize, 7);
                }
            }

            // Parse instruction data length and data
            // Debug: sanity check the offset
            // 10 accounts * ~10KB each = ~100KB, so 200KB should be a reasonable max
            if (data_offset > 200000) {
                // The offset calculation is probably wrong
                return 0x03; // Custom error to distinguish
            }

            const data_len = std.mem.readInt(u64, input[data_offset..][0..8], .little);
            if (data_len > 1280) {
                // Instruction data too large
                return 0x04; // Custom error to distinguish
            }

            const instruction_data = input[data_offset + 8..][0..data_len];

            // Parse program ID (after instruction data)
            const program_id = @as(*const Pubkey, @ptrCast(@alignCast(input + data_offset + 8 + data_len)));

            // Call user's process function with fresh iterator
            const result = process_instruction(
                program_id,
                &iter,
                instruction_data,
            );

            return program_error.resultToU64(result);
        }
    };
    _ = &S.entrypoint;
}