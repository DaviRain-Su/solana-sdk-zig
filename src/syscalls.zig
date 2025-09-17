/// Solana SBF/BPF syscall bindings
const std = @import("std");
const Pubkey = @import("pubkey/pubkey.zig").Pubkey;

/// Success return code for syscalls
pub const SUCCESS: u64 = 0;

/// Curve IDs for curve operations
pub const CurveId = enum(u64) {
    Ed25519 = 0,
    Ristretto255 = 1,
    Secp256k1 = 2,
};

/// Group operations for curve syscalls
pub const CurveGroupOp = enum(u64) {
    Add = 0,
    Sub = 1,
    Mul = 2,
};

/// ALT BN128 Group operations
pub const AltBn128GroupOp = enum(u64) {
    Add = 0,
    Sub = 1,
    Mul = 2,
};

/// ALT BN128 Compression operations
pub const AltBn128Compression = enum(u64) {
    Decompress = 0,
    Compress = 1,
};

/// Poseidon endianness
pub const PoseidonEndianness = enum(u64) {
    BigEndian = 0,
    LittleEndian = 1,
};

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
pub extern "C" fn sol_get_fees_sysvar(fees: *u8) u64;
pub extern "C" fn sol_get_epoch_rewards_sysvar(rewards: *u8) u64;

// Additional cryptographic syscalls
pub extern "C" fn sol_keccak256(vals: [*]const u8, vals_len: u64, hash_result: *u8) u64;
pub extern "C" fn sol_blake3(vals: [*]const u8, vals_len: u64, hash_result: *u8) u64;
pub extern "C" fn sol_secp256k1_recover(
    hash: *const u8,
    recovery_id: u64,
    signature: *const u8,
    result: *u8,
) u64;
pub extern "C" fn sol_poseidon(
    endianness: u64,
    vals: [*]const u8,
    vals_len: u64,
    hash_result: *u8,
) u64;

// Curve operations syscalls
pub extern "C" fn sol_curve_validate_point(
    curve_id: u64,
    point: *const u8,
    result: *u8,
) u64;

pub extern "C" fn sol_curve_group_op(
    curve_id: u64,
    group_op: u64,
    left: *const u8,
    right: *const u8,
    result: *u8,
) u64;

pub extern "C" fn sol_curve_multiscalar_mul(
    curve_id: u64,
    scalars: *const u8,
    points: *const u8,
    points_len: u64,
    result: *u8,
) u64;

pub extern "C" fn sol_curve_pairing_map(
    curve_id: u64,
    point: *const u8,
    result: *u8,
) u64;

pub extern "C" fn sol_alt_bn128_group_op(
    group_op: u64,
    input: *const u8,
    input_size: u64,
    result: *u8,
) u64;

pub extern "C" fn sol_alt_bn128_compression(
    op: u64,
    input: *const u8,
    input_size: u64,
    result: *u8,
) u64;

// Big integer modular arithmetic syscalls
pub extern "C" fn sol_big_mod_exp(
    params: *const u8,
    result: *u8,
) u64;

// Program and instruction syscalls
pub extern "C" fn sol_get_stack_height() u64;
pub extern "C" fn sol_get_processed_sibling_instruction(
    index: u64,
    result: *u8,
) u64;

// Memory management
pub extern "C" fn sol_memmove_(dst: *u8, src: *const u8, n: u64) void;

// Remaining account data syscall
pub extern "C" fn sol_get_epoch_stake(address: *const u8) u64;

// CPI and context syscalls
pub extern "C" fn sol_remaining_compute_units() u64;

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

/// Compute Keccak256 hash
pub inline fn keccak256(vals: []const u8, hash_result: *[32]u8) !void {
    const result = sol_keccak256(vals.ptr, vals.len, @ptrCast(hash_result));
    if (result != SUCCESS) return error.Keccak256Failed;
}

