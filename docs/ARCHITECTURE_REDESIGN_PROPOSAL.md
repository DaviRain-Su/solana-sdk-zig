# Architecture Redesign Proposal for Solana-SDK-Zig

## Problem Statement

The current architecture mixes concerns between internal data management and external CPI requirements, leading to:
- Complex pointer management
- Duplicated data structures
- Alignment issues
- Increased memory usage
- Confusion about which structure to use when

## Proposed Solution: Layered Architecture

### Layer 1: Raw Input Layer (Lowest Level)
Preserves original input exactly as received from runtime.

```zig
pub const RawInput = struct {
    buffer: [*]const u8,
    length: usize,

    pub fn getAccountPointer(self: RawInput, index: usize) ?*const RawAccountInfo {
        // Returns pointer into original buffer
    }
};
```

### Layer 2: Parsing Layer
Handles the complexity of parsing while preserving CPI capability.

```zig
pub const ParsedInput = struct {
    program_id: *const Pubkey,
    accounts: []AccountView,
    instruction_data: []const u8,
    raw_input: RawInput,  // Preserve original
};

pub const AccountView = struct {
    // Safe, ergonomic API for program use
    key: Pubkey,
    lamports: *u64,  // Still mutable
    data: []u8,
    owner: Pubkey,
    is_signer: bool,
    is_writable: bool,

    // CPI support
    raw_index: usize,  // Index in original input

    pub fn getCPIPointer(self: *AccountView, input: RawInput) *const RawAccountInfo {
        return input.getAccountPointer(self.raw_index).?;
    }
};
```

### Layer 3: Application Layer
High-level, safe API for program logic.

```zig
pub const ProgramContext = struct {
    program_id: Pubkey,
    accounts: []Account,
    instruction_data: []const u8,

    // Hidden CPI support
    _parsed: *ParsedInput,

    pub fn invoke(self: *ProgramContext, instruction: Instruction, account_indices: []usize) !void {
        // Automatically handles pointer translation
        var cpi_accounts: [32]*const RawAccountInfo = undefined;
        for (account_indices, 0..) |idx, i| {
            cpi_accounts[i] = self.accounts[idx].getCPIPointer(self._parsed.raw_input);
        }
        // ... perform CPI
    }
};
```

## Benefits of This Design

### 1. Separation of Concerns
- Each layer has a single responsibility
- Clear boundaries between parsing, application logic, and CPI

### 2. Memory Efficiency
- Only pay for what you use
- Programs without CPI can use simpler structures
- Lazy parsing still possible

### 3. Type Safety
- Can't accidentally mix raw and parsed data
- CPI requirements are encoded in types

### 4. Performance
- Minimal overhead for non-CPI programs
- Direct pointer access for CPI when needed
- Compile-time optimization opportunities

## Implementation Strategy

### Phase 1: Parallel Implementation
- Keep current implementation working
- Build new architecture alongside
- Mark old APIs as deprecated

### Phase 2: Migration Helpers
```zig
pub fn migrateToNewAPI(old: AccountInfo) Account {
    // Helper to transition existing code
}
```

### Phase 3: Performance Validation
- Benchmark both implementations
- Ensure no performance regression
- Target: <4000 CU for CPI operations

### Phase 4: Cutover
- Switch examples to new API
- Update documentation
- Remove old implementation

## Specific Design Decisions

### 1. Entrypoint Design
```zig
// Auto-detect requirements
pub fn entrypoint(comptime process: anytype) void {
    const ProcessType = @TypeOf(process);
    const needs_cpi = comptime analyzeNeeds(ProcessType);

    if (needs_cpi) {
        exportCPIEntrypoint(process);
    } else {
        exportSimpleEntrypoint(process);
    }
}

fn exportSimpleEntrypoint(comptime process: anytype) void {
    export fn entrypoint(input: [*]const u8) callconv(.C) u64 {
        // Simpler parsing without preserving pointers
        const context = parseSimple(input);
        return process(context);
    }
}

fn exportCPIEntrypoint(comptime process: anytype) void {
    export fn entrypoint(input: [*]const u8) callconv(.C) u64 {
        // Full parsing with pointer preservation
        const context = parseFull(input);
        return process(context);
    }
}
```

### 2. Account Access Pattern
```zig
// Clear, explicit API
pub const Account = struct {
    pub fn key(self: *const Account) Pubkey { }
    pub fn lamports(self: *Account) *u64 { }
    pub fn data(self: *Account) []u8 { }
    pub fn owner(self: *const Account) Pubkey { }

    // CPI is explicit
    pub fn prepareForCPI(self: *Account) CPIAccount { }
};
```

### 3. Error Handling
```zig
pub const CPIError = error{
    AccountNotCPICapable,  // Clear error when using wrong account type
    PointerValidationFailed,
    InvalidMemoryRegion,
};
```

## Migration Example

### Old Code
```zig
pub fn process_instruction(
    program_id: *const Pubkey,
    accounts: []AccountInfo,
    data: []const u8,
) ProgramResult {
    const from_account = &accounts[0];
    const to_account = &accounts[1];

    // Complex CPI setup
    const ix = Instruction{...};
    try ix.invoke_signed(accounts[0..2], &.{});
}
```

### New Code
```zig
pub fn process_instruction(ctx: *ProgramContext) ProgramResult {
    const from = &ctx.accounts[0];
    const to = &ctx.accounts[1];

    // Simple CPI
    const ix = Instruction{...};
    try ctx.invoke(ix, &.{0, 1});  // Just specify indices
}
```

## Testing Strategy

### 1. Unit Tests
- Test each layer independently
- Mock raw input for parsing tests
- Verify pointer preservation

### 2. Integration Tests
- Full CPI flow tests
- Memory region validation
- Performance benchmarks

### 3. Compatibility Tests
- Ensure works with all Solana versions
- Test against mainnet programs
- Validate with Anchor programs

## Risk Analysis

### Risks
1. **Breaking Changes**: Existing programs need updates
2. **Performance Regression**: New abstraction might add overhead
3. **Complexity**: More layers might confuse developers

### Mitigations
1. **Compatibility Layer**: Provide migration helpers
2. **Benchmarking**: Continuous performance testing
3. **Documentation**: Clear examples and migration guides

## Timeline

- **Week 1**: Prototype new architecture
- **Week 2**: Performance validation
- **Week 3**: Migration helpers and documentation
- **Week 4**: Beta release with parallel APIs
- **Month 2**: Gather feedback and iterate
- **Month 3**: Full release and deprecate old API

## Conclusion

This redesign addresses the fundamental issues discovered during CPI implementation:
- Clear separation between internal and external data
- Explicit handling of pointer requirements
- Better performance for non-CPI use cases
- Safer, more ergonomic API

The layered architecture provides flexibility while maintaining the zero-copy, high-performance goals of the original design.