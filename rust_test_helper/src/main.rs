// Rust helper to generate serialized AccountInfo data for Zig tests
use solana_program::{account_info::AccountInfo, pubkey::Pubkey};

mod serialize_solana_format;

fn main() {
    // Generate test data files in Solana runtime format
    serialize_solana_format::generate_solana_format_test_data();
    serialize_solana_format::test_with_actual_account_info();

    // Also generate the other format for comparison

    println!("\n=== Original tests ===");
    // Create test account data
    let key1 = Pubkey::default(); // All zeros
    let key2 = Pubkey::new_unique();
    let owner = Pubkey::default();

    let mut lamports1: u64 = 1000;
    let mut lamports2: u64 = 500;

    let mut data1 = vec![1u8; 10];
    let mut data2 = vec![2u8; 20];

    // Create AccountInfo instances (8th parameter is rent_epoch)
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

    // Print the memory layout information
    println!("=== Rust AccountInfo Memory Layout ===");
    println!(
        "Size of AccountInfo: {} bytes",
        std::mem::size_of::<AccountInfo>()
    );
    println!(
        "Alignment of AccountInfo: {} bytes",
        std::mem::align_of::<AccountInfo>()
    );

    // Print field offsets using offset_of (if available) or manual calculation
    println!("\n=== Field Offsets ===");
    // AccountInfo struct layout in memory
    println!("Field offsets are compiler-dependent");
    println!("Expected layout based on Rust's AccountInfo:");
    println!("  key: *const Pubkey (8 bytes pointer)");
    println!("  lamports: Rc<RefCell<&mut u64>> (8 bytes)");
    println!("  data: Rc<RefCell<&mut [u8]>> (8 bytes)");
    println!("  owner: *const Pubkey (8 bytes pointer)");
    println!("  _unused: u64 (8 bytes, formerly rent_epoch)");
    println!("  is_signer: bool (1 byte)");
    println!("  is_writable: bool (1 byte)");
    println!("  executable: bool (1 byte)");
    println!("  padding: 5 bytes (for 8-byte alignment)");

    // Serialize account data to bytes for comparison
    println!("\n=== Serialized Account Data (hex) ===");

    // Serialize account1
    unsafe {
        let account_bytes = std::slice::from_raw_parts(
            &account1 as *const _ as *const u8,
            std::mem::size_of::<AccountInfo>(),
        );

        println!("Account1 serialized ({} bytes):", account_bytes.len());
        for (i, chunk) in account_bytes.chunks(16).enumerate() {
            print!("{:04x}: ", i * 16);
            for byte in chunk {
                print!("{:02x} ", byte);
            }
            println!();
        }
    }

    // Print actual field values for verification
    println!("\n=== Account1 Field Values ===");
    println!("key: {:?}", account1.key);
    println!("lamports: {}", account1.lamports());
    println!("data_len: {}", account1.data_len());
    println!("owner: {:?}", account1.owner);
    println!("is_signer: {}", account1.is_signer);
    println!("is_writable: {}", account1.is_writable);
    println!("executable: {}", account1.executable);

    // Create a buffer simulating entrypoint serialization
    println!("\n=== Simulated Entrypoint Serialization ===");
    let mut buffer = Vec::new();

    // Add accounts count
    buffer.push(2u8);

    // Serialize first account (non-duplicate)
    buffer.push(0xFF); // NON_DUP_MARKER
    serialize_account(&account1, &mut buffer);

    // Serialize second account (non-duplicate)
    buffer.push(0xFF); // NON_DUP_MARKER
    serialize_account(&account2, &mut buffer);

    // Add duplicate of first account
    buffer.push(0x00); // Duplicate marker
    buffer.push(0x00); // Index 0

    // Print the buffer
    println!("Total buffer size: {} bytes", buffer.len());
    for (i, chunk) in buffer.chunks(32).enumerate() {
        print!("{:04x}: ", i * 32);
        for byte in chunk {
            print!("{:02x} ", byte);
        }
        println!();
    }
}

fn serialize_account(account: &AccountInfo, buffer: &mut Vec<u8>) {
    // This is a simplified serialization - actual format may differ
    // Serialize key
    buffer.extend_from_slice(&account.key.to_bytes());

    // Serialize lamports pointer (8 bytes)
    let lamports_ptr = account.lamports.as_ptr() as usize;
    buffer.extend_from_slice(&lamports_ptr.to_le_bytes());

    // Serialize data pointer and length
    let data_ref = account.data.borrow();
    let data_ptr = data_ref.as_ptr() as usize;
    buffer.extend_from_slice(&data_ptr.to_le_bytes());
    buffer.extend_from_slice(&(data_ref.len() as u64).to_le_bytes());

    // Serialize owner
    buffer.extend_from_slice(&account.owner.to_bytes());

    // Serialize flags
    buffer.push(account.is_signer as u8);
    buffer.push(account.is_writable as u8);
    buffer.push(account.executable as u8);
}
