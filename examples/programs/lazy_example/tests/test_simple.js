const {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  TransactionInstruction,
  sendAndConfirmTransaction,
} = require("@solana/web3.js");

async function test() {
  const connection = new Connection("http://localhost:8899", "confirmed");
  const payer = Keypair.generate();
  const programId = new PublicKey("Fj6iBgvoj1atNMgg93h2BNToAUWqbREYuAyTreXYAFwL");

  // Airdrop SOL to payer
  const airdropSignature = await connection.requestAirdrop(
    payer.publicKey,
    2 * 1e9 // 2 SOL
  );
  await connection.confirmTransaction(airdropSignature);

  // Test with 10 accounts for ProcessFirstAndLast
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

  try {
    const txSig = await sendAndConfirmTransaction(
      connection,
      transaction,
      [payer],
      { skipPreflight: false }
    );
    console.log("Success! Transaction signature:", txSig);

    const txDetails = await connection.getTransaction(txSig, {
      commitment: "confirmed",
    });
    console.log("CU consumed:", txDetails.meta.computeUnitsConsumed);
    console.log("Logs:", txDetails.meta.logMessages);
  } catch (err) {
    console.error("Error:", err);
    if (err.logs) {
      console.log("Logs:", err.logs);
    }
  }
}

test();