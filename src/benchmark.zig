//! TheHashTable Benchmark Suite
//!
//! Comprehensive performance tests for comparing with other hash table implementations.
//! Run with: zig build bench

const std = @import("std");
const TheHashTable = @import("root.zig").TheHashTable;
const Timer = std.time.Timer;

const vt = @cImport({
    @cInclude("verstable_wrapper.h");
});

// ============================================================================
// Configuration
// ============================================================================

const WARMUP_ITERATIONS = 3;
const BENCHMARK_ITERATIONS = 5;
const SIZE_10: usize = 10;
const SIZE_1K: usize = 1_000;
const SIZE_65524: usize = 65_524;
const SIZE_100K: usize = 100_000;

// ============================================================================
// Value Types
// ============================================================================

const Value4 = extern struct {
    data: [4]u8 = .{ 0, 0, 0, 0 },
    fn fromU64(v: u64) Value4 {
        var r: Value4 = .{};
        @memcpy(&r.data, @as(*const [4]u8, @ptrCast(&v)));
        return r;
    }
};

const Value64 = extern struct {
    data: [64]u8 = .{0} ** 64,
    fn fromU64(v: u64) Value64 {
        var r: Value64 = .{};
        const bytes: [8]u8 = @bitCast(v);
        inline for (0..8) |j| {
            inline for (0..8) |i| r.data[j * 8 + i] = bytes[i];
        }
        return r;
    }
};

const Value256 = extern struct {
    data: [256]u8 = .{0} ** 256,
    fn fromU64(v: u64) Value256 {
        var r: Value256 = .{};
        const bytes: [8]u8 = @bitCast(v);
        inline for (0..32) |j| {
            inline for (0..8) |i| r.data[j * 8 + i] = bytes[i];
        }
        return r;
    }
};

fn makeValue(comptime V: type, i: u64) V {
    if (V == void) return {};
    return V.fromU64(i);
}

// ============================================================================
// Verstable C Wrapper
// ============================================================================

fn VerstableWrapper(comptime K: type, comptime V: type) type {
    const key_name = if (K == u64) "u64" else if (K == u16) "u16" else if (K == []const u8) "str" else @compileError("Unsupported key type");
    const val_name = if (V == void) "void" else if (V == Value4) "val4" else if (V == Value64) "val64" else if (V == Value256) "val256" else @compileError("Unsupported value type");
    const prefix = "vt_" ++ key_name ++ "_" ++ val_name ++ "_";

    return struct {
        const Self = @This();
        map: vt.vt_generic_map,

        const initFn = @field(vt, prefix ++ "init");
        const cleanupFn = @field(vt, prefix ++ "cleanup");
        const insertFn = @field(vt, prefix ++ "insert");
        const getFn = @field(vt, prefix ++ "get");
        const eraseFn = @field(vt, prefix ++ "erase");
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
            if (K == []const u8) {
                return if (V == void) insertFn(&self.map, key.ptr, key.len) != 0 else insertFn(&self.map, key.ptr, key.len, &val.data) != 0;
            } else {
                return if (V == void) insertFn(&self.map, key) != 0 else insertFn(&self.map, key, &val.data) != 0;
            }
        }
        pub fn get(self: *Self, key: K) bool {
            return if (K == []const u8) getFn(&self.map, key.ptr, key.len) != 0 else getFn(&self.map, key) != 0;
        }
        pub fn erase(self: *Self, key: K) bool {
            return if (K == []const u8) eraseFn(&self.map, key.ptr, key.len) != 0 else eraseFn(&self.map, key) != 0;
        }
        pub fn iterCount(self: *Self) u64 {
            var count: u64 = 0;
            var iter = firstFn(&self.map);
            while (is_endFn(iter) == 0) : (iter = nextFn(iter)) count += 1;
            return count;
        }
    };
}

// ============================================================================
// Generic Benchmark Runner
// ============================================================================

