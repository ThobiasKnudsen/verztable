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

// ============================================================================
// Comptime Verstable Wrapper - Uses @field for clean function dispatch
// ============================================================================

fn VerstableWrapper(comptime K: type, comptime V: type) type {
    // Construct the function name prefix based on key and value types
    const key_name = if (K == u64) "u64" else if (K == u16) "u16" else if (K == []const u8) "str" else @compileError("Unsupported key type");
    const val_name = if (V == void) "void" else if (V == Value4) "val4" else if (V == Value64) "val64" else if (V == Value256) "val256" else @compileError("Unsupported value type");
    const prefix = "vt_" ++ key_name ++ "_" ++ val_name ++ "_";
    const is_set = V == void;
    const is_string = K == []const u8;

    return struct {
        const Self = @This();
        map: vt.vt_generic_map,

        // Get C functions by constructed name
        const initFn = @field(vt, prefix ++ "init");
        const cleanupFn = @field(vt, prefix ++ "cleanup");
        const insertFn = @field(vt, prefix ++ "insert");
        const getFn = @field(vt, prefix ++ "get");
        const eraseFn = @field(vt, prefix ++ "erase");
        const sizeFn = @field(vt, prefix ++ "size");
        const firstFn = @field(vt, prefix ++ "first");
        const is_endFn = @field(vt, prefix ++ "is_end");
        const nextFn = @field(vt, prefix ++ "next");

        pub fn init() Self {
            var self: Self = undefined;
            initFn(&self.map);
            return self;
        }

        pub fn deinit(self: *Self) void {
            cleanupFn(&self.map);
        }

        pub fn insert(self: *Self, key: K, val: V) bool {
            if (is_string) {
                if (is_set) {
                    return insertFn(&self.map, key.ptr, key.len) != 0;
                } else {
                    return insertFn(&self.map, key.ptr, key.len, &val.data) != 0;
                }
            } else {
                if (is_set) {
                    return insertFn(&self.map, key) != 0;
                } else {
                    return insertFn(&self.map, key, &val.data) != 0;
                }
            }
        }

        pub fn get(self: *Self, key: K) bool {
            if (is_string) {
                return getFn(&self.map, key.ptr, key.len) != 0;
            } else {
                return getFn(&self.map, key) != 0;
            }
        }

        pub fn erase(self: *Self, key: K) bool {
            if (is_string) {
                return eraseFn(&self.map, key.ptr, key.len) != 0;
            } else {
                return eraseFn(&self.map, key) != 0;
            }
        }

        pub fn size(self: *Self) usize {
            return sizeFn(&self.map);
        }

        pub fn iterCount(self: *Self) u64 {
            var count: u64 = 0;
            var iter = firstFn(&self.map);
            while (is_endFn(iter) == 0) {
                count += 1;
                iter = nextFn(iter);
            }
            return count;
        }
    };
}

// ============================================================================
// Generic Verstable Benchmark Functions
// ============================================================================

fn VerstableBenchmarks(comptime K: type, comptime V: type) type {
    return struct {
        const VtMap = VerstableWrapper(K, V);

        fn makeValue(i: u64) V {
            if (V == void) return {};
            if (V == Value4) return Value4.fromU64(i);
            if (V == Value64) return Value64.fromU64(i);
            if (V == Value256) return Value256.fromU64(i);
            @compileError("Unsupported value type");
        }

        fn keyToU64(key: K) u64 {
            if (K == u16) return key;
            if (K == u64) return key;
            return 0; // strings
        }

        fn benchRandomInsert(comptime size: usize, keys: []const K) !u64 {
            var total_ns: u64 = 0;
            for (0..BENCHMARK_ITERATIONS) |_| {
                var map = VtMap.init();
                defer map.deinit();
                var timer = try Timer.start();
                for (keys[0..size]) |k| {
                    _ = map.insert(k, makeValue(keyToU64(k)));
                }
                total_ns += timer.read();
            }
            return total_ns / BENCHMARK_ITERATIONS;
        }

        fn benchRandomLookup(comptime size: usize, keys: []const K, lookup_order: []const usize) !u64 {
            var map = VtMap.init();
            defer map.deinit();
            for (keys[0..size]) |k| {
                _ = map.insert(k, makeValue(keyToU64(k)));
            }
            var total_ns: u64 = 0;
            for (0..BENCHMARK_ITERATIONS) |_| {
                var timer = try Timer.start();
                var found: u64 = 0;
                for (lookup_order[0..size]) |idx| {
                    if (map.get(keys[idx])) found += 1;
                }
                total_ns += timer.read();
                std.mem.doNotOptimizeAway(found);
            }
            return total_ns / BENCHMARK_ITERATIONS;
        }

        fn benchLookupMiss(comptime size: usize, keys: []const K, miss_keys: []const K) !u64 {
            var map = VtMap.init();
            defer map.deinit();
            for (keys[0..size]) |k| {
                _ = map.insert(k, makeValue(keyToU64(k)));
            }
            var total_ns: u64 = 0;
            for (0..BENCHMARK_ITERATIONS) |_| {
                var timer = try Timer.start();
                var miss_count: u64 = 0;
                for (miss_keys[0..size]) |k| {
                    if (!map.get(k)) miss_count += 1;
                }
                total_ns += timer.read();
                std.mem.doNotOptimizeAway(miss_count);
            }
            return total_ns / BENCHMARK_ITERATIONS;
        }

        fn benchDelete(comptime size: usize, keys: []const K) !u64 {
            var total_ns: u64 = 0;
            for (0..BENCHMARK_ITERATIONS) |_| {
                var map = VtMap.init();
                defer map.deinit();
                for (keys[0..size]) |k| {
                    _ = map.insert(k, makeValue(keyToU64(k)));
                }
                var timer = try Timer.start();
                for (keys[0..size]) |k| {
                    _ = map.erase(k);
                }
                total_ns += timer.read();
            }
            return total_ns / BENCHMARK_ITERATIONS;
        }

        fn benchIteration(comptime size: usize, keys: []const K) !u64 {
            var map = VtMap.init();
            defer map.deinit();
            for (keys[0..size]) |k| {
                _ = map.insert(k, makeValue(keyToU64(k)));
            }
            var total_ns: u64 = 0;
            for (0..BENCHMARK_ITERATIONS) |_| {
                var timer = try Timer.start();
                const count = map.iterCount();
                total_ns += timer.read();
                std.mem.doNotOptimizeAway(count);
            }
            return total_ns / BENCHMARK_ITERATIONS;
        }

        fn benchChurn(comptime size: usize, keys: []const K) !u64 {
            var map = VtMap.init();
            defer map.deinit();
            for (keys[0 .. size / 2]) |k| {
                _ = map.insert(k, makeValue(keyToU64(k)));
            }
            var total_ns: u64 = 0;
            var rng = makeRng(11111);
            for (0..BENCHMARK_ITERATIONS) |_| {
                var timer = try Timer.start();
                for (0..size) |_| {
                    const idx = rng.random().int(usize) % size;
                    if (rng.random().boolean()) {
                        _ = map.insert(keys[idx], makeValue(keyToU64(keys[idx])));
                    } else {
                        _ = map.erase(keys[idx]);
                    }
                }
                total_ns += timer.read();
            }
            return total_ns / BENCHMARK_ITERATIONS;
        }
    };
}

const WARMUP_ITERATIONS = 3;
const BENCHMARK_ITERATIONS = 5;

