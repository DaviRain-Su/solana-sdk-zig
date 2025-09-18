/// Print messages to the Solana program log
///
/// This module provides logging functionality for Solana programs,
/// equivalent to Rust's solana_msg crate
const std = @import("std");
const syscalls = @import("../syscalls.zig");
const base58 = @import("base58");
const BASE58_ENDEC = base58.Table.BITCOIN;

/// Print a message to the log (alias for msg, compatible with log.zig)
pub inline fn log(message: []const u8) void {
    msg(message);
}

/// Print a message to the log
///
/// This is the basic logging function that writes directly to the program log.
/// For formatted messages, use `msgf` instead.
///
/// # Examples
/// ```zig
/// msg("verifying multisig");
/// msg("transaction complete");
/// ```
pub inline fn msg(message: []const u8) void {
    if (isSolana()) {
        syscalls.sol_log_(message.ptr, message.len);
    } else if (shouldPrintDebug()) {
        // In non-Solana environments, print to stderr for debugging (not in tests)
        // Only compile this for non-Solana targets
        if (@import("builtin").os.tag != .solana) {
            std.debug.print("{s}\n", .{message});
        }
    }
}

/// Print a formatted message to the log (alias for msgf, compatible with log.zig)
///
/// This function provides printf-style formatting for log messages.
/// Note that formatting is relatively CPU-intensive for the Solana VM,
/// so use the simple `msg` function when formatting is not needed.
///
/// # Examples
/// ```zig
/// print("multisig failed: {s}", .{err});
/// print("transfer amount: {} lamports", .{amount});
/// ```
pub fn print(comptime fmt: []const u8, args: anytype) void {
    msgf(fmt, args);
}

/// Print a formatted message to the log
///
/// This function provides printf-style formatting for log messages.
/// Note that formatting is relatively CPU-intensive for the Solana VM,
/// so use the simple `msg` function when formatting is not needed.
///
/// # Examples
/// ```zig
/// msgf("multisig failed: {s}", .{err});
/// msgf("transfer amount: {} lamports", .{amount});
/// msgf("account {} balance: {}", .{account_index, balance});
/// ```
pub fn msgf(comptime fmt: []const u8, args: anytype) void {
    // Stack buffer for formatted message - keep small for Solana's limited stack
    var buf: [256]u8 = undefined;

    const formatted = std.fmt.bufPrint(&buf, fmt, args) catch {
        // If formatting fails, log an error message instead
        msg("msg format error");
        return;
    };

    msg(formatted);
}

/// Print multiple values as u64 integers
///
/// This is more efficient than formatting for simple numeric logging.
/// Logs up to 5 u64 values in a single syscall.
///
/// # Examples
/// ```zig
/// msg64(123, 456, 789, 0, 0);
/// msg64(@intFromPtr(ptr), size, offset, 0, 0);
/// ```
pub inline fn msg64(p0: u64, p1: u64, p2: u64, p3: u64, p4: u64) void {
    if (isSolana()) {
        syscalls.sol_log_64_(p0, p1, p2, p3, p4);
    } else if (shouldPrintDebug()) {
        if (@import("builtin").os.tag != .solana) {
            std.debug.print("u64 values: {} {} {} {} {}\n", .{ p0, p1, p2, p3, p4 });
        }
    }
}

/// Print a public key to the log
///
/// # Examples
/// ```zig
/// const pubkey = @import("../pubkey/pubkey.zig");
/// const key = pubkey.Pubkey.fromBytes([_]u8{1} ** 32);
/// msgPubkey(&key);
/// ```
pub inline fn msgPubkey(key: anytype) void {
    const key_ptr = switch (@TypeOf(key)) {
        *const [32]u8 => key,
        *[32]u8 => @as(*const [32]u8, key),
        [32]u8 => &key,
        else => blk: {
            // Handle Pubkey struct type
            const T = @TypeOf(key);
            const info = @typeInfo(T);
            if (info == .pointer) {
                // It's a pointer to a struct, try to access bytes field
                if (@hasField(std.meta.Child(T), "bytes")) {
                    break :blk &key.bytes;
                } else {
                    break :blk @as(*const [32]u8, @ptrCast(key));
                }
            } else if (info == .@"struct") {
                if (@hasField(T, "bytes")) {
                    break :blk &key.bytes;
                } else {
                    @compileError("msgPubkey expects a struct with bytes field");
                }
            } else {
                @compileError("msgPubkey expects a 32-byte array or Pubkey struct with bytes field");
            }
        },
    };

    if (isSolana()) {
        syscalls.sol_log_pubkey(@ptrCast(key_ptr));
    } else if (shouldPrintDebug()) {
        if (@import("builtin").os.tag != .solana) {
            var buf: [64]u8 = undefined;
            const encoded = base58Encode(key_ptr.*, &buf) catch "encoding error";
            std.debug.print("Pubkey: {s}\n", .{encoded});
        }
    }
}

