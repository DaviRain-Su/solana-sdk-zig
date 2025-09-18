# Hello World Client Tests

JavaScript client tests for the Hello World Solana program written in Zig.

## Files

- **`test-all.js`** - Comprehensive test suite that covers all program instructions and edge cases
- **`simple.js`** - Quick test that just calls SayHello instruction without accounts
- **`package.json`** - Node.js dependencies

## Running Tests

### Prerequisites

1. Start local Solana validator:
```bash
solana-test-validator
```

2. Deploy the program:
```bash
cd ../
/path/to/solana-zig/zig build
solana program deploy zig-out/lib/hello_world.so
```

3. Update PROGRAM_ID in the test files with your deployed program ID

### Install Dependencies

```bash
npm install
```

### Run Tests

**Run all tests:**
```bash
node test-all.js
```

**Run simple test:**
```bash
node simple.js
```

## Test Coverage

The comprehensive test (`test-all.js`) covers:

1. **SayHello without account** - Should work and display default message
2. **Initialize without account** - Should fail with proper error
3. **Create account and Initialize together** - Should succeed
4. **SayHello with initialized account** - Should display stored greeting
5. **Update greeting message** - Should update the stored message
6. **SayHello after update** - Should display updated message
7. **Invalid instruction** - Should fail with unknown instruction error
8. **Create and Initialize separately** - Tests two-step account setup

## Expected Output

All tests should pass with clear success/failure indicators:
- ✅ Success for operations that should work
- ✅ Expected failure for operations that should fail
- ❌ Unexpected failure indicates a problem

## Program Instructions

The Hello World program supports three instructions:

- **Initialize (0)** - Initialize a new greeting account
- **UpdateGreeting (1)** - Update the greeting message
- **SayHello (2)** - Display the current greeting

## Account Structure

The greeting account is 40 bytes:
- 4 bytes: Magic number (0xDEADBEEF)
- 4 bytes: Greeting count
- 32 bytes: Message (max 32 characters)