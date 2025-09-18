const std = @import("std");
const msg = @import("msg.zig");
const testing = std.testing;

test "msg module basic functionality" {
    // Basic message
    msg.msg("Test message");

    // Formatted message
    msg.msgf("Test value: {}", .{42});
    msg.msgf("Test string: {s}", .{"hello"});

    // 64-bit values
    msg.msg64(1, 2, 3, 4, 5);

    // Compile-time message
    msg.msgComptime("Compile time message");

    try testing.expect(true);
}

test "msg module log levels" {
    msg.msgDebug("Debug message");
    msg.msgInfo("Info message");
    msg.msgWarn("Warning message");
    msg.msgErr("Error message");

    try testing.expect(true);
}

test "msg module data logging" {
    const data1 = [_]u8{ 0xAA, 0xBB };
    const data2 = [_]u8{ 0xCC, 0xDD, 0xEE };

    msg.msgData(&[_][]const u8{ &data1, &data2 });
    msg.msgHex("Test data", &data1);

    try testing.expect(true);
}

test "msg module assertions" {
    // This should not panic
    msg.msgAssert(true, "This should not panic");

    // Test error logging
    const err = error.TestError;
    msg.msgError("Test context", err);

    try testing.expect(true);
}

test "msg module entry/exit logging" {
    msg.msgEntry(@src());
    defer msg.msgExit(@src());

    msg.msg("Function body");

    try testing.expect(true);
}

test "msg module compute units" {
    msg.msgComputeUnitsLabeled("Test label");

    // Test measure function
    msg.measureComputeUnits("Test measure", testFunction);

    try testing.expect(true);
}

fn testFunction() void {
    var sum: u64 = 0;
    for (0..100) |i| {
        sum += i;
    }
    std.mem.doNotOptimizeAway(&sum);
}
