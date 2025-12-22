//! TheHashTable Benchmark Suite
//!
//! Comprehensive performance tests for comparing with other hash table implementations.
//! Run with: zig build bench
//!
//! Benchmarks:
//! - TheHashTable (this library)
//! - Verstable (C): https://github.com/JacksonAllan/Verstable
//! - std.HashMap (Zig standard library)

const std = @import("std");
const TheHashTable = @import("root.zig").TheHashTable;
const Timer = std.time.Timer;

// Verstable C bindings
const vt = @cImport({
    @cInclude("verstable_wrapper.h");
});

const WARMUP_ITERATIONS = 3;
const BENCHMARK_ITERATIONS = 5;

// Test sizes
const SIZE_100: usize = 100;
const SIZE_1K: usize = 1_000;
const SIZE_10K: usize = 10_000;
const SIZE_100K: usize = 100_000;
const SIZE_1M: usize = 1_000_000;
const SIZE_10M: usize = 10_000_000;

fn printTime(ns: u64) void {
    if (ns < 1000) {
        std.debug.print("{d:>8} ns", .{ns});
    } else if (ns < 1_000_000) {
        std.debug.print("{d:>8.2} us", .{@as(f64, @floatFromInt(ns)) / 1000.0});
    } else if (ns < 1_000_000_000) {
        std.debug.print("{d:>8.2} ms", .{@as(f64, @floatFromInt(ns)) / 1_000_000.0});
    } else {
        std.debug.print("{d:>8.2} s ", .{@as(f64, @floatFromInt(ns)) / 1_000_000_000.0});
    }
}

fn printOpsPerSec(ops: usize, ns: u64) void {
    const ops_per_sec = @as(f64, @floatFromInt(ops)) / (@as(f64, @floatFromInt(ns)) / 1_000_000_000.0);
    if (ops_per_sec >= 1_000_000_000) {
        std.debug.print("{d:>8.2} G/s", .{ops_per_sec / 1_000_000_000.0});
    } else if (ops_per_sec >= 1_000_000) {
        std.debug.print("{d:>8.2} M/s", .{ops_per_sec / 1_000_000.0});
    } else if (ops_per_sec >= 1_000) {
        std.debug.print("{d:>8.2} K/s", .{ops_per_sec / 1_000.0});
    } else {
        std.debug.print("{d:>8.2}  /s", .{ops_per_sec});
    }
}

// PRNG for reproducible random numbers
const Xoshiro = std.Random.Xoshiro256;

fn makeRng(seed: u64) Xoshiro {
    return Xoshiro.init(seed);
}

// ============================================================================
// Benchmark: Sequential Insertions
// ============================================================================

