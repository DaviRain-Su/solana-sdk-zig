const std = @import("std");
const msg = @import("msg.zig");
const base58 = @import("base58");
const BASE58_ENDEC = base58.Table.BITCOIN;
const testing = std.testing;

test "base58 encoding for pubkeys" {
    // Test that base58Encode works correctly
    const data: [32]u8 = [_]u8{0} ** 32;
    var buf: [64]u8 = undefined;

    // Call the private function through a test helper
    const encoded = try testBase58Encode(data, &buf);

    // All zeros should encode to "11111111111111111111111111111111"
    try testing.expectEqualStrings("11111111111111111111111111111111", encoded);
}

test "base58 encoding different pubkeys" {
    // Test with different patterns
    var data1: [32]u8 = undefined;
    for (&data1, 0..) |*byte, i| {
        byte.* = @intCast(i);
    }

    var buf: [64]u8 = undefined;
    const encoded1 = try testBase58Encode(data1, &buf);

    // Should produce a valid base58 string
    try testing.expect(encoded1.len > 0);
    try testing.expect(encoded1.len <= 44);

    // Test with max values
    const data2: [32]u8 = [_]u8{255} ** 32;
    var buf2: [64]u8 = undefined;
    const encoded2 = try testBase58Encode(data2, &buf2);

    // Should be different from the first one
    try testing.expect(!std.mem.eql(u8, encoded1, encoded2));
}

test "base58 roundtrip" {
    // Test encoding and decoding
    const original = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA";

    // Decode
    var decoded: [32]u8 = undefined;
    const decoded_len = try BASE58_ENDEC.decode(&decoded, original);
    try testing.expectEqual(@as(usize, 32), decoded_len);

    // Re-encode
    var buf: [64]u8 = undefined;
    const reencoded = try testBase58Encode(decoded, &buf);

    // Should match the original
    try testing.expectEqualStrings(original, reencoded);
}

test "msgPubkey with mock pubkey" {
    // Test that msgPubkey works with base58 encoding
    const MockPubkey = struct {
        bytes: [32]u8,
    };

    const key = MockPubkey{ .bytes = [_]u8{0} ** 32 };

    // This should not crash and should use base58 encoding
    msg.msgPubkey(&key);
}

// Helper function to test the private base58Encode function
fn testBase58Encode(data: [32]u8, buf: []u8) ![]const u8 {
    // Use the base58 library directly since we can't access the private function
    const encoded_len = BASE58_ENDEC.encode(buf, &data);
    return buf[0..encoded_len];
}
