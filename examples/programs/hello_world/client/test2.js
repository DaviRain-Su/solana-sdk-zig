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

const PROGRAM_ID = "H1QXpm4HmVRKHobHb3AfQ6vMJP9NBBc97U7RY3X9p4wB";

function loadKeypair(filepath) {
  const keypairData = JSON.parse(fs.readFileSync(filepath, "utf8"));
  return Keypair.fromSecretKey(new Uint8Array(keypairData));
}

async function testInstruction(
  connection,
  payer,
  instructionByte,
  description,
) {
  console.log(`\n=== Testing: ${description} ===`);
  console.log(
    `Sending instruction byte: ${instructionByte} (0x${instructionByte.toString(16)})`,
  );

  const ix = new TransactionInstruction({
    keys: [],
    programId: new PublicKey(PROGRAM_ID),
    data: Buffer.from([instructionByte]),
  });

  console.log("Instruction data buffer:", ix.data);
  console.log("Buffer contents:", Array.from(ix.data));

  const tx = new Transaction().add(ix);

  try {
    const simulation = await connection.simulateTransaction(tx, [payer]);

    if (simulation.value.err) {
      console.log("❌ Failed with error:", simulation.value.err);
    } else {
      console.log("✅ Success!");
    }

    // Show logs
    console.log("Logs:");
    simulation.value.logs.forEach((log) => {
      if (log.includes("Program log:")) {
        console.log("  ", log);
      }
    });
  } catch (e) {
    console.error("Exception:", e.message);
  }
}

async function main() {
  const connection = new Connection("http://localhost:8899", "confirmed");
  const payer = loadKeypair(process.env.HOME + "/.config/solana/id.json");

  console.log("Program:", PROGRAM_ID);

  // Test all three instruction types
  await testInstruction(connection, payer, 0, "Initialize (0)");
  await testInstruction(connection, payer, 1, "UpdateGreeting (1)");
  await testInstruction(connection, payer, 2, "SayHello (2)");

  // Also test some edge cases
  await testInstruction(connection, payer, 3, "Invalid instruction (3)");
  await testInstruction(connection, payer, 255, "Max byte value (255)");

  // Test with Initialize and an account
  console.log("\n=== Testing Initialize with Account ===");
  const greetingAccount = Keypair.generate();
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

  // Try different ways of creating the instruction data
  console.log("\nMethod 1: Buffer.from([0])");
  let data1 = Buffer.from([0]);
  console.log("  Buffer:", data1, "Contents:", Array.from(data1));

  console.log("\nMethod 2: Buffer.alloc + writeUInt8");
  let data2 = Buffer.alloc(1);
  data2.writeUInt8(0, 0);
  console.log("  Buffer:", data2, "Contents:", Array.from(data2));

  console.log("\nMethod 3: Uint8Array");
  let data3 = new Uint8Array([0]);
  console.log("  Buffer:", data3, "Contents:", Array.from(data3));

  // Use method 1 for the actual test
  console.log("\nCreating Initialize instruction with data:", data1, "Contents:", Array.from(data1));
  const initIx = new TransactionInstruction({
    keys: [
      {
        pubkey: greetingAccount.publicKey,
        isSigner: true,
        isWritable: true,
      },
    ],
    programId: new PublicKey(PROGRAM_ID),
    data: data1,
  });
  console.log("Instruction created. Data:", initIx.data, "Contents:", Array.from(initIx.data));

  const tx = new Transaction().add(createAccountIx, initIx);

  const simulation = await connection.simulateTransaction(tx, [
    payer,
    greetingAccount,
  ]);
  console.log("\nSimulation logs:");
  simulation.value.logs.forEach((log) => {
    if (log.includes("Program log:")) {
      console.log("  ", log);
    }
  });
}

main().catch(console.error);
