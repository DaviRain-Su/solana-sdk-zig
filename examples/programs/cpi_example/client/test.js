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

// Program ID - Update this with your deployed program ID
const PROGRAM_ID = "9rPdcSEcW5KFnDyFo8YDfjwcR9nBhDtxfKy876xqDSXK";

// Instruction enum matching our Zig program
const CpiExampleInstruction = {
  TransferSol: 0,
  CreatePdaAccount: 1,
  TransferFromPda: 2,
};

// Load keypair from file
function loadKeypair(filepath) {
  const keypairData = JSON.parse(fs.readFileSync(filepath, "utf8"));
  return Keypair.fromSecretKey(new Uint8Array(keypairData));
}

// Create PDA
function findProgramAddress(seeds, programId) {
  return PublicKey.findProgramAddressSync(seeds, programId);
}

async function main() {
  console.log("CPI Example Test Client");
  console.log("=".repeat(80));

  // Connect to local validator
  const connection = new Connection("http://localhost:8899", "confirmed");
  console.log("Connected to local validator");

  // Load payer keypair
  const payer = loadKeypair(process.env.HOME + "/.config/solana/id.json");
  console.log("Payer:", payer.publicKey.toBase58());
  console.log("Program ID:", PROGRAM_ID);

  // Check payer balance
  const balance = await connection.getBalance(payer.publicKey);
  console.log("Payer balance:", balance / LAMPORTS_PER_SOL, "SOL");

  if (balance < 0.1 * LAMPORTS_PER_SOL) {
    console.error("❌ Insufficient balance. Please airdrop some SOL first.");
    console.log("Run: solana airdrop 1");
    return;
  }

  // Create a recipient for transfers
  const recipient = Keypair.generate();
  console.log("Recipient:", recipient.publicKey.toBase58());

  // =============================================================================
  // Test 1: Transfer SOL using CPI
  // =============================================================================
  console.log("\n" + "=".repeat(80));
  console.log("Test 1: Transfer SOL using CPI");
  console.log("=".repeat(80));

  try {
    const lamportsToTransfer = 0.01 * LAMPORTS_PER_SOL; // 0.01 SOL

    // Create instruction data: [instruction_discriminator][lamports as u64]
    const dataBuffer = Buffer.alloc(9);
    dataBuffer.writeUInt8(CpiExampleInstruction.TransferSol, 0);
    dataBuffer.writeBigUInt64LE(BigInt(lamportsToTransfer), 1);

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
    const signature = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer],
      { commitment: "confirmed" }
    );
    console.log("✅ Transfer successful! Transaction:", signature);

    // Check recipient balance
    const recipientBalance = await connection.getBalance(recipient.publicKey);
    console.log("Recipient balance:", recipientBalance / LAMPORTS_PER_SOL, "SOL");

    // Get transaction logs
    const tx = await connection.getTransaction(signature, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0,
    });
    console.log("Logs:");
    tx.meta.logMessages
      .filter((log) => log.includes("Program log:"))
      .forEach((log) => console.log("  ", log));
  } catch (error) {
    console.error("❌ Failed:", error.message);
  }

  // =============================================================================
  // Test 2: Create PDA Account
  // =============================================================================
  console.log("\n" + "=".repeat(80));
  console.log("Test 2: Create PDA Account");
  console.log("=".repeat(80));

  // Derive PDA
  const seed = Buffer.from("vault");
  const [pdaAddress, bump] = findProgramAddress([seed], new PublicKey(PROGRAM_ID));
  console.log("PDA:", pdaAddress.toBase58());
  console.log("Bump:", bump);

  try {
    // Check if PDA already exists
    const pdaInfo = await connection.getAccountInfo(pdaAddress);
    if (pdaInfo) {
      console.log("PDA already exists, skipping creation");
    } else {
      const space = 1024; // 1KB for example

      // Create instruction data: [instruction_discriminator][space as u64]
      const dataBuffer = Buffer.alloc(9);
      dataBuffer.writeUInt8(CpiExampleInstruction.CreatePdaAccount, 0);
      dataBuffer.writeBigUInt64LE(BigInt(space), 1);

      const instruction = new TransactionInstruction({
        keys: [
          { pubkey: payer.publicKey, isSigner: true, isWritable: true },
          { pubkey: pdaAddress, isSigner: false, isWritable: true },
          { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
          { pubkey: PublicKey.default, isSigner: false, isWritable: false }, // Rent sysvar (not used)
        ],
        programId: new PublicKey(PROGRAM_ID),
        data: dataBuffer,
      });

      const transaction = new Transaction().add(instruction);
      const signature = await sendAndConfirmTransaction(
        connection,
        transaction,
        [payer],
        { commitment: "confirmed" }
      );
      console.log("✅ PDA account created! Transaction:", signature);

      // Verify PDA was created
      const newPdaInfo = await connection.getAccountInfo(pdaAddress);
      if (newPdaInfo) {
        console.log("PDA account details:");
        console.log("  Owner:", newPdaInfo.owner.toBase58());
        console.log("  Balance:", newPdaInfo.lamports / LAMPORTS_PER_SOL, "SOL");
        console.log("  Size:", newPdaInfo.data.length, "bytes");
      }

      // Get transaction logs
      const tx = await connection.getTransaction(signature, {
        commitment: "confirmed",
        maxSupportedTransactionVersion: 0,
      });
      console.log("Logs:");
      tx.meta.logMessages
        .filter((log) => log.includes("Program log:"))
        .forEach((log) => console.log("  ", log));
    }
  } catch (error) {
    console.error("❌ Failed:", error.message);
  }

  // =============================================================================
  // Test 3: Transfer from PDA using invoke_signed
  // =============================================================================
  console.log("\n" + "=".repeat(80));
  console.log("Test 3: Transfer from PDA using invoke_signed");
  console.log("=".repeat(80));

  try {
    // First fund the PDA if needed
    const pdaBalance = await connection.getBalance(pdaAddress);
    if (pdaBalance < 0.005 * LAMPORTS_PER_SOL) {
      console.log("Funding PDA first...");
      const fundTx = new Transaction().add(
        SystemProgram.transfer({
          fromPubkey: payer.publicKey,
          toPubkey: pdaAddress,
          lamports: 0.01 * LAMPORTS_PER_SOL,
        })
      );
      await sendAndConfirmTransaction(connection, fundTx, [payer]);
      console.log("✅ PDA funded with 0.01 SOL");
    }

    const lamportsToTransfer = 0.001 * LAMPORTS_PER_SOL; // 0.001 SOL

    // Create instruction data: [instruction_discriminator][lamports as u64]
    const dataBuffer = Buffer.alloc(9);
    dataBuffer.writeUInt8(CpiExampleInstruction.TransferFromPda, 0);
    dataBuffer.writeBigUInt64LE(BigInt(lamportsToTransfer), 1);

    const newRecipient = Keypair.generate();
    console.log("New recipient:", newRecipient.publicKey.toBase58());

    const instruction = new TransactionInstruction({
      keys: [
        { pubkey: pdaAddress, isSigner: false, isWritable: true },
        { pubkey: newRecipient.publicKey, isSigner: false, isWritable: true },
        { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      ],
      programId: new PublicKey(PROGRAM_ID),
      data: dataBuffer,
    });

    const transaction = new Transaction().add(instruction);
    const signature = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer],
      { commitment: "confirmed" }
    );
    console.log("✅ Transfer from PDA successful! Transaction:", signature);

    // Check balances
    const finalPdaBalance = await connection.getBalance(pdaAddress);
    const recipientBalance = await connection.getBalance(newRecipient.publicKey);
    console.log("Final PDA balance:", finalPdaBalance / LAMPORTS_PER_SOL, "SOL");
    console.log("Recipient balance:", recipientBalance / LAMPORTS_PER_SOL, "SOL");

    // Get transaction logs
    const tx = await connection.getTransaction(signature, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0,
    });
    console.log("Logs:");
    tx.meta.logMessages
      .filter((log) => log.includes("Program log:"))
      .forEach((log) => console.log("  ", log));
  } catch (error) {
    console.error("❌ Failed:", error.message);
  }

  // =============================================================================
  // Test 4: Error Case - Invalid System Program
  // =============================================================================
  console.log("\n" + "=".repeat(80));
  console.log("Test 4: Error Case - Invalid System Program");
  console.log("=".repeat(80));

  try {
    const dataBuffer = Buffer.alloc(9);
    dataBuffer.writeUInt8(CpiExampleInstruction.TransferSol, 0);
    dataBuffer.writeBigUInt64LE(BigInt(1000), 1);

    const instruction = new TransactionInstruction({
      keys: [
        { pubkey: payer.publicKey, isSigner: true, isWritable: true },
        { pubkey: recipient.publicKey, isSigner: false, isWritable: true },
        { pubkey: payer.publicKey, isSigner: false, isWritable: false }, // Wrong! Should be SystemProgram
      ],
      programId: new PublicKey(PROGRAM_ID),
      data: dataBuffer,
    });

    const transaction = new Transaction().add(instruction);
    const simulation = await connection.simulateTransaction(transaction, [payer]);

    if (simulation.value.err) {
      console.log("✅ Expected failure:", simulation.value.err);
      console.log("Error logs:");
      simulation.value.logs
        .filter((log) => log.includes("Program log:"))
        .forEach((log) => console.log("  ", log));
    } else {
      console.log("❌ Should have failed but didn't");
    }
  } catch (error) {
    console.log("✅ Expected error:", error.message);
  }

  console.log("\n" + "=".repeat(80));
  console.log("✅ All CPI tests completed!");
  console.log("=".repeat(80));
}

main().catch(console.error);