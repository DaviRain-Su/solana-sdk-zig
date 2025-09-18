// Generate test data using actual Solana runtime serialization format
use solana_program::{account_info::AccountInfo, pubkey::Pubkey};
use std::fs::File;
use std::io::Write;
use std::path::Path;

/// This simulates how Solana runtime serializes accounts for BPF programs
/// Based on solana/programs/bpf_loader/src/serialization.rs
pub fn generate_solana_format_test_data() {
    let test_data_dir = Path::new("../test_data");
    if !test_data_dir.exists() {
        std::fs::create_dir_all(test_data_dir).expect("Failed to create test_data directory");
    }

    // Generate different test cases
    generate_single_account_solana_format(&test_data_dir);
    generate_multiple_accounts_solana_format(&test_data_dir);
    generate_empty_data_accounts_solana_format(&test_data_dir);
    generate_accounts_with_duplicates_solana_format(&test_data_dir);
    generate_complex_iteration_solana_format(&test_data_dir);

    println!("\n✓ All Solana format test data files generated in test_data/");
}

fn generate_single_account_solana_format(test_data_dir: &Path) {
    let mut buffer = Vec::new();

    // Create account data
    let key = Pubkey::default();
    let mut lamports = 1000u64;
    let mut data = vec![0xAA; 10];
    let owner = Pubkey::default();

    // Number of accounts
    buffer.push(1u8);

    // Serialize account following Solana's format
    serialize_account_solana_format(
        &mut buffer,
        &key,
        true, // is_signer
        true, // is_writable
        &mut lamports,
        &mut data,
        &owner,
        false, // executable
        true,  // is_non_dup
        0,     // dup_index (unused for non-dup)
    );

    let file_path = test_data_dir.join("solana_single_account.bin");
    let mut file = File::create(&file_path).expect("Failed to create file");
    file.write_all(&buffer).expect("Failed to write data");

    println!(
        "Generated: solana_single_account.bin ({} bytes)",
        buffer.len()
    );
}

fn generate_multiple_accounts_solana_format(test_data_dir: &Path) {
    let mut buffer = Vec::new();

    // Number of accounts
    buffer.push(3u8);

    // Account 1
    let key1 = Pubkey::default();
    let mut lamports1 = 1000u64;
    let mut data1 = vec![0xAA; 5];
    let owner1 = Pubkey::default();

    serialize_account_solana_format(
        &mut buffer,
        &key1,
        true, // is_signer
        true, // is_writable
        &mut lamports1,
        &mut data1,
        &owner1,
        false, // executable
        true,  // is_non_dup
        0,
    );

    // Account 2
    let mut key2_bytes = [0u8; 32];
    key2_bytes[0] = 1;
    let key2 = Pubkey::new_from_array(key2_bytes);
    let mut lamports2 = 2000u64;
    let mut data2 = vec![0xBB; 10];
    let owner2 = Pubkey::default();

    serialize_account_solana_format(
        &mut buffer,
        &key2,
        false, // is_signer
        true,  // is_writable
        &mut lamports2,
        &mut data2,
        &owner2,
        false, // executable
        true,  // is_non_dup
        0,
    );

    // Account 3
    let mut key3_bytes = [0u8; 32];
    key3_bytes[0] = 2;
    let key3 = Pubkey::new_from_array(key3_bytes);
    let mut lamports3 = 3000u64;
    let mut data3 = vec![0xCC; 15];
    let owner3 = Pubkey::default();

    serialize_account_solana_format(
        &mut buffer,
        &key3,
        false, // is_signer
        false, // is_writable
        &mut lamports3,
        &mut data3,
        &owner3,
        true, // executable
        true, // is_non_dup
        0,
    );

    let file_path = test_data_dir.join("solana_multiple_accounts.bin");
    let mut file = File::create(&file_path).expect("Failed to create file");
    file.write_all(&buffer).expect("Failed to write data");

    println!(
        "Generated: solana_multiple_accounts.bin ({} bytes)",
        buffer.len()
    );
}

fn generate_empty_data_accounts_solana_format(test_data_dir: &Path) {
    let mut buffer = Vec::new();

    // Number of accounts
    buffer.push(2u8);

    // Account 1: empty data
    let key1 = Pubkey::default();
    let mut lamports1 = 1000u64;
    let mut data1 = vec![]; // Empty data
    let owner1 = Pubkey::default();

    serialize_account_solana_format(
        &mut buffer,
        &key1,
        true,  // is_signer
        true,  // is_writable
        &mut lamports1,
        &mut data1,
        &owner1,
        false, // executable
        true,  // is_non_dup
        0,
    );

    // Account 2: with data
    let mut key2_bytes = [0u8; 32];
    key2_bytes[0] = 1;
    let key2 = Pubkey::new_from_array(key2_bytes);
    let mut lamports2 = 2000u64;
    let mut data2 = vec![0xFF; 4]; // Small data buffer
    let owner2 = Pubkey::default();

    serialize_account_solana_format(
        &mut buffer,
        &key2,
        false, // is_signer
        false, // is_writable
        &mut lamports2,
        &mut data2,
        &owner2,
        true, // executable
        true, // is_non_dup
        0,
    );

    let file_path = test_data_dir.join("empty_data_accounts.bin");
    let mut file = File::create(&file_path).expect("Failed to create file");
    file.write_all(&buffer).expect("Failed to write data");

    println!(
        "Generated: empty_data_accounts.bin ({} bytes)",
        buffer.len()
    );
}