/// Compute Blake3 hash
pub inline fn blake3(vals: []const u8, hash_result: *[32]u8) !void {
    const result = sol_blake3(vals.ptr, vals.len, @ptrCast(hash_result));
    if (result != SUCCESS) return error.Blake3Failed;
}

/// Compute Poseidon hash
pub inline fn poseidon(endianness: PoseidonEndianness, vals: []const u8, hash_result: *[32]u8) !void {
    const result = sol_poseidon(@intFromEnum(endianness), vals.ptr, vals.len, @ptrCast(hash_result));
    if (result != SUCCESS) return error.PoseidonFailed;
}

/// Recover secp256k1 public key
pub inline fn secp256k1Recover(
    hash: *const [32]u8,
    recovery_id: u8,
    signature: *const [64]u8,
    pubkey_result: *[64]u8,
) !void {
    const result = sol_secp256k1_recover(
        @ptrCast(hash),
        recovery_id,
        @ptrCast(signature),
        @ptrCast(pubkey_result),
    );
    if (result != SUCCESS) return error.Secp256k1RecoverFailed;
}

/// Memory copy
pub inline fn memcpy(dst: []u8, src: []const u8) void {
    std.debug.assert(dst.len >= src.len);
    sol_memcpy_(dst.ptr, src.ptr, @min(dst.len, src.len));
}

/// Memory move
pub inline fn memmove(dst: []u8, src: []const u8) void {
    std.debug.assert(dst.len >= src.len);
    sol_memmove_(dst.ptr, src.ptr, @min(dst.len, src.len));
}

/// Memory set
pub inline fn memset(dst: []u8, val: u8) void {
    sol_memset_(dst.ptr, val, dst.len);
}

/// Memory compare
pub inline fn memcmp(s1: []const u8, s2: []const u8) i32 {
    var result: i32 = 0;
    const len = @min(s1.len, s2.len);
    sol_memcmp_(s1.ptr, s2.ptr, len, &result);
    if (result == 0 and s1.len != s2.len) {
        return if (s1.len < s2.len) @as(i32, -1) else @as(i32, 1);
    }
    return result;
}

/// Get remaining compute units
pub inline fn getRemainingComputeUnits() u64 {
    return sol_remaining_compute_units();
}

/// Get stack height
pub inline fn getStackHeight() u64 {
    return sol_get_stack_height();
}

/// Set return data
pub inline fn setReturnData(data: []const u8) void {
    sol_set_return_data(data.ptr, data.len);
}

/// Get return data
pub inline fn getReturnData(data: []u8, program_id: *Pubkey) !usize {
    const result = sol_get_return_data(data.ptr, data.len, program_id);
    if (result == std.math.maxInt(u64)) {
        return error.ReturnDataTooLarge;
    }
    return result;
}

/// Log 64-bit values
pub inline fn log64(p0: u64, p1: u64, p2: u64, p3: u64, p4: u64) void {
    sol_log_64_(p0, p1, p2, p3, p4);
}

/// Log data
pub inline fn logData(data_vec: []const []const u8) void {
    var data_ptrs: [16][*]const u8 = undefined;
    const len = @min(data_vec.len, data_ptrs.len);
    for (data_vec[0..len], 0..) |data, i| {
        data_ptrs[i] = data.ptr;
    }
    sol_log_data(@ptrCast(&data_ptrs), len);
}

/// Validate curve point
pub inline fn curveValidatePoint(curve_id: CurveId, point: []const u8) !void {
    var result: u8 = 0;
    const ret = sol_curve_validate_point(@intFromEnum(curve_id), point.ptr, &result);
    if (ret != SUCCESS or result == 0) {
        return error.InvalidCurvePoint;
    }
}

