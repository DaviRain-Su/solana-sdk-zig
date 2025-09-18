import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
  SystemProgram,
  sendAndConfirmTransaction,
  LAMPORTS_PER_SOL,
} from "@solana/web3.js";
import fs from "fs";

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

  // Your deployed program ID - replace with actual program ID
  // You can get this from hello_world-keypair.json or from deployment output
  const programId = new PublicKey(
    "5rhMUmvQSJYP3u89mUwij2ceZzNWUHiaevzKcQT7Dx72",
  );
  console.log("Program ID:", programId.toBase58());

  // Test 1: Say Hello without account
  console.log("\n=== Test 1: Say Hello (no account) ===");
  {
    const instruction = new TransactionInstruction({
      keys: [],
      programId,
      data: Buffer.from([HelloInstruction.SayHello]),
    });

    const transaction = new Transaction().add(instruction);
    const signature = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer],
      { commitment: "confirmed" },
    );
    console.log("Transaction signature:", signature);

    // Get transaction logs
    const tx = await connection.getTransaction(signature, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0,
    });
    console.log(
      "Logs:",
      tx.meta.logMessages.filter((log) => log.includes("Program log:")),
    );
  }

  // Test 2: Initialize a greeting account
  console.log("\n=== Test 2: Initialize Greeting Account ===");
  const greetingAccount = Keypair.generate();
  console.log("Greeting account:", greetingAccount.publicKey.toBase58());

  {
    // Create account (40 bytes for our struct)
    const space = 40;
    const rentExemption =
      await connection.getMinimumBalanceForRentExemption(space);

    const createAccountIx = SystemProgram.createAccount({
      fromPubkey: payer.publicKey,
      newAccountPubkey: greetingAccount.publicKey,
      lamports: rentExemption,
      space,
      programId,
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
      programId,
      data: Buffer.from([HelloInstruction.Initialize]),
    });

    const transaction = new Transaction().add(createAccountIx, initIx);
    const signature = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer, greetingAccount],
      { commitment: "confirmed" },
    );
    console.log("Initialize transaction:", signature);
  }

  // Test 3: Say Hello with account
  console.log("\n=== Test 3: Say Hello (with account) ===");
  {
    const instruction = new TransactionInstruction({
      keys: [
        {
          pubkey: greetingAccount.publicKey,
          isSigner: false,
          isWritable: false,
        },
      ],
      programId,
      data: Buffer.from([HelloInstruction.SayHello]),
    });

    const transaction = new Transaction().add(instruction);
    const signature = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer],
      { commitment: "confirmed" },
    );

    const tx = await connection.getTransaction(signature, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0,
    });
    console.log(
      "Logs:",
      tx.meta.logMessages.filter((log) => log.includes("Program log:")),
    );
  }

  // Test 4: Update greeting
  console.log("\n=== Test 4: Update Greeting ===");
  {
    const newMessage = "Hello from JS!";
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
      programId,
      data,
    });

    const transaction = new Transaction().add(instruction);
    const signature = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer, greetingAccount],
      { commitment: "confirmed" },
    );
    console.log("Update transaction:", signature);
  }

  // Test 5: Say Hello after update
  console.log("\n=== Test 5: Say Hello (after update) ===");
  {
    const instruction = new TransactionInstruction({
      keys: [
        {
          pubkey: greetingAccount.publicKey,
          isSigner: false,
          isWritable: false,
        },
      ],
      programId,
      data: Buffer.from([HelloInstruction.SayHello]),
    });

    const transaction = new Transaction().add(instruction);
    const signature = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer],
      { commitment: "confirmed" },
    );

    const tx = await connection.getTransaction(signature, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0,
    });
    console.log(
      "Logs:",
      tx.meta.logMessages.filter((log) => log.includes("Program log:")),
    );
  }

  console.log("\n✅ All tests completed!");
}

main().catch(console.error);