fn generate_accounts_with_duplicates_solana_format(test_data_dir: &Path) {
    let mut buffer = Vec::new();

    // Number of accounts (including duplicates)
    buffer.push(5u8);

    // Store account data for duplicates
    let key1 = Pubkey::default();
    let mut lamports1 = 1000u64;
    let mut data1 = vec![0xAA; 8];
    let owner1 = Pubkey::default();

    // Account 0: Original
    serialize_account_solana_format(
        &mut buffer,
        &key1,
        true, // is_signer
        true, // is_writable
        &mut lamports1,
        &mut data1,
        &owner1,
        false, // executable
        true,  // is_non_dup
        0,
    );

    // Account 1: Original
    let mut key2_bytes = [0u8; 32];
    key2_bytes[0] = 1;
    let key2 = Pubkey::new_from_array(key2_bytes);
    let mut lamports2 = 2000u64;
    let mut data2 = vec![0xBB; 12];
    let owner2 = Pubkey::default();

    serialize_account_solana_format(
        &mut buffer,
        &key2,
        false, // is_signer
        true,  // is_writable
        &mut lamports2,
        &mut data2,
        &owner2,
        true, // executable
        true, // is_non_dup
        0,
    );

    // Account 2: Duplicate of account 0
    buffer.push(0x00); // Duplicate marker pointing to index 0

    // Account 3: Original
    let mut key3_bytes = [0u8; 32];
    key3_bytes[0] = 3;
    let key3 = Pubkey::new_from_array(key3_bytes);
    let mut lamports3 = 3000u64;
    let mut data3 = vec![0xCC; 6];
    let owner3 = Pubkey::default();

    serialize_account_solana_format(
        &mut buffer,
        &key3,
        true,  // is_signer
        false, // is_writable
        &mut lamports3,
        &mut data3,
        &owner3,
        false, // executable
        true,  // is_non_dup
        0,
    );

    // Account 4: Duplicate of account 1
    buffer.push(0x01); // Duplicate marker pointing to index 1

    let file_path = test_data_dir.join("solana_accounts_with_duplicates.bin");
    let mut file = File::create(&file_path).expect("Failed to create file");
    file.write_all(&buffer).expect("Failed to write data");

    println!(
        "Generated: solana_accounts_with_duplicates.bin ({} bytes)",
        buffer.len()
    );
}

fn generate_complex_iteration_solana_format(test_data_dir: &Path) {
    let mut buffer = Vec::new();

    // Number of accounts
    buffer.push(10u8);

    // Generate accounts with various patterns
    for i in 0..10u8 {
        if i == 4 {
            // Duplicate of account 1
            buffer.push(0x01);
        } else if i == 7 {
            // Duplicate of account 2
            buffer.push(0x02);
        } else {
            // Original account
            let mut key_bytes = [0u8; 32];
            key_bytes[0] = i;
            let key = Pubkey::new_from_array(key_bytes);
            let mut lamports = (i as u64 + 1) * 500;
            let data_len = ((i % 4) + 1) * 3;
            let mut data = vec![0xA0 + i; data_len as usize];
            let owner = Pubkey::default();

            serialize_account_solana_format(
                &mut buffer,
                &key,
                i % 2 == 0, // is_signer
                i % 3 != 0, // is_writable
                &mut lamports,
                &mut data,
                &owner,
                i % 5 == 0, // executable
                true,       // is_non_dup
                0,
            );
        }
    }

    let file_path = test_data_dir.join("solana_complex_iteration.bin");
    let mut file = File::create(&file_path).expect("Failed to create file");
    file.write_all(&buffer).expect("Failed to write data");

    println!(
        "Generated: solana_complex_iteration.bin ({} bytes)",
        buffer.len()
    );
}

