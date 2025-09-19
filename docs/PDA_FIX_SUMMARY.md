# PDA Implementation Fix Summary

## Problem Description
Program Derived Address (PDA) generation in Zig was producing different addresses than the JavaScript SDK, causing cross-program invocations to fail.

### Symptoms
- JS calculated PDA: `BPmmMv4A3NemDhvDiQo2WXqHeH27EsQKCpLJSY7jr3Sz`
- Zig calculated PDA: Different address each time
- Error: `PDA mismatch: expected X, got Y`
- CPI operations failed with error 0x2b (InvalidSeeds)

## Root Cause

The syscall function signatures in `syscalls.zig` were incorrectly declared:

### Incorrect Declaration
```zig
pub extern "C" fn sol_try_find_program_address(
    seeds: [*]const [*]const u8,  // ❌ Wrong: pointer to array of pointers
    seeds_len: u64,
    program_id: *const u8,
    address: *u8,
    bump_seed: *u8,
) u64;
```

### Correct Declaration
```zig
pub extern "C" fn sol_try_find_program_address(
    seeds: [*]const []const u8,   // ✅ Correct: pointer to array of slices
    seeds_len: u64,
    program_id: *const u8,
    address: *u8,
    bump_seed: *u8,
) u64;
```

## Why This Matters

### Memory Layout Difference

1. **Pointer (`[*]const u8`)**: 8 bytes
   ```
   [ptr_to_data]
   ```

2. **Slice (`[]const u8`)**: 16 bytes
   ```
   [ptr_to_data][length]
   ```

### Impact on PDA Generation

Solana's runtime needs to know the length of each seed to correctly compute the PDA hash. When we passed pointers instead of slices:

1. Runtime couldn't determine seed lengths
2. Read incorrect memory as seed data
3. Computed wrong SHA256 hash
4. Generated different PDA address

## Files Modified

1. **`src/syscalls.zig`**:
   - Fixed `sol_create_program_address` signature
   - Fixed `sol_try_find_program_address` signature
   - Updated wrapper functions to pass `seeds.ptr` directly

2. **`examples/programs/cpi_example/src/lib.zig`**:
   - Updated to use `Pubkey.findProgramAddress` from SDK
   - Added debug logging to verify PDA calculation

## Performance Impact

After the fix:
- PDA generation: ~29,435 CU (first calculation)
- PDA with CPI: ~32,750 CU (including System Program invocation)
- Basic CPI transfer: 3,710 CU (unchanged)

## Lessons Learned

1. **ABI Compatibility is Critical**: When interfacing with C/system calls, the exact memory layout must match what the runtime expects.

2. **Slices vs Pointers**: In Zig/Solana context:
   - Use slices (`[]const u8`) when length information is needed
   - Use pointers (`[*]const u8`) only for raw memory access

3. **Reference Implementations**: When in doubt, check working implementations (like `solana-program-sdk-zig`) for correct signatures.

## Testing

### Test Code
```javascript
// Verify PDA calculation matches between JS and Zig
const seed = Buffer.from("vault");
const [pda, bump] = await PublicKey.findProgramAddress([seed], PROGRAM_ID);
```

### Expected Result
Both JS and Zig should produce the same PDA for identical seeds and program ID.

## Prevention

To prevent similar issues:

1. **Always verify syscall signatures** against working implementations
2. **Test PDA generation** against known good values from JS/Rust SDKs
3. **Use proper types**:
   - `[]const u8` for variable-length data with known size
   - `[*]const u8` for raw pointer arithmetic only
4. **Add integration tests** that verify PDA addresses match across implementations

## Related Issues

- The same issue affected `sol_create_program_address`
- Other syscalls like `sol_log_data` may use different patterns and should be verified case-by-case