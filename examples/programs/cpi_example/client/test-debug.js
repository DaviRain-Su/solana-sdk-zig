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

const PROGRAM_ID = "GJthMRM4sffHG2f9WpgZ2qdxRAqH6sTkhcrmsgWHaNjQ";

// Load keypair from file
function loadKeypair(filepath) {
  const keypairData = JSON.parse(fs.readFileSync(filepath, "utf8"));
  return Keypair.fromSecretKey(new Uint8Array(keypairData));
}

async function testDebugCPI() {
  console.log("Testing Debug CPI");
  console.log("=".repeat(80));

  const connection = new Connection("http://localhost:8899", "confirmed");
  const payer = loadKeypair(process.env.HOME + "/.config/solana/id.json");

  console.log("Payer:", payer.publicKey.toBase58());
  console.log("Program ID:", PROGRAM_ID);

  // Test with just System Program, no other accounts
  const dataBuffer = Buffer.alloc(1);
  dataBuffer.writeUInt8(5, 0); // Custom test instruction

  // Create a second keypair for testing transfers
  const recipient = Keypair.generate();

  const instruction = new TransactionInstruction({
    keys: [
      { pubkey: payer.publicKey, isSigner: true, isWritable: true },
      { pubkey: recipient.publicKey, isSigner: false, isWritable: true },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    ],
    programId: new PublicKey(PROGRAM_ID),
    data: dataBuffer,
  });

  const transaction = new Transaction().add(instruction);

  console.log("\nSimulating transaction...");
  const simulation = await connection.simulateTransaction(transaction, [payer]);

  console.log("\nSimulation result:", simulation.value.err ? "FAILED" : "SUCCESS");

  if (simulation.value.err) {
    console.log("Error:", JSON.stringify(simulation.value.err, null, 2));
  }

  console.log("\nLogs:");
  simulation.value.logs?.forEach((log) => console.log(log));
}

testDebugCPI().catch(console.error);