// Test sizes
const SIZE_10: usize = 10;
const SIZE_100: usize = 100;
const SIZE_1K: usize = 1_000;
const SIZE_10K: usize = 10_000;
const SIZE_65524: usize = 65_524;
const SIZE_100K: usize = 100_000;

// ============================================================================
// Value Types for Comprehensive Testing
// ============================================================================

const Value4 = extern struct {
    data: [4]u8 = .{ 0, 0, 0, 0 },

    fn fromU64(v: u64) Value4 {
        var result: Value4 = .{};
        const bytes: [8]u8 = @bitCast(v);
        @memcpy(&result.data, bytes[0..4]);
        return result;
    }
};

const Value64 = extern struct {
    data: [64]u8 = .{0} ** 64,

    fn fromU64(v: u64) Value64 {
        var result: Value64 = .{};
        const bytes: [8]u8 = @bitCast(v);
        for (0..8) |i| {
            result.data[i] = bytes[i];
            result.data[i + 8] = bytes[i];
            result.data[i + 16] = bytes[i];
            result.data[i + 24] = bytes[i];
            result.data[i + 32] = bytes[i];
            result.data[i + 40] = bytes[i];
            result.data[i + 48] = bytes[i];
            result.data[i + 56] = bytes[i];
        }
        return result;
    }
};

const Value256 = extern struct {
    data: [256]u8 = .{0} ** 256,

    fn fromU64(v: u64) Value256 {
        var result: Value256 = .{};
        const bytes: [8]u8 = @bitCast(v);
        for (0..32) |block| {
            for (0..8) |i| {
                result.data[block * 8 + i] = bytes[i];
            }
        }
        return result;
    }
};

fn printTime(ns: u64) void {
    if (ns < 1000) {
        std.debug.print("{d:>6} ns", .{ns});
    } else if (ns < 1_000_000) {
        std.debug.print("{d:>6.1} us", .{@as(f64, @floatFromInt(ns)) / 1000.0});
    } else if (ns < 1_000_000_000) {
        std.debug.print("{d:>6.1} ms", .{@as(f64, @floatFromInt(ns)) / 1_000_000.0});
    } else {
        std.debug.print("{d:>6.1} s ", .{@as(f64, @floatFromInt(ns)) / 1_000_000_000.0});
    }
}

// PRNG for reproducible random numbers
const Xoshiro = std.Random.Xoshiro256;

fn makeRng(seed: u64) Xoshiro {
    return Xoshiro.init(seed);
}

// ============================================================================
// Benchmark: Sequential Insertions (used for warmup)
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
// Benchmark: Verstable (C reference implementation)
// ============================================================================