/// Curve group operation
pub inline fn curveGroupOp(
    curve_id: CurveId,
    op: CurveGroupOp,
    left: []const u8,
    right: []const u8,
    result: []u8,
) !void {
    const ret = sol_curve_group_op(
        @intFromEnum(curve_id),
        @intFromEnum(op),
        left.ptr,
        right.ptr,
        result.ptr,
    );
    if (ret != SUCCESS) return error.CurveOperationFailed;
}

/// Big modular exponentiation
pub inline fn bigModExp(params: []const u8, result: []u8) !void {
    const ret = sol_big_mod_exp(params.ptr, result.ptr);
    if (ret != SUCCESS) return error.BigModExpFailed;
}

/// Get last restart slot
pub inline fn getLastRestartSlot() !u64 {
    var slot: u64 = 0;
    const result = sol_get_last_restart_slot(&slot);
    if (result != SUCCESS) return error.GetLastRestartSlotFailed;
    return slot;
}

/// Get epoch stake
pub inline fn getEpochStake(address: *const Pubkey) u64 {
    return sol_get_epoch_stake(@ptrCast(address));
}

// ============================================================================
// Program Address Syscall Wrappers
// ============================================================================

/// Create a program address from seeds
/// This wrapper handles the conversion between Zig slices and C pointers
pub inline fn createProgramAddress(
    seeds: []const []const u8,
    program_id: *const Pubkey,
    address: *Pubkey,
) !void {
    // Validate input
    if (seeds.len > 16) return error.TooManySeeds;
    for (seeds) |seed| {
        if (seed.len > 32) return error.SeedTooLong;
    }

    // Convert Zig slices to C pointers
    var seed_ptrs: [16][*]const u8 = undefined;
    for (seeds, 0..) |seed, i| {
        seed_ptrs[i] = seed.ptr;
    }

    const result = sol_create_program_address(
        @ptrCast(&seed_ptrs),
        seeds.len,
        @ptrCast(&program_id.bytes),
        @ptrCast(&address.bytes),
    );

    if (result != SUCCESS) {
        return switch (result) {
            1 => error.MaxSeedLengthExceeded,
            2 => error.InvalidSeeds,
            3 => error.IllegalOwner,
            else => error.CreateProgramAddressFailed,
        };
    }
}

/// Try to find a program address with bump seed
/// This wrapper handles the conversion between Zig slices and C pointers
pub inline fn tryFindProgramAddress(
    seeds: []const []const u8,
    program_id: *const Pubkey,
    address: *Pubkey,
    bump_seed: *u8,
) !void {
    // Validate input
    if (seeds.len > 16) return error.TooManySeeds;
    for (seeds) |seed| {
        if (seed.len > 32) return error.SeedTooLong;
    }

    // Convert Zig slices to C pointers
    var seed_ptrs: [16][*]const u8 = undefined;
    for (seeds, 0..) |seed, i| {
        seed_ptrs[i] = seed.ptr;
    }

    const result = sol_try_find_program_address(
        @ptrCast(&seed_ptrs),
        seeds.len,
        @ptrCast(&program_id.bytes),
        @ptrCast(&address.bytes),
        bump_seed,
    );

    if (result != SUCCESS) {
        return switch (result) {
            1 => error.MaxSeedLengthExceeded,
            2 => error.InvalidSeeds,
            3 => error.NoViableBump,
            else => error.FindProgramAddressFailed,
        };
    }
}

/// Higher-level wrapper that returns the PDA and bump
pub const ProgramDerivedAddress = struct {
    address: Pubkey,
    bump: u8,
};

/// Find a program address and return both address and bump
pub inline fn findProgramAddress(
    seeds: []const []const u8,
    program_id: *const Pubkey,
) !ProgramDerivedAddress {
    var address: Pubkey = undefined;
    var bump: u8 = undefined;

    try tryFindProgramAddress(seeds, program_id, &address, &bump);

    return ProgramDerivedAddress{
        .address = address,
        .bump = bump,
    };
}

