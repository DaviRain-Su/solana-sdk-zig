# Pinocchio-Zig Development Guide

## Project Overview

Pinocchio-Zig is a zero-dependency, zero-copy Solana program framework for Zig, inspired by [anza-xyz/pinocchio](https://github.com/anza-xyz/pinocchio). It leverages Zig's compile-time capabilities to minimize Compute Unit (CU) consumption while maintaining developer ergonomics.

### Core Philosophy

- **Zero Dependencies**: No external libraries except Solana syscalls
- **Zero Copy**: Direct memory mapping using Zig's `@ptrCast`/`@alignCast`
- **No Allocations**: All memory is either stack-allocated or uses provided account buffers
- **Compile-Time First**: Leverage Zig's `comptime` for static validation and optimization
- **Explicit Over Implicit**: No hidden costs or magic behavior
- **CU Optimization**: Every abstraction must justify its runtime cost

## Architecture Overview

### Module Mapping: Rust Pinocchio → Zig Pinocchio

| Rust Module | Zig Module | Purpose |
|------------|------------|---------|
| `entrypoint/mod.rs` | `entrypoint.zig` | Standard program entrypoint |
| `entrypoint/lazy.rs` | `lazy_entrypoint.zig` | Lazy parsing entrypoint |
| `account_info.rs` | `account_info.zig` | Account data structures |
| `pubkey.rs` | `pubkey.zig` | Public key type and operations |
| `instruction.rs` | `instruction.zig` | Instruction data structures |
| `cpi.rs` | `cpi.zig` | Cross-program invocation |
| `syscalls.rs` | `syscalls.zig` | Direct syscall bindings |
| `sysvars/*` | `sysvars.zig` | Sysvar access helpers |
| `program_error.rs` | `error.zig` | Error handling |
| `log.rs` | `log.zig` | Logging utilities |
| `memory.rs` | `memory.zig` | Memory operations |

### Project Structure

```
pinocchio-zig/
├── src/
│   ├── lib.zig                 # Main library export
│   ├── entrypoint.zig          # Standard entrypoint
│   ├── lazy_entrypoint.zig     # Lazy parsing entrypoint
│   ├── account_info.zig        # AccountInfo & Account types
│   ├── pubkey.zig              # Pubkey [32]u8 operations
│   ├── instruction.zig         # Instruction & AccountMeta
│   ├── cpi.zig                 # invoke/invoke_signed
│   ├── syscalls.zig            # SBF syscall bindings
│   ├── sysvars.zig             # Clock, Rent, etc.
│   ├── error.zig               # ProgramError mapping
│   ├── log.zig                 # msg! equivalent
│   ├── memory.zig              # Memory utilities
│   └── allocator.zig           # no_allocator & bump allocator
├── examples/
│   ├── hello_world.zig         # Minimal program
│   ├── transfer_lamports.zig   # System transfer
│   ├── cpi_example.zig         # Cross-program invocation
│   └── pda_example.zig         # PDA derivation
├── benchmarks/
│   ├── rosetta_comparison.zig  # CU benchmarks vs Rust
│   └── cu_tracker.zig          # CU measurement utilities
├── tests/
│   └── program_test.zig        # Integration tests
├── build.zig                    # Build configuration
├── README.md                    # User documentation
└── CLAUDE.md                    # This file
```

## Implementation Details

### 1. Core Types

#### Pubkey
```zig
const base58 = @import("base58");

// Direct port from Rust: 32-byte array
pub const Pubkey = struct {
    bytes: [32]u8,

    pub const SIZE: usize = 32;

    pub fn fromBytes(bytes: [32]u8) Pubkey {
        return .{ .bytes = bytes };
    }

    pub fn fromString(str: []const u8) !Pubkey {
        // Use base58 library for string decoding
        var bytes: [32]u8 = undefined;
        const decoded_len = try base58.decode(str, &bytes);
        if (decoded_len != 32) return error.InvalidPubkey;
        return .{ .bytes = bytes };
    }

    pub fn toString(self: Pubkey, buf: []u8) ![]const u8 {
        // Use base58 library for string encoding
        return base58.encode(&self.bytes, buf);
    }

    pub fn equals(self: Pubkey, other: Pubkey) bool {
        // Optimize using u64 comparisons
        const self_u64 = @ptrCast(*const [4]u64, &self.bytes);
        const other_u64 = @ptrCast(*const [4]u64, &other.bytes);
        return self_u64[0] == other_u64[0] and
               self_u64[1] == other_u64[1] and
               self_u64[2] == other_u64[2] and
               self_u64[3] == other_u64[3];
    }
};
```

#### AccountInfo
```zig
// Zero-copy account representation
pub const AccountInfo = struct {
    // Direct memory layout matching Rust
    borrow_state: u8,      // Borrow tracking
    is_signer: bool,
    is_writable: bool,
    executable: bool,
    resize_delta: i32,     // Track resizes
    key: *const Pubkey,    // Account pubkey
    owner: *const Pubkey,  // Program owner
    lamports: *u64,        // Account balance
    data_len: usize,       // Data buffer size
    data: [*]u8,          // Data buffer pointer

    // Zero-copy accessors
    pub fn data_slice(self: *const AccountInfo) []u8 {
        return self.data[0..self.data_len];
    }

    pub fn try_borrow_mut_data(self: *AccountInfo) ![]u8 {
        if (!self.is_writable) return error.AccountNotWritable;
        // Check borrow state using atomic operations
        // ...
        return self.data_slice();
    }
};
```

### 2. Entrypoint Design

#### Standard Entrypoint
```zig
// Equivalent to Rust's entrypoint! macro
pub fn entrypoint(comptime process_instruction: fn(*const Pubkey, []AccountInfo, []const u8) ProgramResult) void {
    // Parse all accounts upfront
    export fn entrypoint_impl(input: [*]u8) callconv(.C) u64 {
        var context = parseInput(input);
        const result = process_instruction(
            context.program_id,
            context.accounts,
            context.instruction_data
        );
        return @intFromError(result);
    }
}
```

#### Lazy Entrypoint
```zig
// Equivalent to Rust's lazy_program_entrypoint!
pub const InstructionContext = struct {
    input: [*]u8,
    offset: usize,
    remaining_accounts: u8,

    pub fn next_account(self: *InstructionContext) ?AccountInfo {
        if (self.remaining_accounts == 0) return null;
        // Parse single account on-demand
        const account = parseAccount(self.input[self.offset..]);
        self.offset += account_size;
        self.remaining_accounts -= 1;
        return account;
    }

    pub fn instruction_data(self: *InstructionContext) []const u8 {
        // Parse instruction data when requested
    }

    pub fn program_id(self: *InstructionContext) *const Pubkey {
        // Parse program ID when requested
    }
};

pub fn lazy_entrypoint(comptime process: fn(InstructionContext) ProgramResult) void {
    export fn entrypoint_impl(input: [*]u8) callconv(.C) u64 {
        var context = InstructionContext{ .input = input, .offset = 0 };
        return @intFromError(process(context));
    }
}
```

### 3. Zero-Allocation CPI

```zig
pub fn invoke(
    instruction: *const Instruction,
    accounts: []AccountInfo,
) ProgramResult {
    // Direct syscall without allocation
    const account_metas = instruction.accounts;
    const ix_data = instruction.data;

    // Stack-allocated buffers for syscall
    var account_infos_buf: [256]u8 = undefined;
    var signers_seeds_buf: [256]u8 = undefined;

    // Serialize directly to stack buffers
    serializeAccounts(&account_infos_buf, accounts);

    return syscalls.sol_invoke_signed_c(
        instruction.ptr,
        account_infos_buf.ptr,
        account_infos_buf.len,
        null, // No signers for regular invoke
        0
    );
}

pub fn invoke_signed(
    instruction: *const Instruction,
    accounts: []AccountInfo,
    signers_seeds: [][]const []const u8,
) ProgramResult {
    // Comptime optimization for constant seeds
    if (comptime isConstant(signers_seeds)) {
        const serialized = comptime serializeSeeds(signers_seeds);
        // Use pre-computed seed buffer
    }
    // Runtime path for dynamic seeds
}
```

### 4. Memory Management

```zig
// No allocator - panics on any allocation attempt
pub const NoAllocator = struct {
    pub fn alloc(self: *NoAllocator, len: usize, ptr_align: u8, len_align: usize, ret_addr: usize) ![]u8 {
        _ = self;
        _ = len;
        _ = ptr_align;
        _ = len_align;
        _ = ret_addr;
        @panic("Allocation not allowed");
    }

    pub fn resize(self: *NoAllocator, buf: []u8, buf_align: u8, new_len: usize, len_align: usize, ret_addr: usize) bool {
        _ = self;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = len_align;
        _ = ret_addr;
        return false;
    }

    pub fn free(self: *NoAllocator, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = self;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
    }
};

// Bump allocator for debug builds
pub const BumpAllocator = struct {
    heap_start: [*]u8,
    heap_end: [*]u8,
    current: [*]u8,

    // Simple bump allocation, no free
};
```

### 5. Syscall Bindings

```zig
// Direct syscall declarations
pub extern "C" fn sol_invoke_signed_c(
    instruction: *const u8,
    account_infos: *const u8,
    account_infos_len: usize,
    signers_seeds: ?*const u8,
    signers_seeds_len: usize,
) u64;

pub extern "C" fn sol_log_(message: *const u8, len: u64) void;

pub extern "C" fn sol_log_64_(p0: u64, p1: u64, p2: u64, p3: u64, p4: u64) void;

pub extern "C" fn sol_memcpy_(dst: *u8, src: *const u8, n: u64) void;

pub extern "C" fn sol_memset_(dst: *u8, val: u8, n: u64) void;

pub extern "C" fn sol_memcmp_(s1: *const u8, s2: *const u8, n: u64, result: *i32) void;

// Type-safe wrappers
pub inline fn log(message: []const u8) void {
    sol_log_(message.ptr, message.len);
}
```

## Build Configuration

```zig
// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .sbfv2,      // or .sbf for v1
        .os_tag = .freestanding,
        .abi = .none,
    });

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast, // Optimize for speed
    });

    const lib = b.addSharedLibrary(.{
        .name = "program",
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add base58 dependency for Pubkey string conversions
    const base58_dep = b.dependency("base58", .{
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("base58", base58_dep.module("base58"));

    // SBF-specific flags
    lib.link_emit_relocs = true;
    lib.entry = .{ .symbol = "entrypoint" };
    lib.script = .{ .path = "sbf.ld" }; // Linker script

    // Disable stack protector
    lib.disable_stack_probing = true;
    lib.stack_protector = false;

    b.installArtifact(lib);
}
```

### build.zig.zon Configuration

```zig
// build.zig.zon
.{
    .name = "pinocchio-zig",
    .version = "0.1.0",
    .dependencies = .{
        .base58 = .{
            .url = "git+https://github.com/Syndica/base58-zig#ed42a74253e71577680ca826ee8ba16631808f3f",
            .hash = "base58-0.2.0-wW0iYDIxAABuG_QuEPHMJgn99CvMhTFzgYhGrneaMhdJ",
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
        "README.md",
        "LICENSE",
    },
}

## Testing Strategy

### Unit Tests
```zig
test "pubkey comparison optimization" {
    const key1 = Pubkey.fromBytes([_]u8{1} ** 32);
    const key2 = Pubkey.fromBytes([_]u8{2} ** 32);
    try std.testing.expect(!key1.equals(key2));

    // Verify no allocations
    const allocator = NoAllocator{};
    // Test should complete without allocations
}

test "lazy account parsing" {
    var mock_input = [_]u8{...}; // Mock serialized input
    var context = InstructionContext{ .input = &mock_input };

    const account1 = context.next_account();
    try std.testing.expect(account1 != null);

    // Verify only parsed what was needed
    try std.testing.expect(context.offset < mock_input.len);
}
```

### Integration Tests
```zig
// tests/program_test.zig
const program_test = @import("solana_program_test");

test "transfer lamports benchmark" {
    var pt = program_test.ProgramTest.init();
    defer pt.deinit();

    const tx = pt.transaction(&.{
        transfer_instruction(...),
    });

    const result = try pt.process_transaction(tx);

    // Measure CU consumption
    const cu_used = result.compute_units_consumed;
    try std.testing.expect(cu_used <= 38); // Target: ≤38 CU
}
```

## Performance Benchmarks

### Target CU Consumption

| Operation | Rust Pinocchio | Zig Target | Status |
|-----------|---------------|------------|--------|
| Hello World | 16 CU | ≤16 CU | TBD |
| Transfer Lamports | 38 CU | ≤35 CU | TBD |
| CPI (logic only) | 309 CU | ≤300 CU | TBD |
| Pubkey Compare | 45 CU | ≤40 CU | TBD |
| Create PDA | ~1500 CU | ≤1400 CU | TBD |

### Optimization Techniques

1. **Comptime Dispatch**
   ```zig
   const ix_type = comptime determineInstructionType(data);
   switch (ix_type) {
       .Transfer => processTransfer(),
       .Initialize => processInit(),
   }
   ```

2. **Inline Everything Small**
   ```zig
   pub inline fn check_signer(account: *const AccountInfo) !void {
       if (!account.is_signer) return error.MissingSigner;
   }
   ```

3. **Unroll Small Loops**
   ```zig
   // For known small arrays, unroll
   inline for (accounts[0..4]) |*account| {
       try validate(account);
   }
   ```

4. **Cache Aligned Access**
   ```zig
   // Ensure proper alignment for SIMD-like operations
   const data = @alignCast(8, account.data);
   ```

## Development Workflow

### Quick Start
```bash
# Clone and setup
git clone https://github.com/your-org/pinocchio-zig
cd pinocchio-zig

# Build program
zig build -Doptimize=ReleaseFast

# Run tests
zig build test

# Deploy to localnet
solana-test-validator &
solana program deploy zig-out/lib/program.so
```

### Debug Commands
```bash
# Build with debug symbols
zig build -Doptimize=Debug

# Disassemble SBF bytecode
llvm-objdump -d zig-out/lib/program.so

# Check stack usage
zig build -fstack-report

# Profile CU consumption
solana program deploy --final \
  --program-id <id> \
  --with-compute-unit-price 1
```

## Code Review Checklist

- [ ] **No heap allocations** - All memory is stack or account buffer
- [ ] **Zero-copy parsing** - Use `@ptrCast` for direct memory access
- [ ] **Comptime validation** - Leverage comptime for static checks
- [ ] **Inline small functions** - Use `inline fn` for hot paths
- [ ] **Explicit alignment** - Handle alignment with `@alignCast`
- [ ] **Error codes only** - Return u64 error codes, no strings
- [ ] **Lazy parsing** - Don't parse unused accounts
- [ ] **CU benchmark** - Include CU measurements for changes

## Migration Guide (Rust → Zig)

### Type Mappings
| Rust Type | Zig Type |
|-----------|----------|
| `[u8; 32]` | `[32]u8` |
| `&[u8]` | `[]const u8` |
| `&mut [u8]` | `[]u8` |
| `*const T` | `*const T` |
| `Option<T>` | `?T` |
| `Result<T, E>` | `!T` (error union) |
| `u64` | `u64` |
| `bool` | `bool` |

### Macro Equivalents
| Rust Macro | Zig Pattern |
|------------|-------------|
| `entrypoint!` | `pub fn entrypoint(comptime ...)` |
| `msg!` | `pub fn msg(text: []const u8)` |
| `#[derive(...)]` | Explicit implementation |
| `#[repr(C)]` | Default in Zig |

### Key Differences
1. **No trait system** - Use comptime duck typing or explicit interfaces
2. **Explicit error handling** - Use error unions instead of Result
3. **No lifetime annotations** - Manual lifetime management
4. **Comptime instead of macros** - More powerful compile-time execution

## Common Patterns

### Pattern 1: Zero-Copy Deserialization
```zig
const TokenAccount = packed struct {
    mint: Pubkey,
    owner: Pubkey,
    amount: u64,
    // ...
};

pub fn deserialize(data: []const u8) !*const TokenAccount {
    if (data.len < @sizeOf(TokenAccount)) return error.InvalidData;
    return @ptrCast(*const TokenAccount, @alignCast(@alignOf(TokenAccount), data.ptr));
}
```

### Pattern 2: Efficient PDA Validation
```zig
pub fn validate_pda(
    seeds: []const []const u8,
    program_id: *const Pubkey,
    expected: *const Pubkey,
) !void {
    var pda_buf: [32]u8 = undefined;
    var bump: u8 = undefined;

    try create_program_address(seeds, program_id, &pda_buf, &bump);

    if (!std.mem.eql(u8, &pda_buf, &expected.bytes)) {
        return error.InvalidPDA;
    }
}
```

### Pattern 3: Comptime Instruction Dispatch
```zig
pub fn process(comptime Instructions: type) fn([]const u8) ProgramResult {
    return struct {
        fn process_impl(data: []const u8) ProgramResult {
            const discriminator = data[0];
            inline for (@typeInfo(Instructions).Enum.fields) |field| {
                if (field.value == discriminator) {
                    return @field(Instructions, field.name).process(data[1..]);
                }
            }
            return error.UnknownInstruction;
        }
    }.process_impl;
}
```

## Troubleshooting

### Common Issues

1. **Stack Overflow**
   - Reduce local array sizes
   - Use account data buffers for large data
   - Check recursion depth

2. **Alignment Errors**
   ```zig
   // Wrong
   const ptr = @ptrCast(*const T, data.ptr);

   // Right
   const ptr = @ptrCast(*const T, @alignCast(@alignOf(T), data.ptr));
   ```

3. **CU Spikes**
   - Profile with CU checkpoints
   - Check for hidden loops
   - Use lazy parsing
   - Verify inlining

4. **Borrow Conflicts**
   - Track borrow state explicitly
   - Use atomic operations for shared state
   - Validate account ownership

## References

- [anza-xyz/pinocchio](https://github.com/anza-xyz/pinocchio) - Rust implementation
- [Solana SBF Docs](https://docs.solana.com/developing/on-chain-programs/developing-rust)
- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Rosetta Benchmarks](https://github.com/joncinque/solana-program-rosetta?tab=readme-ov-file#current-programs)

## Next Steps

1. **Week 1 Goals**
   - [x] Complete CLAUDE.md documentation
   - [ ] Implement core types (Pubkey, AccountInfo)
   - [ ] Standard entrypoint with zero-copy parsing
   - [ ] Transfer lamports example (<38 CU)

2. **Week 2 Goals**
   - [ ] Lazy entrypoint implementation
   - [ ] CPI wrappers (invoke/invoke_signed)
   - [ ] PDA helpers with comptime optimization
   - [ ] SPL Token operations subset

3. **Future Phases**
   - [ ] Anchor-lite layer (separate repo)
   - [ ] IDL generation
   - [ ] Client SDK generation
   - [ ] Program test framework

## 重写原理

- zig所有重写实现的结构体,直接匹配 Solana 运行时序列化的数据布局
