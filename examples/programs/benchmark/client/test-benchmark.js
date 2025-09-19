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

const PROGRAM_ID = new PublicKey("acvHoEGfxPSHncc48uGc6nsXcT3uKcw5bRSkhBFzxT6");

async function testBenchmark(testType, testName, needsPDA = false) {
  console.log(`\n=== Test ${testType}: ${testName} ===`);

  const connection = new Connection("http://localhost:8899", "confirmed");
  const payer = Keypair.generate();

  // Airdrop if needed
  const balance = await connection.getBalance(payer.publicKey);
  if (balance < LAMPORTS_PER_SOL / 2) {
    const sig = await connection.requestAirdrop(payer.publicKey, LAMPORTS_PER_SOL);
    await connection.confirmTransaction(sig);
  }

  let keys = [];
  let data = Buffer.from([testType]);

  // Add PDA for tests that need it
  if (needsPDA) {
    const seed = Buffer.from("You pass butter", "utf8");
    let bump = 255;
    let pda;
    while (bump > 0) {
      try {
        pda = PublicKey.createProgramAddressSync([seed, Buffer.from([bump])], PROGRAM_ID);
        break;
      } catch (e) {
        bump--;
      }
    }
    keys.push({ pubkey: pda, isSigner: false, isWritable: true });
    data = Buffer.concat([Buffer.from([testType]), Buffer.from([bump])]);
  } else if (testType > 0) {
    // Add a dummy account for tests that need one
    keys.push({ pubkey: payer.publicKey, isSigner: false, isWritable: false });
    if (testType >= 2) {
      // Add bump seed for PDA test
      data = Buffer.concat([Buffer.from([testType]), Buffer.from([255])]);
    }
  }

  // Add system program for build_ix test
  if (testType === 3) {
    keys.push({ pubkey: SystemProgram.programId, isSigner: false, isWritable: false });
  }

  const instruction = new TransactionInstruction({
    keys: keys,
    programId: PROGRAM_ID,
    data: data,
  });

  const transaction = new Transaction().add(instruction);

  try {
    const signature = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer],
      { commitment: "confirmed", skipPreflight: false }
    );

    // Get transaction details to extract CU usage
    const txDetails = await connection.getTransaction(signature, {
      commitment: "confirmed",
      maxSupportedTransactionVersion: 0
    });

    if (txDetails && txDetails.meta && txDetails.meta.logMessages) {
      for (const log of txDetails.meta.logMessages) {
        if (log.includes("consumed") && log.includes("compute units")) {
          const match = log.match(/consumed (\d+) of \d+ compute units/);
          if (match) {
            const cu = parseInt(match[1]);
            console.log(`CU consumed: ${cu}`);
            return cu;
          }
        }
      }
    }
  } catch (error) {
    if (error.logs) {
      for (const log of error.logs) {
        if (log.includes("consumed") && log.includes("compute units")) {
          const match = log.match(/consumed (\d+) of \d+ compute units/);
          if (match) {
            const cu = parseInt(match[1]);
            console.log(`CU consumed: ${cu}`);
            return cu;
          }
        }
      }
    }
    console.log("Error:", error.message);
  }
  return 0;
}

async function main() {
  console.log("=== Zig SDK CU Bottleneck Analysis ===");
  console.log("Program ID:", PROGRAM_ID.toBase58());

  const results = {};

  // Run tests
  results.empty = await testBenchmark(0, "Empty processor (pure entrypoint overhead)");
  results.accountAccess = await testBenchmark(1, "Single account key access");
  results.pdaDerivation = await testBenchmark(2, "PDA derivation only (no CPI)");
  results.buildIx = await testBenchmark(3, "Build instruction (no invoke)");

  // Calculate incremental costs
  console.log("\n=== CU Breakdown Analysis ===");
  console.log(`1. Pure entrypoint overhead: ${results.empty} CU`);
  console.log(`2. Account access cost: ${results.accountAccess - results.empty} CU`);
  console.log(`3. PDA derivation cost: ${results.pdaDerivation - results.empty} CU`);
  console.log(`4. Instruction building cost: ${results.buildIx - results.empty} CU`);

  console.log("\n=== Comparison with Rosetta ===");
  console.log(`Rosetta Rust (allocate with CPI): 309 CU (program logic)`);
  console.log(`Our Zig rosetta_cpi: 2226 CU total`);
  console.log(`Our Zig entrypoint overhead: ${results.empty} CU`);
  console.log(`Estimated Zig program logic: ${2226 - results.empty} CU`);

  if (results.empty > 300) {
    console.log("\n⚠️ MAJOR BOTTLENECK: Entrypoint parsing alone exceeds Rosetta's total!");
  }
}

main().catch(console.error);