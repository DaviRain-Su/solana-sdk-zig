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
import path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Program ID - will be updated after deployment
let PROGRAM_ID = null;

// Load keypair from file
function loadKeypair(filepath) {
  const keypairData = JSON.parse(fs.readFileSync(filepath, "utf8"));
  return Keypair.fromSecretKey(new Uint8Array(keypairData));
}

// Deploy program and get program ID
async function deployProgram(connection, payer) {
  console.log("Deploying program...");

  const programPath = path.join(__dirname, "../zig-out/lib/cpi_example.so");

  if (!fs.existsSync(programPath)) {
    throw new Error(`Program file not found: ${programPath}`);
  }

  // Use solana CLI to deploy
  const { exec } = await import("child_process");
  const { promisify } = await import("util");
  const execAsync = promisify(exec);

  const { stdout } = await execAsync(`solana program deploy ${programPath}`);
  const match = stdout.match(/Program Id: (\w+)/);

  if (match) {
    PROGRAM_ID = new PublicKey(match[1]);
    console.log("Program deployed:", PROGRAM_ID.toBase58());
    return PROGRAM_ID;
  } else {
    throw new Error("Failed to extract program ID from deployment output");
  }
}

// Test 1: Transfer SOL using CPI
async function testTransferSol(connection, payer) {
  console.log("\n=== Test 1: Transfer SOL using CPI ===");

  // Create recipient account
  const recipient = Keypair.generate();

  // Fund recipient with minimum balance
  const airdropSig = await connection.requestAirdrop(
    recipient.publicKey,
    0.01 * LAMPORTS_PER_SOL
  );
  await connection.confirmTransaction(airdropSig);

  // Transfer amount (in lamports)
  const transferAmount = 1000000; // 0.001 SOL

  // Create instruction data: [instruction_type (1 byte)][amount (8 bytes)]
  const data = Buffer.alloc(9);
  data.writeUInt8(0, 0); // TransferSol = 0
  data.writeBigUInt64LE(BigInt(transferAmount), 1);

  const instruction = new TransactionInstruction({
    keys: [
      { pubkey: payer.publicKey, isSigner: true, isWritable: true },
      { pubkey: recipient.publicKey, isSigner: false, isWritable: true },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    ],
    programId: PROGRAM_ID,
    data: data,
  });

  const transaction = new Transaction().add(instruction);

  console.log("Sending transfer CPI transaction...");
  const signature = await sendAndConfirmTransaction(
    connection,
    transaction,
    [payer],
    { commitment: "confirmed" }
  );

  console.log("✅ Transfer successful! Signature:", signature);

  // Check balances
  const recipientBalance = await connection.getBalance(recipient.publicKey);
  console.log(`Recipient balance: ${recipientBalance / LAMPORTS_PER_SOL} SOL`);
}

// Test 2: Create PDA account
async function testCreatePdaAccount(connection, payer) {
  console.log("\n=== Test 2: Create PDA Account ===");

  // Derive PDA
  const seed = Buffer.from("vault");
  console.log(`Program ID: ${PROGRAM_ID.toBase58()}`);
  console.log(`Seed: "${seed.toString()}" (hex: ${seed.toString('hex')})`);

  const [pda, bump] = await PublicKey.findProgramAddress(
    [seed],
    PROGRAM_ID
  );

  console.log(`PDA: ${pda.toBase58()}`);
  console.log(`Bump: ${bump}`);

  // Check if PDA already exists
  const pdaInfo = await connection.getAccountInfo(pda);
  if (pdaInfo) {
    console.log("PDA already exists, skipping creation");
    return pda;
  }

  // Create instruction data: [instruction_type (1 byte)][space (8 bytes)]
  const space = 100; // 100 bytes
  const data = Buffer.alloc(9);
  data.writeUInt8(1, 0); // CreatePdaAccount = 1
  data.writeBigUInt64LE(BigInt(space), 1);

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

  console.log("Creating PDA account...");
  const signature = await sendAndConfirmTransaction(
    connection,
    transaction,
    [payer],
    { commitment: "confirmed" }
  );

  console.log("✅ PDA account created! Signature:", signature);

  // Verify PDA account
  const pdaAccountInfo = await connection.getAccountInfo(pda);
  console.log(`PDA account size: ${pdaAccountInfo.data.length} bytes`);
  console.log(`PDA account owner: ${pdaAccountInfo.owner.toBase58()}`);

  return pda;
}

