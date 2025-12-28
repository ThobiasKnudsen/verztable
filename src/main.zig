//! verztable Usage Examples
//!
//! This file demonstrates the various ways to use verztable,
//! a high-performance hash table ported from Verstable.

const std = @import("std");
const HashMap = @import("root.zig").HashMap;
const HashMapWithFns = @import("root.zig").HashMapWithFns;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== HashMap Examples ===\n\n", .{});

    // =========================================================================
    // Example 1: Basic Map (key -> value)
    // =========================================================================
    std.debug.print("1. Basic Map Usage:\n", .{});
    {
        var map = HashMap(u32, []const u8).init(allocator);
        defer map.deinit();

        // Insert key-value pairs
        try map.put(1, "one");
        try map.put(2, "two");
        try map.put(3, "three");

        // Lookup
        if (map.get(2)) |val| {
            std.debug.print("   map.get(2) = {s}\n", .{val});
        }

        // Update
        try map.put(2, "TWO");
        std.debug.print("   After update: map.get(2) = {s}\n", .{map.get(2).?});

        // Remove
        _ = map.remove(1);
        std.debug.print("   After remove(1): count = {d}\n", .{map.count()});
    }

    // =========================================================================
    // Example 2: Set (just keys, V = void)
    // =========================================================================
    std.debug.print("\n2. Set Usage (V = void):\n", .{});
    {
        var set = HashMap([]const u8, void).init(allocator);
        defer set.deinit();

        // Add elements
        try set.add("apple");
        try set.add("banana");
        try set.add("cherry");

        // Check membership
        std.debug.print("   contains 'banana': {}\n", .{set.contains("banana")});
        std.debug.print("   contains 'grape': {}\n", .{set.contains("grape")});

        // Remove
        _ = set.remove("banana");
        std.debug.print("   After remove: contains 'banana': {}\n", .{set.contains("banana")});
    }

    // =========================================================================
    // Example 3: getOrPut for Accumulation Patterns
    // =========================================================================
    std.debug.print("\n3. Word Frequency Counter (getOrPut):\n", .{});
    {
        var freq = HashMap([]const u8, u32).init(allocator);
        defer freq.deinit();

        const words = [_][]const u8{ "the", "quick", "brown", "fox", "the", "lazy", "dog", "the" };

        for (words) |word| {
            const result = try freq.getOrPut(word);
            if (!result.found_existing) {
                result.value_ptr.* = 0;
            }
            result.value_ptr.* += 1;
        }

        std.debug.print("   'the' appears {d} times\n", .{freq.get("the").?});
        std.debug.print("   'fox' appears {d} times\n", .{freq.get("fox").?});
    }

    // =========================================================================
    // Example 4: Iteration
    // =========================================================================
    std.debug.print("\n4. Iteration:\n", .{});
    {
        var map = HashMap(u32, u32).init(allocator);
        defer map.deinit();

        try map.put(10, 100);
        try map.put(20, 200);
        try map.put(30, 300);

        // Iterate over buckets
        std.debug.print("   All entries: ", .{});
        var iter = map.iterator();
        while (iter.next()) |bucket| {
            std.debug.print("{d}:{d} ", .{ bucket.key, bucket.val });
        }
        std.debug.print("\n", .{});

        // Key iterator
        std.debug.print("   Keys: ", .{});
        var key_iter = map.keyIterator();
        while (key_iter.next()) |key| {
            std.debug.print("{d} ", .{key});
        }
        std.debug.print("\n", .{});

        // Value iterator
        std.debug.print("   Values: ", .{});
        var val_iter = map.valueIterator();
        while (val_iter.next()) |val| {
            std.debug.print("{d} ", .{val});
        }
        std.debug.print("\n", .{});
    }

    // =========================================================================
    // Example 5: Configuration
    // =========================================================================
    std.debug.print("\n5. Configuration:\n", .{});
    {
        var map = HashMap(u32, u32).init(allocator);
        defer map.deinit();

        // Adjust load factor (higher = more memory efficient, lower = faster)
        map.setMaxLoadFactor(0.75);

        // Pre-allocate for expected size
        try map.reserve(1000);
        std.debug.print("   After reserve(1000): capacity = {d}\n", .{map.capacity()});

        for (0..500) |i| {
            try map.put(@intCast(i), @intCast(i * 2));
        }

        // Shrink to fit
        try map.shrink();
        std.debug.print("   After shrink: bucket_count = {d}\n", .{map.bucketCount()});
    }

    // =========================================================================
    // Example 6: Custom Hash Function
    // =========================================================================
    std.debug.print("\n6. Custom Hash Function:\n", .{});
    {
        // Case-insensitive string map
        const CaseInsensitiveHash = struct {
            fn hash(s: []const u8) u64 {
                var h: u64 = 0;
                for (s) |c| {
                    const lower = if (c >= 'A' and c <= 'Z') c + 32 else c;
                    h = h *% 31 +% lower;
                }
                return h;
            }
        };
        const CaseInsensitiveEql = struct {
            fn eql(a: []const u8, b: []const u8) bool {
                if (a.len != b.len) return false;
                for (a, b) |ca, cb| {
                    const la = if (ca >= 'A' and ca <= 'Z') ca + 32 else ca;
                    const lb = if (cb >= 'A' and cb <= 'Z') cb + 32 else cb;
                    if (la != lb) return false;
                }
                return true;
            }
        };

        var map = HashMapWithFns(
            []const u8,
            i32,
            CaseInsensitiveHash.hash,
            CaseInsensitiveEql.eql,
        ).init(allocator);
        defer map.deinit();

        try map.put("Hello", 1);
        std.debug.print("   get('HELLO') = {d}\n", .{map.get("HELLO").?});
        std.debug.print("   get('hello') = {d}\n", .{map.get("hello").?});
    }

    // =========================================================================
    // Example 7: Clone
    // =========================================================================
    std.debug.print("\n7. Clone:\n", .{});
    {
        var map1 = HashMap(u32, u32).init(allocator);
        defer map1.deinit();

        try map1.put(1, 100);
        try map1.put(2, 200);

        var map2 = try map1.clone();
        defer map2.deinit();

        // Modify original
        try map1.put(1, 999);

        std.debug.print("   Original map1.get(1) = {d}\n", .{map1.get(1).?});
        std.debug.print("   Clone map2.get(1) = {d} (unchanged)\n", .{map2.get(1).?});
    }

    std.debug.print("\n=== All examples completed! ===\n\n", .{});
}

test "main runs without error" {
    try main();
}
