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

// Test the Rosetta-compatible CPI program
async function testRosettaCPI() {
  console.log("=== Testing Rosetta-compatible Zig CPI Program ===");

  const connection = new Connection("http://localhost:8899", "confirmed");
  const payer = Keypair.generate();

  // Airdrop SOL
  const sig = await connection.requestAirdrop(payer.publicKey, LAMPORTS_PER_SOL);
  await connection.confirmTransaction(sig);

  // Use our deployed program
  const programId = new PublicKey("3LP6iCbbwaKCqMPHnG5GaBxVw4qs1mVTrAx49etKiBe5");
  console.log("Program ID:", programId.toBase58());

  // Find PDA with seed "You pass butter" (matching Rosetta)
  const seed = Buffer.from("You pass butter", "utf8");
  let bump = 255;
  let pda;

  while (bump > 0) {
    try {
      pda = PublicKey.createProgramAddressSync([seed, Buffer.from([bump])], programId);
      break;
    } catch (e) {
      bump--;
    }
  }

  if (!pda) throw new Error("Could not find PDA");
  console.log("PDA:", pda.toBase58(), "Bump:", bump);

  // Create instruction with bump seed as data
  const instruction = new TransactionInstruction({
    keys: [
      { pubkey: pda, isSigner: false, isWritable: true },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    ],
    programId: programId,
    data: Buffer.from([bump]), // Pass bump seed as instruction data
  });

  const transaction = new Transaction().add(instruction);

  console.log("Executing allocate instruction...");
  try {
    const signature = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer],
      {
        commitment: "confirmed",
        skipPreflight: false,
        preflightCommitment: "confirmed"
      }
    );

    console.log("✅ Allocate successful! Signature:", signature);

    // Get transaction details to extract CU usage
    const txDetails = await connection.getTransaction(signature, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0
    });

    if (txDetails && txDetails.meta && txDetails.meta.logMessages) {
      for (const log of txDetails.meta.logMessages) {
        if (log.includes("consumed") && log.includes("compute units")) {
          console.log("CU Usage:", log);

          // Extract CU numbers
          const match = log.match(/consumed (\d+) of \d+ compute units/);
          if (match) {
            const totalCU = parseInt(match[1]);
            const syscallCU = 1500 + 1000; // create_program_address + invoke_signed
            const programLogicCU = totalCU - syscallCU;

            console.log("\n=== CU Analysis (Zig Implementation) ===");
            console.log("Total CU Usage:", totalCU);
            console.log("Syscall CUs (create_program_address + invoke_signed):", syscallCU);
            console.log("Program Logic CUs (minus syscalls):", programLogicCU);
            console.log("Rosetta Target (Rust):", 309, "CU");
            console.log("Zig vs Rust Performance:", programLogicCU > 309 ? `+${programLogicCU - 309} CU` : `${programLogicCU - 309} CU`);
          }
          break;
        }
      }
    }

  } catch (error) {
    console.log("Transaction failed, checking logs for CU data...");

    // Extract CU usage from error logs
    if (error.logs) {
      for (const log of error.logs) {
        if (log.includes("consumed") && log.includes("compute units")) {
          console.log("\nCU Usage:", log);

          const match = log.match(/consumed (\d+) of \d+ compute units/);
          if (match) {
            const totalCU = parseInt(match[1]);
            const syscallCU = 1500 + 1000;
            const programLogicCU = totalCU - syscallCU;

            console.log("\n=== CU Analysis (Zig Implementation) ===");
            console.log("Total CU Usage:", totalCU);
            console.log("Syscall CUs:", syscallCU);
            console.log("Program Logic CUs:", programLogicCU);
            console.log("Rosetta Target (Rust):", 309, "CU");
            console.log("Zig Performance Gap:", `+${programLogicCU - 309} CU`);
          }
          break;
        }
      }
    }
  }
}

// Run test
testRosettaCPI().catch(console.error);