/// Print the current compute units consumed (alias, compatible with log.zig)
pub inline fn logComputeUnits() void {
    msgComputeUnits();
}

/// Print the current compute units consumed
///
/// Useful for performance debugging and optimization.
///
/// # Examples
/// ```zig
/// msgComputeUnits();
/// // ... some operation ...
/// msgComputeUnits(); // See how many CUs were used
/// ```
pub inline fn msgComputeUnits() void {
    if (isSolana()) {
        syscalls.sol_log_compute_units_();
    } else if (shouldPrintDebug()) {
        if (@import("builtin").os.tag != .solana) {
            std.debug.print("Compute units logging not available outside Solana\n", .{});
        }
    }
}

/// Log multiple data slices (alias, compatible with log.zig)
pub fn logData(data_slices: []const []const u8) void {
    msgData(data_slices);
}

/// Log multiple data slices
///
/// Can log up to 16 data slices in a single syscall.
/// Each slice is printed as hex bytes.
///
/// # Examples
/// ```zig
/// const data1 = [_]u8{1, 2, 3};
/// const data2 = [_]u8{4, 5, 6};
/// msgData(&[_][]const u8{ &data1, &data2 });
/// ```
pub fn msgData(data_slices: []const []const u8) void {
    if (isSolana()) {
        const max_slices = 16;
        var data_ptrs: [max_slices][*]const u8 = undefined;
        const len = @min(data_slices.len, max_slices);

        for (data_slices[0..len], 0..) |slice, i| {
            data_ptrs[i] = slice.ptr;
        }

        syscalls.sol_log_data(@ptrCast(&data_ptrs), len);
    } else if (shouldPrintDebug()) {
        if (@import("builtin").os.tag != .solana) {
            std.debug.print("Data slices ({} items):\n", .{data_slices.len});
            for (data_slices, 0..) |slice, i| {
                std.debug.print("  [{}]: ", .{i});
                for (slice) |byte| {
                    std.debug.print("{x:0>2} ", .{byte});
                }
                std.debug.print("\n", .{});
            }
        }
    }
}

/// Log a slice of bytes as hexadecimal
///
/// Convenience function for logging raw data.
///
/// # Examples
/// ```zig
/// const data = [_]u8{0xAA, 0xBB, 0xCC};
/// msgHex("signature", &data);
/// ```
pub fn msgHex(label: []const u8, data: []const u8) void {
    msg(label);
    msgData(&[_][]const u8{data});
}

/// Panic with a message
///
/// Logs the message and then panics, terminating the program.
///
/// # Examples
/// ```zig
/// if (balance < amount) {
///     msgPanic("insufficient balance");
/// }
/// ```
pub fn msgPanic(message: []const u8) noreturn {
    msg(message);
    @panic(message);
}

/// Assert a condition with a message
///
/// If the condition is false, logs the message and panics.
///
/// # Examples
/// ```zig
/// msgAssert(account.is_signer, "account must be signer");
/// msgAssert(amount > 0, "amount must be positive");
/// ```
pub inline fn msgAssert(condition: bool, message: []const u8) void {
    if (!condition) {
        msgPanic(message);
    }
}

/// Log an error with context
///
/// # Examples
/// ```zig
/// msgError("transfer failed", error.InsufficientFunds);
/// ```
pub fn msgError(context: []const u8, err: anyerror) void {
    msgf("{s}: {s}", .{ context, @errorName(err) });
}

