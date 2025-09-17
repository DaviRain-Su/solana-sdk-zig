# Syscall Wrapper Functions Summary

## Overview
This document lists all the wrapper functions added to `syscalls.zig` to provide Zig-idiomatic interfaces for Solana's C-style syscalls.

## Wrapper Functions Implemented

### 1. Logging Functions
- `log(message: []const u8)` - Log a message
- `logPubkey(pubkey: *const Pubkey)` - Log a public key
- `logComputeUnits()` - Log compute units consumed
- `log64(p0-p4: u64)` - Log 64-bit values
- `logData(data_vec: []const []const u8)` - Log data arrays
- `logFormatted(fmt, args)` - Log formatted strings
- `logPubkeys(keys: []const Pubkey)` - Log multiple pubkeys

### 2. Program Address Functions
- `createProgramAddress(seeds, program_id, address)` - Create PDA with detailed error handling
- `tryFindProgramAddress(seeds, program_id, address, bump)` - Find PDA with bump
- `findProgramAddress(seeds, program_id)` - Returns ProgramDerivedAddress struct
- `createPDA(seeds, program_id)` - Simple PDA creation returning Pubkey
- `findPDA(seeds, program_id)` - Simple PDA finding with bump

### 3. Cryptographic Functions
- `sha256(vals, hash_result)` - SHA256 hashing
- `keccak256(vals, hash_result)` - Keccak256 hashing with error handling
- `blake3(vals, hash_result)` - Blake3 hashing with error handling
- `poseidon(endianness, vals, hash_result)` - Poseidon hashing
- `secp256k1Recover(hash, recovery_id, signature, pubkey_result)` - Secp256k1 recovery

### 4. Memory Operations
- `memcpy(dst, src)` - Safe memory copy
- `memmove(dst, src)` - Safe memory move
- `memset(dst, val)` - Memory set
- `memcmp(s1, s2)` - Memory compare with proper length handling

### 5. Sysvar Accessors
- `getClock()` - Returns Clock struct
- `getRent()` - Returns Rent struct
- `getEpochSchedule()` - Returns EpochSchedule struct
- `getFees()` - Returns Fees struct
- `getEpochRewards()` - Returns EpochRewards struct
- `getLastRestartSlot()` - Get last restart slot
- `getEpochStake(address)` - Get epoch stake for address

### 6. Cross-Program Invocation (CPI)
- `invoke(instruction, account_infos)` - Simple program invocation
- `invokeSigned(instruction, account_infos, signers_seeds)` - Signed invocation

### 7. Curve Operations
- `curveValidatePoint(curve_id, point)` - Validate curve point
- `curveGroupOp(curve_id, op, left, right, result)` - Curve group operations
- `curveMultiscalarMul(curve_id, scalars, points, points_len, result)` - Multiscalar multiplication
- `curvePairingMap(curve_id, point, result)` - Pairing map
- `altBn128GroupOp(op, input, result)` - ALT BN128 group operations
- `altBn128Compression(op, input, result)` - ALT BN128 compression

### 8. Program Context Functions
- `getRemainingComputeUnits()` - Get remaining CU
- `getStackHeight()` - Get current stack height
- `setReturnData(data)` - Set return data
- `getReturnData(data, program_id)` - Get return data with error handling
- `getProcessedSiblingInstruction(index, result)` - Get sibling instruction

### 9. Utility Functions
- `bigModExp(params, result)` - Big modular exponentiation
- `checkSuccess(result)` - Check syscall success
- `convertError(result)` - Convert error codes to Zig errors
- `assert(condition, message)` - Assertion with panic message
- `panic(message)` - Panic with log message

## Key Design Decisions

### 1. Type Conversion
All wrappers handle the conversion between Zig types and C types:
- `[]const u8` → `[*]const u8` with length
- `*const Pubkey` → `*const u8` via `@ptrCast`
- Slice arrays → Pointer arrays for seeds

### 2. Error Handling
- Functions that can fail return error unions (`!T`)
- Success codes are checked and converted to meaningful errors
- Error names are descriptive (e.g., `error.MaxSeedLengthExceeded`)

### 3. Memory Safety
- Input validation (seed lengths, array bounds)
- Buffer size checks to prevent overflows
- Assertions for debug builds

### 4. Performance
- All wrappers are `inline` for zero-cost abstraction
- No heap allocations
- Stack buffers for temporary data

## Usage Examples

### Creating a PDA
```zig
const seeds = [_][]const u8{ "vault", user_key.bytes[0..] };
const pda = try syscalls.findPDA(&seeds, &program_id);
// pda.address - the derived address
// pda.bump - the bump seed
```

### Logging
```zig
syscalls.log("Processing transaction");
syscalls.logPubkey(&user_key);
syscalls.logFormatted("Amount: {} lamports", .{amount});
```

### Getting Sysvars
```zig
const clock = try syscalls.getClock();
const rent = try syscalls.getRent();
const min_balance = rent.minimum_balance(data_len);
```

### CPI
```zig
try syscalls.invoke(instruction_data, account_infos);
// or with signers
try syscalls.invokeSigned(instruction_data, account_infos, signer_seeds);
```

## Compatibility

These wrappers are designed to work with:
- Solana BPF/SBF runtime
- Zig 0.14.0 and later
- Both on-chain and local testing environments

## Testing

All wrapper functions are tested through:
1. Unit tests in `src/root.zig`
2. Integration tests with example programs
3. CU consumption benchmarks

## Notes

- The wrappers complement the higher-level implementations in `pubkey/pubkey.zig`
- Both approaches (syscalls.zig wrappers and pubkey.zig implementations) are valid
- Choose based on your needs: low-level control vs type safety