/// Create a program address (simple version without error details)
pub inline fn createPDA(
    seeds: []const []const u8,
    program_id: *const Pubkey,
) !Pubkey {
    var address: Pubkey = undefined;
    try createProgramAddress(seeds, program_id, &address);
    return address;
}

/// Find PDA with automatic bump seed management
pub inline fn findPDA(
    seeds: []const []const u8,
    program_id: *const Pubkey,
) !ProgramDerivedAddress {
    return findProgramAddress(seeds, program_id);
}

// ============================================================================
// Sysvar Accessor Wrappers
// ============================================================================

/// Clock sysvar structure
pub const Clock = extern struct {
    slot: u64,
    epoch_start_timestamp: i64,
    epoch: u64,
    leader_schedule_epoch: u64,
    unix_timestamp: i64,
};

/// Rent sysvar structure
pub const Rent = extern struct {
    lamports_per_byte_year: u64,
    exemption_threshold: f64,
    burn_percent: u8,
};

/// EpochSchedule sysvar structure
pub const EpochSchedule = extern struct {
    slots_per_epoch: u64,
    leader_schedule_slot_offset: u64,
    warmup: bool,
    first_normal_epoch: u64,
    first_normal_slot: u64,
};

/// Get clock sysvar
pub inline fn getClock() !Clock {
    var clock: Clock = undefined;
    const result = sol_get_clock_sysvar(@ptrCast(&clock));
    if (result != SUCCESS) return error.GetClockFailed;
    return clock;
}

/// Get rent sysvar
pub inline fn getRent() !Rent {
    var rent: Rent = undefined;
    const result = sol_get_rent_sysvar(@ptrCast(&rent));
    if (result != SUCCESS) return error.GetRentFailed;
    return rent;
}

/// Get epoch schedule sysvar
pub inline fn getEpochSchedule() !EpochSchedule {
    var schedule: EpochSchedule = undefined;
    const result = sol_get_epoch_schedule_sysvar(@ptrCast(&schedule));
    if (result != SUCCESS) return error.GetEpochScheduleFailed;
    return schedule;
}

// ============================================================================
// CPI (Cross-Program Invocation) Wrappers
// ============================================================================

/// Invoke a program with signed seeds
pub inline fn invoke(
    instruction: []const u8,
    account_infos: []const u8,
) !void {
    const result = sol_invoke_signed_c(
        instruction.ptr,
        account_infos.ptr,
        account_infos.len,
        null,
        0,
    );
    if (result != SUCCESS) {
        return error.InvokeFailed;
    }
}

/// Invoke a program with signed seeds
pub inline fn invokeSigned(
    instruction: []const u8,
    account_infos: []const u8,
    signers_seeds: []const []const []const u8,
) !void {
    // Convert signer seeds to the expected format
    var seeds_buffer: [256]u8 = undefined;
    var offset: usize = 0;

    for (signers_seeds) |signer| {
        if (offset >= seeds_buffer.len) return error.BufferTooSmall;
        seeds_buffer[offset] = @intCast(signer.len);
        offset += 1;

        for (signer) |seed| {
            if (offset + seed.len > seeds_buffer.len) return error.BufferTooSmall;
            @memcpy(seeds_buffer[offset..][0..seed.len], seed);
            offset += seed.len;
        }
    }

    const result = sol_invoke_signed_c(
        instruction.ptr,
        account_infos.ptr,
        account_infos.len,
        &seeds_buffer,
        offset,
    );

    if (result != SUCCESS) {
        return error.InvokeSignedFailed;
    }
}

// ============================================================================
// Additional Curve Operation Wrappers
// ============================================================================

/// Curve multiscalar multiplication
pub inline fn curveMultiscalarMul(
    curve_id: CurveId,
    scalars: []const u8,
    points: []const u8,
    points_len: u64,
    result: []u8,
) !void {
    const ret = sol_curve_multiscalar_mul(
        @intFromEnum(curve_id),
        scalars.ptr,
        points.ptr,
        points_len,
        result.ptr,
    );
    if (ret != SUCCESS) return error.CurveMultiscalarMulFailed;
}

