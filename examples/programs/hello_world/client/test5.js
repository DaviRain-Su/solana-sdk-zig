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

const PROGRAM_ID = "5rhMUmvQSJYP3u89mUwij2ceZzNWUHiaevzKcQT7Dx72";

function loadKeypair(filepath) {
  const keypairData = JSON.parse(fs.readFileSync(filepath, "utf8"));
  return Keypair.fromSecretKey(new Uint8Array(keypairData));
}

async function main() {
  const connection = new Connection("http://localhost:8899", "confirmed");
  const payer = loadKeypair(process.env.HOME + "/.config/solana/id.json");

  console.log("Program:", PROGRAM_ID);
  console.log("Payer:", payer.publicKey.toBase58());

  // Create and initialize account in one transaction
  console.log("\n=== Creating and Initializing Account ===");

  const greetingAccount = Keypair.generate();
  console.log("New greeting account:", greetingAccount.publicKey.toBase58());

  const space = 40;
  const rentExemption = await connection.getMinimumBalanceForRentExemption(space);

  // Create account with the program as owner
  const createAccountIx = SystemProgram.createAccount({
    fromPubkey: payer.publicKey,
    newAccountPubkey: greetingAccount.publicKey,
    lamports: rentExemption,
    space,
    programId: new PublicKey(PROGRAM_ID),
  });

  console.log("Create account instruction prepared");
  console.log("  Owner will be:", PROGRAM_ID);
  console.log("  Space:", space, "bytes");
  console.log("  Lamports:", rentExemption);

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
    data: Buffer.from([0]), // Initialize = 0
  });

  console.log("Initialize instruction prepared");

  // Send transaction
  const tx = new Transaction().add(createAccountIx, initIx);

  try {
    const signature = await sendAndConfirmTransaction(
      connection,
      tx,
      [payer, greetingAccount],
      { commitment: "confirmed" }
    );

    console.log("✅ Success! Transaction:", signature);

    // Get transaction details
    const txDetails = await connection.getTransaction(signature, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0,
    });

    console.log("\nTransaction logs:");
    txDetails.meta.logMessages.forEach(log => {
      if (log.includes("Program log:")) {
        console.log("  ", log);
      }
    });

    // Now test SayHello with the initialized account
    console.log("\n=== Testing SayHello with Initialized Account ===");

    const sayHelloIx = new TransactionInstruction({
      keys: [
        {
          pubkey: greetingAccount.publicKey,
          isSigner: false,
          isWritable: false,
        },
      ],
      programId: new PublicKey(PROGRAM_ID),
      data: Buffer.from([2]), // SayHello = 2
    });

    const sayHelloTx = new Transaction().add(sayHelloIx);
    const sayHelloSig = await sendAndConfirmTransaction(
      connection,
      sayHelloTx,
      [payer],
      { commitment: "confirmed" }
    );

    console.log("✅ SayHello success! Transaction:", sayHelloSig);

    const sayHelloDetails = await connection.getTransaction(sayHelloSig, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0,
    });

    console.log("\nSayHello logs:");
    sayHelloDetails.meta.logMessages.forEach(log => {
      if (log.includes("Program log:")) {
        console.log("  ", log);
      }
    });

  } catch (error) {
    console.error("❌ Error:", error.message);
    if (error.logs) {
      console.log("\nError logs:");
      error.logs.forEach(log => {
        if (log.includes("Program log:")) {
          console.log("  ", log);
        }
      });
    }
  }
}

main().catch(console.error);