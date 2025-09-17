# Solana Syscalls Implementation in Zig

## Overview
This document describes the complete syscall implementation for Solana programs in Zig, based on the Rust Pinocchio implementation.

## Implemented Syscalls

### 1. Logging Syscalls
- `sol_log_` - Log a message
- `sol_log_64_` - Log 64-bit values
- `sol_log_pubkey` - Log a public key
- `sol_log_compute_units_` - Log computational units
- `sol_log_data` - Log data arrays

### 2. Cryptographic Syscalls
- `sol_sha256` - Compute SHA-256 hash
- `sol_keccak256` - Compute Keccak-256 hash
- `sol_blake3` - Compute Blake3 hash
- `sol_secp256k1_recover` - Recover secp256k1 public key
- `sol_poseidon` - Compute Poseidon hash

### 3. System Variable Syscalls
- `sol_get_clock_sysvar` - Get clock sysvar
- `sol_get_epoch_schedule_sysvar` - Get epoch schedule
- `sol_get_fees_sysvar` - Get fees sysvar
- `sol_get_rent_sysvar` - Get rent sysvar
- `sol_get_last_restart_slot` - Get last restart slot
- `sol_get_epoch_rewards_sysvar` - Get epoch rewards
- `sol_get_epoch_stake` - Get epoch stake

### 4. Memory Management Syscalls
- `sol_memcpy_` - Memory copy
- `sol_memmove_` - Memory move
- `sol_memcmp_` - Memory compare
- `sol_memset_` - Memory set

### 5. Cross-Program Invocation (CPI) Syscalls
- `sol_invoke_signed_c` - Invoke signed (C ABI)
- `sol_invoke_signed_rust` - Invoke signed (Rust ABI)
- `sol_set_return_data` - Set return data
- `sol_get_return_data` - Get return data

### 6. Program and Instruction Syscalls
- `sol_get_stack_height` - Get current stack height
- `sol_get_processed_sibling_instruction` - Get sibling instruction
- `sol_remaining_compute_units` - Get remaining compute units

### 7. Curve Operations Syscalls
- `sol_curve_validate_point` - Validate curve point
- `sol_curve_group_op` - Perform curve group operation
- `sol_curve_multiscalar_mul` - Multiscalar multiplication
- `sol_curve_pairing_map` - Pairing map operation
- `sol_alt_bn128_group_op` - ALT BN128 group operation
- `sol_alt_bn128_compression` - ALT BN128 compression

### 8. Big Integer Arithmetic
- `sol_big_mod_exp` - Big modular exponentiation

## Helper Functions

The implementation provides type-safe Zig wrappers for all syscalls:

### Logging Helpers
- `log(message: []const u8)` - Log a message
- `logPubkey(pubkey: *const Pubkey)` - Log a public key
- `logComputeUnits()` - Log compute units
- `log64(p0, p1, p2, p3, p4)` - Log 64-bit values
- `logData(data_vec: []const []const u8)` - Log data arrays

### Cryptographic Helpers
- `sha256(vals, hash_result)` - Compute SHA-256
- `keccak256(vals, hash_result)` - Compute Keccak-256
- `blake3(vals, hash_result)` - Compute Blake3
- `poseidon(endianness, vals, hash_result)` - Compute Poseidon
- `secp256k1Recover(hash, recovery_id, signature, pubkey_result)` - Recover public key

### Memory Helpers
- `memcpy(dst, src)` - Copy memory
- `memmove(dst, src)` - Move memory
- `memset(dst, val)` - Set memory
- `memcmp(s1, s2)` - Compare memory

### System Helpers
- `getRemainingComputeUnits()` - Get remaining CUs
- `getStackHeight()` - Get stack height
- `setReturnData(data)` - Set return data
- `getReturnData(data, program_id)` - Get return data
- `getLastRestartSlot()` - Get last restart slot
- `getEpochStake(address)` - Get epoch stake

### Curve Operation Helpers
- `curveValidatePoint(curve_id, point)` - Validate point
- `curveGroupOp(curve_id, op, left, right, result)` - Group operation
- `bigModExp(params, result)` - Modular exponentiation

## Constants and Enums

### CurveId
```zig
pub const CurveId = enum(u64) {
    Ed25519 = 0,
    Ristretto255 = 1,
    Secp256k1 = 2,
};
```

### CurveGroupOp
```zig
pub const CurveGroupOp = enum(u64) {
    Add = 0,
    Sub = 1,
    Mul = 2,
};
```

### AltBn128GroupOp
```zig
pub const AltBn128GroupOp = enum(u64) {
    Add = 0,
    Sub = 1,
    Mul = 2,
};
```

### AltBn128Compression
```zig
pub const AltBn128Compression = enum(u64) {
    Decompress = 0,
    Compress = 1,
};
```

### PoseidonEndianness
```zig
pub const PoseidonEndianness = enum(u64) {
    BigEndian = 0,
    LittleEndian = 1,
};
```

## Usage Examples

### Logging
```zig
const syscalls = @import("syscalls.zig");

// Log a message
syscalls.log("Hello from Solana!");

// Log a public key
const pubkey = Pubkey.fromString("...");
syscalls.logPubkey(&pubkey);

// Log compute units
syscalls.logComputeUnits();
```

### Cryptography
```zig
// Compute SHA256
var hash_result: [32]u8 = undefined;
syscalls.sha256(data, &hash_result);

// Compute Keccak256
try syscalls.keccak256(data, &hash_result);

// Recover secp256k1 public key
var pubkey_result: [64]u8 = undefined;
try syscalls.secp256k1Recover(&hash, recovery_id, &signature, &pubkey_result);
```

### Memory Operations
```zig
// Copy memory
syscalls.memcpy(dst[0..], src[0..]);

// Compare memory
const cmp = syscalls.memcmp(s1[0..], s2[0..]);
```

### System Information
```zig
// Get remaining compute units
const cu = syscalls.getRemainingComputeUnits();

// Get stack height
const height = syscalls.getStackHeight();

// Get last restart slot
const slot = try syscalls.getLastRestartSlot();
```

## Testing

All syscall wrappers have been tested with:
- ✅ Build verification
- ✅ Type safety checks
- ✅ Error handling validation
- ✅ Integration with existing SDK components

## Compatibility

This implementation is fully compatible with:
- Solana BPF/SBF runtime
- Rust Pinocchio syscall ABI
- Existing Solana program standards

## Performance Considerations

All syscall wrappers are marked as `inline` to ensure:
- Zero overhead function calls
- Direct syscall invocation
- Minimal stack usage
- Optimal CU consumption