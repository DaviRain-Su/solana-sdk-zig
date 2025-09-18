import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
  SystemProgram,
} from "@solana/web3.js";
import fs from "fs";

const PROGRAM_ID = "Ck26NDSrDy55bFdqwpDondhTqKzeyw9zYJWefsKmzugx";

function loadKeypair(filepath) {
  const keypairData = JSON.parse(fs.readFileSync(filepath, "utf8"));
  return Keypair.fromSecretKey(new Uint8Array(keypairData));
}

async function main() {
  const connection = new Connection("http://localhost:8899", "confirmed");
  const payer = loadKeypair(process.env.HOME + "/.config/solana/id.json");

  console.log("Program:", PROGRAM_ID);

  // Test with a pre-created account
  const greetingAccount = Keypair.generate();

  // First create the account
  console.log("\n=== Creating Account First ===");
  const space = 40;
  const rentExemption = await connection.getMinimumBalanceForRentExemption(space);

  const createAccountIx = SystemProgram.createAccount({
    fromPubkey: payer.publicKey,
    newAccountPubkey: greetingAccount.publicKey,
    lamports: rentExemption,
    space,
    programId: new PublicKey(PROGRAM_ID),
  });

  const createTx = new Transaction().add(createAccountIx);
  const createSimulation = await connection.simulateTransaction(createTx, [payer, greetingAccount]);

  if (createSimulation.value.err) {
    console.log("Create account failed:", createSimulation.value.err);
  } else {
    console.log("Account would be created successfully");
  }

  // Now test Initialize instruction separately
  console.log("\n=== Testing Initialize Separately ===");
  const initData = Buffer.from([0]);
  console.log("Initialize data:", initData, "Contents:", Array.from(initData));

  const initIx = new TransactionInstruction({
    keys: [
      {
        pubkey: greetingAccount.publicKey,
        isSigner: true,
        isWritable: true,
      },
    ],
    programId: new PublicKey(PROGRAM_ID),
    data: initData,
  });

  const initTx = new Transaction().add(initIx);
  console.log("Transaction created with single Initialize instruction");

  const simulation = await connection.simulateTransaction(initTx, [payer, greetingAccount]);

  if (simulation.value.err) {
    console.log("❌ Failed with error:", simulation.value.err);
  } else {
    console.log("✅ Success!");
  }

  console.log("\nLogs:");
  simulation.value.logs.forEach((log) => {
    if (log.includes("Program log:")) {
      console.log("  ", log);
    }
  });
}

main().catch(console.error);