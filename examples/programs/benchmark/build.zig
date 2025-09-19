const std = @import("std");

// Import the SDK's build configuration
const solana_sdk = @import("solana_sdk_zig");

pub fn build(b: *std.Build) !void {
    // Be sure to specify a solana target
    const target = b.resolveTargetQuery(solana_sdk.sbf_target);
    const optimize = .ReleaseFast;

    const program = b.addSharedLibrary(.{
        .name = "benchmark",
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

    // Optional: generate a keypair for the program
    const keypair_step = b.step("keypair", "Generate a keypair for the program");
    const keypair = generateProgramKeypair(b, program);
    keypair_step.dependOn(keypair);

    // Create a test step for unit tests (native target)
    const test_step = b.step("test", "Run unit tests");

    // Tests run on native target, not SBF
    const native_target = b.resolveTargetQuery(.{});
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = native_target,
        .optimize = .Debug,
    });

    // Add SDK module for tests (native build)
    const test_sdk_dep = b.dependency("solana_sdk_zig", .{
        .target = native_target,
        .optimize = .Debug,
    });
    lib_unit_tests.root_module.addImport("solana_sdk_zig", test_sdk_dep.module("solana_sdk_zig"));

    const run_unit_tests = b.addRunArtifact(lib_unit_tests);
    test_step.dependOn(&run_unit_tests.step);
}

/// Generate a keypair file for the program
fn generateProgramKeypair(b: *std.Build, program: *std.Build.Step.Compile) *std.Build.Step {
    const step = b.allocator.create(std.Build.Step) catch unreachable;
    step.* = std.Build.Step.init(.{
        .id = .custom,
        .name = "generate-keypair",
        .owner = b,
        .makeFn = makeKeypair,
    });

    // Store program info in step
    step.dependOn(&program.step);

    return step;
}

fn makeKeypair(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
    const b = step.owner;

    // Get the program name from dependencies
    const program_name = "benchmark";
    const keypair_path = try std.fmt.allocPrint(b.allocator, "{s}-keypair.json", .{program_name});
    defer b.allocator.free(keypair_path);

    // Check if keypair already exists
    std.fs.cwd().access(keypair_path, .{}) catch {
        // Generate new keypair using solana-keygen
        var cmd = std.ArrayList([]const u8).init(b.allocator);
        defer cmd.deinit();

        try cmd.append("solana-keygen");
        try cmd.append("new");
        try cmd.append("--no-bip39-passphrase");
        try cmd.append("-o");
        try cmd.append(keypair_path);
        try cmd.append("--force");

        var child = std.process.Child.init(cmd.items, b.allocator);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        _ = try child.spawnAndWait();

        std.debug.print("Generated keypair: {s}\n", .{keypair_path});

        // Also extract the public key
        var pubkey_cmd = std.ArrayList([]const u8).init(b.allocator);
        defer pubkey_cmd.deinit();

        try pubkey_cmd.append("solana-keygen");
        try pubkey_cmd.append("pubkey");
        try pubkey_cmd.append(keypair_path);

        var pubkey_child = std.process.Child.init(pubkey_cmd.items, b.allocator);
        pubkey_child.stdin_behavior = .Ignore;
        pubkey_child.stdout_behavior = .Pipe;
        pubkey_child.stderr_behavior = .Ignore;

        try pubkey_child.spawn();

        const stdout = try pubkey_child.stdout.?.reader().readAllAlloc(b.allocator, 1024);
        defer b.allocator.free(stdout);

        _ = try pubkey_child.wait();

        std.debug.print("Program ID: {s}", .{stdout});
        return;
    };

    std.debug.print("Keypair already exists: {s}\n", .{keypair_path});
}