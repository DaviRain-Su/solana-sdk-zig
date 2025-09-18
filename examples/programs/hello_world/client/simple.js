import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
  sendAndConfirmTransaction,
} from "@solana/web3.js";
import fs from "fs";

// 使用时替换为你的程序 ID
const PROGRAM_ID = "5rhMUmvQSJYP3u89mUwij2ceZzNWUHiaevzKcQT7Dx72";

async function main() {
  const connection = new Connection("http://localhost:8899", "confirmed");
  const payer = Keypair.fromSecretKey(
    new Uint8Array(
      JSON.parse(
        fs.readFileSync(process.env.HOME + "/.config/solana/id.json", "utf8"),
      ),
    ),
  );

  console.log("Payer:", payer.publicKey.toBase58());
  console.log("Program:", PROGRAM_ID);

  // Call SayHello instruction (instruction type = 2)
  const instruction = new TransactionInstruction({
    keys: [],
    programId: new PublicKey(PROGRAM_ID),
    data: Buffer.from([2]), // SayHello = 2
  });

  const transaction = new Transaction().add(instruction);

  console.log("\nSending transaction...");
  const signature = await sendAndConfirmTransaction(connection, transaction, [
    payer,
  ]);

  console.log("Transaction successful!");
  console.log("Signature:", signature);

  // Get and display logs
  const tx = await connection.getTransaction(signature, {
    commitment: "confirmed",
    maxSupportedTransactionVersion: 0,
  });

  console.log("\nProgram logs:");
  tx.meta.logMessages
    .filter((log) => log.includes("Program log:"))
    .forEach((log) => console.log(" ", log));
}

main().catch(console.error);
