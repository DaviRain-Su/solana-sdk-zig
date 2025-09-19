const {
  Connection,
  Keypair,
  SystemProgram,
  PublicKey,
  Transaction,
  TransactionInstruction,
  sendAndConfirmTransaction,
  clusterApiUrl
} = require("@solana/web3.js");

describe("lazy_example", () => {
  const connection = new Connection("http://localhost:8899", "confirmed");
  const payer = Keypair.generate();
  const programId = new PublicKey("BnDd117ZBPZiJ16XUsXYbZ3hXAwd5F7xvktHMFTbB2is");

  beforeAll(async () => {
    // Airdrop SOL to payer
    const airdropSignature = await connection.requestAirdrop(
      payer.publicKey,
      2 * 1e9 // 2 SOL
    );
    await connection.confirmTransaction(airdropSignature);
  });

  it("ProcessFirstAndLast - Best case for lazy parsing", async () => {
    // Create multiple test accounts
    const accounts = [];
    for (let i = 0; i < 10; i++) {
      accounts.push({
        pubkey: Keypair.generate().publicKey,
        isSigner: false,
        isWritable: false,
      });
    }

    const instruction = new TransactionInstruction({
      programId,
      keys: accounts,
      data: Buffer.from([0]), // ProcessFirstAndLast = 0
    });

    const transaction = new Transaction().add(instruction);

    const txSig = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer],
      { skipPreflight: true }
    );

    console.log("ProcessFirstAndLast transaction signature:", txSig);

    // Get transaction details to see CU consumption
    const txDetails = await connection.getTransaction(txSig, {
      commitment: "confirmed",
    });

    console.log("CU consumed (ProcessFirstAndLast):", txDetails.meta.computeUnitsConsumed);
  });

  it("SkipMiddleAccounts - Skip pattern demonstration", async () => {
    // Create multiple test accounts
    const accounts = [];
    for (let i = 0; i < 8; i++) {
      accounts.push({
        pubkey: Keypair.generate().publicKey,
        isSigner: false,
        isWritable: false,
      });
    }

    const instruction = new TransactionInstruction({
      programId,
      keys: accounts,
      data: Buffer.from([1]), // SkipMiddleAccounts = 1
    });

    const transaction = new Transaction().add(instruction);

    const txSig = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer],
      { skipPreflight: true }
    );

    console.log("SkipMiddleAccounts transaction signature:", txSig);

    // Get transaction details to see CU consumption
    const txDetails = await connection.getTransaction(txSig, {
      commitment: "confirmed",
    });

    console.log("CU consumed (SkipMiddleAccounts):", txDetails.meta.computeUnitsConsumed);
  });

  it("FindAccount - Early exit benefit", async () => {
    // Create multiple test accounts
    const accounts = [];
    const targetKeypair = Keypair.generate();

    // Add some accounts before target
    for (let i = 0; i < 3; i++) {
      accounts.push({
        pubkey: Keypair.generate().publicKey,
        isSigner: false,
        isWritable: false,
      });
    }

    // Add target account
    accounts.push({
      pubkey: targetKeypair.publicKey,
      isSigner: false,
      isWritable: false,
    });

    // Add more accounts after target (these won't be parsed)
    for (let i = 0; i < 5; i++) {
      accounts.push({
        pubkey: Keypair.generate().publicKey,
        isSigner: false,
        isWritable: false,
      });
    }

    // Create instruction data with target key
    const instructionData = Buffer.concat([
      Buffer.from([2]), // FindAccount = 2
      targetKeypair.publicKey.toBuffer(),
    ]);

    const instruction = new TransactionInstruction({
      programId,
      keys: accounts,
      data: instructionData,
    });

    const transaction = new Transaction().add(instruction);

    const txSig = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer],
      { skipPreflight: true }
    );

    console.log("FindAccount transaction signature:", txSig);

    // Get transaction details to see CU consumption
    const txDetails = await connection.getTransaction(txSig, {
      commitment: "confirmed",
    });

    console.log("CU consumed (FindAccount):", txDetails.meta.computeUnitsConsumed);
  });

  it("ProcessAll - Worst case (but still optimized)", async () => {
    // Create multiple test accounts
    const accounts = [];
    for (let i = 0; i < 10; i++) {
      accounts.push({
        pubkey: Keypair.generate().publicKey,
        isSigner: false,
        isWritable: false,
      });
    }

    const instruction = new TransactionInstruction({
      programId,
      keys: accounts,
      data: Buffer.from([3]), // ProcessAll = 3
    });

    const transaction = new Transaction().add(instruction);

    const txSig = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer],
      { skipPreflight: true }
    );

    console.log("ProcessAll transaction signature:", txSig);

    // Get transaction details to see CU consumption
    const txDetails = await connection.getTransaction(txSig, {
      commitment: "confirmed",
    });

    console.log("CU consumed (ProcessAll):", txDetails.meta.computeUnitsConsumed);
  });

  it("Compare: Standard parsing vs Lazy parsing", async () => {
    console.log("\n=== CU Comparison Summary ===");
    console.log("Expected savings with lazy parsing:");
    console.log("- ProcessFirstAndLast: ~60% savings (only 2 of 10 accounts parsed)");
    console.log("- SkipMiddleAccounts: ~50% savings (half accounts skipped)");
    console.log("- FindAccount: ~40% savings (early exit after finding target)");
    console.log("- ProcessAll: ~10% savings (overhead reduction only)");
  });
});