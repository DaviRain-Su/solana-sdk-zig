# CPI Example Program

This example demonstrates Cross-Program Invocation (CPI) in Solana using Zig.

## Overview

Cross-Program Invocation (CPI) allows Solana programs to call other programs. This example shows:

1. **Basic CPI** - Calling the System Program to transfer SOL
2. **PDA Creation** - Creating accounts owned by Program Derived Addresses
3. **Signed CPI** - Using `invoke_signed` for PDA-authorized operations

## Features

### Instructions

The program implements three main instructions:

#### 1. `TransferSol` (0x00)
Transfers SOL from one account to another using CPI to the System Program.

**Accounts:**
- `[signer, writable]` From account
- `[writable]` To account
- `[]` System Program

**Data:**
- `[0]` Instruction discriminator (0x00)
- `[1..9]` Lamports to transfer (u64, little-endian)

#### 2. `CreatePdaAccount` (0x01)
Creates a new account owned by a PDA using CPI with `invoke_signed`.

**Accounts:**
- `[signer, writable]` Payer
- `[writable]` PDA account to create
- `[]` System Program
- `[]` Rent Sysvar (unused, for compatibility)

**Data:**
- `[0]` Instruction discriminator (0x01)
- `[1..9]` Space in bytes (u64, little-endian)

**PDA Derivation:**
- Seed: `"vault"`
- Program ID: This program's ID

#### 3. `TransferFromPda` (0x02)
Transfers SOL from a PDA-owned account using `invoke_signed`.

**Accounts:**
- `[writable]` PDA account (from)
- `[writable]` To account
- `[]` System Program

**Data:**
- `[0]` Instruction discriminator (0x02)
- `[1..9]` Lamports to transfer (u64, little-endian)

## Key Concepts Demonstrated

### 1. Cross-Program Invocation (CPI)
```zig
// Create instruction for another program
const transfer_ix = createSystemTransferInstruction(from, to, lamports);

// Invoke the other program
try transfer_ix.invoke(&[_]AccountInfo{from, to, system_program});
```

### 2. Program Derived Addresses (PDAs)
```zig
// Derive PDA
const seed = "vault";
const seeds = [_][]const u8{seed};
const bump = try findProgramAddressBump(&seeds, program_id);

// Verify PDA matches expected address
const expected_pda = try deriveProgramAddress(&seeds, bump, program_id);
```

### 3. Signed CPI with PDAs
```zig
// Sign for PDA using invoke_signed
const signer_seeds = [_][]const u8{ seed, &[_]u8{bump} };
try instruction.invoke_signed(
    accounts,
    &[_][]const []const u8{&signer_seeds}
);
```

## Building

### Prerequisites

- Zig compiler with Solana BPF support
- Solana CLI tools
- Node.js and npm (for client tests)

### Build the Program

```bash
# From the cpi_example directory
../../../solana-zig/zig build

# Generate a keypair for the program
../../../solana-zig/zig build keypair
```

The built program will be at `zig-out/lib/cpi_example.so`.

## Testing

### 1. Start Local Validator

```bash
solana-test-validator
```

### 2. Deploy the Program

```bash
cd client
npm install
npm run deploy
```

This will:
- Build the program
- Generate a keypair (if needed)
- Deploy to localnet
- Save the program ID to `.env`

### 3. Run Tests

```bash
npm test
```

The test script will:
1. Transfer SOL using CPI
2. Create a PDA-owned account
3. Transfer from the PDA
4. Test error handling

## Program Structure

```
cpi_example/
├── src/
│   └── lib.zig           # Main program logic
├── client/
│   ├── package.json      # Node dependencies
│   ├── deploy.js         # Deployment script
│   └── test.js           # Test client
├── build.zig             # Build configuration
├── build.zig.zon         # Package manifest
└── README.md             # This file
```

## Implementation Details

### CPI Module (`src/cpi.zig`)

The SDK provides a CPI module with:

- `invoke()` - Basic cross-program invocation
- `invoke_signed()` - CPI with PDA signing
- Serialization helpers for instructions and accounts

### Instruction Structure

Instructions use the `Instruction` struct:

```zig
pub const Instruction = struct {
    program_id: Pubkey,           // Target program
    accounts: []const AccountMeta, // Required accounts
    data: []const u8,             // Instruction data

    // CPI methods
    pub fn invoke(self: *const Instruction, accounts: []const AccountInfo) !void
    pub fn invoke_signed(self: *const Instruction, accounts: []const AccountInfo, seeds: []const []const []const u8) !void
};
```

### Account Metadata

```zig
pub const AccountMeta = struct {
    pubkey: Pubkey,
    is_signer: bool,
    is_writable: bool,
};
```

## Common Issues

### 1. "Program not found"
- Make sure the program is deployed: `npm run deploy`
- Check the program ID in `.env` matches deployment

### 2. "Invalid system program"
- Ensure System Program account is passed correctly
- System Program ID should be all zeros

### 3. "PDA mismatch"
- Verify seed and bump calculation
- Check program ID used for derivation

### 4. "Cross-program invocation failed"
- Check account permissions (signer/writable)
- Verify instruction data format
- Ensure sufficient lamports for operations

## Security Considerations

1. **Validate Program IDs** - Always verify you're calling the expected program
2. **Check PDA Derivation** - Ensure PDAs match expected addresses
3. **Verify Account Ownership** - Check account owners before operations
4. **Sanitize Inputs** - Validate all instruction data

## Advanced Usage

### Custom CPI Instructions

Create custom instructions for other programs:

```zig
fn createCustomInstruction(/* params */) Instruction {
    const accounts = [_]AccountMeta{
        // Define required accounts
    };

    var data: [SIZE]u8 = undefined;
    // Serialize instruction data

    return Instruction.init(program_id, &accounts, &data);
}
```

### Multiple Signer Seeds

For complex PDAs with multiple seeds:

```zig
const seeds = [_][]const u8{
    "prefix",
    user_pubkey.bytes[0..32],
    &[_]u8{bump},
};
try instruction.invoke_signed(accounts, &[_][]const []const u8{&seeds});
```

## Resources

- [Solana CPI Documentation](https://solana.com/docs/core/cpi)
- [System Program Reference](https://docs.rs/solana-program/latest/solana_program/system_instruction/index.html)
- [PDA Documentation](https://solana.com/docs/core/pda)

## License

MIT