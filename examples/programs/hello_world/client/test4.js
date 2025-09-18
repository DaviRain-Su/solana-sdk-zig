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

const PROGRAM_ID = "4KhLdiEpNoxu5qMLwDFyAxLZVT1C2Sv72MmXkBY56u94";

function loadKeypair(filepath) {
  const keypairData = JSON.parse(fs.readFileSync(filepath, "utf8"));
  return Keypair.fromSecretKey(new Uint8Array(keypairData));
}

async function main() {
  const connection = new Connection("http://localhost:8899", "confirmed");
  const payer = loadKeypair(process.env.HOME + "/.config/solana/id.json");

  console.log("Program:", PROGRAM_ID);

  // Test SayHello with a real account that exists
  console.log("\n=== Testing SayHello with Payer Account ===");

  const sayHelloData = Buffer.from([2]); // SayHello = 2
  console.log("SayHello data:", sayHelloData, "Contents:", Array.from(sayHelloData));

  const sayHelloIx = new TransactionInstruction({
    keys: [
      {
        pubkey: payer.publicKey,  // Use payer account which definitely exists
        isSigner: false,
        isWritable: false,
      },
    ],
    programId: new PublicKey(PROGRAM_ID),
    data: sayHelloData,
  });

  const sayHelloTx = new Transaction().add(sayHelloIx);
  console.log("Transaction created with SayHello instruction and payer account");

  const simulation = await connection.simulateTransaction(sayHelloTx, [payer]);

  if (simulation.value.err) {
    console.log("❌ Failed with error:", simulation.value.err);
  } else {
    console.log("✅ Success!");
  }

  console.log("\nLogs:");
  simulation.value.logs.forEach((log) => {
    console.log("  ", log);
  });
}

main().catch(console.error);