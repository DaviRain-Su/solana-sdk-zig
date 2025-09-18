const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build msg_example as a regular executable for testing
    const msg_example = b.addExecutable(.{
        .name = "msg_example",
        .root_source_file = b.path("msg_example.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add the base58 dependency
    const base58_dep = b.dependency("base58", .{
        .target = target,
        .optimize = optimize,
    });
    msg_example.root_module.addImport("base58", base58_dep.module("base58"));

    b.installArtifact(msg_example);

    // Create run command for msg_example
    const run_msg_example = b.addRunArtifact(msg_example);
    run_msg_example.step.dependOn(b.getInstallStep());

    // Add command line arguments if provided
    if (b.args) |args| {
        run_msg_example.addArgs(args);
    }

    const run_msg_step = b.step("run-msg", "Run the msg example");
    run_msg_step.dependOn(&run_msg_example.step);

    // Add tests for msg_example
    const msg_example_tests = b.addTest(.{
        .root_source_file = b.path("msg_example.zig"),
        .target = target,
        .optimize = optimize,
    });

    msg_example_tests.root_module.addImport("base58", base58_dep.module("base58"));

    const run_msg_tests = b.addRunArtifact(msg_example_tests);
    const test_msg_step = b.step("test-msg", "Run msg example tests");
    test_msg_step.dependOn(&run_msg_tests.step);

    // Create a step to run all examples
    const run_all_step = b.step("run", "Run all examples");
    run_all_step.dependOn(&run_msg_example.step);

    // Create a step to test all examples
    const test_all_step = b.step("test", "Test all examples");
    test_all_step.dependOn(&run_msg_tests.step);
}