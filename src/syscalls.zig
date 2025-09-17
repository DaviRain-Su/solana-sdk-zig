/// Solana SBF/BPF syscall bindings
const std = @import("std");
const Pubkey = @import("pubkey.zig").Pubkey;

/// Success return code for syscalls
pub const SUCCESS: u64 = 0;

// Logging syscalls
pub extern "C" fn sol_log_(message: [*]const u8, len: u64) void;
pub extern "C" fn sol_log_64_(p0: u64, p1: u64, p2: u64, p3: u64, p4: u64) void;
pub extern "C" fn sol_log_pubkey(pubkey: *const u8) void;
pub extern "C" fn sol_log_compute_units_() void;
pub extern "C" fn sol_log_data(data: [*]const [*]const u8, len: u64) void;

// Program address syscalls
pub extern "C" fn sol_create_program_address(
    seeds: [*]const [*]const u8,
    seeds_len: u64,
    program_id: *const u8,
    address: *u8,
) u64;

pub extern "C" fn sol_try_find_program_address(
    seeds: [*]const [*]const u8,
    seeds_len: u64,
    program_id: *const u8,
    address: *u8,
    bump_seed: *u8,
) u64;

// SHA256 syscall
pub extern "C" fn sol_sha256(
    vals: [*]const u8,
    vals_len: u64,
    hash_result: *u8,
) void;

// Memory syscalls
pub extern "C" fn sol_memcpy_(dst: *u8, src: *const u8, n: u64) void;
pub extern "C" fn sol_memset_(dst: *u8, val: u8, n: u64) void;
pub extern "C" fn sol_memcmp_(s1: *const u8, s2: *const u8, n: u64, result: *i32) void;

// CPI syscalls
pub extern "C" fn sol_invoke_signed_c(
    instruction: *const u8,
    account_infos: *const u8,
    account_infos_len: u64,
    signers_seeds: ?*const u8,
    signers_seeds_len: u64,
) u64;

pub extern "C" fn sol_invoke_signed_rust(
    instruction: *const u8,
    account_infos: *const u8,
    account_infos_len: u64,
    signers_seeds: ?*const u8,
    signers_seeds_len: u64,
) u64;

// Account data syscalls
pub extern "C" fn sol_set_return_data(data: *const u8, len: u64) void;
pub extern "C" fn sol_get_return_data(data: *u8, len: u64, program_id: *Pubkey) u64;

// Sysvar syscalls
pub extern "C" fn sol_get_clock_sysvar(clock: *u8) u64;
pub extern "C" fn sol_get_rent_sysvar(rent: *u8) u64;
pub extern "C" fn sol_get_epoch_schedule_sysvar(epoch_schedule: *u8) u64;
pub extern "C" fn sol_get_last_restart_slot(slot: *u64) u64;

// Helper functions for type-safe syscall wrappers
pub inline fn log(message: []const u8) void {
    sol_log_(message.ptr, message.len);
}

pub inline fn logPubkey(pubkey: *const Pubkey) void {
    sol_log_pubkey(@ptrCast(pubkey));
}

pub inline fn logComputeUnits() void {
    sol_log_compute_units_();
}

pub inline fn sha256(vals: []const u8, hash_result: *[32]u8) void {
    sol_sha256(vals.ptr, vals.len, @ptrCast(hash_result));
}