/// A simple Solana program using the msg module
/// This program can be compiled for the Solana runtime
const std = @import("std");

// In a real Solana program, you would import from pinocchio
// const pinocchio = @import("pinocchio");
// const msg = pinocchio.msg;

// For this example, we'll use conditional compilation
const is_solana = @import("builtin").cpu.arch == .bpfel or @import("builtin").cpu.arch == .bpfeb;

// Mock implementations for non-Solana environments
const msg = struct {
    pub fn msg(message: []const u8) void {
        if (is_solana) {
            // On Solana, this would call sol_log_
            @panic("Not implemented for Solana target");
        } else {
            std.debug.print("{s}\n", .{message});
        }
    }

    pub fn msgf(comptime fmt: []const u8, args: anytype) void {
        if (is_solana) {
            @panic("Not implemented for Solana target");
        } else {
            std.debug.print(fmt ++ "\n", args);
        }
    }
};

/// Solana program entrypoint
/// This is the function that Solana runtime calls
pub export fn entrypoint(input: [*]u8) callconv(.C) u64 {
    msg.msg("=== Hello Solana Program ===");
    msg.msg("Program entrypoint called");

    // Parse the input data
    const result = processInstruction(input);

    if (result) {
        msg.msg("Instruction processed successfully");
        return 0; // SUCCESS
    } else |err| {
        msg.msgf("Error processing instruction: {s}", .{@errorName(err)});
        return 1; // ERROR
    }
}

/// Process the instruction
fn processInstruction(input: [*]u8) !void {
    _ = input; // In a real program, you would parse this

    msg.msg("Processing instruction...");

    // Example instruction types
    const InstructionType = enum(u8) {
        Initialize = 0,
        Transfer = 1,
        Close = 2,
    };

    // Mock instruction type (in reality, parse from input)
    const instruction_type = InstructionType.Initialize;

    switch (instruction_type) {
        .Initialize => {
            msg.msg("Initializing account...");
            try initializeAccount();
        },
        .Transfer => {
            msg.msg("Processing transfer...");
            try processTransfer();
        },
        .Close => {
            msg.msg("Closing account...");
            try closeAccount();
        },
    }
}

fn initializeAccount() !void {
    msg.msg("Account initialized successfully");
    // Account initialization logic here
}

fn processTransfer() !void {
    const amount: u64 = 1000;
    msg.msgf("Transferring {} lamports", .{amount});
    // Transfer logic here
}

fn closeAccount() !void {
    msg.msg("Account closed successfully");
    // Account closing logic here
}

/// Custom panic handler for Solana
pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    msg.msg("PANIC!");
    msg.msg(message);
    std.process.abort();
}

// For testing as a regular program
pub fn main() !void {
    msg.msg("Running Hello Solana example locally");
    msg.msg("This would be the entrypoint on Solana");

    // Simulate calling the entrypoint
    var mock_input: [256]u8 = undefined;
    const result = entrypoint(&mock_input);

    if (result == 0) {
        msg.msg("Program executed successfully");
    } else {
        msg.msgf("Program failed with error code: {}", .{result});
    }
}

test "hello solana program" {
    var mock_input: [256]u8 = undefined;
    const result = entrypoint(&mock_input);
    try std.testing.expectEqual(@as(u64, 0), result);
}