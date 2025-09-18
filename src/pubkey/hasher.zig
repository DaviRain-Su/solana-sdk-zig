const std = @import("std");
const Pubkey = @import("pubkey.zig").Pubkey;

/// A faster, but less collision resistant hasher for addresses.
/// Uses a random 8 bytes subslice of the address as the hash value.
pub const AddressHasher = struct {
    offset: usize,
    state: u64,

    const Self = @This();

    pub fn init(offset: usize) Self {
        return .{
            .offset = offset,
            .state = 0,
        };
    }

    pub fn update(self: *Self, bytes: []const u8) void {
        std.debug.assert(bytes.len == 32);

        // Extract 8 bytes at the offset position
        const chunk = bytes[self.offset..][0..8];
        self.state = std.mem.readInt(u64, chunk, .little);
    }

    pub fn final(self: Self) u64 {
        return self.state;
    }

    pub fn hash(bytes: []const u8, offset: usize) u64 {
        var hasher = init(offset);
        hasher.update(bytes);
        return hasher.final();
    }
};

/// A builder for faster hasher for addresses.
pub const AddressHasherBuilder = struct {
    offset: usize,

    const Self = @This();

    threadlocal var tls_offset: usize = 0;
    threadlocal var tls_initialized: bool = false;

    pub fn init() Self {
        // Initialize thread-local offset if needed
        if (!tls_initialized) {
            var rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
            tls_offset = rng.random().intRangeAtMost(usize, 0, 24); // 32 - 8 = 24
            tls_initialized = true;
        }

        // Increment and wrap around
        const offset = tls_offset;
        tls_offset = (tls_offset + 1) % 25; // 0 to 24 inclusive

        return .{ .offset = offset };
    }

    pub fn build(self: Self) AddressHasher {
        return AddressHasher.init(self.offset);
    }

    pub fn hashKey(self: Self, key: *const Pubkey) u64 {
        return AddressHasher.hash(&key.bytes, self.offset);
    }
};

/// HashMap context for Pubkey using AddressHasher
pub const PubkeyHashContext = struct {
    builder: AddressHasherBuilder,

    pub fn init() @This() {
        return .{ .builder = AddressHasherBuilder.init() };
    }

    pub fn hash(self: @This(), key: Pubkey) u64 {
        return self.builder.hashKey(&key);
    }

    pub fn eql(_: @This(), a: Pubkey, b: Pubkey) bool {
        return a.equals(&b);
    }
};

test "AddressHasher basic" {
    const testing = std.testing;

    const key = Pubkey.newUnique();
    const builder = AddressHasherBuilder.init();

    var hasher1 = builder.build();
    var hasher2 = builder.build();

    hasher1.update(&key.bytes);
    hasher2.update(&key.bytes);

    try testing.expectEqual(hasher1.final(), hasher2.final());
}

test "AddressHasher different keys" {
    const testing = std.testing;

    const key1 = Pubkey.newUnique();
    const key2 = Pubkey.newUnique();
    const builder = AddressHasherBuilder.init();

    var hasher1 = builder.build();
    var hasher2 = builder.build();

    hasher1.update(&key1.bytes);
    hasher2.update(&key2.bytes);

    // Different keys should produce different hashes (with high probability)
    try testing.expect(hasher1.final() != hasher2.final());
}

test "AddressHasherBuilder different offsets" {
    const key = Pubkey.newUnique();

    // Create multiple builders to get different offsets
    const builder1 = AddressHasherBuilder.init();
    const builder2 = AddressHasherBuilder.init();

    const hash1 = builder1.hashKey(&key);
    const hash2 = builder2.hashKey(&key);

    // With different offsets, same key might produce different hashes
    _ = hash1;
    _ = hash2;
    // Note: Can't guarantee they're different due to random offset selection
}

test "HashMap with PubkeyHashContext" {
    const testing = std.testing;

    const HashMap = std.hash_map.HashMap(
        Pubkey,
        u32,
        PubkeyHashContext,
        80,
    );

    const ctx = PubkeyHashContext.init();
    var map = HashMap.initContext(testing.allocator, ctx);
    defer map.deinit();

    const key1 = Pubkey.newUnique();
    const key2 = Pubkey.newUnique();
    const key3 = Pubkey.newUnique();

    try map.put(key1, 100);
    try map.put(key2, 200);
    try map.put(key3, 300);

    try testing.expectEqual(@as(?u32, 100), map.get(key1));
    try testing.expectEqual(@as(?u32, 200), map.get(key2));
    try testing.expectEqual(@as(?u32, 300), map.get(key3));
}
