# Solana Environment Detection Implementation

## Overview

The SDK uses a compile-time constant to detect whether the code is running on Solana. This enables zero-cost conditional compilation and ensures the correct code paths are taken for Solana vs. test/debug environments.

## Implementation

### Current Implementation (`is_solana`)

Located in `src/msg/msg.zig`:

```zig
/// Check if we're running on Solana
pub const is_solana = blk: {
    const builtin = @import("builtin");
    const std_inner = @import("std");

    // Not in test mode
    if (builtin.is_test) break :blk false;

    // Check for explicit Solana OS tag
    if (builtin.os.tag == .solana) break :blk true;

    // Check for SBF (Solana Binary Format)
    if (builtin.cpu.arch == .sbf) break :blk true;

    // Check for BPF with Solana features
    if (builtin.os.tag == .freestanding and
        builtin.cpu.arch == .bpfel and
        std_inner.Target.bpf.featureSetHas(builtin.cpu.features, .solana)) {
        break :blk true;
    }

    break :blk false;
};
```

### Debug Mode Detection

```zig
/// Check if we should print debug messages
const should_print_debug = blk: {
    const builtin = @import("builtin");
    // In non-test mode, always print (unless on Solana)
    if (!builtin.is_test and !is_solana) break :blk true;
    // In test mode or on Solana, don't print
    break :blk false;
};
```

## Key Features

### 1. **Compile-Time Constant**
- Zero runtime overhead
- Compiler can optimize away unused branches
- No function call overhead

### 2. **Comprehensive Detection**
- Checks for `.solana` OS tag
- Detects SBF (Solana Binary Format) architecture
- Verifies BPF with Solana feature set
- Excludes test mode to avoid syscall errors

### 3. **Accurate Environment Detection**
- Distinguishes between Solana BPF and other BPF environments
- Verifies the Solana feature set is present
- Ensures freestanding OS for BPF targets

## Usage Examples

### Conditional Syscalls

```zig
pub inline fn msg(message: []const u8) void {
    if (is_solana) {
        // Use Solana syscall
        syscalls.sol_log_(message.ptr, message.len);
    } else if (should_print_debug) {
        // Use standard debug print for testing
        std.debug.print("{s}\n", .{message});
    }
}
```

### Compute Units Logging

```zig
pub inline fn msgComputeUnits() void {
    if (is_solana) {
        syscalls.sol_log_compute_units_();
    } else if (should_print_debug) {
        std.debug.print("Compute units logging not available outside Solana\n", .{});
    }
}
```

### Platform-Specific Code

```zig
pub fn processTransaction() !void {
    if (comptime is_solana) {
        // Solana-specific transaction processing
        try processSolanaTransaction();
    } else {
        // Mock implementation for testing
        try processMockTransaction();
    }
}
```

## Comparison with Alternative Implementations

### Simple Architecture Check (Less Accurate)
```zig
// ❌ Less accurate - may match non-Solana BPF environments
inline fn isSolana() bool {
    const builtin = @import("builtin");
    if (builtin.os.tag == .solana) return true;
    return switch (builtin.target.cpu.arch) {
        .bpfel, .bpfeb, .sbf => true,
        else => false,
    };
}
```

### Feature Set Verification (More Accurate)
```zig
// ✅ More accurate - verifies Solana-specific features
pub const is_solana = blk: {
    // ... includes feature set verification ...
    if (builtin.os.tag == .freestanding and
        builtin.cpu.arch == .bpfel and
        std.Target.bpf.featureSetHas(builtin.cpu.features, .solana)) {
        break :blk true;
    }
    // ...
};
```

## Build Targets

The detection works correctly with these Solana build targets:

### Solana BPF v2
```zig
const target = b.resolveTargetQuery(.{
    .cpu_arch = .sbf,
    .os_tag = .solana,
});
```

### Solana BPF v1
```zig
const target = b.resolveTargetQuery(.{
    .cpu_arch = .bpfel,
    .os_tag = .freestanding,
    .cpu_features_add = std.Target.bpf.featureSet(&.{.solana}),
});
```

## Testing

The implementation correctly handles different scenarios:

1. **Production Solana Environment**: `is_solana = true`
   - Uses Solana syscalls
   - No debug output

2. **Test Environment**: `is_solana = false`
   - Uses mock implementations
   - No syscall attempts

3. **Debug/Development**: `is_solana = false`, `should_print_debug = true`
   - Uses standard library functions
   - Prints debug information

## Benefits

1. **Zero Cost Abstraction**: Compile-time evaluation means no runtime overhead
2. **Safety**: Prevents syscall attempts in non-Solana environments
3. **Testability**: Allows unit testing without Solana runtime
4. **Maintainability**: Single source of truth for environment detection
5. **Optimization**: Compiler can eliminate dead code branches

## Migration Guide

To update existing code:

```zig
// Old function-based approach
inline fn isSolana() bool {
    // ...
}

if (isSolana()) {
    // Solana code
}

// New constant-based approach
pub const is_solana = blk: {
    // ...
};

if (is_solana) {
    // Solana code
}
```

## Conclusion

The `is_solana` compile-time constant provides accurate, zero-cost environment detection for Solana programs. It ensures correct behavior across different environments while maintaining optimal performance through compile-time evaluation.