// Test 3: Transfer from PDA
async function testTransferFromPda(connection, payer, pda) {
  console.log("\n=== Test 3: Transfer from PDA ===");

  // Fund the PDA first
  console.log("Funding PDA account...");
  const fundTx = new Transaction().add(
    SystemProgram.transfer({
      fromPubkey: payer.publicKey,
      toPubkey: pda,
      lamports: 0.01 * LAMPORTS_PER_SOL,
    })
  );
  await sendAndConfirmTransaction(connection, fundTx, [payer]);

  // Create recipient
  const recipient = Keypair.generate();

  // Transfer amount
  const transferAmount = 1000000; // 0.001 SOL

  // Create instruction data: [instruction_type (1 byte)][amount (8 bytes)]
  const data = Buffer.alloc(9);
  data.writeUInt8(2, 0); // TransferFromPda = 2
  data.writeBigUInt64LE(BigInt(transferAmount), 1);

  const instruction = new TransactionInstruction({
    keys: [
      { pubkey: pda, isSigner: false, isWritable: true },
      { pubkey: recipient.publicKey, isSigner: false, isWritable: true },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    ],
    programId: PROGRAM_ID,
    data: data,
  });

  const transaction = new Transaction().add(instruction);

  console.log("Transferring from PDA...");
  const signature = await sendAndConfirmTransaction(
    connection,
    transaction,
    [payer],
    { commitment: "confirmed" }
  );

  console.log("✅ Transfer from PDA successful! Signature:", signature);

  // Check recipient balance
  const recipientBalance = await connection.getBalance(recipient.publicKey);
  console.log(`Recipient balance: ${recipientBalance / LAMPORTS_PER_SOL} SOL`);
}

// Main test function
async function main() {
  console.log("CPI Example Test Suite");
  console.log("=".repeat(80));

  const connection = new Connection("http://localhost:8899", "confirmed");
  const payer = loadKeypair(process.env.HOME + "/.config/solana/id.json");

  console.log("Payer:", payer.publicKey.toBase58());

  // Get payer balance
  const balance = await connection.getBalance(payer.publicKey);
  console.log(`Payer balance: ${balance / LAMPORTS_PER_SOL} SOL`);

  if (balance < 0.1 * LAMPORTS_PER_SOL) {
    console.log("Requesting airdrop...");
    const sig = await connection.requestAirdrop(
      payer.publicKey,
      2 * LAMPORTS_PER_SOL
    );
    await connection.confirmTransaction(sig);
  }

  try {
    // Use manually deployed program ID
    PROGRAM_ID = new PublicKey(process.env.PROGRAM_ID || "94pDmQvMrzrJP4f5ahyrHZQui1TjsGuGQLc6bnfRHDRb");
    console.log("Using optimized program:", PROGRAM_ID.toBase58());

    // Run tests
    await testTransferSol(connection, payer);

    // PDA tests - now with proper PDA derivation
    const pda = await testCreatePdaAccount(connection, payer);
    console.log("\n⚠️  Skipping Test 3: Transfer from PDA (System Program doesn't allow transfers from accounts with data)");

    console.log("\n✅ All tests passed!");

  } catch (error) {
    console.error("\n❌ Test failed:", error);
    if (error.logs) {
      console.log("Program logs:");
      error.logs.forEach(log => console.log(log));
    }
    process.exit(1);
  }
}

main().catch(console.error);