/// Serialize account in the exact format used by Solana runtime
/// Based on solana/programs/bpf_loader/src/serialization.rs
fn serialize_account_solana_format(
    buffer: &mut Vec<u8>,
    key: &Pubkey,
    is_signer: bool,
    is_writable: bool,
    lamports: &mut u64,
    data: &mut Vec<u8>,
    owner: &Pubkey,
    executable: bool,
    is_non_dup: bool,
    dup_index: u8,
) {
    if is_non_dup {
        // Non-duplicate marker
        buffer.push(0xFF);

        // Serialize as packed struct matching what Solana runtime creates
        // This is the 88-byte structure we're targeting

        // duplicate_index (always 0xFF for non-dup)
        buffer.push(0xFF);

        // Flags
        buffer.push(is_signer as u8);
        buffer.push(is_writable as u8);
        buffer.push(executable as u8);

        // original_data_len (4 bytes, little-endian)
        let original_len = data.len() as u32;
        buffer.extend_from_slice(&original_len.to_le_bytes());

        // key (32 bytes)
        buffer.extend_from_slice(&key.to_bytes());

        // owner (32 bytes)
        buffer.extend_from_slice(&owner.to_bytes());

        // lamports (8 bytes, little-endian)
        buffer.extend_from_slice(&lamports.to_le_bytes());

        // data_len (8 bytes, little-endian)
        let data_len = data.len() as u64;
        buffer.extend_from_slice(&data_len.to_le_bytes());

        // Actual data bytes
        buffer.extend_from_slice(data);
    } else {
        // For duplicates, just the index
        buffer.push(dup_index);
    }
}

/// Create a test that mimics actual Solana runtime behavior
pub fn test_with_actual_account_info() {
    println!("\n=== Testing with actual AccountInfo structures ===");

    // Create AccountInfo instances like a real Solana program would
    let key1 = Pubkey::default();
    let key2 = Pubkey::new_unique();
    let owner = Pubkey::default();

    let mut lamports1 = 1000u64;
    let mut lamports2 = 2000u64;

    let mut data1 = vec![0xAA; 10];
    let mut data2 = vec![0xBB; 20];

    // AccountInfo requires mutable references to be wrapped in Rc<RefCell<>>
    let account1 = AccountInfo::new(
        &key1,
        true, // is_signer
        true, // is_writable
        &mut lamports1,
        &mut data1,
        &owner,
        false, // executable
        0,     // rent_epoch
    );

    let account2 = AccountInfo::new(
        &key2,
        false, // is_signer
        false, // is_writable
        &mut lamports2,
        &mut data2,
        &owner,
        true, // executable
        0,    // rent_epoch
    );

    // Print info about the accounts
    println!("Account1:");
    println!("  key: {:?}", account1.key);
    println!("  lamports: {}", account1.lamports.borrow());
    println!("  data_len: {}", account1.data_len());
    println!("  is_signer: {}", account1.is_signer);
    println!("  is_writable: {}", account1.is_writable);
    println!("  executable: {}", account1.executable);

    println!("\nAccount2:");
    println!("  key: {:?}", account2.key);
    println!("  lamports: {}", account2.lamports.borrow());
    println!("  data_len: {}", account2.data_len());
    println!("  is_signer: {}", account2.is_signer);
    println!("  is_writable: {}", account2.is_writable);
    println!("  executable: {}", account2.executable);

    // Create a buffer simulating what the runtime would pass to a program
    let mut runtime_buffer = Vec::new();

    // Number of accounts
    runtime_buffer.push(2u8);

    // Serialize first account
    serialize_account_info_as_runtime(&account1, &mut runtime_buffer, true);

    // Serialize second account
    serialize_account_info_as_runtime(&account2, &mut runtime_buffer, true);

    // Save to file
    let test_data_dir = Path::new("../test_data");
    let file_path = test_data_dir.join("solana_actual_accountinfo.bin");
    let mut file = File::create(&file_path).expect("Failed to create file");
    file.write_all(&runtime_buffer)
        .expect("Failed to write data");

    println!(
        "\nGenerated: solana_actual_accountinfo.bin ({} bytes)",
        runtime_buffer.len()
    );
}

/// Serialize an AccountInfo as the runtime would
fn serialize_account_info_as_runtime(
    account: &AccountInfo,
    buffer: &mut Vec<u8>,
    is_non_dup: bool,
) {
    if is_non_dup {
        // Non-duplicate marker
        buffer.push(0xFF);

        // duplicate_index
        buffer.push(0xFF);

        // Flags
        buffer.push(account.is_signer as u8);
        buffer.push(account.is_writable as u8);
        buffer.push(account.executable as u8);

        // original_data_len
        let data_len = account.data.borrow().len() as u32;
        buffer.extend_from_slice(&data_len.to_le_bytes());

        // key
        buffer.extend_from_slice(&account.key.to_bytes());

        // owner
        buffer.extend_from_slice(&account.owner.to_bytes());

        // lamports
        let lamports_val = **account.lamports.borrow();
        buffer.extend_from_slice(&lamports_val.to_le_bytes());

        // data_len
        let data_len_64 = account.data.borrow().len() as u64;
        buffer.extend_from_slice(&data_len_64.to_le_bytes());

        // Actual data
        buffer.extend_from_slice(&account.data.borrow());
    }
}
