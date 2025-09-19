import { Connection, Keypair, PublicKey } from "@solana/web3.js";
import { execSync } from "child_process";
import fs from "fs";
import path from "path";

async function deploy() {
  console.log("CPI Example Deployment Script");
  console.log("=".repeat(80));

  // Get project root
  const projectRoot = path.resolve(process.cwd(), "..");
  console.log("Project root:", projectRoot);

  // Build the program
  console.log("\nBuilding program...");
  try {
    execSync("../../../solana-zig/zig build", {
      cwd: projectRoot,
      stdio: "inherit",
    });
    console.log("✅ Build successful!");
  } catch (error) {
    console.error("❌ Build failed:", error.message);
    process.exit(1);
  }

  // Check if keypair exists
  const keypairPath = path.join(projectRoot, "cpi_example-keypair.json");
  let programId;

  if (!fs.existsSync(keypairPath)) {
    console.log("\nGenerating program keypair...");
    try {
      execSync("../../../solana-zig/zig build keypair", {
        cwd: projectRoot,
        stdio: "inherit",
      });
      console.log("✅ Keypair generated!");
    } catch (error) {
      console.error("❌ Keypair generation failed:", error.message);
      process.exit(1);
    }
  }

  // Load the keypair to get program ID
  const keypairData = JSON.parse(fs.readFileSync(keypairPath, "utf8"));
  const programKeypair = Keypair.fromSecretKey(new Uint8Array(keypairData));
  programId = programKeypair.publicKey.toBase58();
  console.log("\nProgram ID:", programId);

  // Check if local validator is running
  const connection = new Connection("http://localhost:8899", "confirmed");
  try {
    const version = await connection.getVersion();
    console.log("Solana version:", version["solana-core"]);
  } catch (error) {
    console.error("❌ Cannot connect to local validator");
    console.log("Please start local validator with: solana-test-validator");
    process.exit(1);
  }

  // Deploy the program
  console.log("\nDeploying program...");
  const programPath = path.join(projectRoot, "zig-out/lib/cpi_example.so");

  if (!fs.existsSync(programPath)) {
    console.error("❌ Program binary not found at:", programPath);
    process.exit(1);
  }

  try {
    const deployCommand = `solana program deploy ${programPath} --program-id ${keypairPath}`;
    console.log("Running:", deployCommand);
    execSync(deployCommand, { stdio: "inherit" });
    console.log("✅ Program deployed successfully!");
  } catch (error) {
    console.error("❌ Deployment failed:", error.message);
    console.log("\nTroubleshooting:");
    console.log("1. Make sure local validator is running: solana-test-validator");
    console.log("2. Make sure you have enough SOL: solana airdrop 2");
    console.log("3. Check your Solana CLI config: solana config get");
    process.exit(1);
  }

  // Verify deployment
  console.log("\nVerifying deployment...");
  const programInfo = await connection.getAccountInfo(new PublicKey(programId));
  if (programInfo && programInfo.executable) {
    console.log("✅ Program verified on-chain!");
    console.log("  Owner:", programInfo.owner.toBase58());
    console.log("  Executable:", programInfo.executable);
    console.log("  Size:", programInfo.data.length, "bytes");
  } else {
    console.error("❌ Program not found on-chain");
    process.exit(1);
  }

  // Save program ID to environment file for easy testing
  const envContent = `PROGRAM_ID=${programId}\n`;
  fs.writeFileSync(path.join(process.cwd(), ".env"), envContent);
  console.log("\n✅ Program ID saved to .env file");

  console.log("\n" + "=".repeat(80));
  console.log("Deployment complete!");
  console.log("Program ID:", programId);
  console.log("\nNext steps:");
  console.log("1. Run tests: npm test");
  console.log("2. Or set PROGRAM_ID and run: PROGRAM_ID=" + programId + " npm test");
  console.log("=".repeat(80));
}

deploy().catch((error) => {
  console.error("Deployment error:", error);
  process.exit(1);
});