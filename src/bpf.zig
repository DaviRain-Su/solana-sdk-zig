const std = @import("std");
const builtin = @import("builtin");
const Pubkey = @import("pubkey/pubkey.zig").Pubkey;

pub const bpf_loader_deprecated_program_id = Pubkey.parse("BPFLoader1111111111111111111111111111111111");
pub const bpf_loader_program_id = Pubkey.parse("BPFLoader2111111111111111111111111111111111");
pub const bpf_upgradeable_loader_program_id = Pubkey.parse("BPFLoaderUpgradeab1e11111111111111111111111");

pub const UpgradeableLoaderState = union(enum(u32)) {
    pub const ProgramData = struct {
        slot: u64,
        upgrade_authority_id: ?Pubkey,
    };

    uninitialized: void,
    buffer: struct {
        authority_id: ?Pubkey,
    },
    program: struct {
        program_data_id: Pubkey,
    },
    program_data: ProgramData,
};

pub fn getUpgradeableLoaderProgramDataId(program_id: Pubkey) !Pubkey {
    const seeds = [_][]const u8{&program_id.bytes};
    const pda = try Pubkey.findProgramAddress(&seeds, bpf_upgradeable_loader_program_id);
    return pda.address;
}

/// Check if we're running on Solana
/// This is the canonical way to detect Solana environment
pub const is_solana = blk: {
    // Not in test mode
    if (builtin.is_test) break :blk false;

    // Check for explicit Solana OS tag
    if (builtin.os.tag == .solana) break :blk true;

    // Check for SBF (Solana Binary Format)
    if (builtin.cpu.arch == .sbf) break :blk true;

    // Check for BPF with Solana features
    if (builtin.os.tag == .freestanding and
        builtin.cpu.arch == .bpfel and
        std.Target.bpf.featureSetHas(builtin.cpu.features, .solana))
    {
        break :blk true;
    }

    break :blk false;
};

/// Legacy alias for backward compatibility
pub const is_bpf_program = is_solana;

/// Check if we should print debug messages
pub const should_print_debug = blk: {
    // In non-test mode, always print (unless on Solana)
    if (!builtin.is_test and !is_solana) break :blk true;
    // In test mode or on Solana, don't print
    break :blk false;
};

/// Check if we're in test mode
pub const is_test = builtin.is_test;

/// Check if we're building for BPF (any variant)
pub const is_bpf = blk: {
    const arch = builtin.cpu.arch;
    break :blk arch == .bpfel or arch == .bpfeb or arch == .sbf;
};