fn benchVerstableRandomInsert(comptime size: usize, allocator: std.mem.Allocator) !u64 {
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

fn benchVerstableRandomLookup(comptime size: usize, allocator: std.mem.Allocator) !u64 {
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

    for (0..size) |i| {
        _ = vt.vt_wrapper_insert(&map, i * 2, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var miss_count: u64 = 0;

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

fn benchVerstableDelete(comptime size: usize) !u64 {
    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var map: vt.vt_u64_map = undefined;
        vt.vt_wrapper_init(&map);
        defer vt.vt_wrapper_cleanup(&map);

        for (0..size) |i| {
            _ = vt.vt_wrapper_insert(&map, i, i);
        }

        var timer = try Timer.start();

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

    for (0..size / 2) |i| {
        _ = vt.vt_wrapper_insert(&map, i, i);
    }

    var total_ns: u64 = 0;
    var rng = makeRng(11111);

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();

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
// Benchmark: Verstable u16 Keys (C reference implementation)
// ============================================================================

fn benchVerstableU16RandomInsert(comptime size: usize, keys: []const u16) !u64 {
    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var map: vt.vt_u16_map = undefined;
        vt.vt_u16_wrapper_init(&map);
        defer vt.vt_u16_wrapper_cleanup(&map);

        var timer = try Timer.start();

        for (keys[0..size]) |k| {
            _ = vt.vt_u16_wrapper_insert(&map, k, @as(u64, k));
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableU16RandomLookup(comptime size: usize, keys: []const u16, lookup_order: []const usize) !u64 {
    var map: vt.vt_u16_map = undefined;
    vt.vt_u16_wrapper_init(&map);
    defer vt.vt_u16_wrapper_cleanup(&map);

    for (keys[0..size]) |k| {
        _ = vt.vt_u16_wrapper_insert(&map, k, @as(u64, k));
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var sum: u64 = 0;

        for (lookup_order[0..size]) |idx| {
            const val_ptr = vt.vt_u16_wrapper_get(&map, keys[idx]);
            if (val_ptr) |ptr| {
                sum +%= ptr.*;
            }
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableU16LookupMiss(comptime size: usize, keys: []const u16, miss_keys: []const u16) !u64 {
    var map: vt.vt_u16_map = undefined;
    vt.vt_u16_wrapper_init(&map);
    defer vt.vt_u16_wrapper_cleanup(&map);

    for (keys[0..size]) |k| {
        _ = vt.vt_u16_wrapper_insert(&map, k, @as(u64, k));
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var miss_count: u64 = 0;

        for (miss_keys[0..size]) |k| {
            if (vt.vt_u16_wrapper_get(&map, k) == null) {
                miss_count += 1;
            }
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(miss_count);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableU16Delete(comptime size: usize, keys: []const u16) !u64 {
    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var map: vt.vt_u16_map = undefined;
        vt.vt_u16_wrapper_init(&map);
        defer vt.vt_u16_wrapper_cleanup(&map);

        for (keys[0..size]) |k| {
            _ = vt.vt_u16_wrapper_insert(&map, k, @as(u64, k));
        }

        var timer = try Timer.start();

        for (keys[0..size]) |k| {
            _ = vt.vt_u16_wrapper_erase(&map, k);
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableU16Iteration(comptime size: usize, keys: []const u16) !u64 {
    var map: vt.vt_u16_map = undefined;
    vt.vt_u16_wrapper_init(&map);
    defer vt.vt_u16_wrapper_cleanup(&map);

    for (keys[0..size]) |k| {
        _ = vt.vt_u16_wrapper_insert(&map, k, @as(u64, k));
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var sum: u64 = 0;

        var iter = vt.vt_u16_wrapper_first(&map);
        while (vt.vt_u16_wrapper_is_end(iter) == 0) {
            sum +%= vt.vt_u16_wrapper_iter_val(iter);
            iter = vt.vt_u16_wrapper_next(iter);
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableU16Churn(comptime size: usize, keys: []const u16) !u64 {
    var map: vt.vt_u16_map = undefined;
    vt.vt_u16_wrapper_init(&map);
    defer vt.vt_u16_wrapper_cleanup(&map);

    for (keys[0 .. size / 2]) |k| {
        _ = vt.vt_u16_wrapper_insert(&map, k, @as(u64, k));
    }

    var total_ns: u64 = 0;
    var rng = makeRng(11111);

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();

        for (0..size) |_| {
            const idx = rng.random().int(usize) % size;
            const key = keys[idx];
            if (rng.random().boolean()) {
                _ = vt.vt_u16_wrapper_insert(&map, key, @as(u64, key));
            } else {
                _ = vt.vt_u16_wrapper_erase(&map, key);
            }
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

// ============================================================================
// Benchmark: Verstable String Keys (C reference implementation)
// ============================================================================

fn benchVerstableStrRandomInsert(comptime size: usize, keys: []const []const u8) !u64 {
    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var map: vt.vt_str_map = undefined;
        vt.vt_str_wrapper_init(&map);
        defer vt.vt_str_wrapper_cleanup(&map);

        var timer = try Timer.start();

        for (keys[0..size], 0..) |k, i| {
            _ = vt.vt_str_wrapper_insert(&map, k.ptr, k.len, i);
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableStrRandomLookup(comptime size: usize, keys: []const []const u8, lookup_order: []const usize) !u64 {
    var map: vt.vt_str_map = undefined;
    vt.vt_str_wrapper_init(&map);
    defer vt.vt_str_wrapper_cleanup(&map);

    for (keys[0..size], 0..) |k, i| {
        _ = vt.vt_str_wrapper_insert(&map, k.ptr, k.len, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var found: u64 = 0;

        for (lookup_order[0..size]) |idx| {
            const k = keys[idx];
            if (vt.vt_str_wrapper_get(&map, k.ptr, k.len) != null) {
                found += 1;
            }
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(found);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableStrLookupMiss(comptime size: usize, keys: []const []const u8, miss_keys: []const []const u8) !u64 {
    var map: vt.vt_str_map = undefined;
    vt.vt_str_wrapper_init(&map);
    defer vt.vt_str_wrapper_cleanup(&map);

    for (keys[0..size], 0..) |k, i| {
        _ = vt.vt_str_wrapper_insert(&map, k.ptr, k.len, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var miss_count: u64 = 0;

        for (miss_keys[0..size]) |k| {
            if (vt.vt_str_wrapper_get(&map, k.ptr, k.len) == null) {
                miss_count += 1;
            }
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(miss_count);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableStrDelete(comptime size: usize, keys: []const []const u8) !u64 {
    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var map: vt.vt_str_map = undefined;
        vt.vt_str_wrapper_init(&map);
        defer vt.vt_str_wrapper_cleanup(&map);

        for (keys[0..size], 0..) |k, i| {
            _ = vt.vt_str_wrapper_insert(&map, k.ptr, k.len, i);
        }

        var timer = try Timer.start();

        for (keys[0..size]) |k| {
            _ = vt.vt_str_wrapper_erase(&map, k.ptr, k.len);
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableStrIteration(comptime size: usize, keys: []const []const u8) !u64 {
    var map: vt.vt_str_map = undefined;
    vt.vt_str_wrapper_init(&map);
    defer vt.vt_str_wrapper_cleanup(&map);

    for (keys[0..size], 0..) |k, i| {
        _ = vt.vt_str_wrapper_insert(&map, k.ptr, k.len, i);
    }

    var total_ns: u64 = 0;

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var sum: u64 = 0;

        var iter = vt.vt_str_wrapper_first(&map);
        while (vt.vt_str_wrapper_is_end(iter) == 0) {
            sum +%= vt.vt_str_wrapper_iter_val(iter);
            iter = vt.vt_str_wrapper_next(iter);
        }

        total_ns += timer.read();
        std.mem.doNotOptimizeAway(sum);
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

fn benchVerstableStrChurn(comptime size: usize, keys: []const []const u8) !u64 {
    var map: vt.vt_str_map = undefined;
    vt.vt_str_wrapper_init(&map);
    defer vt.vt_str_wrapper_cleanup(&map);

    for (keys[0 .. size / 2], 0..) |k, i| {
        _ = vt.vt_str_wrapper_insert(&map, k.ptr, k.len, i);
    }

    var total_ns: u64 = 0;
    var rng = makeRng(11111);

    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();

        for (0..size) |_| {
            const idx = rng.random().int(usize) % size;
            const k = keys[idx];
            if (rng.random().boolean()) {
                _ = vt.vt_str_wrapper_insert(&map, k.ptr, k.len, idx);
            } else {
                _ = vt.vt_str_wrapper_erase(&map, k.ptr, k.len);
            }
        }

        total_ns += timer.read();
    }

    return total_ns / BENCHMARK_ITERATIONS;
}

// ============================================================================
// Helpers
// ============================================================================

fn formatSize(size: usize) []const u8 {
    return switch (size) {
        10 => "10",
        100 => "100",
        1_000 => "1K",
        10_000 => "10K",
        65_524 => "65524",
        100_000 => "100K",
        else => "?",
    };
}

// ============================================================================
// Generic Benchmark Functions for Key/Value Type Combinations
// ============================================================================

fn GenericBenchmarks(comptime K: type, comptime V: type) type {
    return struct {
        const Map = TheHashTable(K, V);
        const StdMap = std.AutoHashMap(K, V);
        const is_set = V == void;

        fn makeValue(i: u64) V {
            if (V == void) {
                return {};
            } else if (V == Value4) {
                return Value4.fromU64(i);
            } else if (V == Value64) {
                return Value64.fromU64(i);
            } else if (V == Value256) {
                return Value256.fromU64(i);
            } else {
                @compileError("Unsupported value type");
            }
        }

        fn benchRandomInsert(comptime size: usize, keys: []const K, allocator: std.mem.Allocator) !u64 {
            var total_ns: u64 = 0;

            for (0..BENCHMARK_ITERATIONS) |_| {
                var map = Map.init(allocator);
                defer map.deinit();

                var timer = try Timer.start();

                for (keys[0..size]) |k| {
                    if (is_set) {
                        try map.add(k);
                    } else {
                        const v = makeValue(@as(u64, if (K == u16) k else if (K == u64) k else 0));
                        try map.put(k, v);
                    }
                }

                total_ns += timer.read();
            }

            return total_ns / BENCHMARK_ITERATIONS;
        }

        fn benchRandomLookup(comptime size: usize, keys: []const K, lookup_order: []const usize, allocator: std.mem.Allocator) !u64 {
            var map = Map.init(allocator);
            defer map.deinit();

            for (keys[0..size]) |k| {
                if (is_set) {
                    try map.add(k);
                } else {
                    const v = makeValue(@as(u64, if (K == u16) k else if (K == u64) k else 0));
                    try map.put(k, v);
                }
            }

            var total_ns: u64 = 0;

            for (0..BENCHMARK_ITERATIONS) |_| {
                var timer = try Timer.start();
                var found: u64 = 0;

                for (lookup_order[0..size]) |idx| {
                    if (is_set) {
                        if (map.contains(keys[idx])) found += 1;
                    } else {
                        if (map.get(keys[idx]) != null) found += 1;
                    }
                }

                total_ns += timer.read();
                std.mem.doNotOptimizeAway(found);
            }

            return total_ns / BENCHMARK_ITERATIONS;
        }

        fn benchLookupMiss(comptime size: usize, keys: []const K, miss_keys: []const K, allocator: std.mem.Allocator) !u64 {
            var map = Map.init(allocator);
            defer map.deinit();

            for (keys[0..size]) |k| {
                if (is_set) {
                    try map.add(k);
                } else {
                    const v = makeValue(@as(u64, if (K == u16) k else if (K == u64) k else 0));
                    try map.put(k, v);
                }
            }

            var total_ns: u64 = 0;

            for (0..BENCHMARK_ITERATIONS) |_| {
                var timer = try Timer.start();
                var miss_count: u64 = 0;

                for (miss_keys[0..size]) |k| {
                    if (is_set) {
                        if (!map.contains(k)) miss_count += 1;
                    } else {
                        if (map.get(k) == null) miss_count += 1;
                    }
                }

                total_ns += timer.read();
                std.mem.doNotOptimizeAway(miss_count);
            }

            return total_ns / BENCHMARK_ITERATIONS;
        }

        fn benchDelete(comptime size: usize, keys: []const K, allocator: std.mem.Allocator) !u64 {
            var total_ns: u64 = 0;

            for (0..BENCHMARK_ITERATIONS) |_| {
                var map = Map.init(allocator);
                defer map.deinit();

                for (keys[0..size]) |k| {
                    if (is_set) {
                        try map.add(k);
                    } else {
                        const v = makeValue(@as(u64, if (K == u16) k else if (K == u64) k else 0));
                        try map.put(k, v);
                    }
                }

                var timer = try Timer.start();

                for (keys[0..size]) |k| {
                    _ = map.remove(k);
                }

                total_ns += timer.read();
            }

            return total_ns / BENCHMARK_ITERATIONS;
        }

        fn benchIteration(comptime size: usize, keys: []const K, allocator: std.mem.Allocator) !u64 {
            var map = Map.init(allocator);
            defer map.deinit();

            for (keys[0..size]) |k| {
                if (is_set) {
                    try map.add(k);
                } else {
                    const v = makeValue(@as(u64, if (K == u16) k else if (K == u64) k else 0));
                    try map.put(k, v);
                }
            }

            var total_ns: u64 = 0;

            for (0..BENCHMARK_ITERATIONS) |_| {
                var timer = try Timer.start();
                var count: u64 = 0;

                var iter = map.iterator();
                while (iter.next()) |_| {
                    count += 1;
                }

                total_ns += timer.read();
                std.mem.doNotOptimizeAway(count);
            }

            return total_ns / BENCHMARK_ITERATIONS;
        }

        fn benchChurn(comptime size: usize, keys: []const K, allocator: std.mem.Allocator) !u64 {
            var map = Map.init(allocator);
            defer map.deinit();

            for (keys[0 .. size / 2]) |k| {
                if (is_set) {
                    try map.add(k);
                } else {
                    const v = makeValue(@as(u64, if (K == u16) k else if (K == u64) k else 0));
                    try map.put(k, v);
                }
            }

            var total_ns: u64 = 0;
            var rng = makeRng(11111);

            for (0..BENCHMARK_ITERATIONS) |_| {
                var timer = try Timer.start();

                for (0..size) |_| {
                    const idx = rng.random().int(usize) % size;
                    if (rng.random().boolean()) {
                        if (is_set) {
                            try map.add(keys[idx]);
                        } else {
                            const v = makeValue(@as(u64, if (K == u16) keys[idx] else if (K == u64) keys[idx] else 0));
                            try map.put(keys[idx], v);
                        }
                    } else {
                        _ = map.remove(keys[idx]);
                    }
                }

                total_ns += timer.read();
            }

            return total_ns / BENCHMARK_ITERATIONS;
        }

        // std.AutoHashMap benchmarks for comparison
        fn benchStdRandomInsert(comptime size: usize, keys: []const K, allocator: std.mem.Allocator) !u64 {
            var total_ns: u64 = 0;

            for (0..BENCHMARK_ITERATIONS) |_| {
                var map = StdMap.init(allocator);
                defer map.deinit();

                var timer = try Timer.start();

                for (keys[0..size]) |k| {
                    const v = if (is_set) {} else makeValue(@as(u64, if (K == u16) k else if (K == u64) k else 0));
                    try map.put(k, v);
                }

                total_ns += timer.read();
            }

            return total_ns / BENCHMARK_ITERATIONS;
        }

        fn benchStdRandomLookup(comptime size: usize, keys: []const K, lookup_order: []const usize, allocator: std.mem.Allocator) !u64 {
            var map = StdMap.init(allocator);
            defer map.deinit();

            for (keys[0..size]) |k| {
                const v = if (is_set) {} else makeValue(@as(u64, if (K == u16) k else if (K == u64) k else 0));
                try map.put(k, v);
            }

            var total_ns: u64 = 0;

            for (0..BENCHMARK_ITERATIONS) |_| {
                var timer = try Timer.start();
                var found: u64 = 0;

                for (lookup_order[0..size]) |idx| {
                    if (map.get(keys[idx]) != null) found += 1;
                }

                total_ns += timer.read();
                std.mem.doNotOptimizeAway(found);
            }

            return total_ns / BENCHMARK_ITERATIONS;
        }

        fn benchStdLookupMiss(comptime size: usize, keys: []const K, miss_keys: []const K, allocator: std.mem.Allocator) !u64 {
            var map = StdMap.init(allocator);
            defer map.deinit();

            for (keys[0..size]) |k| {
                const v = if (is_set) {} else makeValue(@as(u64, if (K == u16) k else if (K == u64) k else 0));
                try map.put(k, v);
            }

            var total_ns: u64 = 0;

            for (0..BENCHMARK_ITERATIONS) |_| {
                var timer = try Timer.start();
                var miss_count: u64 = 0;

                for (miss_keys[0..size]) |k| {
                    if (map.get(k) == null) miss_count += 1;
                }

                total_ns += timer.read();
                std.mem.doNotOptimizeAway(miss_count);
            }

            return total_ns / BENCHMARK_ITERATIONS;
        }

        fn benchStdDelete(comptime size: usize, keys: []const K, allocator: std.mem.Allocator) !u64 {
            var total_ns: u64 = 0;

            for (0..BENCHMARK_ITERATIONS) |_| {
                var map = StdMap.init(allocator);
                defer map.deinit();

                for (keys[0..size]) |k| {
                    const v = if (is_set) {} else makeValue(@as(u64, if (K == u16) k else if (K == u64) k else 0));
                    try map.put(k, v);
                }

                var timer = try Timer.start();

                for (keys[0..size]) |k| {
                    _ = map.remove(k);
                }

                total_ns += timer.read();
            }

            return total_ns / BENCHMARK_ITERATIONS;
        }

        fn benchStdIteration(comptime size: usize, keys: []const K, allocator: std.mem.Allocator) !u64 {
            var map = StdMap.init(allocator);
            defer map.deinit();

            for (keys[0..size]) |k| {
                const v = if (is_set) {} else makeValue(@as(u64, if (K == u16) k else if (K == u64) k else 0));
                try map.put(k, v);
            }

            var total_ns: u64 = 0;

            for (0..BENCHMARK_ITERATIONS) |_| {
                var timer = try Timer.start();
                var count: u64 = 0;

                var iter = map.iterator();
                while (iter.next()) |_| {
                    count += 1;
                }

                total_ns += timer.read();
                std.mem.doNotOptimizeAway(count);
            }

            return total_ns / BENCHMARK_ITERATIONS;
        }

        fn benchStdChurn(comptime size: usize, keys: []const K, allocator: std.mem.Allocator) !u64 {
            var map = StdMap.init(allocator);
            defer map.deinit();

            for (keys[0 .. size / 2]) |k| {
                const v = if (is_set) {} else makeValue(@as(u64, if (K == u16) k else if (K == u64) k else 0));
                try map.put(k, v);
            }

            var total_ns: u64 = 0;
            var rng = makeRng(11111);

            for (0..BENCHMARK_ITERATIONS) |_| {
                var timer = try Timer.start();

                for (0..size) |_| {
                    const idx = rng.random().int(usize) % size;
                    if (rng.random().boolean()) {
                        const v = if (is_set) {} else makeValue(@as(u64, if (K == u16) keys[idx] else if (K == u64) keys[idx] else 0));
                        try map.put(keys[idx], v);
                    } else {
                        _ = map.remove(keys[idx]);
                    }
                }

                total_ns += timer.read();
            }

            return total_ns / BENCHMARK_ITERATIONS;
        }
    };
}

fn keyTypeName(comptime K: type) []const u8 {
    if (K == u16) return "u16";
    if (K == u64) return "u64";
    if (K == []const u8) return "string";
    return "?";
}

fn valueTypeName(comptime V: type) []const u8 {
    if (V == void) return "void (set)";
    if (V == Value4) return "4B";
    if (V == Value64) return "64B";
    if (V == Value256) return "256B";
    return "?";
}

fn runGenericComparison(
    comptime K: type,
    comptime V: type,
    comptime size: usize,
    keys: []const K,
    miss_keys: []const K,
    lookup_order: []const usize,
    allocator: std.mem.Allocator,
) !void {
    const B = GenericBenchmarks(K, V);
    const VB = VerstableBenchmarks(K, V);
    const size_str = comptime formatSize(size);
    // Include Verstable comparison for all key/value combinations (including sets)
    const include_verstable = K == u64 or K == u16;

    std.debug.print("\n  {s} elements:\n", .{size_str});
    if (include_verstable) {
        std.debug.print("  ┌────────────────┬───────────────┬───────────────┬───────────────┬───────────┬───────────┐\n", .{});
        std.debug.print("  │ Operation      │ TheHashTable  │ Verstable (C) │ std.AutoHash  │ vs Verst. │ vs std    │\n", .{});
        std.debug.print("  ├────────────────┼───────────────┼───────────────┼───────────────┼───────────┼───────────┤\n", .{});
    } else {
        std.debug.print("  ┌────────────────┬───────────────┬───────────────┬───────────┐\n", .{});
        std.debug.print("  │ Operation      │ TheHashTable  │ std.AutoHash  │ Speedup   │\n", .{});
        std.debug.print("  ├────────────────┼───────────────┼───────────────┼───────────┤\n", .{});
    }

    // Random Insert
    const ours_insert = try B.benchRandomInsert(size, keys, allocator) / size;
    const std_insert = try B.benchStdRandomInsert(size, keys, allocator) / size;
    if (include_verstable) {
        const vt_insert = try VB.benchRandomInsert(size, keys) / size;
        std.debug.print("  │ Rand. Insert   │", .{});
        printTime(ours_insert);
        std.debug.print("      │", .{});
        printTime(vt_insert);
        std.debug.print("      │", .{});
        printTime(std_insert);
        std.debug.print("      │ {d:>5.2}x    │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(vt_insert)) / @as(f64, @floatFromInt(@max(ours_insert, 1))),
            @as(f64, @floatFromInt(std_insert)) / @as(f64, @floatFromInt(@max(ours_insert, 1))),
        });
    } else {
        std.debug.print("  │ Rand. Insert   │", .{});
        printTime(ours_insert);
        std.debug.print("      │", .{});
        printTime(std_insert);
        std.debug.print("      │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(std_insert)) / @as(f64, @floatFromInt(@max(ours_insert, 1))),
        });
    }

    // Random Lookup
    const ours_lookup = try B.benchRandomLookup(size, keys, lookup_order, allocator) / size;
    const std_lookup = try B.benchStdRandomLookup(size, keys, lookup_order, allocator) / size;
    if (include_verstable) {
        const vt_lookup = try VB.benchRandomLookup(size, keys, lookup_order) / size;
        std.debug.print("  │ Rand. Lookup   │", .{});
        printTime(ours_lookup);
        std.debug.print("      │", .{});
        printTime(vt_lookup);
        std.debug.print("      │", .{});
        printTime(std_lookup);
        std.debug.print("      │ {d:>5.2}x    │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(vt_lookup)) / @as(f64, @floatFromInt(@max(ours_lookup, 1))),
            @as(f64, @floatFromInt(std_lookup)) / @as(f64, @floatFromInt(@max(ours_lookup, 1))),
        });
    } else {
        std.debug.print("  │ Rand. Lookup   │", .{});
        printTime(ours_lookup);
        std.debug.print("      │", .{});
        printTime(std_lookup);
        std.debug.print("      │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(std_lookup)) / @as(f64, @floatFromInt(@max(ours_lookup, 1))),
        });
    }

    // Lookup Miss
    const ours_miss = try B.benchLookupMiss(size, keys, miss_keys, allocator) / size;
    const std_miss = try B.benchStdLookupMiss(size, keys, miss_keys, allocator) / size;
    if (include_verstable) {
        const vt_miss = try VB.benchLookupMiss(size, keys, miss_keys) / size;
        std.debug.print("  │ Lookup Miss    │", .{});
        printTime(ours_miss);
        std.debug.print("      │", .{});
        printTime(vt_miss);
        std.debug.print("      │", .{});
        printTime(std_miss);
        std.debug.print("      │ {d:>5.2}x    │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(vt_miss)) / @as(f64, @floatFromInt(@max(ours_miss, 1))),
            @as(f64, @floatFromInt(std_miss)) / @as(f64, @floatFromInt(@max(ours_miss, 1))),
        });
    } else {
        std.debug.print("  │ Lookup Miss    │", .{});
        printTime(ours_miss);
        std.debug.print("      │", .{});
        printTime(std_miss);
        std.debug.print("      │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(std_miss)) / @as(f64, @floatFromInt(@max(ours_miss, 1))),
        });
    }

    // Delete
    const ours_delete = try B.benchDelete(size, keys, allocator) / size;
    const std_delete = try B.benchStdDelete(size, keys, allocator) / size;
    if (include_verstable) {
        const vt_delete = try VB.benchDelete(size, keys) / size;
        std.debug.print("  │ Delete         │", .{});
        printTime(ours_delete);
        std.debug.print("      │", .{});
        printTime(vt_delete);
        std.debug.print("      │", .{});
        printTime(std_delete);
        std.debug.print("      │ {d:>5.2}x    │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(vt_delete)) / @as(f64, @floatFromInt(@max(ours_delete, 1))),
            @as(f64, @floatFromInt(std_delete)) / @as(f64, @floatFromInt(@max(ours_delete, 1))),
        });
    } else {
        std.debug.print("  │ Delete         │", .{});
        printTime(ours_delete);
        std.debug.print("      │", .{});
        printTime(std_delete);
        std.debug.print("      │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(std_delete)) / @as(f64, @floatFromInt(@max(ours_delete, 1))),
        });
    }

    // Iteration
    const ours_iter = try B.benchIteration(size, keys, allocator) / size;
    const std_iter = try B.benchStdIteration(size, keys, allocator) / size;
    if (include_verstable) {
        const vt_iter = try VB.benchIteration(size, keys) / size;
        std.debug.print("  │ Iteration      │", .{});
        printTime(ours_iter);
        std.debug.print("      │", .{});
        printTime(vt_iter);
        std.debug.print("      │", .{});
        printTime(std_iter);
        std.debug.print("      │ {d:>5.2}x    │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(vt_iter)) / @as(f64, @floatFromInt(@max(ours_iter, 1))),
            @as(f64, @floatFromInt(std_iter)) / @as(f64, @floatFromInt(@max(ours_iter, 1))),
        });
    } else {
        std.debug.print("  │ Iteration      │", .{});
        printTime(ours_iter);
        std.debug.print("      │", .{});
        printTime(std_iter);
        std.debug.print("      │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(std_iter)) / @as(f64, @floatFromInt(@max(ours_iter, 1))),
        });
    }

    // Churn
    const ours_churn = try B.benchChurn(size, keys, allocator) / size;
    const std_churn = try B.benchStdChurn(size, keys, allocator) / size;
    if (include_verstable) {
        const vt_churn = try VB.benchChurn(size, keys) / size;
        std.debug.print("  │ Churn          │", .{});
        printTime(ours_churn);
        std.debug.print("      │", .{});
        printTime(vt_churn);
        std.debug.print("      │", .{});
        printTime(std_churn);
        std.debug.print("      │ {d:>5.2}x    │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(vt_churn)) / @as(f64, @floatFromInt(@max(ours_churn, 1))),
            @as(f64, @floatFromInt(std_churn)) / @as(f64, @floatFromInt(@max(ours_churn, 1))),
        });
        std.debug.print("  └────────────────┴───────────────┴───────────────┴───────────────┴───────────┴───────────┘\n", .{});
    } else {
        std.debug.print("  │ Churn          │", .{});
        printTime(ours_churn);
        std.debug.print("      │", .{});
        printTime(std_churn);
        std.debug.print("      │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(std_churn)) / @as(f64, @floatFromInt(@max(ours_churn, 1))),
        });
        std.debug.print("  └────────────────┴───────────────┴───────────────┴───────────┘\n", .{});
    }
}

fn runAllSizesForKeyValue(
    comptime K: type,
    comptime V: type,
    keys: []const K,
    miss_keys: []const K,
    lookup_order: []const usize,
    allocator: std.mem.Allocator,
) !void {
    const key_name = comptime keyTypeName(K);
    const val_name = comptime valueTypeName(V);

    std.debug.print("\n", .{});
    std.debug.print("════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  {s} key → {s} value\n", .{ key_name, val_name });
    std.debug.print("════════════════════════════════════════════════════════════════════════════════\n", .{});

    try runGenericComparison(K, V, SIZE_10, keys, miss_keys, lookup_order, allocator);

    if (K == u16) {
        try runGenericComparison(K, V, SIZE_1K, keys, miss_keys, lookup_order, allocator);
        try runGenericComparison(K, V, SIZE_65524, keys, miss_keys, lookup_order, allocator);
    } else {
        try runGenericComparison(K, V, SIZE_1K, keys, miss_keys, lookup_order, allocator);
        try runGenericComparison(K, V, SIZE_100K, keys, miss_keys, lookup_order, allocator);
    }
}

fn runComprehensiveBenchmarks(allocator: std.mem.Allocator) !void {
    std.debug.print("\n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("         Comprehensive Key/Value Type Combination Benchmarks                   \n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("  Key types:   u16, u64, string                                                \n", .{});
    std.debug.print("  Value types: void (set), 4B, 64B, 256B                                       \n", .{});
    std.debug.print("  Sizes:       10, 1K, 65524 (u16) / 10, 1K, 100K (u64, string)                \n", .{});
    std.debug.print("  Operations:  Rand Insert, Rand Lookup, Lookup Miss, Delete, Iteration, Churn \n", .{});
    std.debug.print("================================================================================\n", .{});

    // u16 keys (limited to 65536 unique values)
    {
        const max_u16_keys = SIZE_65524;
        const u16_keys = try allocator.alloc(u16, max_u16_keys);
        defer allocator.free(u16_keys);
        const u16_miss_keys = try allocator.alloc(u16, max_u16_keys);
        defer allocator.free(u16_miss_keys);
        const u16_lookup_order = try allocator.alloc(usize, max_u16_keys);
        defer allocator.free(u16_lookup_order);

        var rng = makeRng(12345);
        for (0..max_u16_keys) |i| {
            u16_keys[i] = @truncate(i);
            // Miss keys are offset to avoid overlap - wrap around for u16 max
            u16_miss_keys[i] = @truncate(i + 11); // offset by a prime to create mostly misses
            u16_lookup_order[i] = i;
        }
        rng.random().shuffle(usize, u16_lookup_order);

        try runAllSizesForKeyValue(u16, void, u16_keys, u16_miss_keys, u16_lookup_order, allocator);
        try runAllSizesForKeyValue(u16, Value4, u16_keys, u16_miss_keys, u16_lookup_order, allocator);
        try runAllSizesForKeyValue(u16, Value64, u16_keys, u16_miss_keys, u16_lookup_order, allocator);
        try runAllSizesForKeyValue(u16, Value256, u16_keys, u16_miss_keys, u16_lookup_order, allocator);
    }

    // u64 keys - with Verstable comparison
    {
        const u64_keys = try allocator.alloc(u64, SIZE_100K);
        defer allocator.free(u64_keys);
        const u64_miss_keys = try allocator.alloc(u64, SIZE_100K);
        defer allocator.free(u64_miss_keys);
        const u64_lookup_order = try allocator.alloc(usize, SIZE_100K);
        defer allocator.free(u64_lookup_order);

        var rng = makeRng(12345);
        for (0..SIZE_100K) |i| {
            u64_keys[i] = rng.random().int(u64);
            u64_lookup_order[i] = i;
        }
        var miss_rng = makeRng(99999);
        for (0..SIZE_100K) |i| {
            u64_miss_keys[i] = miss_rng.random().int(u64) | (1 << 63);
        }
        rng.random().shuffle(usize, u64_lookup_order);

        try runAllSizesForKeyValue(u64, void, u64_keys, u64_miss_keys, u64_lookup_order, allocator);
        try runAllSizesForKeyValue(u64, Value4, u64_keys, u64_miss_keys, u64_lookup_order, allocator);
        try runAllSizesForKeyValue(u64, Value64, u64_keys, u64_miss_keys, u64_lookup_order, allocator);
        try runAllSizesForKeyValue(u64, Value256, u64_keys, u64_miss_keys, u64_lookup_order, allocator);
    }

    // String keys
    {
        const key_storage = try allocator.alloc([32]u8, SIZE_100K);
        defer allocator.free(key_storage);
        const miss_key_storage = try allocator.alloc([32]u8, SIZE_100K);
        defer allocator.free(miss_key_storage);

        const string_keys = try allocator.alloc([]const u8, SIZE_100K);
        defer allocator.free(string_keys);
        const string_miss_keys = try allocator.alloc([]const u8, SIZE_100K);
        defer allocator.free(string_miss_keys);
        const string_lookup_order = try allocator.alloc(usize, SIZE_100K);
        defer allocator.free(string_lookup_order);

        var rng = makeRng(12345);
        for (0..SIZE_100K) |i| {
            const rand_val = rng.random().int(u64);
            const slice = std.fmt.bufPrint(&key_storage[i], "key_{d:0>16}", .{rand_val}) catch unreachable;
            string_keys[i] = slice;

            const miss_val = rng.random().int(u64);
            const miss_slice = std.fmt.bufPrint(&miss_key_storage[i], "miss_{d:0>16}", .{miss_val}) catch unreachable;
            string_miss_keys[i] = miss_slice;

            string_lookup_order[i] = i;
        }
        rng.random().shuffle(usize, string_lookup_order);

        try runStringBenchmarksAllSizes(string_keys, string_miss_keys, string_lookup_order, allocator);
    }
}

fn runStringBenchmarksAllSizes(
    keys: []const []const u8,
    miss_keys: []const []const u8,
    lookup_order: []const usize,
    allocator: std.mem.Allocator,
) !void {
    inline for (.{ void, Value4, Value64, Value256 }) |V| {
        const val_name = comptime valueTypeName(V);

        std.debug.print("\n", .{});
        std.debug.print("════════════════════════════════════════════════════════════════════════════════\n", .{});
        std.debug.print("  string key → {s} value\n", .{val_name});
        std.debug.print("════════════════════════════════════════════════════════════════════════════════\n", .{});

        try runStringBenchmarksSingle(V, SIZE_10, keys, miss_keys, lookup_order, allocator);
        try runStringBenchmarksSingle(V, SIZE_1K, keys, miss_keys, lookup_order, allocator);
        try runStringBenchmarksSingle(V, SIZE_100K, keys, miss_keys, lookup_order, allocator);
    }
}

fn runStringBenchmarksSingle(
    comptime V: type,
    comptime size: usize,
    keys: []const []const u8,
    miss_keys: []const []const u8,
    lookup_order: []const usize,
    allocator: std.mem.Allocator,
) !void {
    const size_str = comptime formatSize(size);
    const Map = TheHashTable([]const u8, V);
    const StdMap = std.StringHashMap(V);
    const VB = VerstableBenchmarks([]const u8, V);
    const is_set = V == void;
    // Include Verstable comparison for all value sizes (including sets)
    const include_verstable = true;

    std.debug.print("\n  {s} elements:\n", .{size_str});
    if (include_verstable) {
        std.debug.print("  ┌────────────────┬───────────────┬───────────────┬───────────────┬───────────┬───────────┐\n", .{});
        std.debug.print("  │ Operation      │ TheHashTable  │ Verstable (C) │ std.StringHash│ vs Verst. │ vs std    │\n", .{});
        std.debug.print("  ├────────────────┼───────────────┼───────────────┼───────────────┼───────────┼───────────┤\n", .{});
    } else {
        std.debug.print("  ┌────────────────┬───────────────┬───────────────┬───────────┐\n", .{});
        std.debug.print("  │ Operation      │ TheHashTable  │ std.StringHash│ Speedup   │\n", .{});
        std.debug.print("  ├────────────────┼───────────────┼───────────────┼───────────┤\n", .{});
    }

    // Random Insert - TheHashTable
    var ours_insert: u64 = 0;
    for (0..BENCHMARK_ITERATIONS) |_| {
        var map = Map.init(allocator);
        defer map.deinit();
        var timer = try Timer.start();
        for (keys[0..size]) |k| {
            if (is_set) {
                try map.add(k);
            } else {
                try map.put(k, V.fromU64(0));
            }
        }
        ours_insert += timer.read();
    }
    ours_insert = ours_insert / BENCHMARK_ITERATIONS / size;

    // Random Insert - Verstable (for all value types now)
    const vt_insert = if (include_verstable) try VB.benchRandomInsert(size, keys) / size else 0;

    // Random Insert - std
    var std_insert: u64 = 0;
    for (0..BENCHMARK_ITERATIONS) |_| {
        var map = StdMap.init(allocator);
        defer map.deinit();
        var timer = try Timer.start();
        for (keys[0..size]) |k| {
            const v = if (is_set) {} else V.fromU64(0);
            try map.put(k, v);
        }
        std_insert += timer.read();
    }
    std_insert = std_insert / BENCHMARK_ITERATIONS / size;

    std.debug.print("  │ Rand. Insert   │", .{});
    printTime(ours_insert);
    std.debug.print("      │", .{});
    if (include_verstable) {
        printTime(vt_insert);
        std.debug.print("      │", .{});
        printTime(std_insert);
        std.debug.print("      │ {d:>5.2}x    │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(vt_insert)) / @as(f64, @floatFromInt(@max(ours_insert, 1))),
            @as(f64, @floatFromInt(std_insert)) / @as(f64, @floatFromInt(@max(ours_insert, 1))),
        });
    } else {
        printTime(std_insert);
        std.debug.print("      │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(std_insert)) / @as(f64, @floatFromInt(@max(ours_insert, 1))),
        });
    }

    // Random Lookup
    var ours_map = Map.init(allocator);
    defer ours_map.deinit();
    var std_map = StdMap.init(allocator);
    defer std_map.deinit();
    for (keys[0..size]) |k| {
        if (is_set) {
            try ours_map.add(k);
        } else {
            try ours_map.put(k, V.fromU64(0));
        }
        const v = if (is_set) {} else V.fromU64(0);
        try std_map.put(k, v);
    }

    var ours_lookup: u64 = 0;
    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var found: u64 = 0;
        for (lookup_order[0..size]) |idx| {
            if (is_set) {
                if (ours_map.contains(keys[idx])) found += 1;
            } else {
                if (ours_map.get(keys[idx]) != null) found += 1;
            }
        }
        ours_lookup += timer.read();
        std.mem.doNotOptimizeAway(found);
    }
    ours_lookup = ours_lookup / BENCHMARK_ITERATIONS / size;

    const vt_lookup = if (include_verstable) try VB.benchRandomLookup(size, keys, lookup_order) / size else 0;

    var std_lookup: u64 = 0;
    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var found: u64 = 0;
        for (lookup_order[0..size]) |idx| {
            if (std_map.get(keys[idx]) != null) found += 1;
        }
        std_lookup += timer.read();
        std.mem.doNotOptimizeAway(found);
    }
    std_lookup = std_lookup / BENCHMARK_ITERATIONS / size;

    std.debug.print("  │ Rand. Lookup   │", .{});
    printTime(ours_lookup);
    std.debug.print("      │", .{});
    if (include_verstable) {
        printTime(vt_lookup);
        std.debug.print("      │", .{});
        printTime(std_lookup);
        std.debug.print("      │ {d:>5.2}x    │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(vt_lookup)) / @as(f64, @floatFromInt(@max(ours_lookup, 1))),
            @as(f64, @floatFromInt(std_lookup)) / @as(f64, @floatFromInt(@max(ours_lookup, 1))),
        });
    } else {
        printTime(std_lookup);
        std.debug.print("      │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(std_lookup)) / @as(f64, @floatFromInt(@max(ours_lookup, 1))),
        });
    }

    // Lookup Miss
    var ours_miss: u64 = 0;
    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var miss_count: u64 = 0;
        for (miss_keys[0..size]) |k| {
            if (is_set) {
                if (!ours_map.contains(k)) miss_count += 1;
            } else {
                if (ours_map.get(k) == null) miss_count += 1;
            }
        }
        ours_miss += timer.read();
        std.mem.doNotOptimizeAway(miss_count);
    }
    ours_miss = ours_miss / BENCHMARK_ITERATIONS / size;

    const vt_miss = if (include_verstable) try VB.benchLookupMiss(size, keys, miss_keys) / size else 0;

    var std_miss: u64 = 0;
    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var miss_count: u64 = 0;
        for (miss_keys[0..size]) |k| {
            if (std_map.get(k) == null) miss_count += 1;
        }
        std_miss += timer.read();
        std.mem.doNotOptimizeAway(miss_count);
    }
    std_miss = std_miss / BENCHMARK_ITERATIONS / size;

    std.debug.print("  │ Lookup Miss    │", .{});
    printTime(ours_miss);
    std.debug.print("      │", .{});
    if (include_verstable) {
        printTime(vt_miss);
        std.debug.print("      │", .{});
        printTime(std_miss);
        std.debug.print("      │ {d:>5.2}x    │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(vt_miss)) / @as(f64, @floatFromInt(@max(ours_miss, 1))),
            @as(f64, @floatFromInt(std_miss)) / @as(f64, @floatFromInt(@max(ours_miss, 1))),
        });
    } else {
        printTime(std_miss);
        std.debug.print("      │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(std_miss)) / @as(f64, @floatFromInt(@max(ours_miss, 1))),
        });
    }

    // Delete
    var ours_delete: u64 = 0;
    for (0..BENCHMARK_ITERATIONS) |_| {
        var map = Map.init(allocator);
        defer map.deinit();
        for (keys[0..size]) |k| {
            if (is_set) {
                try map.add(k);
            } else {
                try map.put(k, V.fromU64(0));
            }
        }
        var timer = try Timer.start();
        for (keys[0..size]) |k| {
            _ = map.remove(k);
        }
        ours_delete += timer.read();
    }
    ours_delete = ours_delete / BENCHMARK_ITERATIONS / size;

    const vt_delete = if (include_verstable) try VB.benchDelete(size, keys) / size else 0;

    var std_delete: u64 = 0;
    for (0..BENCHMARK_ITERATIONS) |_| {
        var map = StdMap.init(allocator);
        defer map.deinit();
        for (keys[0..size]) |k| {
            const v = if (is_set) {} else V.fromU64(0);
            try map.put(k, v);
        }
        var timer = try Timer.start();
        for (keys[0..size]) |k| {
            _ = map.remove(k);
        }
        std_delete += timer.read();
    }
    std_delete = std_delete / BENCHMARK_ITERATIONS / size;

    std.debug.print("  │ Delete         │", .{});
    printTime(ours_delete);
    std.debug.print("      │", .{});
    if (include_verstable) {
        printTime(vt_delete);
        std.debug.print("      │", .{});
        printTime(std_delete);
        std.debug.print("      │ {d:>5.2}x    │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(vt_delete)) / @as(f64, @floatFromInt(@max(ours_delete, 1))),
            @as(f64, @floatFromInt(std_delete)) / @as(f64, @floatFromInt(@max(ours_delete, 1))),
        });
    } else {
        printTime(std_delete);
        std.debug.print("      │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(std_delete)) / @as(f64, @floatFromInt(@max(ours_delete, 1))),
        });
    }

    // Iteration
    var ours_iter: u64 = 0;
    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var count: u64 = 0;
        var iter = ours_map.iterator();
        while (iter.next()) |_| {
            count += 1;
        }
        ours_iter += timer.read();
        std.mem.doNotOptimizeAway(count);
    }
    ours_iter = ours_iter / BENCHMARK_ITERATIONS / size;

    const vt_iter = if (include_verstable) try VB.benchIteration(size, keys) / size else 0;

    var std_iter: u64 = 0;
    for (0..BENCHMARK_ITERATIONS) |_| {
        var timer = try Timer.start();
        var count: u64 = 0;
        var iter = std_map.iterator();
        while (iter.next()) |_| {
            count += 1;
        }
        std_iter += timer.read();
        std.mem.doNotOptimizeAway(count);
    }
    std_iter = std_iter / BENCHMARK_ITERATIONS / size;

    std.debug.print("  │ Iteration      │", .{});
    printTime(ours_iter);
    std.debug.print("      │", .{});
    if (include_verstable) {
        printTime(vt_iter);
        std.debug.print("      │", .{});
        printTime(std_iter);
        std.debug.print("      │ {d:>5.2}x    │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(vt_iter)) / @as(f64, @floatFromInt(@max(ours_iter, 1))),
            @as(f64, @floatFromInt(std_iter)) / @as(f64, @floatFromInt(@max(ours_iter, 1))),
        });
    } else {
        printTime(std_iter);
        std.debug.print("      │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(std_iter)) / @as(f64, @floatFromInt(@max(ours_iter, 1))),
        });
    }

    // Churn
    var ours_churn: u64 = 0;
    {
        var map = Map.init(allocator);
        defer map.deinit();
        for (keys[0 .. size / 2]) |k| {
            if (is_set) {
                try map.add(k);
            } else {
                try map.put(k, V.fromU64(0));
            }
        }
        var rng = makeRng(11111);
        for (0..BENCHMARK_ITERATIONS) |_| {
            var timer = try Timer.start();
            for (0..size) |_| {
                const idx = rng.random().int(usize) % size;
                if (rng.random().boolean()) {
                    if (is_set) {
                        try map.add(keys[idx]);
                    } else {
                        try map.put(keys[idx], V.fromU64(0));
                    }
                } else {
                    _ = map.remove(keys[idx]);
                }
            }
            ours_churn += timer.read();
        }
    }
    ours_churn = ours_churn / BENCHMARK_ITERATIONS / size;

    const vt_churn = if (include_verstable) try VB.benchChurn(size, keys) / size else 0;

    var std_churn: u64 = 0;
    {
        var map = StdMap.init(allocator);
        defer map.deinit();
        for (keys[0 .. size / 2]) |k| {
            const v = if (is_set) {} else V.fromU64(0);
            try map.put(k, v);
        }
        var rng = makeRng(11111);
        for (0..BENCHMARK_ITERATIONS) |_| {
            var timer = try Timer.start();
            for (0..size) |_| {
                const idx = rng.random().int(usize) % size;
                if (rng.random().boolean()) {
                    const v = if (is_set) {} else V.fromU64(0);
                    try map.put(keys[idx], v);
                } else {
                    _ = map.remove(keys[idx]);
                }
            }
            std_churn += timer.read();
        }
    }
    std_churn = std_churn / BENCHMARK_ITERATIONS / size;

    std.debug.print("  │ Churn          │", .{});
    printTime(ours_churn);
    std.debug.print("      │", .{});
    if (include_verstable) {
        printTime(vt_churn);
        std.debug.print("      │", .{});
        printTime(std_churn);
        std.debug.print("      │ {d:>5.2}x    │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(vt_churn)) / @as(f64, @floatFromInt(@max(ours_churn, 1))),
            @as(f64, @floatFromInt(std_churn)) / @as(f64, @floatFromInt(@max(ours_churn, 1))),
        });
        std.debug.print("  └────────────────┴───────────────┴───────────────┴───────────────┴───────────┴───────────┘\n", .{});
    } else {
        printTime(std_churn);
        std.debug.print("      │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(std_churn)) / @as(f64, @floatFromInt(@max(ours_churn, 1))),
        });
        std.debug.print("  └────────────────┴───────────────┴───────────────┴───────────┘\n", .{});
    }
}

// ============================================================================
// Main Benchmark Runner
// ============================================================================

pub fn main() !void {
    const allocator = std.heap.c_allocator;

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
    std.debug.print("  - Test sizes:           10, 100, 1K, 10K, 100K\n", .{});
    std.debug.print("\n", .{});

    // Warmup
    std.debug.print("Warming up...\n", .{});
    for (0..WARMUP_ITERATIONS) |_| {
        _ = try benchSequentialInsert(SIZE_100K, allocator);
    }
    std.debug.print("\n", .{});

    try runComprehensiveBenchmarks(allocator);

    std.debug.print("\n", .{});
}
