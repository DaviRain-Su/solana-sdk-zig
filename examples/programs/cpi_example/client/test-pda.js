import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
  SystemProgram,
} from "@solana/web3.js";
import fs from "fs";

const PROGRAM_ID = new PublicKey("2wT81zXKjq3P2ZDpCPSGQ4K1HigsUzUmLrxT8WYycDxS");

// Load keypair
function loadKeypair(filepath) {
  const keypairData = JSON.parse(fs.readFileSync(filepath, "utf8"));
  return Keypair.fromSecretKey(new Uint8Array(keypairData));
}

async function main() {
  const connection = new Connection("http://localhost:8899", "confirmed");
  const payer = loadKeypair(process.env.HOME + "/.config/solana/id.json");

  console.log("Testing PDA Generation");
  console.log("Program ID:", PROGRAM_ID.toBase58());

  // Derive PDA using same seed as Zig program
  const seed = Buffer.from("vault");
  console.log(`Seed: "${seed.toString()}" (hex: ${seed.toString('hex')})`);

  const [pda, bump] = await PublicKey.findProgramAddress(
    [seed],
    PROGRAM_ID
  );

  console.log("JS calculated PDA:", pda.toBase58());
  console.log("JS calculated Bump:", bump);

  // Now call the program to see what it calculates
  const data = Buffer.alloc(9);
  data.writeUInt8(1, 0); // CreatePdaAccount = 1
  data.writeBigUInt64LE(BigInt(100), 1); // space

  const instruction = new TransactionInstruction({
    keys: [
      { pubkey: payer.publicKey, isSigner: true, isWritable: true },
      { pubkey: pda, isSigner: false, isWritable: true },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    ],
    programId: PROGRAM_ID,
    data: data,
  });

  const transaction = new Transaction().add(instruction);

  console.log("\nSimulating transaction to see Zig PDA calculation...");
  const simulation = await connection.simulateTransaction(transaction, [payer]);

  console.log("\nSimulation logs:");
  simulation.value.logs?.forEach(log => console.log(log));
}

main().catch(console.error);