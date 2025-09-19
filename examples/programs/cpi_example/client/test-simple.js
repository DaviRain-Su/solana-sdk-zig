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

const PROGRAM_ID = "GJthMRM4sffHG2f9WpgZ2qdxRAqH6sTkhcrmsgWHaNjQ";

// Load keypair from file
function loadKeypair(filepath) {
  const keypairData = JSON.parse(fs.readFileSync(filepath, "utf8"));
  return Keypair.fromSecretKey(new Uint8Array(keypairData));
}

async function testSimpleTransfer() {
  console.log("Testing Simple CPI Transfer");
  console.log("=".repeat(80));

  const connection = new Connection("http://localhost:8899", "confirmed");
  const payer = loadKeypair(process.env.HOME + "/.config/solana/id.json");

  console.log("Payer:", payer.publicKey.toBase58());
  console.log("Program ID:", PROGRAM_ID);

  // Create a recipient
  const recipient = Keypair.generate();
  console.log("Recipient:", recipient.publicKey.toBase58());

  // Small amount for testing
  const lamports = 1000; // 0.000001 SOL

  // Create instruction data: [instruction_discriminator][lamports as u64]
  const dataBuffer = Buffer.alloc(9);
  dataBuffer.writeUInt8(0, 0); // TransferSol instruction
  dataBuffer.writeBigUInt64LE(BigInt(lamports), 1);

  const instruction = new TransactionInstruction({
    keys: [
      { pubkey: payer.publicKey, isSigner: true, isWritable: true },
      { pubkey: recipient.publicKey, isSigner: false, isWritable: true },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    ],
    programId: new PublicKey(PROGRAM_ID),
    data: dataBuffer,
  });

  // First, let's just simulate to see the logs
  const transaction = new Transaction().add(instruction);

  console.log("\nSimulating transaction...");
  const simulation = await connection.simulateTransaction(transaction, [payer]);

  console.log("\nSimulation result:", simulation.value.err ? "FAILED" : "SUCCESS");

  if (simulation.value.err) {
    console.log("Error:", JSON.stringify(simulation.value.err, null, 2));
  }

  console.log("\nLogs:");
  simulation.value.logs?.forEach((log) => console.log(log));

  // Check where exactly the error occurs
  const errorLog = simulation.value.logs?.find(log => log.includes("failed"));
  if (errorLog) {
    console.log("\n❌ Error detected:", errorLog);
  }
}

testSimpleTransfer().catch(console.error);