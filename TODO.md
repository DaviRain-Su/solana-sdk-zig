# question


## CPI 问题

syscalls.zig中的接口 但是实际上实现又重新定义了一个
```zig
// src/syscalls.zig

// CPI syscalls
pub extern "C" fn sol_invoke_signed_c(
    instruction: *const u8,
    account_infos: *const u8,
    account_infos_len: u64,
    signers_seeds: ?*const u8,
    signers_seeds_len: u64,
) u64;

// Alternative CPI syscall signature for testing
pub extern "C" fn sol_invoke_signed_c_alt(
    instruction: *const anyopaque,  // Instruction struct pointer
    account_infos: *const anyopaque, // AccountInfo array pointer
    account_infos_len: u64,
    signers_seeds: ?*const anyopaque,
    signers_seeds_len: u64,
) u64;

pub extern "C" fn sol_invoke_signed_rust(
    instruction: *const u8,
    account_infos: *const u8,
    account_infos_len: u64,
    signers_seeds: ?*const u8,
    signers_seeds_len: u64,
) u64;
```

这个是实际的接口和实现
```zig
 /// Declare syscall directly in the struct like solana-program-sdk-zig
    extern fn sol_invoke_signed_c(
        instruction: *const Instruction,
        account_infos: *const anyopaque,  // Will be cast from AccountInfo array
        account_infos_len: usize,
        signer_seeds: ?[*]const []const []const u8,
        signer_seeds_len: usize,
    ) callconv(.C) u64;

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

            // Optimized fallback: use comptime loop unrolling for small arrays
            if (account_infos.len > 0) {
                if (account_infos.len <= 8) {
                    // Stack-allocated small array with unrolled loop
                    var cpi_accounts: [8]CPIAccountInfo = undefined;
                    inline for (0..8) |i| {
                        if (i >= account_infos.len) break;
                        const info = &account_infos[i];
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
                } else {
                    // Fallback for larger arrays
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
                }
            }
        }
        return; // Mock success in test
    }
```

需要研究能使用syscall.zig中定义的吗 一直有问题

## CU优化