fn benchSequentialInsert(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var map = TheHashTable(u64, u64).init(allocator);
        defer map.deinit();

        var timer = try Timer.start();

        for (0..size) |i| {
            try map.put(i, i);
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

// ============================================================================
// Benchmark: Random Insertions
// ============================================================================

fn benchRandomInsert(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    // Pre-generate random keys (heap allocated for large sizes)
    const keys = try allocator.alloc(u64, size);
    defer allocator.free(keys);

    var rng = makeRng(12345);
    for (keys) |*k| {
        k.* = rng.random().int(u64);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var map = TheHashTable(u64, u64).init(allocator);
        defer map.deinit();

        var timer = try Timer.start();

        for (keys) |k| {
            try map.put(k, k);
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

// ============================================================================
// Benchmark: Sequential Lookups (all hits)
// ============================================================================

fn benchSequentialLookupHit(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    var map = TheHashTable(u64, u64).init(allocator);
    defer map.deinit();

    for (0..size) |i| {
        try map.put(i, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var sum: u64 = 0;

        for (0..size) |i| {
            sum +%= map.get(i) orelse 0;
        }

        total_ns += timer.read();

        // Prevent optimization
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

// ============================================================================
// Benchmark: Random Lookups (all hits)
// ============================================================================

fn benchRandomLookupHit(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    // Heap allocate for large sizes
    const keys = try allocator.alloc(u64, size);
    defer allocator.free(keys);

    var rng = makeRng(12345);
    for (keys) |*k| {
        k.* = rng.random().int(u64);
    }

    var map = TheHashTable(u64, u64).init(allocator);
    defer map.deinit();

    for (keys) |k| {
        try map.put(k, k);
    }

    // Shuffle lookup order (heap allocated)
    const lookup_order = try allocator.alloc(usize, size);
    defer allocator.free(lookup_order);

    var lookup_rng = makeRng(67890);
    for (0..size) |i| {
        lookup_order[i] = i;
    }
    lookup_rng.random().shuffle(usize, lookup_order);

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var sum: u64 = 0;

        for (lookup_order) |idx| {
            sum +%= map.get(keys[idx]) orelse 0;
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

// ============================================================================
// Benchmark: Lookups (all misses)
// ============================================================================

fn benchLookupMiss(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    var map = TheHashTable(u64, u64).init(allocator);
    defer map.deinit();

    // Insert even numbers
    for (0..size) |i| {
        try map.put(i * 2, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var miss_count: u64 = 0;

        // Look up odd numbers (guaranteed misses)
        for (0..size) |i| {
            if (map.get(i * 2 + 1) == null) {
                miss_count += 1;
            }
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(miss_count);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

// ============================================================================
// Benchmark: Mixed Lookups (50% hit rate)
// ============================================================================

fn benchLookupMixed(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    var map = TheHashTable(u64, u64).init(allocator);
    defer map.deinit();

    // Insert even numbers only
    for (0..size) |i| {
        try map.put(i * 2, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var sum: u64 = 0;

        // Look up all numbers (50% hit rate)
        for (0..size * 2) |i| {
            sum +%= map.get(i) orelse 0;
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

// ============================================================================
// Benchmark: Deletions
// ============================================================================

fn benchDelete(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var map = TheHashTable(u64, u64).init(allocator);
        defer map.deinit();

        // First insert all
        for (0..size) |i| {
            try map.put(i, i);
        }

        var timer = try Timer.start();

        // Delete all
        for (0..size) |i| {
            _ = map.remove(i);
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

// ============================================================================
// Benchmark: Iteration
// ============================================================================

fn benchIteration(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    var map = TheHashTable(u64, u64).init(allocator);
    defer map.deinit();

    for (0..size) |i| {
        try map.put(i, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var sum: u64 = 0;

        var iter = map.iterator();
        while (iter.next()) |bucket| {
            sum +%= bucket.val;
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

// ============================================================================
// Benchmark: Insert + Delete Churn
// ============================================================================

fn benchChurn(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    var map = TheHashTable(u64, u64).init(allocator);
    defer map.deinit();

    // Pre-fill to half capacity
    for (0..size / 2) |i| {
        try map.put(i, i);
    }

    var total_ns: u64 = 0;
    var rng = makeRng(11111);

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();

        // Do size operations: alternating insert/delete
        for (0..size) |_| {
            const key = rng.random().int(u64) % (size * 2);
            if (rng.random().boolean()) {
                try map.put(key, key);
            } else {
                _ = map.remove(key);
            }
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

// ============================================================================
// Benchmark: String Keys
// ============================================================================

fn benchStringKeys(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    // Generate string keys - use a fixed-width format for simplicity
    var key_storage = try allocator.alloc([16]u8, size);
    defer allocator.free(key_storage);

    var keys = try allocator.alloc([]const u8, size);
    defer allocator.free(keys);

    for (0..size) |i| {
        const slice = std.fmt.bufPrint(&key_storage[i], "{d:0>10}", .{i}) catch unreachable;
        keys[i] = slice;
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var map = TheHashTable([]const u8, u64).init(allocator);
        defer map.deinit();

        var timer = try Timer.start();

        // Insert
        for (keys, 0..) |k, i| {
            try map.put(k, i);
        }

        // Lookup
        var sum: u64 = 0;
        for (keys) |k| {
            sum +%= map.get(k) orelse 0;
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

// ============================================================================
// Benchmark: std.HashMap Comparison
// ============================================================================

fn benchStdHashMapInsert(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var map = std.AutoHashMap(u64, u64).init(allocator);
        defer map.deinit();

        var timer = try Timer.start();

        for (0..size) |i| {
            try map.put(i, i);
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchStdHashMapLookup(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    var map = std.AutoHashMap(u64, u64).init(allocator);
    defer map.deinit();

    for (0..size) |i| {
        try map.put(i, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var sum: u64 = 0;

        for (0..size) |i| {
            sum +%= map.get(i) orelse 0;
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchStdHashMapRandomInsert(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    // Pre-generate random keys (heap allocated for large sizes)
    const keys = try allocator.alloc(u64, size);
    defer allocator.free(keys);

    var rng = makeRng(12345);
    for (keys) |*k| {
        k.* = rng.random().int(u64);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var map = std.AutoHashMap(u64, u64).init(allocator);
        defer map.deinit();

        var timer = try Timer.start();

        for (keys) |k| {
            try map.put(k, k);
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchStdHashMapRandomLookup(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    // Heap allocate for large sizes
    const keys = try allocator.alloc(u64, size);
    defer allocator.free(keys);

    var rng = makeRng(12345);
    for (keys) |*k| {
        k.* = rng.random().int(u64);
    }

    var map = std.AutoHashMap(u64, u64).init(allocator);
    defer map.deinit();

    for (keys) |k| {
        try map.put(k, k);
    }

    // Shuffle lookup order (heap allocated)
    var lookup_order = try allocator.alloc(usize, size);
    defer allocator.free(lookup_order);

    var lookup_rng = makeRng(67890);
    for (0..size) |i| {
        lookup_order[i] = i;
    }
    lookup_rng.random().shuffle(usize, lookup_order);

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var sum: u64 = 0;

        for (lookup_order) |idx| {
            sum +%= map.get(keys[idx]) orelse 0;
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchStdHashMapLookupMiss(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    var map = std.AutoHashMap(u64, u64).init(allocator);
    defer map.deinit();

    // Insert even numbers
    for (0..size) |i| {
        try map.put(i * 2, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var miss_count: u64 = 0;

        // Look up odd numbers (guaranteed misses)
        for (0..size) |i| {
            if (map.get(i * 2 + 1) == null) {
                miss_count += 1;
            }
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(miss_count);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchStdHashMapLookupMixed(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    var map = std.AutoHashMap(u64, u64).init(allocator);
    defer map.deinit();

    // Insert even numbers only
    for (0..size) |i| {
        try map.put(i * 2, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var sum: u64 = 0;

        // Look up all numbers (50% hit rate)
        for (0..size * 2) |i| {
            sum +%= map.get(i) orelse 0;
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchStdHashMapDelete(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var map = std.AutoHashMap(u64, u64).init(allocator);
        defer map.deinit();

        // First insert all
        for (0..size) |i| {
            try map.put(i, i);
        }

        var timer = try Timer.start();

        // Delete all
        for (0..size) |i| {
            _ = map.remove(i);
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchStdHashMapIteration(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    var map = std.AutoHashMap(u64, u64).init(allocator);
    defer map.deinit();

    for (0..size) |i| {
        try map.put(i, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var sum: u64 = 0;

        var iter = map.iterator();
        while (iter.next()) |entry| {
            sum +%= entry.value_ptr.*;
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchStdHashMapChurn(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    var map = std.AutoHashMap(u64, u64).init(allocator);
    defer map.deinit();

    // Pre-fill to half capacity
    for (0..size / 2) |i| {
        try map.put(i, i);
    }

    var total_ns: u64 = 0;
    var rng = makeRng(11111);

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();

        // Do size operations: alternating insert/delete
        for (0..size) |_| {
            const key = rng.random().int(u64) % (size * 2);
            if (rng.random().boolean()) {
                try map.put(key, key);
            } else {
                _ = map.remove(key);
            }
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

// ============================================================================
// Benchmark: Verstable (C reference implementation)
// ============================================================================

fn benchVerstableInsert(comptime size: usize) !u64 {
    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var map: vt.vt_u64_map = undefined;
        vt.vt_wrapper_init(&map);
        defer vt.vt_wrapper_cleanup(&map);

        var timer = try Timer.start();

        for (0..size) |i| {
            _ = vt.vt_wrapper_insert(&map, i, i);
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableRandomInsert(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    // Pre-generate random keys (heap allocated for large sizes)
    const keys = try allocator.alloc(u64, size);
    defer allocator.free(keys);

    var rng = makeRng(12345);
    for (keys) |*k| {
        k.* = rng.random().int(u64);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var map: vt.vt_u64_map = undefined;
        vt.vt_wrapper_init(&map);
        defer vt.vt_wrapper_cleanup(&map);

        var timer = try Timer.start();

        for (keys) |k| {
            _ = vt.vt_wrapper_insert(&map, k, k);
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableLookup(comptime size: usize) !u64 {
    var map: vt.vt_u64_map = undefined;
    vt.vt_wrapper_init(&map);
    defer vt.vt_wrapper_cleanup(&map);

    for (0..size) |i| {
        _ = vt.vt_wrapper_insert(&map, i, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var sum: u64 = 0;

        for (0..size) |i| {
            const val_ptr = vt.vt_wrapper_get(&map, i);
            if (val_ptr) |ptr| {
                sum +%= ptr.*;
            }
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableRandomLookup(comptime size: usize, allocator: std.mem.Allocator) !u64 {
    // Heap allocate for large sizes
    const keys = try allocator.alloc(u64, size);
    defer allocator.free(keys);

    var rng = makeRng(12345);
    for (keys) |*k| {
        k.* = rng.random().int(u64);
    }

    var map: vt.vt_u64_map = undefined;
    vt.vt_wrapper_init(&map);
    defer vt.vt_wrapper_cleanup(&map);

    for (keys) |k| {
        _ = vt.vt_wrapper_insert(&map, k, k);
    }

    // Shuffle lookup order (heap allocated)
    const lookup_order = try allocator.alloc(usize, size);
    defer allocator.free(lookup_order);

    var lookup_rng = makeRng(67890);
    for (0..size) |i| {
        lookup_order[i] = i;
    }
    lookup_rng.random().shuffle(usize, lookup_order);

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var sum: u64 = 0;

        for (lookup_order) |idx| {
            const val_ptr = vt.vt_wrapper_get(&map, keys[idx]);
            if (val_ptr) |ptr| {
                sum +%= ptr.*;
            }
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableLookupMiss(comptime size: usize) !u64 {
    var map: vt.vt_u64_map = undefined;
    vt.vt_wrapper_init(&map);
    defer vt.vt_wrapper_cleanup(&map);

    // Insert even numbers
    for (0..size) |i| {
        _ = vt.vt_wrapper_insert(&map, i * 2, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var miss_count: u64 = 0;

        // Look up odd numbers (guaranteed misses)
        for (0..size) |i| {
            if (vt.vt_wrapper_get(&map, i * 2 + 1) == null) {
                miss_count += 1;
            }
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(miss_count);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableLookupMixed(comptime size: usize) !u64 {
    var map: vt.vt_u64_map = undefined;
    vt.vt_wrapper_init(&map);
    defer vt.vt_wrapper_cleanup(&map);

    // Insert even numbers only
    for (0..size) |i| {
        _ = vt.vt_wrapper_insert(&map, i * 2, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var sum: u64 = 0;

        // Look up all numbers (50% hit rate)
        for (0..size * 2) |i| {
            const val_ptr = vt.vt_wrapper_get(&map, i);
            if (val_ptr) |ptr| {
                sum +%= ptr.*;
            }
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableDelete(comptime size: usize) !u64 {
    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var map: vt.vt_u64_map = undefined;
        vt.vt_wrapper_init(&map);
        defer vt.vt_wrapper_cleanup(&map);

        // First insert all
        for (0..size) |i| {
            _ = vt.vt_wrapper_insert(&map, i, i);
        }

        var timer = try Timer.start();

        // Delete all
        for (0..size) |i| {
            _ = vt.vt_wrapper_erase(&map, i);
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableIteration(comptime size: usize) !u64 {
    var map: vt.vt_u64_map = undefined;
    vt.vt_wrapper_init(&map);
    defer vt.vt_wrapper_cleanup(&map);

    for (0..size) |i| {
        _ = vt.vt_wrapper_insert(&map, i, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var sum: u64 = 0;

        var iter = vt.vt_wrapper_first(&map);
        while (vt.vt_wrapper_is_end(iter) == 0) {
            sum +%= vt.vt_wrapper_iter_val(iter);
            iter = vt.vt_wrapper_next(iter);
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableChurn(comptime size: usize) !u64 {
    var map: vt.vt_u64_map = undefined;
    vt.vt_wrapper_init(&map);
    defer vt.vt_wrapper_cleanup(&map);

    // Pre-fill to half capacity
    for (0..size / 2) |i| {
        _ = vt.vt_wrapper_insert(&map, i, i);
    }

    var total_ns: u64 = 0;
    var rng = makeRng(11111);

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();

        // Do size operations: alternating insert/delete
        for (0..size) |_| {
            const key = rng.random().int(u64) % (size * 2);
            if (rng.random().boolean()) {
                _ = vt.vt_wrapper_insert(&map, key, key);
            } else {
                _ = vt.vt_wrapper_erase(&map, key);
            }
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

// ============================================================================
// Full Comparison Runner
// ============================================================================

fn formatSize(size: usize) []const u8 {
    return switch (size) {
        100 => "100",
        1_000 => "1K",
        10_000 => "10K",
        100_000 => "100K",
        1_000_000 => "1M",
        10_000_000 => "10M",
        else => "?",
    };
}

fn runFullComparison(comptime size: usize, allocator: std.mem.Allocator) !void {
    const size_str = comptime formatSize(size);

    std.debug.print("\n", .{});
    std.debug.print("====================================================================================================\n", .{});
    std.debug.print("| Full Comparison ({s} elements) - Average time per operation{s}|\n", .{ size_str, " " ** (58 - size_str.len) });
    std.debug.print("====================================================================================================\n", .{});
    std.debug.print("| Operation          | TheHashTable  | Verstable (C) | std.AutoHashMap | vs Verstable | vs std     |\n", .{});
    std.debug.print("----------------------------------------------------------------------------------------------------\n", .{});

    // Sequential Insert
    const ours_insert = try benchSequentialInsert(size, allocator) / size;
    const vt_insert = try benchVerstableInsert(size) / size;
    const std_insert = try benchStdHashMapInsert(size, allocator) / size;

    std.debug.print("| Seq. Insert        | ", .{});
    printTime(ours_insert);
    std.debug.print("   | ", .{});
    printTime(vt_insert);
    std.debug.print("   | ", .{});
    printTime(std_insert);
    std.debug.print("     | {d:>6.2}x      | {d:>6.2}x    |\n", .{
        @as(f64, @floatFromInt(vt_insert)) / @as(f64, @floatFromInt(@max(ours_insert, 1))),
        @as(f64, @floatFromInt(std_insert)) / @as(f64, @floatFromInt(@max(ours_insert, 1))),
    });

    // Random Insert
    const ours_rand_insert = try benchRandomInsert(size, allocator) / size;
    const vt_rand_insert = try benchVerstableRandomInsert(size, allocator) / size;
    const std_rand_insert = try benchStdHashMapRandomInsert(size, allocator) / size;

    std.debug.print("| Rand. Insert       | ", .{});
    printTime(ours_rand_insert);
    std.debug.print("   | ", .{});
    printTime(vt_rand_insert);
    std.debug.print("   | ", .{});
    printTime(std_rand_insert);
    std.debug.print("     | {d:>6.2}x      | {d:>6.2}x    |\n", .{
        @as(f64, @floatFromInt(vt_rand_insert)) / @as(f64, @floatFromInt(@max(ours_rand_insert, 1))),
        @as(f64, @floatFromInt(std_rand_insert)) / @as(f64, @floatFromInt(@max(ours_rand_insert, 1))),
    });

    // Sequential Lookup
    const ours_lookup = try benchSequentialLookupHit(size, allocator) / size;
    const vt_lookup = try benchVerstableLookup(size) / size;
    const std_lookup = try benchStdHashMapLookup(size, allocator) / size;

    std.debug.print("| Seq. Lookup        | ", .{});
    printTime(ours_lookup);
    std.debug.print("   | ", .{});
    printTime(vt_lookup);
    std.debug.print("   | ", .{});
    printTime(std_lookup);
    std.debug.print("     | {d:>6.2}x      | {d:>6.2}x    |\n", .{
        @as(f64, @floatFromInt(vt_lookup)) / @as(f64, @floatFromInt(@max(ours_lookup, 1))),
        @as(f64, @floatFromInt(std_lookup)) / @as(f64, @floatFromInt(@max(ours_lookup, 1))),
    });

    // Random Lookup
    const ours_rand_lookup = try benchRandomLookupHit(size, allocator) / size;
    const vt_rand_lookup = try benchVerstableRandomLookup(size, allocator) / size;
    const std_rand_lookup = try benchStdHashMapRandomLookup(size, allocator) / size;

    std.debug.print("| Rand. Lookup       | ", .{});
    printTime(ours_rand_lookup);
    std.debug.print("   | ", .{});
    printTime(vt_rand_lookup);
    std.debug.print("   | ", .{});
    printTime(std_rand_lookup);
    std.debug.print("     | {d:>6.2}x      | {d:>6.2}x    |\n", .{
        @as(f64, @floatFromInt(vt_rand_lookup)) / @as(f64, @floatFromInt(@max(ours_rand_lookup, 1))),
        @as(f64, @floatFromInt(std_rand_lookup)) / @as(f64, @floatFromInt(@max(ours_rand_lookup, 1))),
    });

    // Lookup Miss
    const ours_miss = try benchLookupMiss(size, allocator) / size;
    const vt_miss = try benchVerstableLookupMiss(size) / size;
    const std_miss = try benchStdHashMapLookupMiss(size, allocator) / size;

    std.debug.print("| Lookup Miss        | ", .{});
    printTime(ours_miss);
    std.debug.print("   | ", .{});
    printTime(vt_miss);
    std.debug.print("   | ", .{});
    printTime(std_miss);
    std.debug.print("     | {d:>6.2}x      | {d:>6.2}x    |\n", .{
        @as(f64, @floatFromInt(vt_miss)) / @as(f64, @floatFromInt(@max(ours_miss, 1))),
        @as(f64, @floatFromInt(std_miss)) / @as(f64, @floatFromInt(@max(ours_miss, 1))),
    });

    // Mixed Lookup (50% hit) - does size*2 lookups
    const ours_mixed = try benchLookupMixed(size, allocator) / (size * 2);
    const vt_mixed = try benchVerstableLookupMixed(size) / (size * 2);
    const std_mixed = try benchStdHashMapLookupMixed(size, allocator) / (size * 2);

    std.debug.print("| Mixed Lookup       | ", .{});
    printTime(ours_mixed);
    std.debug.print("   | ", .{});
    printTime(vt_mixed);
    std.debug.print("   | ", .{});
    printTime(std_mixed);
    std.debug.print("     | {d:>6.2}x      | {d:>6.2}x    |\n", .{
        @as(f64, @floatFromInt(vt_mixed)) / @as(f64, @floatFromInt(@max(ours_mixed, 1))),
        @as(f64, @floatFromInt(std_mixed)) / @as(f64, @floatFromInt(@max(ours_mixed, 1))),
    });

    // Delete
    const ours_delete = try benchDelete(size, allocator) / size;
    const vt_delete = try benchVerstableDelete(size) / size;
    const std_delete = try benchStdHashMapDelete(size, allocator) / size;

    std.debug.print("| Delete             | ", .{});
    printTime(ours_delete);
    std.debug.print("   | ", .{});
    printTime(vt_delete);
    std.debug.print("   | ", .{});
    printTime(std_delete);
    std.debug.print("     | {d:>6.2}x      | {d:>6.2}x    |\n", .{
        @as(f64, @floatFromInt(vt_delete)) / @as(f64, @floatFromInt(@max(ours_delete, 1))),
        @as(f64, @floatFromInt(std_delete)) / @as(f64, @floatFromInt(@max(ours_delete, 1))),
    });

    // Iteration (iterates over size elements)
    const ours_iter = try benchIteration(size, allocator) / size;
    const vt_iter = try benchVerstableIteration(size) / size;
    const std_iter = try benchStdHashMapIteration(size, allocator) / size;

    std.debug.print("| Iteration          | ", .{});
    printTime(ours_iter);
    std.debug.print("   | ", .{});
    printTime(vt_iter);
    std.debug.print("   | ", .{});
    printTime(std_iter);
    std.debug.print("     | {d:>6.2}x      | {d:>6.2}x    |\n", .{
        @as(f64, @floatFromInt(vt_iter)) / @as(f64, @floatFromInt(@max(ours_iter, 1))),
        @as(f64, @floatFromInt(std_iter)) / @as(f64, @floatFromInt(@max(ours_iter, 1))),
    });

    // Churn (does size operations)
    const ours_churn = try benchChurn(size, allocator) / size;
    const vt_churn = try benchVerstableChurn(size) / size;
    const std_churn = try benchStdHashMapChurn(size, allocator) / size;

    std.debug.print("| Churn              | ", .{});
    printTime(ours_churn);
    std.debug.print("   | ", .{});
    printTime(vt_churn);
    std.debug.print("   | ", .{});
    printTime(std_churn);
    std.debug.print("     | {d:>6.2}x      | {d:>6.2}x    |\n", .{
        @as(f64, @floatFromInt(vt_churn)) / @as(f64, @floatFromInt(@max(ours_churn, 1))),
        @as(f64, @floatFromInt(std_churn)) / @as(f64, @floatFromInt(@max(ours_churn, 1))),
    });

    std.debug.print("----------------------------------------------------------------------------------------------------\n", .{});
    std.debug.print("| Note: vs Verstable/std shows how many times faster TheHashTable is (>1 = faster)                |\n", .{});
    std.debug.print("====================================================================================================\n", .{});
}

// ============================================================================
// Main Benchmark Runner
// ============================================================================

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("                      TheHashTable Benchmark Suite                              \n", .{});
    std.debug.print("                                                                                \n", .{});
    std.debug.print("  Comparing:                                                                    \n", .{});
    std.debug.print("  - TheHashTable (Zig port)                                                     \n", .{});
    std.debug.print("  - Verstable (C original): https://github.com/JacksonAllan/Verstable           \n", .{});
    std.debug.print("  - std.AutoHashMap (Zig standard library)                                      \n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("Configuration:\n", .{});
    std.debug.print("  - Warmup iterations:    {d}\n", .{WARMUP_ITERATIONS});
    std.debug.print("  - Benchmark iterations: {d}\n", .{BENCHMARK_ITERATIONS});
    std.debug.print("  - Test sizes:           {d}, {d}, {d}, {d}, {d}, {d}\n", .{ SIZE_100, SIZE_1K, SIZE_10K, SIZE_100K, SIZE_1M, SIZE_10M });
    std.debug.print("\n", .{});

    // Warmup
    std.debug.print("Warming up...\n", .{});
    for (0..WARMUP_ITERATIONS) |_| {
        _ = try benchSequentialInsert(SIZE_100, allocator);
    }
    std.debug.print("\n", .{});

    // Run full comparison for all sizes
    try runFullComparison(SIZE_100, allocator);
    try runFullComparison(SIZE_1K, allocator);
    try runFullComparison(SIZE_10K, allocator);
    try runFullComparison(SIZE_100K, allocator);
    try runFullComparison(SIZE_1M, allocator);
    try runFullComparison(SIZE_10M, allocator);

    // Memory usage
    std.debug.print("\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("| Memory Overhead Analysis (1M entries, u64->u64)                              |\n", .{});
    std.debug.print("================================================================================\n", .{});

    {
        var map = TheHashTable(u64, u64).init(allocator);
        defer map.deinit();

        for (0..SIZE_1M) |i| {
            try map.put(i, i);
        }

        const bucket_count = map.bucketCount();
        const bucket_size = @sizeOf(@TypeOf(map).Bucket);
        const metadata_size: usize = 2; // u16 per bucket
        const total_overhead_per_entry = @as(f64, @floatFromInt((bucket_count * (bucket_size + metadata_size)))) / @as(f64, @floatFromInt(SIZE_1M));
        const metadata_only_per_entry = @as(f64, @floatFromInt(bucket_count * metadata_size)) / @as(f64, @floatFromInt(SIZE_1M));

        std.debug.print("| Entries:                    {d:>48} |\n", .{SIZE_1M});
        std.debug.print("| Bucket count:               {d:>48} |\n", .{bucket_count});
        std.debug.print("| Load factor:                {d:>47.1}% |\n", .{@as(f64, @floatFromInt(SIZE_1M)) / @as(f64, @floatFromInt(bucket_count)) * 100});
        std.debug.print("| Bucket size:                {d:>44} bytes |\n", .{bucket_size});
        std.debug.print("| Metadata per bucket:        {d:>44} bytes |\n", .{metadata_size});
        std.debug.print("| Total bytes per entry:      {d:>44.1} bytes |\n", .{total_overhead_per_entry});
        std.debug.print("| Metadata overhead/entry:    {d:>44.1} bytes |\n", .{metadata_only_per_entry});
    }

    std.debug.print("================================================================================\n", .{});
    std.debug.print("\n", .{});
}