/// Curve pairing map
pub inline fn curvePairingMap(
    curve_id: CurveId,
    point: []const u8,
    result: []u8,
) !void {
    const ret = sol_curve_pairing_map(
        @intFromEnum(curve_id),
        point.ptr,
        result.ptr,
    );
    if (ret != SUCCESS) return error.CurvePairingMapFailed;
}

/// ALT BN128 group operation
pub inline fn altBn128GroupOp(
    op: AltBn128GroupOp,
    input: []const u8,
    result: []u8,
) !void {
    const ret = sol_alt_bn128_group_op(
        @intFromEnum(op),
        input.ptr,
        input.len,
        result.ptr,
    );
    if (ret != SUCCESS) return error.AltBn128GroupOpFailed;
}

/// ALT BN128 compression operation
pub inline fn altBn128Compression(
    op: AltBn128Compression,
    input: []const u8,
    result: []u8,
) !void {
    const ret = sol_alt_bn128_compression(
        @intFromEnum(op),
        input.ptr,
        input.len,
        result.ptr,
    );
    if (ret != SUCCESS) return error.AltBn128CompressionFailed;
}

// ============================================================================
// Processed Instruction Wrapper
// ============================================================================

/// Get processed sibling instruction
pub inline fn getProcessedSiblingInstruction(index: u64, result: []u8) !void {
    const ret = sol_get_processed_sibling_instruction(index, result.ptr);
    if (ret != SUCCESS) return error.GetProcessedSiblingInstructionFailed;
}

// ============================================================================
// Additional Sysvar Wrappers
// ============================================================================

/// Fees sysvar structure
pub const Fees = extern struct {
    fee_calculator: FeeCalculator,
};

pub const FeeCalculator = extern struct {
    lamports_per_signature: u64,
};

/// EpochRewards sysvar structure
pub const EpochRewards = extern struct {
    distribution_starting_block_height: u64,
    num_partitions: u64,
    parent_blockhash: [32]u8,
    total_points: u128,
    total_rewards: u64,
    distributed_rewards: u64,
    active: bool,
};

/// Get fees sysvar
pub inline fn getFees() !Fees {
    var fees: Fees = undefined;
    const result = sol_get_fees_sysvar(@ptrCast(&fees));
    if (result != SUCCESS) return error.GetFeesFailed;
    return fees;
}

/// Get epoch rewards sysvar
pub inline fn getEpochRewards() !EpochRewards {
    var rewards: EpochRewards = undefined;
    const result = sol_get_epoch_rewards_sysvar(@ptrCast(&rewards));
    if (result != SUCCESS) return error.GetEpochRewardsFailed;
    return rewards;
}

// ============================================================================
// Utility Helper Functions
// ============================================================================

/// Check if a syscall was successful
pub inline fn checkSuccess(result: u64) !void {
    if (result != SUCCESS) {
        return error.SyscallFailed;
    }
}

/// Convert error code to error
pub inline fn convertError(result: u64) !void {
    return switch (result) {
        SUCCESS => {},
        1 => error.InvalidArgument,
        2 => error.InvalidSeeds,
        3 => error.InvalidOwner,
        else => error.UnknownError,
    };
}

// ============================================================================
// Debug Helper Functions
// ============================================================================

/// Log a formatted string with values
pub fn logFormatted(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch "log format error";
    log(msg);
}

/// Log multiple pubkeys
pub fn logPubkeys(keys: []const Pubkey) void {
    for (keys) |key| {
        logPubkey(&key);
    }
}

/// Panic with a message (for debugging)
pub fn panic(message: []const u8) noreturn {
    log(message);
    @panic(message);
}

/// Assert with message
pub inline fn assert(condition: bool, message: []const u8) void {
    if (!condition) {
        panic(message);
    }
}