# Hello World Solana Program in Zig

A simple Solana program demonstrating basic functionality using Pinocchio-Zig.

## Features

This program demonstrates:
- Program initialization
- Account data storage
- Instruction processing
- Message updates
- Greeting counter

## Instructions

The program supports three instructions:

1. **Initialize (0)**: Initialize a new greeting account with default message
2. **UpdateGreeting (1)**: Update the greeting message (requires message data)
3. **SayHello (2)**: Log the current greeting message

## Account Structure

The program uses a `GreetingAccount` structure:
```zig
const GreetingAccount = packed struct {
    magic: u32,              // Magic number (0xDEADBEEF)
    greeting_count: u32,     // Number of updates
    message: [32]u8,         // Greeting message (max 32 bytes)
};
```

## Building

### For Solana deployment:
```bash
# Build the program for Solana BPF/SBF target
zig build -Dtarget=sbf -Doptimize=ReleaseFast
```

### For testing:
```bash
# Run tests locally
zig build test
```

## Usage Examples

### Initialize Account
```javascript
// Client code (JavaScript/TypeScript)
const instruction = Buffer.from([0]); // Initialize instruction
const tx = new Transaction().add(
    new TransactionInstruction({
        programId: PROGRAM_ID,
        keys: [
            { pubkey: greetingAccount, isSigner: true, isWritable: true }
        ],
        data: instruction,
    })
);
```

### Update Greeting
```javascript
const message = "Hello from Zig!";
const instruction = Buffer.concat([
    Buffer.from([1]), // UpdateGreeting instruction
    Buffer.from(message)
]);
const tx = new Transaction().add(
    new TransactionInstruction({
        programId: PROGRAM_ID,
        keys: [
            { pubkey: greetingAccount, isSigner: true, isWritable: true }
        ],
        data: instruction,
    })
);
```

### Say Hello
```javascript
const instruction = Buffer.from([2]); // SayHello instruction
const tx = new Transaction().add(
    new TransactionInstruction({
        programId: PROGRAM_ID,
        keys: [
            { pubkey: greetingAccount, isSigner: false, isWritable: false }
        ],
        data: instruction,
    })
);
```

## Testing

Run the included tests:
```bash
zig build test
```

## Deployment

1. Build the program:
```bash
zig build -Dtarget=sbf -Doptimize=ReleaseFast
```

2. Deploy to devnet:
```bash
solana program deploy zig-out/lib/hello_world.so --program-id <KEYPAIR>
```

3. Or deploy to localnet:
```bash
# Start local validator
solana-test-validator

# Deploy program
solana program deploy zig-out/lib/hello_world.so
```

## Program Logs

When the program runs, it will output logs like:
```
Program log: Hello World Program - Entry Point
Program log: Processing instruction: Initialize
Program log: Initializing greeting account
Program log: Successfully initialized greeting account
Program log: Default message: Hello, Solana!
```

## Notes

- Accounts must have sufficient space (at least 40 bytes) for the GreetingAccount structure
- The program owner must match for initialization and updates
- Signer authority is required for Initialize and UpdateGreeting instructions
- SayHello can be called by anyone and doesn't require write access