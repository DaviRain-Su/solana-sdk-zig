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

const PROGRAM_ID = "EixRGSKt2SFsXtVDSqePUsWKGTvt6zod9X7nBGd7cD2W";

// Load keypair
function loadKeypair(filepath) {
  const keypairData = JSON.parse(fs.readFileSync(filepath, "utf8"));
  return Keypair.fromSecretKey(new Uint8Array(keypairData));
}

async function main() {
  const connection = new Connection("http://localhost:8899", "confirmed");
  const payer = loadKeypair(process.env.HOME + "/.config/solana/id.json");

  console.log("Payer:", payer.publicKey.toBase58());
  console.log("Program:", PROGRAM_ID);

  // Test each instruction type separately

  // Test 1: SayHello without parameters
  console.log("\n=== Test SayHello (no params) ===");
  try {
    const ix = new TransactionInstruction({
      keys: [],
      programId: new PublicKey(PROGRAM_ID),
      data: Buffer.from([2]), // SayHello = 2
    });

    const tx = new Transaction().add(ix);

    // Simulate first to see what happens
    const simulation = await connection.simulateTransaction(tx, [payer]);
    console.log("Simulation result:", simulation);

    if (simulation.value.err) {
      console.log("Simulation error:", simulation.value.err);
      console.log("Logs:", simulation.value.logs);
    } else {
      // If simulation succeeds, send it
      const sig = await sendAndConfirmTransaction(connection, tx, [payer]);
      console.log("Success! Signature:", sig);

      // Get full transaction details
      const txDetails = await connection.getTransaction(sig, {
        commitment: "confirmed",
        maxSupportedTransactionVersion: 0,
      });

      console.log("All logs:");
      txDetails.meta.logMessages.forEach((log) => console.log("  ", log));
    }
  } catch (e) {
    console.error("Error:", e);
  }

  // Test 2: Initialize with a new account
  console.log("\n=== Test Initialize ===");
  const greetingAccount = Keypair.generate();
  console.log("New account:", greetingAccount.publicKey.toBase58());

  try {
    // First create the account
    const space = 40;
    const rentExemption =
      await connection.getMinimumBalanceForRentExemption(space);

    const createAccountIx = SystemProgram.createAccount({
      fromPubkey: payer.publicKey,
      newAccountPubkey: greetingAccount.publicKey,
      lamports: rentExemption,
      space,
      programId: new PublicKey(PROGRAM_ID),
    });

    // Initialize instruction with just the instruction type byte
    const initIx = new TransactionInstruction({
      keys: [
        {
          pubkey: greetingAccount.publicKey,
          isSigner: true,
          isWritable: true,
        },
      ],
      programId: new PublicKey(PROGRAM_ID),
      data: Buffer.from([0]), // Initialize = 0
    });

    const tx = new Transaction().add(createAccountIx, initIx);

    // Simulate first
    const simulation = await connection.simulateTransaction(tx, [
      payer,
      greetingAccount,
    ]);
    console.log("Simulation result:", simulation);

    if (simulation.value.err) {
      console.log("Simulation error:", simulation.value.err);
      console.log("Logs:", simulation.value.logs);

      // Let's check what the program is receiving
      console.log("\nInstruction data being sent:");
      console.log("  Instruction type byte:", initIx.data[0]);
      console.log("  Full data buffer:", initIx.data);
      console.log("  Data length:", initIx.data.length);
    } else {
      const sig = await sendAndConfirmTransaction(connection, tx, [
        payer,
        greetingAccount,
      ]);
      console.log("Success! Signature:", sig);

      // Read the account data
      const accountInfo = await connection.getAccountInfo(
        greetingAccount.publicKey,
      );
      console.log("Account data:", accountInfo.data);
    }
  } catch (e) {
    console.error("Error:", e);
    if (e.logs) {
      console.log("Transaction logs:");
      e.logs.forEach((log) => console.log("  ", log));
    }
  }

  // Test 3: Try sending empty data
  console.log("\n=== Test with empty instruction data ===");
  try {
    const ix = new TransactionInstruction({
      keys: [],
      programId: new PublicKey(PROGRAM_ID),
      data: Buffer.from([]), // Empty data
    });

    const tx = new Transaction().add(ix);
    const simulation = await connection.simulateTransaction(tx, [payer]);
    console.log("Simulation result:", simulation);
    console.log("Logs:", simulation.value.logs);
  } catch (e) {
    console.error("Error:", e);
  }
}

main().catch(console.error);