/// Check if we're running on Solana
inline fn isSolana() bool {
    const arch = @import("builtin").target.cpu.arch;
    // Check for BPF/SBF architectures
    return switch (arch) {
        .bpfel, .bpfeb => true,
        else => false,
    };
}

/// Check if we should print debug messages
inline fn shouldPrintDebug() bool {
    const builtin = @import("builtin");
    // In non-test mode, always print
    if (!builtin.is_test) return true;

    // In test mode, don't print by default
    // This avoids the build_options dependency issue
    return false;
}

/// Base58 encoding for debug environments
fn base58Encode(data: [32]u8, buf: []u8) ![]const u8 {
    // Use the actual base58 library for proper encoding
    // Base58 encoding of 32 bytes produces at most 44 characters
    if (buf.len < 44) return error.BufferTooSmall;

    // Encode using the base58 library
    const encoded_len = BASE58_ENDEC.encode(buf, &data);
    return buf[0..encoded_len];
}

// ============================================================================
// Compile-time logging helpers
// ============================================================================

/// Compile-time message validation
///
/// Ensures message is a compile-time constant when possible for optimization.
pub inline fn msgComptime(comptime message: []const u8) void {
    msg(message);
}

/// Log function entry (for debugging)
///
/// # Examples
/// ```zig
/// pub fn transfer() void {
///     msgEntry(@src());
///     // ... function body
/// }
/// ```
pub fn msgEntry(src: std.builtin.SourceLocation) void {
    msgf("-> {s}:{}", .{ src.fn_name, src.line });
}

/// Log function exit (for debugging)
pub fn msgExit(src: std.builtin.SourceLocation) void {
    msgf("<- {s}:{}", .{ src.fn_name, src.line });
}

// ============================================================================
// Structured logging helpers
// ============================================================================

/// Log level for structured logging
pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
        };
    }
};

/// Structured log with level
pub fn msgLog(level: LogLevel, message: []const u8) void {
    msgf("[{s}] {s}", .{ level.toString(), message });
}

/// Debug log (only in debug builds)
pub inline fn msgDebug(message: []const u8) void {
    if (std.debug.runtime_safety) {
        msgLog(.debug, message);
    }
}

/// Info log
pub inline fn msgInfo(message: []const u8) void {
    msgLog(.info, message);
}

/// Warning log
pub inline fn msgWarn(message: []const u8) void {
    msgLog(.warn, message);
}

/// Error log
pub inline fn msgErr(message: []const u8) void {
    msgLog(.err, message);
}

// ============================================================================
// Performance monitoring helpers
// ============================================================================

/// Log compute units with a label
pub fn msgComputeUnitsLabeled(label: []const u8) void {
    msg(label);
    msgComputeUnits();
}

/// Measure compute units for a block
pub fn measureComputeUnits(label: []const u8, func: fn () void) void {
    msg(label);
    msg("start");
    msgComputeUnits();
    func();
    msg("end");
    msgComputeUnits();
}

// ============================================================================
// Tests
// ============================================================================

test "msg basic functionality" {
    // These tests will only do basic compilation checks
    // since we can't test syscalls outside of Solana
    const testing = std.testing;

    // Basic message
    msg("test message");

    // Formatted message
    msgf("test {s}: {}", .{ "value", 42 });

    // 64-bit values
    msg64(1, 2, 3, 4, 5);

    // Compile-time message
    msgComptime("compile time message");

    // Log levels
    msgDebug("debug message");
    msgInfo("info message");
    msgWarn("warning message");
    msgErr("error message");

    try testing.expect(true);
}

test "msg data logging" {
    const data1 = [_]u8{ 0xAA, 0xBB };
    const data2 = [_]u8{ 0xCC, 0xDD, 0xEE };

    msgData(&[_][]const u8{ &data1, &data2 });
    msgHex("test data", &data1);
}

test "msg assertions" {
    msgAssert(true, "this should not panic");

    // Test error logging
    const err = error.TestError;
    msgError("test context", err);
}

// Include Rust compatibility tests
test {
    _ = @import("base58_test.zig");
}
