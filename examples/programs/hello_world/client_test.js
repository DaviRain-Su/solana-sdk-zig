#!/usr/bin/env node

/**
 * Simple client test for Hello World program
 *
 * This demonstrates how to interact with the Zig program from JavaScript
 */

const {
    Connection,
    Keypair,
    PublicKey,
    Transaction,
    TransactionInstruction,
    SystemProgram,
    sendAndConfirmTransaction,
} = require('@solana/web3.js');

// Constants
const PROGRAM_ID = new PublicKey('YOUR_PROGRAM_ID_HERE'); // Replace with actual program ID
const GREETING_SIZE = 40; // Size of GreetingAccount struct

// Instructions
const Instructions = {
    Initialize: 0,
    UpdateGreeting: 1,
    SayHello: 2,
};

async function main() {
    // Connect to cluster
    const connection = new Connection('http://localhost:8899', 'confirmed');

    // Generate a new keypair for the payer
    const payer = Keypair.generate();

    // Airdrop SOL to payer (only works on localhost/devnet)
    console.log('Requesting airdrop...');
    const airdropSignature = await connection.requestAirdrop(
        payer.publicKey,
        2 * 1000000000, // 2 SOL
    );
    await connection.confirmTransaction(airdropSignature);

    // Generate greeting account
    const greetingAccount = Keypair.generate();

    console.log('Program ID:', PROGRAM_ID.toBase58());
    console.log('Payer:', payer.publicKey.toBase58());
    console.log('Greeting Account:', greetingAccount.publicKey.toBase58());

    // Create greeting account
    console.log('\n1. Creating greeting account...');
    const createAccountTx = new Transaction().add(
        SystemProgram.createAccount({
            fromPubkey: payer.publicKey,
            newAccountPubkey: greetingAccount.publicKey,
            lamports: await connection.getMinimumBalanceForRentExemption(GREETING_SIZE),
            space: GREETING_SIZE,
            programId: PROGRAM_ID,
        })
    );

    await sendAndConfirmTransaction(
        connection,
        createAccountTx,
        [payer, greetingAccount],
    );
    console.log('Account created');

    // Initialize the greeting account
    console.log('\n2. Initializing greeting account...');
    const initTx = new Transaction().add(
        new TransactionInstruction({
            programId: PROGRAM_ID,
            keys: [
                { pubkey: greetingAccount.publicKey, isSigner: true, isWritable: true }
            ],
            data: Buffer.from([Instructions.Initialize]),
        })
    );

    await sendAndConfirmTransaction(
        connection,
        initTx,
        [payer, greetingAccount],
    );
    console.log('Account initialized');

    // Say hello (read greeting)
    console.log('\n3. Saying hello...');
    const sayHelloTx = new Transaction().add(
        new TransactionInstruction({
            programId: PROGRAM_ID,
            keys: [
                { pubkey: greetingAccount.publicKey, isSigner: false, isWritable: false }
            ],
            data: Buffer.from([Instructions.SayHello]),
        })
    );

    await sendAndConfirmTransaction(
        connection,
        sayHelloTx,
        [payer],
    );
    console.log('Said hello');

    // Update greeting
    console.log('\n4. Updating greeting...');
    const newMessage = "Hello from JavaScript!";
    const updateData = Buffer.concat([
        Buffer.from([Instructions.UpdateGreeting]),
        Buffer.from(newMessage),
    ]);

    const updateTx = new Transaction().add(
        new TransactionInstruction({
            programId: PROGRAM_ID,
            keys: [
                { pubkey: greetingAccount.publicKey, isSigner: true, isWritable: true }
            ],
            data: updateData,
        })
    );

    await sendAndConfirmTransaction(
        connection,
        updateTx,
        [payer, greetingAccount],
    );
    console.log('Greeting updated');

    // Say hello again
    console.log('\n5. Saying hello again...');
    await sendAndConfirmTransaction(
        connection,
        sayHelloTx,
        [payer],
    );
    console.log('Said hello with new message');

    // Fetch and display account data
    console.log('\n6. Fetching account data...');
    const accountInfo = await connection.getAccountInfo(greetingAccount.publicKey);
    if (accountInfo) {
        console.log('Account data (hex):', accountInfo.data.toString('hex'));

        // Parse the data
        const magic = accountInfo.data.readUInt32LE(0);
        const greetingCount = accountInfo.data.readUInt32LE(4);
        const message = accountInfo.data.subarray(8, 40);

        // Find null terminator
        let messageEnd = message.indexOf(0);
        if (messageEnd === -1) messageEnd = message.length;
        const messageStr = message.subarray(0, messageEnd).toString('utf8');

        console.log('Parsed data:');
        console.log('  Magic:', magic.toString(16));
        console.log('  Greeting Count:', greetingCount);
        console.log('  Message:', messageStr);
    }
}

main().catch(console.error);