fn Benchmarks(comptime K: type, comptime V: type) type {
    return struct {
        const is_set = V == void;
        const is_string = K == []const u8;

        fn keyToU64(key: K) u64 {
            return if (K == u16 or K == u64) key else 0;
        }

        // TheHashTable benchmarks
        fn benchOurs(comptime Op: enum { insert, lookup, miss, delete, iter, churn }, comptime size: usize, keys: []const K, extra: anytype, alloc: std.mem.Allocator) !u64 {
            const Map = TheHashTable(K, V);
            var total: u64 = 0;

            for (0..BENCHMARK_ITERATIONS) |_| {
                var map = Map.init(alloc);
                defer map.deinit();

                // Setup (except for insert which measures this)
                if (Op != .insert) {
                    const setup_keys = if (Op == .churn) keys[0 .. size / 2] else keys[0..size];
                    for (setup_keys) |k| {
                        if (is_set) try map.add(k) else try map.put(k, makeValue(V, keyToU64(k)));
                    }
                }

                var timer = try Timer.start();
                switch (Op) {
                    .insert => for (keys[0..size]) |k| {
                        if (is_set) try map.add(k) else try map.put(k, makeValue(V, keyToU64(k)));
                    },
                    .lookup => {
                        var found: u64 = 0;
                        for (extra[0..size]) |idx| {
                            if (is_set) {
                                if (map.contains(keys[idx])) found += 1;
                            } else {
                                if (map.get(keys[idx]) != null) found += 1;
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                    .miss => {
                        var miss: u64 = 0;
                        const miss_keys: []const K = extra;
                        for (miss_keys[0..size]) |k| {
                            if (is_set) {
                                if (!map.contains(k)) miss += 1;
                            } else {
                                if (map.get(k) == null) miss += 1;
                            }
                        }
                        std.mem.doNotOptimizeAway(miss);
                    },
                    .delete => for (keys[0..size]) |k| {
                        _ = map.remove(k);
                    },
                    .iter => {
                        var count: u64 = 0;
                        var it = map.iterator();
                        while (it.next()) |_| count += 1;
                        std.mem.doNotOptimizeAway(count);
                    },
                    .churn => {
                        var rng = makeRng(11111);
                        for (0..size) |_| {
                            const idx = rng.random().int(usize) % size;
                            if (rng.random().boolean()) {
                                if (is_set) try map.add(keys[idx]) else try map.put(keys[idx], makeValue(V, keyToU64(keys[idx])));
                            } else _ = map.remove(keys[idx]);
                        }
                    },
                }
                total += timer.read();
            }
            return total / BENCHMARK_ITERATIONS;
        }

        // std.HashMap benchmarks
        fn benchStd(comptime Op: enum { insert, lookup, miss, delete, iter, churn }, comptime size: usize, keys: []const K, extra: anytype, alloc: std.mem.Allocator) !u64 {
            const StdMap = if (is_string) std.StringHashMap(V) else std.AutoHashMap(K, V);
            var total: u64 = 0;

            for (0..BENCHMARK_ITERATIONS) |_| {
                var map = StdMap.init(alloc);
                defer map.deinit();

                if (Op != .insert) {
                    const setup_keys = if (Op == .churn) keys[0 .. size / 2] else keys[0..size];
                    for (setup_keys) |k| try map.put(k, makeValue(V, keyToU64(k)));
                }

                var timer = try Timer.start();
                switch (Op) {
                    .insert => for (keys[0..size]) |k| {
                        try map.put(k, makeValue(V, keyToU64(k)));
                    },
                    .lookup => {
                        var found: u64 = 0;
                        for (extra[0..size]) |idx| if (map.get(keys[idx]) != null) {
                            found += 1;
                        };
                        std.mem.doNotOptimizeAway(found);
                    },
                    .miss => {
                        var miss: u64 = 0;
                        const miss_keys: []const K = extra;
                        for (miss_keys[0..size]) |k| if (map.get(k) == null) {
                            miss += 1;
                        };
                        std.mem.doNotOptimizeAway(miss);
                    },
                    .delete => for (keys[0..size]) |k| {
                        _ = map.remove(k);
                    },
                    .iter => {
                        var count: u64 = 0;
                        var it = map.iterator();
                        while (it.next()) |_| count += 1;
                        std.mem.doNotOptimizeAway(count);
                    },
                    .churn => {
                        var rng = makeRng(11111);
                        for (0..size) |_| {
                            const idx = rng.random().int(usize) % size;
                            if (rng.random().boolean()) {
                                try map.put(keys[idx], makeValue(V, keyToU64(keys[idx])));
                            } else _ = map.remove(keys[idx]);
                        }
                    },
                }
                total += timer.read();
            }
            return total / BENCHMARK_ITERATIONS;
        }

        // Verstable benchmarks
        fn benchVt(comptime Op: enum { insert, lookup, miss, delete, iter, churn }, comptime size: usize, keys: []const K, extra: anytype) !u64 {
            const VtMap = VerstableWrapper(K, V);
            var total: u64 = 0;

            for (0..BENCHMARK_ITERATIONS) |_| {
                var map = VtMap.init();
                defer map.deinit();

                if (Op != .insert) {
                    const setup_keys = if (Op == .churn) keys[0 .. size / 2] else keys[0..size];
                    for (setup_keys) |k| _ = map.insert(k, makeValue(V, keyToU64(k)));
                }

                var timer = try Timer.start();
                switch (Op) {
                    .insert => for (keys[0..size]) |k| {
                        _ = map.insert(k, makeValue(V, keyToU64(k)));
                    },
                    .lookup => {
                        var found: u64 = 0;
                        for (extra[0..size]) |idx| if (map.get(keys[idx])) {
                            found += 1;
                        };
                        std.mem.doNotOptimizeAway(found);
                    },
                    .miss => {
                        var miss: u64 = 0;
                        const miss_keys: []const K = extra;
                        for (miss_keys[0..size]) |k| if (!map.get(k)) {
                            miss += 1;
                        };
                        std.mem.doNotOptimizeAway(miss);
                    },
                    .delete => for (keys[0..size]) |k| {
                        _ = map.erase(k);
                    },
                    .iter => {
                        const count = map.iterCount();
                        std.mem.doNotOptimizeAway(count);
                    },
                    .churn => {
                        var rng = makeRng(11111);
                        for (0..size) |_| {
                            const idx = rng.random().int(usize) % size;
                            if (rng.random().boolean()) {
                                _ = map.insert(keys[idx], makeValue(V, keyToU64(keys[idx])));
                            } else _ = map.erase(keys[idx]);
                        }
                    },
                }
                total += timer.read();
            }
            return total / BENCHMARK_ITERATIONS;
        }
    };
}

// ============================================================================
// Output Helpers
// ============================================================================

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

fn printRow(name: []const u8, ours: u64, vt_val: ?u64, std_val: u64) void {
    std.debug.print("  │ {s:<14} │", .{name});
    printTime(ours);
    std.debug.print("      │", .{});
    if (vt_val) |v| {
        printTime(v);
        std.debug.print("      │", .{});
    }
    printTime(std_val);
    const ours_f = @as(f64, @floatFromInt(@max(ours, 1)));
    if (vt_val) |v| {
        std.debug.print("      │ {d:>5.2}x    │ {d:>5.2}x    │\n", .{
            @as(f64, @floatFromInt(v)) / ours_f,
            @as(f64, @floatFromInt(std_val)) / ours_f,
        });
    } else {
        std.debug.print("      │ {d:>5.2}x    │\n", .{@as(f64, @floatFromInt(std_val)) / ours_f});
    }
}

fn formatSize(size: usize) []const u8 {
    return switch (size) {
        10 => "10",
        1_000 => "1K",
        65_524 => "65524",
        100_000 => "100K",
        else => "?",
    };
}

fn keyTypeName(comptime K: type) []const u8 {
    return if (K == u16) "u16" else if (K == u64) "u64" else if (K == []const u8) "string" else "?";
}

fn valueTypeName(comptime V: type) []const u8 {
    return if (V == void) "void (set)" else if (V == Value4) "4B" else if (V == Value64) "64B" else if (V == Value256) "256B" else "?";
}

const Xoshiro = std.Random.Xoshiro256;
fn makeRng(seed: u64) Xoshiro {
    return Xoshiro.init(seed);
}

// ============================================================================
// Benchmark Runner
// ============================================================================

fn runComparison(
    comptime K: type,
    comptime V: type,
    comptime size: usize,
    keys: []const K,
    miss_keys: []const K,
    lookup_order: []const usize,
    allocator: std.mem.Allocator,
) !void {
    const B = Benchmarks(K, V);
    const size_str = comptime formatSize(size);
    const include_vt = K == u64 or K == u16 or K == []const u8;
    const std_name = if (K == []const u8) "std.StringHash" else "std.AutoHash ";

    std.debug.print("\n  {s} elements:\n", .{size_str});
    if (include_vt) {
        std.debug.print("  ┌────────────────┬───────────────┬───────────────┬───────────────┬───────────┬───────────┐\n", .{});
        std.debug.print("  │ Operation      │ TheHashTable  │ Verstable (C) │ {s} │ vs Verst. │ vs std    │\n", .{std_name});
        std.debug.print("  ├────────────────┼───────────────┼───────────────┼───────────────┼───────────┼───────────┤\n", .{});
    } else {
        std.debug.print("  ┌────────────────┬───────────────┬───────────────┬───────────┐\n", .{});
        std.debug.print("  │ Operation      │ TheHashTable  │ {s}│ Speedup   │\n", .{std_name});
        std.debug.print("  ├────────────────┼───────────────┼───────────────┼───────────┤\n", .{});
    }

    const ops = [_]struct { name: []const u8, op: @TypeOf(.insert) }{
        .{ .name = "Rand. Insert", .op = .insert },
        .{ .name = "Rand. Lookup", .op = .lookup },
        .{ .name = "Lookup Miss", .op = .miss },
        .{ .name = "Delete", .op = .delete },
        .{ .name = "Iteration", .op = .iter },
        .{ .name = "Churn", .op = .churn },
    };

    inline for (ops) |o| {
        const extra = if (o.op == .miss) miss_keys else if (o.op == .lookup) lookup_order else {};
        const ours = try B.benchOurs(o.op, size, keys, extra, allocator) / size;
        const std_val = try B.benchStd(o.op, size, keys, extra, allocator) / size;
        const vt_val: ?u64 = if (include_vt) try B.benchVt(o.op, size, keys, extra) / size else null;
        printRow(o.name, ours, vt_val, std_val);
    }

    if (include_vt) {
        std.debug.print("  └────────────────┴───────────────┴───────────────┴───────────────┴───────────┴───────────┘\n", .{});
    } else {
        std.debug.print("  └────────────────┴───────────────┴───────────────┴───────────┘\n", .{});
    }
}

fn runAllSizes(
    comptime K: type,
    comptime V: type,
    keys: []const K,
    miss_keys: []const K,
    lookup_order: []const usize,
    allocator: std.mem.Allocator,
) !void {
    std.debug.print("\n════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  {s} key → {s} value\n", .{ keyTypeName(K), valueTypeName(V) });
    std.debug.print("════════════════════════════════════════════════════════════════════════════════\n", .{});

    try runComparison(K, V, SIZE_10, keys, miss_keys, lookup_order, allocator);
    try runComparison(K, V, SIZE_1K, keys, miss_keys, lookup_order, allocator);
    if (K == u16) {
        try runComparison(K, V, SIZE_65524, keys, miss_keys, lookup_order, allocator);
    } else {
        try runComparison(K, V, SIZE_100K, keys, miss_keys, lookup_order, allocator);
    }
}

fn runComprehensiveBenchmarks(allocator: std.mem.Allocator) !void {
    std.debug.print("\n================================================================================\n", .{});
    std.debug.print("         Comprehensive Key/Value Type Combination Benchmarks                   \n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("  Key types:   u16, u64, string                                                \n", .{});
    std.debug.print("  Value types: void (set), 4B, 64B, 256B                                       \n", .{});
    std.debug.print("  Sizes:       10, 1K, 65524 (u16) / 10, 1K, 100K (u64, string)                \n", .{});
    std.debug.print("  Operations:  Rand Insert, Rand Lookup, Lookup Miss, Delete, Iteration, Churn \n", .{});
    std.debug.print("================================================================================\n", .{});

    // u16 keys
    {
        const u16_keys = try allocator.alloc(u16, SIZE_65524);
        defer allocator.free(u16_keys);
        const u16_miss = try allocator.alloc(u16, SIZE_65524);
        defer allocator.free(u16_miss);
        const u16_order = try allocator.alloc(usize, SIZE_65524);
        defer allocator.free(u16_order);

        var rng = makeRng(12345);
        for (0..SIZE_65524) |i| {
            u16_keys[i] = @truncate(i);
            u16_miss[i] = @truncate(i + 11);
            u16_order[i] = i;
        }
        rng.random().shuffle(usize, u16_order);

        inline for (.{ void, Value4, Value64, Value256 }) |V| {
            try runAllSizes(u16, V, u16_keys, u16_miss, u16_order, allocator);
        }
    }

    // u64 keys
    {
        const u64_keys = try allocator.alloc(u64, SIZE_100K);
        defer allocator.free(u64_keys);
        const u64_miss = try allocator.alloc(u64, SIZE_100K);
        defer allocator.free(u64_miss);
        const u64_order = try allocator.alloc(usize, SIZE_100K);
        defer allocator.free(u64_order);

        var rng = makeRng(12345);
        var miss_rng = makeRng(99999);
        for (0..SIZE_100K) |i| {
            u64_keys[i] = rng.random().int(u64);
            u64_miss[i] = miss_rng.random().int(u64) | (1 << 63);
            u64_order[i] = i;
        }
        rng.random().shuffle(usize, u64_order);

        inline for (.{ void, Value4, Value64, Value256 }) |V| {
            try runAllSizes(u64, V, u64_keys, u64_miss, u64_order, allocator);
        }
    }

    // String keys
    {
        const key_storage = try allocator.alloc([32]u8, SIZE_100K);
        defer allocator.free(key_storage);
        const miss_storage = try allocator.alloc([32]u8, SIZE_100K);
        defer allocator.free(miss_storage);
        const str_keys = try allocator.alloc([]const u8, SIZE_100K);
        defer allocator.free(str_keys);
        const str_miss = try allocator.alloc([]const u8, SIZE_100K);
        defer allocator.free(str_miss);
        const str_order = try allocator.alloc(usize, SIZE_100K);
        defer allocator.free(str_order);

        var rng = makeRng(12345);
        for (0..SIZE_100K) |i| {
            str_keys[i] = std.fmt.bufPrint(&key_storage[i], "key_{d:0>16}", .{rng.random().int(u64)}) catch unreachable;
            str_miss[i] = std.fmt.bufPrint(&miss_storage[i], "miss_{d:0>16}", .{rng.random().int(u64)}) catch unreachable;
            str_order[i] = i;
        }
        rng.random().shuffle(usize, str_order);

        inline for (.{ void, Value4, Value64, Value256 }) |V| {
            try runAllSizes([]const u8, V, str_keys, str_miss, str_order, allocator);
        }
    }
}

// ============================================================================
// Main
// ============================================================================

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    std.debug.print("\n================================================================================\n", .{});
    std.debug.print("                      TheHashTable Benchmark Suite                              \n", .{});
    std.debug.print("                                                                                \n", .{});
    std.debug.print("  Comparing:                                                                    \n", .{});
    std.debug.print("  - TheHashTable (Zig port)                                                     \n", .{});
    std.debug.print("  - Verstable (C original): https://github.com/JacksonAllan/Verstable           \n", .{});
    std.debug.print("  - std.AutoHashMap (Zig standard library)                                      \n", .{});
    std.debug.print("================================================================================\n\n", .{});

    std.debug.print("Configuration:\n", .{});
    std.debug.print("  - Warmup iterations:    {d}\n", .{WARMUP_ITERATIONS});
    std.debug.print("  - Benchmark iterations: {d}\n", .{BENCHMARK_ITERATIONS});
    std.debug.print("  - Test sizes:           10, 1K, 65524/100K\n\n", .{});

    std.debug.print("Warming up...\n", .{});
    for (0..WARMUP_ITERATIONS) |_| {
        var map = TheHashTable(u64, u64).init(allocator);
        defer map.deinit();
        for (0..SIZE_100K) |i| try map.put(i, i);
    }

    try runComprehensiveBenchmarks(allocator);
    std.debug.print("\n", .{});
}
