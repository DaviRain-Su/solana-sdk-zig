const std = @import("std");

// Import the SDK's build configuration
const solana_sdk = @import("solana_sdk_zig");

pub fn build(b: *std.Build) !void {
    // Be sure to specify a solana target
    const target = b.resolveTargetQuery(solana_sdk.sbf_target);
    const optimize = .ReleaseFast;

    const program = b.addSharedLibrary(.{
        .name = "lazy_example",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Adding required dependencies, link the program properly, and get a
    // prepared solana-program module
    const solana_mod = solana_sdk.buildProgram(b, program, target, optimize);

    // Add the import to the program
    program.root_module.addImport("solana_sdk_zig", solana_mod);

    // Install the program artifact
    b.installArtifact(program);
}