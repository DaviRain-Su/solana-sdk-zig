import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
  SystemProgram,
  sendAndConfirmTransaction,
} from "@solana/web3.js";
import fs from "fs";

// Program ID - Update this with your deployed program ID
const PROGRAM_ID = "7sciCbCQXYdWcsKszrNAMsuwhhNBNWEhjEPmKPMucBd2";

// Instruction enum matching our Zig program
const HelloInstruction = {
  Initialize: 0,
  UpdateGreeting: 1,
  SayHello: 2,
};

// Load keypair from file
function loadKeypair(filepath) {
  const keypairData = JSON.parse(fs.readFileSync(filepath, "utf8"));
  return Keypair.fromSecretKey(new Uint8Array(keypairData));
}

async function main() {
  // Connect to local validator
  const connection = new Connection("http://localhost:8899", "confirmed");
  console.log("Connected to local validator");

  // Load payer keypair
  const payer = loadKeypair(process.env.HOME + "/.config/solana/id.json");
  console.log("Payer:", payer.publicKey.toBase58());
  console.log("Program ID:", PROGRAM_ID);

  // =============================================================================
  // Test 1: SayHello without account (should work)
  // =============================================================================
  console.log("\n" + "=".repeat(80));
  console.log("Test 1: SayHello without account");
  console.log("=".repeat(80));

  try {
    const instruction = new TransactionInstruction({
      keys: [],
      programId: new PublicKey(PROGRAM_ID),
      data: Buffer.from([HelloInstruction.SayHello]),
    });

    const transaction = new Transaction().add(instruction);
    const signature = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer],
      { commitment: "confirmed" }
    );
    console.log("✅ Success! Transaction:", signature);

    // Get transaction logs
    const tx = await connection.getTransaction(signature, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0,
    });
    console.log("Logs:");
    tx.meta.logMessages
      .filter((log) => log.includes("Program log:"))
      .forEach((log) => console.log("  ", log));
  } catch (error) {
    console.error("❌ Failed:", error.message);
  }

  // =============================================================================
  // Test 2: Initialize without account (should fail)
  // =============================================================================
  console.log("\n" + "=".repeat(80));
  console.log("Test 2: Initialize without account (should fail)");
  console.log("=".repeat(80));

  try {
    const instruction = new TransactionInstruction({
      keys: [],
      programId: new PublicKey(PROGRAM_ID),
      data: Buffer.from([HelloInstruction.Initialize]),
    });

    const transaction = new Transaction().add(instruction);
    const simulation = await connection.simulateTransaction(transaction, [payer]);

    if (simulation.value.err) {
      console.log("✅ Expected failure:", simulation.value.err);
      console.log("Error logs:");
      simulation.value.logs
        .filter((log) => log.includes("Program log:"))
        .forEach((log) => console.log("  ", log));
    } else {
      console.log("❌ Should have failed but didn't");
    }
  } catch (error) {
    console.log("✅ Expected error:", error.message);
  }

  // =============================================================================
  // Test 3: Create account and Initialize together
  // =============================================================================
  console.log("\n" + "=".repeat(80));
  console.log("Test 3: Create account and Initialize together");
  console.log("=".repeat(80));

  const greetingAccount = Keypair.generate();
  console.log("Greeting account:", greetingAccount.publicKey.toBase58());

  try {
    // Create account (40 bytes for our struct)
    const space = 40;
    const rentExemption = await connection.getMinimumBalanceForRentExemption(space);

    const createAccountIx = SystemProgram.createAccount({
      fromPubkey: payer.publicKey,
      newAccountPubkey: greetingAccount.publicKey,
      lamports: rentExemption,
      space,
      programId: new PublicKey(PROGRAM_ID),
    });

    // Initialize instruction
    const initIx = new TransactionInstruction({
      keys: [
        {
          pubkey: greetingAccount.publicKey,
          isSigner: true,
          isWritable: true,
        },
      ],
      programId: new PublicKey(PROGRAM_ID),
      data: Buffer.from([HelloInstruction.Initialize]),
    });

    const transaction = new Transaction().add(createAccountIx, initIx);
    const signature = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer, greetingAccount],
      { commitment: "confirmed" }
    );
    console.log("✅ Success! Transaction:", signature);

    const tx = await connection.getTransaction(signature, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0,
    });
    console.log("Logs:");
    tx.meta.logMessages
      .filter((log) => log.includes("Program log:"))
      .forEach((log) => console.log("  ", log));
  } catch (error) {
    console.error("❌ Failed:", error.message);
    return;
  }

  // =============================================================================
  // Test 4: SayHello with initialized account
  // =============================================================================
  console.log("\n" + "=".repeat(80));
  console.log("Test 4: SayHello with initialized account");
  console.log("=".repeat(80));

  try {
    const instruction = new TransactionInstruction({
      keys: [
        {
          pubkey: greetingAccount.publicKey,
          isSigner: false,
          isWritable: false,
        },
      ],
      programId: new PublicKey(PROGRAM_ID),
      data: Buffer.from([HelloInstruction.SayHello]),
    });

    const transaction = new Transaction().add(instruction);
    const signature = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer],
      { commitment: "confirmed" }
    );
    console.log("✅ Success! Transaction:", signature);

    const tx = await connection.getTransaction(signature, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0,
    });
    console.log("Logs:");
    tx.meta.logMessages
      .filter((log) => log.includes("Program log:"))
      .forEach((log) => console.log("  ", log));
  } catch (error) {
    console.error("❌ Failed:", error.message);
  }

  // =============================================================================
  // Test 5: Update greeting message
  // =============================================================================
  console.log("\n" + "=".repeat(80));
  console.log("Test 5: Update greeting message");
  console.log("=".repeat(80));

  try {
    const newMessage = "Hello from JavaScript!";
    const data = Buffer.concat([
      Buffer.from([HelloInstruction.UpdateGreeting]),
      Buffer.from(newMessage),
    ]);

    const instruction = new TransactionInstruction({
      keys: [
        {
          pubkey: greetingAccount.publicKey,
          isSigner: true,
          isWritable: true,
        },
      ],
      programId: new PublicKey(PROGRAM_ID),
      data,
    });

    const transaction = new Transaction().add(instruction);
    const signature = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer, greetingAccount],
      { commitment: "confirmed" }
    );
    console.log("✅ Success! Transaction:", signature);

    const tx = await connection.getTransaction(signature, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0,
    });
    console.log("Logs:");
    tx.meta.logMessages
      .filter((log) => log.includes("Program log:"))
      .forEach((log) => console.log("  ", log));
  } catch (error) {
    console.error("❌ Failed:", error.message);
  }

  // =============================================================================
  // Test 6: SayHello after update
  // =============================================================================
  console.log("\n" + "=".repeat(80));
  console.log("Test 6: SayHello after update");
  console.log("=".repeat(80));

  try {
    const instruction = new TransactionInstruction({
      keys: [
        {
          pubkey: greetingAccount.publicKey,
          isSigner: false,
          isWritable: false,
        },
      ],
      programId: new PublicKey(PROGRAM_ID),
      data: Buffer.from([HelloInstruction.SayHello]),
    });

    const transaction = new Transaction().add(instruction);
    const signature = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer],
      { commitment: "confirmed" }
    );
    console.log("✅ Success! Transaction:", signature);

    const tx = await connection.getTransaction(signature, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0,
    });
    console.log("Logs:");
    tx.meta.logMessages
      .filter((log) => log.includes("Program log:"))
      .forEach((log) => console.log("  ", log));
  } catch (error) {
    console.error("❌ Failed:", error.message);
  }

  // =============================================================================
  // Test 7: Invalid instruction (should fail)
  // =============================================================================
  console.log("\n" + "=".repeat(80));
  console.log("Test 7: Invalid instruction (should fail)");
  console.log("=".repeat(80));

  try {
    const instruction = new TransactionInstruction({
      keys: [],
      programId: new PublicKey(PROGRAM_ID),
      data: Buffer.from([99]), // Invalid instruction
    });

    const transaction = new Transaction().add(instruction);
    const simulation = await connection.simulateTransaction(transaction, [payer]);

    if (simulation.value.err) {
      console.log("✅ Expected failure:", simulation.value.err);
      console.log("Error logs:");
      simulation.value.logs
        .filter((log) => log.includes("Program log:"))
        .forEach((log) => console.log("  ", log));
    } else {
      console.log("❌ Should have failed but didn't");
    }
  } catch (error) {
    console.log("✅ Expected error:", error.message);
  }

  // =============================================================================
  // Test 8: Create and Initialize in separate transactions
  // =============================================================================
  console.log("\n" + "=".repeat(80));
  console.log("Test 8: Create and Initialize in separate transactions");
  console.log("=".repeat(80));

  const separateAccount = Keypair.generate();
  console.log("Account:", separateAccount.publicKey.toBase58());

  try {
    // Step 1: Create account
    const space = 40;
    const rentExemption = await connection.getMinimumBalanceForRentExemption(space);

    const createAccountIx = SystemProgram.createAccount({
      fromPubkey: payer.publicKey,
      newAccountPubkey: separateAccount.publicKey,
      lamports: rentExemption,
      space,
      programId: new PublicKey(PROGRAM_ID),
    });

    const createTx = new Transaction().add(createAccountIx);
    const createSig = await sendAndConfirmTransaction(
      connection,
      createTx,
      [payer, separateAccount],
      { commitment: "confirmed" }
    );
    console.log("✅ Account created! Signature:", createSig);

    // Step 2: Initialize account
    const initIx = new TransactionInstruction({
      keys: [
        {
          pubkey: separateAccount.publicKey,
          isSigner: true,
          isWritable: true,
        },
      ],
      programId: new PublicKey(PROGRAM_ID),
      data: Buffer.from([HelloInstruction.Initialize]),
    });

    const initTx = new Transaction().add(initIx);
    const initSig = await sendAndConfirmTransaction(
      connection,
      initTx,
      [payer, separateAccount],
      { commitment: "confirmed" }
    );
    console.log("✅ Initialize successful! Signature:", initSig);

    const tx = await connection.getTransaction(initSig, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0,
    });
    console.log("Logs:");
    tx.meta.logMessages
      .filter((log) => log.includes("Program log:"))
      .forEach((log) => console.log("  ", log));
  } catch (error) {
    console.error("❌ Failed:", error.message);
  }

  console.log("\n" + "=".repeat(80));
  console.log("✅ All tests completed!");
  console.log("=".repeat(80));
}

main().catch(console.error);