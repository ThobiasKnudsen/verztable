//! TheHashTable Benchmark Suite
//!
//! Comprehensive performance tests for comparing with other hash table implementations.
//! Run with: zig build benchmark

const std = @import("std");
const TheHashTable = @import("root.zig").TheHashTable;
const Timer = std.time.Timer;

const cpp = @cImport({
    @cInclude("cpp_hashtables_wrapper.h");
});

// ============================================================================
// Configuration
// ============================================================================

const WARMUP_ITERATIONS = 3;
const BENCHMARK_ITERATIONS = 15;
const SIZE_100: usize = 100;
const SIZE_1K: usize = 1_000; // Used for memory benchmarks
const SIZE_3K: usize = 3_000;
const SIZE_100K: usize = 100_000;
const SIZE_1M: usize = 1_000_000;

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

fn makeValue(comptime V: type, i: u64) V {
    if (V == void) return {};
    return V.fromU64(i);
}

// ============================================================================
// C++ Hash Table Wrappers (Abseil, Boost, Ankerl)
// ============================================================================

fn CppWrapper(comptime lib_prefix: []const u8, comptime K: type, comptime V: type) type {
    const key_name = if (K == u32) "u32" else if (K == u64) "u64" else if (K == []const u8) "str" else @compileError("Unsupported key type");
    const val_name = if (V == void) "void" else if (V == Value4) "val4" else if (V == Value64) "val64" else @compileError("Unsupported value type");
    const prefix = lib_prefix ++ "_" ++ key_name ++ "_" ++ val_name ++ "_";

    return struct {
        const Self = @This();
        handle: cpp.cpp_map_handle,

        const initFn = @field(cpp, prefix ++ "init");
        const cleanupFn = @field(cpp, prefix ++ "cleanup");
        const insertFn = @field(cpp, prefix ++ "insert");
        const getFn = @field(cpp, prefix ++ "get");
        const eraseFn = @field(cpp, prefix ++ "erase");
        const iterCountFn = @field(cpp, prefix ++ "iter_count");
        const memoryFn = @field(cpp, prefix ++ "memory");

        pub fn init() Self {
            return .{ .handle = initFn() };
        }
        pub fn deinit(self: *Self) void {
            cleanupFn(self.handle);
        }
        pub fn insert(self: *Self, key: K, val: V) bool {
            if (K == []const u8) {
                return if (V == void) insertFn(self.handle, key.ptr, key.len) != 0 else insertFn(self.handle, key.ptr, key.len, &val.data) != 0;
            } else if (K == u32 or K == u64) {
                return if (V == void) insertFn(self.handle, key) != 0 else insertFn(self.handle, key, &val.data) != 0;
            } else {
                @compileError("Unsupported key type");
            }
        }
        pub fn get(self: *Self, key: K) bool {
            if (K == []const u8) {
                return getFn(self.handle, key.ptr, key.len) != 0;
            } else if (K == u32 or K == u64) {
                return getFn(self.handle, key) != 0;
            } else {
                @compileError("Unsupported key type");
            }
        }
        pub fn erase(self: *Self, key: K) bool {
            if (K == []const u8) {
                return eraseFn(self.handle, key.ptr, key.len) != 0;
            } else if (K == u32 or K == u64) {
                return eraseFn(self.handle, key) != 0;
            } else {
                @compileError("Unsupported key type");
            }
        }
        pub fn iterCount(self: *Self) u64 {
            return iterCountFn(self.handle);
        }
        pub fn memory(self: *Self) usize {
            return memoryFn(self.handle);
        }
    };
}

fn AbslWrapper(comptime K: type, comptime V: type) type {
    return CppWrapper("absl", K, V);
}

fn BoostWrapper(comptime K: type, comptime V: type) type {
    return CppWrapper("boost", K, V);
}

fn AnkerlWrapper(comptime K: type, comptime V: type) type {
    return CppWrapper("ankerl", K, V);
}

// ============================================================================
// Statistics Helpers
// ============================================================================

const BenchStats = struct {
    mean: u64,
    min: u64,
    max: u64,
    stddev: u64,

    fn compute(samples: []const u64) BenchStats {
        if (samples.len == 0) return .{ .mean = 0, .min = 0, .max = 0, .stddev = 0 };

        var sum: u64 = 0;
        var min_val: u64 = std.math.maxInt(u64);
        var max_val: u64 = 0;

        for (samples) |s| {
            sum += s;
            if (s < min_val) min_val = s;
            if (s > max_val) max_val = s;
        }

        const mean = sum / samples.len;

        // Compute standard deviation
        var sum_sq: u128 = 0;
        for (samples) |s| {
            const diff: i128 = @as(i128, s) - @as(i128, mean);
            sum_sq += @intCast(@as(u128, @intCast(diff * diff)));
        }
        const variance = sum_sq / samples.len;
        const stddev: u64 = @intFromFloat(@sqrt(@as(f64, @floatFromInt(variance))));

        return .{
            .mean = mean,
            .min = min_val,
            .max = max_val,
            .stddev = stddev,
        };
    }
};

// ============================================================================
// Generic Benchmark Runner
// ============================================================================

const BenchOp = enum {
    insert,
    insert_reserved,
    insert_seq,
    update,
    lookup,
    miss,
    delete,
    iter,
    churn,
    mixed,
    tombstone,
    high_load,
    // Additional mixed workloads
    read_heavy, // 95% lookup, 3% insert, 2% delete (cache-like)
    write_heavy, // 70% insert, 20% lookup, 10% delete (streaming)
    update_heavy, // 80% update, 15% lookup, 5% insert (counters)
    zipfian, // Skewed access - 80% of ops hit 20% of keys
};

fn Benchmarks(comptime K: type, comptime V: type) type {
    return struct {
        const is_set = V == void;
        const is_string = K == []const u8;

        fn keyToU64(key: K) u64 {
            return if (K == u64) key else if (K == u32) key else 0;
        }

        fn benchThis(comptime Op: BenchOp, comptime size: usize, keys: []const K, extra: anytype, alloc: std.mem.Allocator) ![BENCHMARK_ITERATIONS]u64 {
            const Map = TheHashTable(K, V);
            var times: [BENCHMARK_ITERATIONS]u64 = undefined;

            for (0..BENCHMARK_ITERATIONS) |iter_idx| {
                var map = Map.init(alloc);
                defer map.deinit();

                switch (Op) {
                    .insert, .insert_seq => {},
                    .insert_reserved => try map.ensureTotalCapacity(size),
                    .high_load => {
                        const fill_count = (size * 95) / 100;
                        for (keys[0..fill_count]) |k| {
                            if (is_set) try map.add(k) else try map.put(k, makeValue(V, keyToU64(k)));
                        }
                    },
                    .tombstone => {
                        for (keys[0..size]) |k| {
                            if (is_set) try map.add(k) else try map.put(k, makeValue(V, keyToU64(k)));
                        }
                    },
                    .churn => {
                        for (keys[0 .. size / 2]) |k| {
                            if (is_set) try map.add(k) else try map.put(k, makeValue(V, keyToU64(k)));
                        }
                    },
                    else => {
                        for (keys[0..size]) |k| {
                            if (is_set) try map.add(k) else try map.put(k, makeValue(V, keyToU64(k)));
                        }
                    },
                }

                var timer = try Timer.start();
                switch (Op) {
                    .insert, .insert_reserved => for (keys[0..size]) |k| {
                        if (is_set) try map.add(k) else try map.put(k, makeValue(V, keyToU64(k)));
                    },
                    .insert_seq => for (0..size) |i| {
                        if (K == u64) {
                            if (is_set) try map.add(@intCast(i)) else try map.put(@intCast(i), makeValue(V, i));
                        } else {
                            // For strings, use the keys but in order
                            if (is_set) try map.add(keys[i]) else try map.put(keys[i], makeValue(V, i));
                        }
                    },
                    .update => for (keys[0..size]) |k| {
                        if (is_set) try map.add(k) else try map.put(k, makeValue(V, keyToU64(k) +% 1));
                    },
                    .lookup => {
                        var found: u64 = 0;
                        const order: []const usize = extra;
                        for (order[0..size]) |idx| {
                            if (is_set) {
                                if (map.contains(keys[idx])) found += 1;
                            } else {
                                if (map.get(keys[idx]) != null) found += 1;
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                    .miss => {
                        var miss_count: u64 = 0;
                        const miss_keys: []const K = extra;
                        for (miss_keys[0..size]) |k| {
                            if (is_set) {
                                if (!map.contains(k)) miss_count += 1;
                            } else {
                                if (map.get(k) == null) miss_count += 1;
                            }
                        }
                        std.mem.doNotOptimizeAway(miss_count);
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
                    .mixed => {
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        for (mixed_data.ops[0..size], mixed_data.indices[0..size]) |op, idx| {
                            switch (op) {
                                0 => {
                                    if (is_set) {
                                        if (map.contains(mixed_data.hit_keys[idx])) found += 1;
                                    } else {
                                        if (map.get(mixed_data.hit_keys[idx]) != null) found += 1;
                                    }
                                },
                                1 => {
                                    if (is_set) {
                                        if (!map.contains(mixed_data.miss_keys[idx])) found += 1;
                                    } else {
                                        if (map.get(mixed_data.miss_keys[idx]) == null) found += 1;
                                    }
                                },
                                2 => {
                                    if (is_set) try map.add(mixed_data.hit_keys[idx]) else try map.put(mixed_data.hit_keys[idx], makeValue(V, keyToU64(mixed_data.hit_keys[idx])));
                                },
                                3 => {
                                    _ = map.remove(mixed_data.hit_keys[idx]);
                                    if (is_set) try map.add(mixed_data.hit_keys[idx]) else try map.put(mixed_data.hit_keys[idx], makeValue(V, keyToU64(mixed_data.hit_keys[idx])));
                                },
                                else => {
                                    var it = map.iterator();
                                    var steps: usize = 0;
                                    while (it.next()) |_| {
                                        found += 1;
                                        steps += 1;
                                        if (steps >= 10) break;
                                    }
                                },
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                    .tombstone => {
                        for (keys[0 .. size / 2]) |k| _ = map.remove(k);
                        const miss_keys: []const K = extra;
                        for (miss_keys[0 .. size / 2]) |k| {
                            if (is_set) try map.add(k) else try map.put(k, makeValue(V, keyToU64(k)));
                        }
                    },
                    .high_load => {
                        var found: u64 = 0;
                        const order: []const usize = extra;
                        const fill_count = (size * 95) / 100;
                        for (order[0..fill_count]) |idx| {
                            if (is_set) {
                                if (map.contains(keys[idx])) found += 1;
                            } else {
                                if (map.get(keys[idx]) != null) found += 1;
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                    .read_heavy => {
                        // 95% lookup, 3% insert, 2% delete
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        for (mixed_data.ops[0..size], mixed_data.indices[0..size]) |op, idx| {
                            switch (op) {
                                0 => { // lookup
                                    if (is_set) {
                                        if (map.contains(mixed_data.hit_keys[idx])) found += 1;
                                    } else {
                                        if (map.get(mixed_data.hit_keys[idx]) != null) found += 1;
                                    }
                                },
                                1 => { // insert
                                    if (is_set) try map.add(mixed_data.miss_keys[idx]) else try map.put(mixed_data.miss_keys[idx], makeValue(V, keyToU64(mixed_data.miss_keys[idx])));
                                },
                                else => { // delete
                                    _ = map.remove(mixed_data.hit_keys[idx]);
                                },
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                    .write_heavy => {
                        // 70% insert, 20% lookup, 10% delete
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        for (mixed_data.ops[0..size], mixed_data.indices[0..size]) |op, idx| {
                            switch (op) {
                                0 => { // insert
                                    if (is_set) try map.add(mixed_data.miss_keys[idx]) else try map.put(mixed_data.miss_keys[idx], makeValue(V, keyToU64(mixed_data.miss_keys[idx])));
                                },
                                1 => { // lookup
                                    if (is_set) {
                                        if (map.contains(mixed_data.hit_keys[idx])) found += 1;
                                    } else {
                                        if (map.get(mixed_data.hit_keys[idx]) != null) found += 1;
                                    }
                                },
                                else => { // delete
                                    _ = map.remove(mixed_data.hit_keys[idx]);
                                },
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                    .update_heavy => {
                        // 80% update, 15% lookup, 5% insert
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        for (mixed_data.ops[0..size], mixed_data.indices[0..size]) |op, idx| {
                            switch (op) {
                                0 => { // update existing
                                    if (is_set) try map.add(mixed_data.hit_keys[idx]) else try map.put(mixed_data.hit_keys[idx], makeValue(V, keyToU64(mixed_data.hit_keys[idx]) +% 1));
                                },
                                1 => { // lookup
                                    if (is_set) {
                                        if (map.contains(mixed_data.hit_keys[idx])) found += 1;
                                    } else {
                                        if (map.get(mixed_data.hit_keys[idx]) != null) found += 1;
                                    }
                                },
                                else => { // insert new
                                    if (is_set) try map.add(mixed_data.miss_keys[idx]) else try map.put(mixed_data.miss_keys[idx], makeValue(V, keyToU64(mixed_data.miss_keys[idx])));
                                },
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                    .zipfian => {
                        // Same ops as mixed but with skewed key access (80% hit 20% of keys)
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        for (mixed_data.ops[0..size], mixed_data.indices[0..size]) |op, idx| {
                            switch (op) {
                                0 => {
                                    if (is_set) {
                                        if (map.contains(mixed_data.hit_keys[idx])) found += 1;
                                    } else {
                                        if (map.get(mixed_data.hit_keys[idx]) != null) found += 1;
                                    }
                                },
                                1 => {
                                    if (is_set) {
                                        if (!map.contains(mixed_data.miss_keys[idx])) found += 1;
                                    } else {
                                        if (map.get(mixed_data.miss_keys[idx]) == null) found += 1;
                                    }
                                },
                                2 => {
                                    if (is_set) try map.add(mixed_data.hit_keys[idx]) else try map.put(mixed_data.hit_keys[idx], makeValue(V, keyToU64(mixed_data.hit_keys[idx])));
                                },
                                3 => {
                                    _ = map.remove(mixed_data.hit_keys[idx]);
                                    if (is_set) try map.add(mixed_data.hit_keys[idx]) else try map.put(mixed_data.hit_keys[idx], makeValue(V, keyToU64(mixed_data.hit_keys[idx])));
                                },
                                else => {
                                    var it = map.iterator();
                                    var steps: usize = 0;
                                    while (it.next()) |_| {
                                        found += 1;
                                        steps += 1;
                                        if (steps >= 10) break;
                                    }
                                },
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                }
                times[iter_idx] = timer.read();
            }
            return times;
        }

        fn benchStd(comptime Op: BenchOp, comptime size: usize, keys: []const K, extra: anytype, alloc: std.mem.Allocator) ![BENCHMARK_ITERATIONS]u64 {
            const StdMap = if (is_string) std.StringHashMap(V) else std.AutoHashMap(K, V);
            var times: [BENCHMARK_ITERATIONS]u64 = undefined;

            for (0..BENCHMARK_ITERATIONS) |iter_idx| {
                var map = StdMap.init(alloc);
                defer map.deinit();

                switch (Op) {
                    .insert, .insert_seq => {},
                    .insert_reserved => try map.ensureTotalCapacity(@intCast(size)),
                    .high_load => {
                        const fill_count = (size * 95) / 100;
                        for (keys[0..fill_count]) |k| try map.put(k, makeValue(V, keyToU64(k)));
                    },
                    .tombstone => {
                        for (keys[0..size]) |k| try map.put(k, makeValue(V, keyToU64(k)));
                    },
                    .churn => {
                        for (keys[0 .. size / 2]) |k| try map.put(k, makeValue(V, keyToU64(k)));
                    },
                    else => {
                        for (keys[0..size]) |k| try map.put(k, makeValue(V, keyToU64(k)));
                    },
                }

                var timer = try Timer.start();
                switch (Op) {
                    .insert, .insert_reserved => for (keys[0..size]) |k| {
                        try map.put(k, makeValue(V, keyToU64(k)));
                    },
                    .insert_seq => for (0..size) |i| {
                        if (K == u64) {
                            try map.put(@intCast(i), makeValue(V, i));
                        } else {
                            try map.put(keys[i], makeValue(V, i));
                        }
                    },
                    .update => for (keys[0..size]) |k| {
                        try map.put(k, makeValue(V, keyToU64(k) +% 1));
                    },
                    .lookup => {
                        var found: u64 = 0;
                        const order: []const usize = extra;
                        for (order[0..size]) |idx| if (map.get(keys[idx]) != null) {
                            found += 1;
                        };
                        std.mem.doNotOptimizeAway(found);
                    },
                    .miss => {
                        var miss_count: u64 = 0;
                        const miss_keys: []const K = extra;
                        for (miss_keys[0..size]) |k| if (map.get(k) == null) {
                            miss_count += 1;
                        };
                        std.mem.doNotOptimizeAway(miss_count);
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
                    .mixed => {
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        for (mixed_data.ops[0..size], mixed_data.indices[0..size]) |op, idx| {
                            switch (op) {
                                0 => if (map.get(mixed_data.hit_keys[idx]) != null) {
                                    found += 1;
                                },
                                1 => if (map.get(mixed_data.miss_keys[idx]) == null) {
                                    found += 1;
                                },
                                2 => try map.put(mixed_data.hit_keys[idx], makeValue(V, keyToU64(mixed_data.hit_keys[idx]))),
                                3 => {
                                    _ = map.remove(mixed_data.hit_keys[idx]);
                                    try map.put(mixed_data.hit_keys[idx], makeValue(V, keyToU64(mixed_data.hit_keys[idx])));
                                },
                                else => {
                                    var it = map.iterator();
                                    var steps: usize = 0;
                                    while (it.next()) |_| {
                                        found += 1;
                                        steps += 1;
                                        if (steps >= 10) break;
                                    }
                                },
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                    .tombstone => {
                        for (keys[0 .. size / 2]) |k| _ = map.remove(k);
                        const miss_keys: []const K = extra;
                        for (miss_keys[0 .. size / 2]) |k| try map.put(k, makeValue(V, keyToU64(k)));
                    },
                    .high_load => {
                        var found: u64 = 0;
                        const order: []const usize = extra;
                        const fill_count = (size * 95) / 100;
                        for (order[0..fill_count]) |idx| if (map.get(keys[idx]) != null) {
                            found += 1;
                        };
                        std.mem.doNotOptimizeAway(found);
                    },
                    .read_heavy => {
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        for (mixed_data.ops[0..size], mixed_data.indices[0..size]) |op, idx| {
                            switch (op) {
                                0 => if (map.get(mixed_data.hit_keys[idx]) != null) {
                                    found += 1;
                                },
                                1 => try map.put(mixed_data.miss_keys[idx], makeValue(V, keyToU64(mixed_data.miss_keys[idx]))),
                                else => _ = map.remove(mixed_data.hit_keys[idx]),
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                    .write_heavy => {
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        for (mixed_data.ops[0..size], mixed_data.indices[0..size]) |op, idx| {
                            switch (op) {
                                0 => try map.put(mixed_data.miss_keys[idx], makeValue(V, keyToU64(mixed_data.miss_keys[idx]))),
                                1 => if (map.get(mixed_data.hit_keys[idx]) != null) {
                                    found += 1;
                                },
                                else => _ = map.remove(mixed_data.hit_keys[idx]),
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                    .update_heavy => {
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        for (mixed_data.ops[0..size], mixed_data.indices[0..size]) |op, idx| {
                            switch (op) {
                                0 => try map.put(mixed_data.hit_keys[idx], makeValue(V, keyToU64(mixed_data.hit_keys[idx]) +% 1)),
                                1 => if (map.get(mixed_data.hit_keys[idx]) != null) {
                                    found += 1;
                                },
                                else => try map.put(mixed_data.miss_keys[idx], makeValue(V, keyToU64(mixed_data.miss_keys[idx]))),
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                    .zipfian => {
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        for (mixed_data.ops[0..size], mixed_data.indices[0..size]) |op, idx| {
                            switch (op) {
                                0 => if (map.get(mixed_data.hit_keys[idx]) != null) {
                                    found += 1;
                                },
                                1 => if (map.get(mixed_data.miss_keys[idx]) == null) {
                                    found += 1;
                                },
                                2 => try map.put(mixed_data.hit_keys[idx], makeValue(V, keyToU64(mixed_data.hit_keys[idx]))),
                                3 => {
                                    _ = map.remove(mixed_data.hit_keys[idx]);
                                    try map.put(mixed_data.hit_keys[idx], makeValue(V, keyToU64(mixed_data.hit_keys[idx])));
                                },
                                else => {
                                    var it = map.iterator();
                                    var steps: usize = 0;
                                    while (it.next()) |_| {
                                        found += 1;
                                        steps += 1;
                                        if (steps >= 10) break;
                                    }
                                },
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                }
                times[iter_idx] = timer.read();
            }
            return times;
        }

        fn benchCpp(comptime WrapperFn: fn (type, type) type, comptime Op: BenchOp, comptime size: usize, keys: []const K, extra: anytype) ![BENCHMARK_ITERATIONS]u64 {
            const CppMap = WrapperFn(K, V);
            var times: [BENCHMARK_ITERATIONS]u64 = undefined;

            for (0..BENCHMARK_ITERATIONS) |iter_idx| {
                var map = CppMap.init();
                defer map.deinit();

                switch (Op) {
                    .insert, .insert_reserved, .insert_seq => {},
                    .high_load => {
                        const fill_count = (size * 95) / 100;
                        for (keys[0..fill_count]) |k| _ = map.insert(k, makeValue(V, keyToU64(k)));
                    },
                    .tombstone => {
                        for (keys[0..size]) |k| _ = map.insert(k, makeValue(V, keyToU64(k)));
                    },
                    .churn => {
                        for (keys[0 .. size / 2]) |k| _ = map.insert(k, makeValue(V, keyToU64(k)));
                    },
                    else => {
                        for (keys[0..size]) |k| _ = map.insert(k, makeValue(V, keyToU64(k)));
                    },
                }

                var timer = try Timer.start();
                switch (Op) {
                    .insert, .insert_reserved => for (keys[0..size]) |k| {
                        _ = map.insert(k, makeValue(V, keyToU64(k)));
                    },
                    .insert_seq => for (0..size) |i| {
                        if (K == u64) {
                            _ = map.insert(@intCast(i), makeValue(V, i));
                        } else {
                            _ = map.insert(keys[i], makeValue(V, i));
                        }
                    },
                    .update => for (keys[0..size]) |k| {
                        _ = map.insert(k, makeValue(V, keyToU64(k) +% 1));
                    },
                    .lookup => {
                        var found: u64 = 0;
                        const order: []const usize = extra;
                        for (order[0..size]) |idx| if (map.get(keys[idx])) {
                            found += 1;
                        };
                        std.mem.doNotOptimizeAway(found);
                    },
                    .miss => {
                        var miss_count: u64 = 0;
                        const miss_keys: []const K = extra;
                        for (miss_keys[0..size]) |k| if (!map.get(k)) {
                            miss_count += 1;
                        };
                        std.mem.doNotOptimizeAway(miss_count);
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
                    .mixed => {
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        for (mixed_data.ops[0..size], mixed_data.indices[0..size]) |op, idx| {
                            switch (op) {
                                0 => if (map.get(mixed_data.hit_keys[idx])) {
                                    found += 1;
                                },
                                1 => if (!map.get(mixed_data.miss_keys[idx])) {
                                    found += 1;
                                },
                                2 => _ = map.insert(mixed_data.hit_keys[idx], makeValue(V, keyToU64(mixed_data.hit_keys[idx]))),
                                3 => {
                                    _ = map.erase(mixed_data.hit_keys[idx]);
                                    _ = map.insert(mixed_data.hit_keys[idx], makeValue(V, keyToU64(mixed_data.hit_keys[idx])));
                                },
                                else => {
                                    for (mixed_data.hit_keys[0..@min(10, mixed_data.hit_keys.len)]) |k| {
                                        if (map.get(k)) found += 1;
                                    }
                                },
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                    .tombstone => {
                        for (keys[0 .. size / 2]) |k| _ = map.erase(k);
                        const miss_keys: []const K = extra;
                        for (miss_keys[0 .. size / 2]) |k| _ = map.insert(k, makeValue(V, keyToU64(k)));
                    },
                    .high_load => {
                        var found: u64 = 0;
                        const order: []const usize = extra;
                        const fill_count = (size * 95) / 100;
                        for (order[0..fill_count]) |idx| if (map.get(keys[idx])) {
                            found += 1;
                        };
                        std.mem.doNotOptimizeAway(found);
                    },
                    .read_heavy => {
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        for (mixed_data.ops[0..size], mixed_data.indices[0..size]) |op, idx| {
                            switch (op) {
                                0 => if (map.get(mixed_data.hit_keys[idx])) {
                                    found += 1;
                                },
                                1 => _ = map.insert(mixed_data.miss_keys[idx], makeValue(V, keyToU64(mixed_data.miss_keys[idx]))),
                                else => _ = map.erase(mixed_data.hit_keys[idx]),
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                    .write_heavy => {
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        for (mixed_data.ops[0..size], mixed_data.indices[0..size]) |op, idx| {
                            switch (op) {
                                0 => _ = map.insert(mixed_data.miss_keys[idx], makeValue(V, keyToU64(mixed_data.miss_keys[idx]))),
                                1 => if (map.get(mixed_data.hit_keys[idx])) {
                                    found += 1;
                                },
                                else => _ = map.erase(mixed_data.hit_keys[idx]),
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                    .update_heavy => {
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        for (mixed_data.ops[0..size], mixed_data.indices[0..size]) |op, idx| {
                            switch (op) {
                                0 => _ = map.insert(mixed_data.hit_keys[idx], makeValue(V, keyToU64(mixed_data.hit_keys[idx]) +% 1)),
                                1 => if (map.get(mixed_data.hit_keys[idx])) {
                                    found += 1;
                                },
                                else => _ = map.insert(mixed_data.miss_keys[idx], makeValue(V, keyToU64(mixed_data.miss_keys[idx]))),
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                    .zipfian => {
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        for (mixed_data.ops[0..size], mixed_data.indices[0..size]) |op, idx| {
                            switch (op) {
                                0 => if (map.get(mixed_data.hit_keys[idx])) {
                                    found += 1;
                                },
                                1 => if (!map.get(mixed_data.miss_keys[idx])) {
                                    found += 1;
                                },
                                2 => _ = map.insert(mixed_data.hit_keys[idx], makeValue(V, keyToU64(mixed_data.hit_keys[idx]))),
                                3 => {
                                    _ = map.erase(mixed_data.hit_keys[idx]);
                                    _ = map.insert(mixed_data.hit_keys[idx], makeValue(V, keyToU64(mixed_data.hit_keys[idx])));
                                },
                                else => {
                                    for (mixed_data.hit_keys[0..@min(10, mixed_data.hit_keys.len)]) |k| {
                                        if (map.get(k)) found += 1;
                                    }
                                },
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                }
                times[iter_idx] = timer.read();
            }
            return times;
        }

        fn benchAbsl(comptime Op: BenchOp, comptime size: usize, keys: []const K, extra: anytype) ![BENCHMARK_ITERATIONS]u64 {
            return benchCpp(AbslWrapper, Op, size, keys, extra);
        }

        fn benchBoost(comptime Op: BenchOp, comptime size: usize, keys: []const K, extra: anytype) ![BENCHMARK_ITERATIONS]u64 {
            return benchCpp(BoostWrapper, Op, size, keys, extra);
        }

        fn benchAnkerl(comptime Op: BenchOp, comptime size: usize, keys: []const K, extra: anytype) ![BENCHMARK_ITERATIONS]u64 {
            return benchCpp(AnkerlWrapper, Op, size, keys, extra);
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
        std.debug.print("{d:>6.1} µs", .{@as(f64, @floatFromInt(ns)) / 1000.0});
    } else if (ns < 1_000_000_000) {
        std.debug.print("{d:>6.1} ms", .{@as(f64, @floatFromInt(ns)) / 1_000_000.0});
    } else {
        std.debug.print("{d:>6.1} s ", .{@as(f64, @floatFromInt(ns)) / 1_000_000_000.0});
    }
}

const BenchResults = struct {
    ours: BenchStats,
    absl: BenchStats,
    boost: BenchStats,
    ankerl: BenchStats,
    std_val: BenchStats,
};

// ============================================================================
// Accumulator for Key-Type Averages
// ============================================================================

const OpAccumulator = struct {
    ours_sum: u64 = 0,
    absl_sum: u64 = 0,
    boost_sum: u64 = 0,
    ankerl_sum: u64 = 0,
    std_sum: u64 = 0,
    count: u64 = 0,

    fn add(self: *OpAccumulator, r: BenchResults) void {
        self.ours_sum += r.ours.mean;
        self.absl_sum += r.absl.mean;
        self.boost_sum += r.boost.mean;
        self.ankerl_sum += r.ankerl.mean;
        self.std_sum += r.std_val.mean;
        self.count += 1;
    }

    fn avgOurs(self: OpAccumulator) u64 {
        return if (self.count > 0) self.ours_sum / self.count else 0;
    }
    fn avgAbsl(self: OpAccumulator) u64 {
        return if (self.count > 0) self.absl_sum / self.count else 0;
    }
    fn avgBoost(self: OpAccumulator) u64 {
        return if (self.count > 0) self.boost_sum / self.count else 0;
    }
    fn avgAnkerl(self: OpAccumulator) u64 {
        return if (self.count > 0) self.ankerl_sum / self.count else 0;
    }
    fn avgStd(self: OpAccumulator) u64 {
        return if (self.count > 0) self.std_sum / self.count else 0;
    }
};

const KeyTypeAccumulator = struct {
    insert: OpAccumulator = .{},
    insert_seq: OpAccumulator = .{},
    insert_reserved: OpAccumulator = .{},
    update: OpAccumulator = .{},
    lookup: OpAccumulator = .{},
    high_load: OpAccumulator = .{},
    miss: OpAccumulator = .{},
    tombstone: OpAccumulator = .{},
    delete: OpAccumulator = .{},
    iter: OpAccumulator = .{},
    churn: OpAccumulator = .{},
    mixed: OpAccumulator = .{},
    read_heavy: OpAccumulator = .{},
    write_heavy: OpAccumulator = .{},
    update_heavy: OpAccumulator = .{},
    zipfian: OpAccumulator = .{},

    fn addResult(self: *KeyTypeAccumulator, op: BenchOp, results: BenchResults) void {
        switch (op) {
            .insert => self.insert.add(results),
            .insert_seq => self.insert_seq.add(results),
            .insert_reserved => self.insert_reserved.add(results),
            .update => self.update.add(results),
            .lookup => self.lookup.add(results),
            .high_load => self.high_load.add(results),
            .miss => self.miss.add(results),
            .tombstone => self.tombstone.add(results),
            .delete => self.delete.add(results),
            .iter => self.iter.add(results),
            .churn => self.churn.add(results),
            .mixed => self.mixed.add(results),
            .read_heavy => self.read_heavy.add(results),
            .write_heavy => self.write_heavy.add(results),
            .update_heavy => self.update_heavy.add(results),
            .zipfian => self.zipfian.add(results),
        }
    }

    fn printTable(self: *KeyTypeAccumulator, key_type_name: []const u8) void {
        std.debug.print("\n════════════════════════════════════════════════════════════════════════════════\n", .{});
        std.debug.print("  {s} keys — Average across all value types and sizes ({d} configs)\n", .{ key_type_name, self.insert.count });
        std.debug.print("════════════════════════════════════════════════════════════════════════════════\n", .{});

        std.debug.print("\n  ┌────────────────┬──────────┬──────────┬──────────┬──────────┬──────────┐\n", .{});
        std.debug.print("  │ Operation      │ This     │ Abseil   │ Boost    │ Ankerl   │ std      │\n", .{});
        std.debug.print("  ├────────────────┼──────────┼──────────┼──────────┼──────────┼──────────┤\n", .{});

        printAvgRow("Rand. Insert", self.insert);
        printAvgRow("Seq. Insert", self.insert_seq);
        printAvgRow("Reserved Ins.", self.insert_reserved);
        printAvgRow("Update", self.update);
        printAvgRow("Rand. Lookup", self.lookup);
        printAvgRow("High Load", self.high_load);
        printAvgRow("Lookup Miss", self.miss);
        printAvgRow("Tombstone", self.tombstone);
        printAvgRow("Delete", self.delete);
        printAvgRow("Iteration", self.iter);
        printAvgRow("Churn", self.churn);
        printAvgRow("Mixed", self.mixed);
        printAvgRow("Read-Heavy", self.read_heavy);
        printAvgRow("Write-Heavy", self.write_heavy);
        printAvgRow("Update-Heavy", self.update_heavy);
        printAvgRow("Zipfian", self.zipfian);

        std.debug.print("  └────────────────┴──────────┴──────────┴──────────┴──────────┴──────────┘\n", .{});
    }
};

fn printAvgRow(name: []const u8, acc: OpAccumulator) void {
    std.debug.print("  │ {s:<14} │", .{name});
    printTime(acc.avgOurs());
    std.debug.print(" │", .{});
    printTime(acc.avgAbsl());
    std.debug.print(" │", .{});
    printTime(acc.avgBoost());
    std.debug.print(" │", .{});
    printTime(acc.avgAnkerl());
    std.debug.print(" │", .{});
    printTime(acc.avgStd());
    std.debug.print(" │\n", .{});
}

var g_acc_u32: KeyTypeAccumulator = .{};
var g_acc_u64: KeyTypeAccumulator = .{};
var g_acc_string: KeyTypeAccumulator = .{};

fn printRow(name: []const u8, r: BenchResults) void {
    std.debug.print("  │ {s:<14} │", .{name});
    printTime(r.ours.mean);
    std.debug.print(" │", .{});
    printTime(r.absl.mean);
    std.debug.print(" │", .{});
    printTime(r.boost.mean);
    std.debug.print(" │", .{});
    printTime(r.ankerl.mean);
    std.debug.print(" │", .{});
    printTime(r.std_val.mean);
    std.debug.print(" │\n", .{});
}

fn formatSize(size: usize) []const u8 {
    return switch (size) {
        100 => "100",
        1_000 => "1K",
        3_000 => "3K",
        100_000 => "100K",
        1_000_000 => "1M",
        else => "?",
    };
}

fn keyTypeName(comptime K: type) []const u8 {
    return if (K == u32) "u32" else if (K == u64) "u64" else if (K == []const u8) "string" else "?";
}

fn valueTypeName(comptime V: type) []const u8 {
    return if (V == void) "void (set)" else if (V == Value4) "4B" else if (V == Value64) "64B" else "?";
}

const Xoshiro = std.Random.Xoshiro256;
fn makeRng(seed: u64) Xoshiro {
    return Xoshiro.init(seed);
}

fn MixedOpsData(comptime K: type) type {
    return struct {
        ops: []u8,
        indices: []usize,
        hit_keys: []const K,
        miss_keys: []const K,
    };
}

fn generateMixedOps(comptime size: usize, allocator: std.mem.Allocator) !struct { ops: []u8, indices: []usize } {
    const ops = try allocator.alloc(u8, size);
    const indices = try allocator.alloc(usize, size);

    var rng = makeRng(22222);
    for (0..size) |i| {
        indices[i] = rng.random().int(usize) % size;
        const op_roll = rng.random().int(u8) % 100;
        if (op_roll < 65) ops[i] = 0 else if (op_roll < 75) ops[i] = 1 else if (op_roll < 85) ops[i] = 2 else if (op_roll < 95) ops[i] = 3 else ops[i] = 4;
    }
    return .{ .ops = ops, .indices = indices };
}

// Read-heavy: 95% lookup, 3% insert, 2% delete (cache-like workload)
fn generateReadHeavyOps(comptime size: usize, allocator: std.mem.Allocator) !struct { ops: []u8, indices: []usize } {
    const ops = try allocator.alloc(u8, size);
    const indices = try allocator.alloc(usize, size);

    var rng = makeRng(33333);
    for (0..size) |i| {
        indices[i] = rng.random().int(usize) % size;
        const op_roll = rng.random().int(u8) % 100;
        // 0 = lookup hit, 1 = insert, 2 = delete
        if (op_roll < 95) ops[i] = 0 else if (op_roll < 98) ops[i] = 1 else ops[i] = 2;
    }
    return .{ .ops = ops, .indices = indices };
}

// Write-heavy: 70% insert, 20% lookup, 10% delete (streaming workload)
fn generateWriteHeavyOps(comptime size: usize, allocator: std.mem.Allocator) !struct { ops: []u8, indices: []usize } {
    const ops = try allocator.alloc(u8, size);
    const indices = try allocator.alloc(usize, size);

    var rng = makeRng(44444);
    for (0..size) |i| {
        indices[i] = rng.random().int(usize) % size;
        const op_roll = rng.random().int(u8) % 100;
        // 0 = insert, 1 = lookup, 2 = delete
        if (op_roll < 70) ops[i] = 0 else if (op_roll < 90) ops[i] = 1 else ops[i] = 2;
    }
    return .{ .ops = ops, .indices = indices };
}

// Update-heavy: 80% update, 15% lookup, 5% insert (counters/stats workload)
fn generateUpdateHeavyOps(comptime size: usize, allocator: std.mem.Allocator) !struct { ops: []u8, indices: []usize } {
    const ops = try allocator.alloc(u8, size);
    const indices = try allocator.alloc(usize, size);

    var rng = makeRng(55555);
    for (0..size) |i| {
        indices[i] = rng.random().int(usize) % size;
        const op_roll = rng.random().int(u8) % 100;
        // 0 = update existing, 1 = lookup, 2 = insert new
        if (op_roll < 80) ops[i] = 0 else if (op_roll < 95) ops[i] = 1 else ops[i] = 2;
    }
    return .{ .ops = ops, .indices = indices };
}

// Zipfian distribution: generates indices where ~80% of accesses hit ~20% of keys
fn generateZipfianIndices(comptime size: usize, allocator: std.mem.Allocator) ![]usize {
    const indices = try allocator.alloc(usize, size);
    var rng = makeRng(66666);

    // Zipf with s=1.0 approximation using rejection sampling
    const hot_set_size = size / 5; // Top 20% of keys

    for (0..size) |i| {
        // 80% chance to pick from hot set, 20% from cold set
        if (rng.random().int(u8) % 100 < 80) {
            indices[i] = rng.random().int(usize) % hot_set_size;
        } else {
            indices[i] = hot_set_size + (rng.random().int(usize) % (size - hot_set_size));
        }
    }
    return indices;
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

    const mixed_gen = try generateMixedOps(size, allocator);
    defer allocator.free(mixed_gen.ops);
    defer allocator.free(mixed_gen.indices);
    const mixed_data = MixedOpsData(K){ .ops = mixed_gen.ops, .indices = mixed_gen.indices, .hit_keys = keys, .miss_keys = miss_keys };

    // Generate data for new workloads
    const read_heavy_gen = try generateReadHeavyOps(size, allocator);
    defer allocator.free(read_heavy_gen.ops);
    defer allocator.free(read_heavy_gen.indices);
    const read_heavy_data = MixedOpsData(K){ .ops = read_heavy_gen.ops, .indices = read_heavy_gen.indices, .hit_keys = keys, .miss_keys = miss_keys };

    const write_heavy_gen = try generateWriteHeavyOps(size, allocator);
    defer allocator.free(write_heavy_gen.ops);
    defer allocator.free(write_heavy_gen.indices);
    const write_heavy_data = MixedOpsData(K){ .ops = write_heavy_gen.ops, .indices = write_heavy_gen.indices, .hit_keys = keys, .miss_keys = miss_keys };

    const update_heavy_gen = try generateUpdateHeavyOps(size, allocator);
    defer allocator.free(update_heavy_gen.ops);
    defer allocator.free(update_heavy_gen.indices);
    const update_heavy_data = MixedOpsData(K){ .ops = update_heavy_gen.ops, .indices = update_heavy_gen.indices, .hit_keys = keys, .miss_keys = miss_keys };

    // Zipfian: use same ops as mixed but with skewed indices
    const zipfian_indices = try generateZipfianIndices(size, allocator);
    defer allocator.free(zipfian_indices);
    const zipfian_data = MixedOpsData(K){ .ops = mixed_gen.ops, .indices = zipfian_indices, .hit_keys = keys, .miss_keys = miss_keys };

    std.debug.print("\n  {s} elements:\n", .{comptime formatSize(size)});
    std.debug.print("  ┌────────────────┬──────────┬──────────┬──────────┬──────────┬──────────┐\n", .{});
    std.debug.print("  │ Operation      │ This     │ Abseil   │ Boost    │ Ankerl   │ std      │\n", .{});
    std.debug.print("  ├────────────────┼──────────┼──────────┼──────────┼──────────┼──────────┤\n", .{});

    const runOp = struct {
        fn run(comptime op: BenchOp, name: []const u8, k: []const K, extra: anytype, alloc: std.mem.Allocator, comptime s: usize) !void {
            const divisor = if (op == .high_load) (s * 95) / 100 else s;
            var ours_per: [BENCHMARK_ITERATIONS]u64 = undefined;
            var std_per: [BENCHMARK_ITERATIONS]u64 = undefined;
            var absl_per: [BENCHMARK_ITERATIONS]u64 = undefined;
            var boost_per: [BENCHMARK_ITERATIONS]u64 = undefined;
            var ankerl_per: [BENCHMARK_ITERATIONS]u64 = undefined;

            const ours = try B.benchThis(op, s, k, extra, alloc);
            const std_t = try B.benchStd(op, s, k, extra, alloc);
            const absl = try B.benchAbsl(op, s, k, extra);
            const boost = try B.benchBoost(op, s, k, extra);
            const ankerl = try B.benchAnkerl(op, s, k, extra);

            for (0..BENCHMARK_ITERATIONS) |i| {
                ours_per[i] = ours[i] / divisor;
                std_per[i] = std_t[i] / divisor;
                absl_per[i] = absl[i] / divisor;
                boost_per[i] = boost[i] / divisor;
                ankerl_per[i] = ankerl[i] / divisor;
            }

            const results = BenchResults{
                .ours = BenchStats.compute(&ours_per),
                .absl = BenchStats.compute(&absl_per),
                .boost = BenchStats.compute(&boost_per),
                .ankerl = BenchStats.compute(&ankerl_per),
                .std_val = BenchStats.compute(&std_per),
            };

            printRow(name, results);

            // Accumulate for key-type summary
            const acc = if (K == u32) &g_acc_u32 else if (K == u64) &g_acc_u64 else &g_acc_string;
            acc.addResult(op, results);
        }
    }.run;

    try runOp(.insert, "Rand. Insert", keys, {}, allocator, size);
    try runOp(.insert_seq, "Seq. Insert", keys, {}, allocator, size);
    try runOp(.insert_reserved, "Reserved Ins.", keys, {}, allocator, size);
    try runOp(.update, "Update", keys, {}, allocator, size);
    try runOp(.lookup, "Rand. Lookup", keys, lookup_order, allocator, size);
    try runOp(.high_load, "High Load", keys, lookup_order, allocator, size);
    try runOp(.miss, "Lookup Miss", keys, miss_keys, allocator, size);
    try runOp(.tombstone, "Tombstone", keys, miss_keys, allocator, size);
    try runOp(.delete, "Delete", keys, {}, allocator, size);
    try runOp(.iter, "Iteration", keys, {}, allocator, size);
    try runOp(.churn, "Churn", keys, {}, allocator, size);
    try runOp(.mixed, "Mixed", keys, &mixed_data, allocator, size);
    try runOp(.read_heavy, "Read-Heavy", keys, &read_heavy_data, allocator, size);
    try runOp(.write_heavy, "Write-Heavy", keys, &write_heavy_data, allocator, size);
    try runOp(.update_heavy, "Update-Heavy", keys, &update_heavy_data, allocator, size);
    try runOp(.zipfian, "Zipfian", keys, &zipfian_data, allocator, size);

    std.debug.print("  └────────────────┴──────────┴──────────┴──────────┴──────────┴──────────┘\n", .{});
}

fn runAllSizes(comptime K: type, comptime V: type, keys: []const K, miss_keys: []const K, lookup_order: []const usize, allocator: std.mem.Allocator) !void {
    std.debug.print("\n════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  {s} key → {s} value\n", .{ keyTypeName(K), valueTypeName(V) });
    std.debug.print("════════════════════════════════════════════════════════════════════════════════\n", .{});

    try runComparison(K, V, SIZE_100, keys, miss_keys, lookup_order, allocator);
    try runComparison(K, V, SIZE_3K, keys, miss_keys, lookup_order, allocator);
    try runComparison(K, V, SIZE_100K, keys, miss_keys, lookup_order, allocator);
}

// ============================================================================
// Memory Benchmark
// ============================================================================

const MemoryResults = struct {
    ours: usize,
    absl: usize,
    boost: usize,
    ankerl: usize,
    std_val: usize,
};

fn formatMemory(bytes: usize) void {
    if (bytes < 1024) {
        std.debug.print("{d:>7} B", .{bytes});
    } else if (bytes < 1024 * 1024) {
        std.debug.print("{d:>6.1} KB", .{@as(f64, @floatFromInt(bytes)) / 1024.0});
    } else if (bytes < 1024 * 1024 * 1024) {
        std.debug.print("{d:>6.1} MB", .{@as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0)});
    } else {
        std.debug.print("{d:>6.1} GB", .{@as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0 * 1024.0)});
    }
}

fn printMemRow(name: []const u8, r: MemoryResults) void {
    std.debug.print("  │ {s:<12} │", .{name});
    formatMemory(r.ours);
    std.debug.print(" │", .{});
    formatMemory(r.absl);
    std.debug.print(" │", .{});
    formatMemory(r.boost);
    std.debug.print(" │", .{});
    formatMemory(r.ankerl);
    std.debug.print(" │", .{});
    formatMemory(r.std_val);
    std.debug.print(" │\n", .{});
}

fn runMemoryBenchmark(comptime K: type, comptime V: type, comptime size: usize, keys: []const K, allocator: std.mem.Allocator) !void {
    const is_set = V == void;
    const is_string = K == []const u8;

    // This
    var ours_mem: usize = 0;
    {
        const Map = TheHashTable(K, V);
        var map = Map.init(allocator);
        defer map.deinit();
        for (keys[0..size]) |k| {
            if (is_set) try map.add(k) else try map.put(k, makeValue(V, if (K == u64 or K == u32) k else 0));
        }
        // Approximate memory: bucket_count * (bucket_size + metadata)
        const bucket_count = map.bucketCount();
        const bucket_size = @sizeOf(Map.Bucket);
        const meta_size = @sizeOf(u16);
        ours_mem = bucket_count * (bucket_size + meta_size);
        if (is_string) {
            // Add string storage (keys are slices pointing to external storage, not counted)
            // For fair comparison, we don't own the strings
        }
    }

    // Abseil
    var absl_mem: usize = 0;
    {
        var map = AbslWrapper(K, V).init();
        defer map.deinit();
        for (keys[0..size]) |k| {
            _ = map.insert(k, makeValue(V, if (K == u64 or K == u32) k else 0));
        }
        absl_mem = map.memory();
    }

    // Boost
    var boost_mem: usize = 0;
    {
        var map = BoostWrapper(K, V).init();
        defer map.deinit();
        for (keys[0..size]) |k| {
            _ = map.insert(k, makeValue(V, if (K == u64 or K == u32) k else 0));
        }
        boost_mem = map.memory();
    }

    // Ankerl
    var ankerl_mem: usize = 0;
    {
        var map = AnkerlWrapper(K, V).init();
        defer map.deinit();
        for (keys[0..size]) |k| {
            _ = map.insert(k, makeValue(V, if (K == u64 or K == u32) k else 0));
        }
        ankerl_mem = map.memory();
    }

    // std
    var std_mem: usize = 0;
    {
        const StdMap = if (is_string) std.StringHashMap(V) else std.AutoHashMap(K, V);
        var map = StdMap.init(allocator);
        defer map.deinit();
        for (keys[0..size]) |k| {
            try map.put(k, makeValue(V, if (K == u64 or K == u32) k else 0));
        }
        // Approximate: capacity * entry_size
        const cap = map.capacity();
        const entry_size = @sizeOf(K) + @sizeOf(V) + 1; // +1 for metadata byte
        std_mem = cap * entry_size;
    }

    printMemRow(comptime formatSize(size), .{
        .ours = ours_mem,
        .absl = absl_mem,
        .boost = boost_mem,
        .ankerl = ankerl_mem,
        .std_val = std_mem,
    });
}

fn runMemoryBenchmarks(allocator: std.mem.Allocator) !void {
    std.debug.print("\n╔══════════════════════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                         Memory Usage Comparison                              ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════════════════════╝\n", .{});

    // Allocate u32 keys for 1M elements
    const u32_keys = try allocator.alloc(u32, SIZE_1M);
    defer allocator.free(u32_keys);

    var rng = makeRng(12345);
    for (0..SIZE_1M) |i| {
        u32_keys[i] = rng.random().int(u32);
    }

    // u32 -> void (set)
    std.debug.print("\n════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  u32 key → void (set)\n", .{});
    std.debug.print("════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  ┌──────────────┬──────────┬──────────┬──────────┬──────────┬──────────┐\n", .{});
    std.debug.print("  │ Size         │ This     │ Abseil   │ Boost    │ Ankerl   │ std      │\n", .{});
    std.debug.print("  ├──────────────┼──────────┼──────────┼──────────┼──────────┼──────────┤\n", .{});
    try runMemoryBenchmark(u32, void, SIZE_1K, u32_keys, allocator);
    try runMemoryBenchmark(u32, void, SIZE_100K, u32_keys, allocator);
    try runMemoryBenchmark(u32, void, SIZE_1M, u32_keys, allocator);
    std.debug.print("  └──────────────┴──────────┴──────────┴──────────┴──────────┴──────────┘\n", .{});

    // u32 -> 4B
    std.debug.print("\n════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  u32 key → 4B value\n", .{});
    std.debug.print("════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  ┌──────────────┬──────────┬──────────┬──────────┬──────────┬──────────┐\n", .{});
    std.debug.print("  │ Size         │ This     │ Abseil   │ Boost    │ Ankerl   │ std      │\n", .{});
    std.debug.print("  ├──────────────┼──────────┼──────────┼──────────┼──────────┼──────────┤\n", .{});
    try runMemoryBenchmark(u32, Value4, SIZE_1K, u32_keys, allocator);
    try runMemoryBenchmark(u32, Value4, SIZE_100K, u32_keys, allocator);
    try runMemoryBenchmark(u32, Value4, SIZE_1M, u32_keys, allocator);
    std.debug.print("  └──────────────┴──────────┴──────────┴──────────┴──────────┴──────────┘\n", .{});

    // Allocate u64 keys for 1M elements
    const u64_keys = try allocator.alloc(u64, SIZE_1M);
    defer allocator.free(u64_keys);

    rng = makeRng(12345);
    for (0..SIZE_1M) |i| {
        u64_keys[i] = rng.random().int(u64);
    }

    // u64 -> void (set)
    std.debug.print("\n════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  u64 key → void (set)\n", .{});
    std.debug.print("════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  ┌──────────────┬──────────┬──────────┬──────────┬──────────┬──────────┐\n", .{});
    std.debug.print("  │ Size         │ This     │ Abseil   │ Boost    │ Ankerl   │ std      │\n", .{});
    std.debug.print("  ├──────────────┼──────────┼──────────┼──────────┼──────────┼──────────┤\n", .{});
    try runMemoryBenchmark(u64, void, SIZE_1K, u64_keys, allocator);
    try runMemoryBenchmark(u64, void, SIZE_100K, u64_keys, allocator);
    try runMemoryBenchmark(u64, void, SIZE_1M, u64_keys, allocator);
    std.debug.print("  └──────────────┴──────────┴──────────┴──────────┴──────────┴──────────┘\n", .{});

    // u64 -> 4B
    std.debug.print("\n════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  u64 key → 4B value\n", .{});
    std.debug.print("════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  ┌──────────────┬──────────┬──────────┬──────────┬──────────┬──────────┐\n", .{});
    std.debug.print("  │ Size         │ This     │ Abseil   │ Boost    │ Ankerl   │ std      │\n", .{});
    std.debug.print("  ├──────────────┼──────────┼──────────┼──────────┼──────────┼──────────┤\n", .{});
    try runMemoryBenchmark(u64, Value4, SIZE_1K, u64_keys, allocator);
    try runMemoryBenchmark(u64, Value4, SIZE_100K, u64_keys, allocator);
    try runMemoryBenchmark(u64, Value4, SIZE_1M, u64_keys, allocator);
    std.debug.print("  └──────────────┴──────────┴──────────┴──────────┴──────────┴──────────┘\n", .{});

    // u64 -> 64B
    std.debug.print("\n════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  u64 key → 64B value\n", .{});
    std.debug.print("════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  ┌──────────────┬──────────┬──────────┬──────────┬──────────┬──────────┐\n", .{});
    std.debug.print("  │ Size         │ This     │ Abseil   │ Boost    │ Ankerl   │ std      │\n", .{});
    std.debug.print("  ├──────────────┼──────────┼──────────┼──────────┼──────────┼──────────┤\n", .{});
    try runMemoryBenchmark(u64, Value64, SIZE_1K, u64_keys, allocator);
    try runMemoryBenchmark(u64, Value64, SIZE_100K, u64_keys, allocator);
    try runMemoryBenchmark(u64, Value64, SIZE_1M, u64_keys, allocator);
    std.debug.print("  └──────────────┴──────────┴──────────┴──────────┴──────────┴──────────┘\n", .{});

    // String keys - allocate storage
    const key_storage = try allocator.alloc([80]u8, SIZE_1M);
    defer allocator.free(key_storage);
    const str_keys = try allocator.alloc([]const u8, SIZE_1M);
    defer allocator.free(str_keys);

    rng = makeRng(12345);
    for (0..SIZE_1M) |i| {
        const len = 8 + (rng.random().int(usize) % 57);
        for (0..len) |j| key_storage[i][j] = @truncate(32 + (rng.random().int(u8) % 95));
        str_keys[i] = key_storage[i][0..len];
    }

    // string -> void (set)
    std.debug.print("\n════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  string key → void (set)\n", .{});
    std.debug.print("════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  ┌──────────────┬──────────┬──────────┬──────────┬──────────┬──────────┐\n", .{});
    std.debug.print("  │ Size         │ This     │ Abseil   │ Boost    │ Ankerl   │ std      │\n", .{});
    std.debug.print("  ├──────────────┼──────────┼──────────┼──────────┼──────────┼──────────┤\n", .{});
    try runMemoryBenchmark([]const u8, void, SIZE_1K, str_keys, allocator);
    try runMemoryBenchmark([]const u8, void, SIZE_100K, str_keys, allocator);
    std.debug.print("  └──────────────┴──────────┴──────────┴──────────┴──────────┴──────────┘\n", .{});

    // string -> 4B
    std.debug.print("\n════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  string key → 4B value\n", .{});
    std.debug.print("════════════════════════════════════════════════════════════════════════════════\n", .{});
    std.debug.print("  ┌──────────────┬──────────┬──────────┬──────────┬──────────┬──────────┐\n", .{});
    std.debug.print("  │ Size         │ This     │ Abseil   │ Boost    │ Ankerl   │ std      │\n", .{});
    std.debug.print("  ├──────────────┼──────────┼──────────┼──────────┼──────────┼──────────┤\n", .{});
    try runMemoryBenchmark([]const u8, Value4, SIZE_1K, str_keys, allocator);
    try runMemoryBenchmark([]const u8, Value4, SIZE_100K, str_keys, allocator);
    std.debug.print("  └──────────────┴──────────┴──────────┴──────────┴──────────┴──────────┘\n", .{});
}

fn runBenchmarks(allocator: std.mem.Allocator) !void {
    std.debug.print("\n================================================================================\n", .{});
    std.debug.print("         Comprehensive Hash Table Benchmarks                                   \n", .{});
    std.debug.print("================================================================================\n", .{});
    std.debug.print("  Key types:   u32, u64, string (random length 8-64 chars)                    \n", .{});
    std.debug.print("  Value types: void (set), 4B, 64B                                            \n", .{});
    std.debug.print("  Sizes:       100, 3K, 100K                                                  \n", .{});
    std.debug.print("  Iterations:  {d} per measurement                                            \n", .{BENCHMARK_ITERATIONS});
    std.debug.print("================================================================================\n", .{});

    // u32 keys
    {
        std.debug.print("\n╔══════════════════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║                           u32 Integer Keys                                  ║\n", .{});
        std.debug.print("╚══════════════════════════════════════════════════════════════════════════════╝\n", .{});

        const u32_keys = try allocator.alloc(u32, SIZE_100K);
        defer allocator.free(u32_keys);
        const u32_miss = try allocator.alloc(u32, SIZE_100K);
        defer allocator.free(u32_miss);
        const u32_order = try allocator.alloc(usize, SIZE_100K);
        defer allocator.free(u32_order);

        var rng = makeRng(12345);
        var miss_rng = makeRng(99999);
        for (0..SIZE_100K) |i| {
            u32_keys[i] = rng.random().int(u32);
            u32_miss[i] = miss_rng.random().int(u32) | (1 << 31);
            u32_order[i] = i;
        }
        rng.random().shuffle(usize, u32_order);

        inline for (.{ void, Value4, Value64 }) |V| {
            try runAllSizes(u32, V, u32_keys, u32_miss, u32_order, allocator);
        }
    }

    // u64 keys
    {
        std.debug.print("\n╔══════════════════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║                           u64 Integer Keys                                  ║\n", .{});
        std.debug.print("╚══════════════════════════════════════════════════════════════════════════════╝\n", .{});

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

        inline for (.{ void, Value4, Value64 }) |V| {
            try runAllSizes(u64, V, u64_keys, u64_miss, u64_order, allocator);
        }
    }

    // String keys with random lengths (8-64 chars)
    {
        std.debug.print("\n╔══════════════════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║                    String Keys (Random Length 8-64 chars)                   ║\n", .{});
        std.debug.print("╚══════════════════════════════════════════════════════════════════════════════╝\n", .{});

        const key_storage = try allocator.alloc([80]u8, SIZE_100K);
        defer allocator.free(key_storage);
        const miss_storage = try allocator.alloc([80]u8, SIZE_100K);
        defer allocator.free(miss_storage);
        const str_keys = try allocator.alloc([]const u8, SIZE_100K);
        defer allocator.free(str_keys);
        const str_miss = try allocator.alloc([]const u8, SIZE_100K);
        defer allocator.free(str_miss);
        const str_order = try allocator.alloc(usize, SIZE_100K);
        defer allocator.free(str_order);

        var rng = makeRng(12345);
        for (0..SIZE_100K) |i| {
            const len = 8 + (rng.random().int(usize) % 57);
            for (0..len) |j| key_storage[i][j] = @truncate(32 + (rng.random().int(u8) % 95));
            str_keys[i] = key_storage[i][0..len];

            const miss_len = 8 + (rng.random().int(usize) % 57);
            for (0..miss_len) |j| miss_storage[i][j] = @truncate(32 + (rng.random().int(u8) % 95));
            miss_storage[i][0] = '~';
            str_miss[i] = miss_storage[i][0..miss_len];
            str_order[i] = i;
        }
        rng.random().shuffle(usize, str_order);

        inline for (.{ void, Value4, Value64 }) |V| {
            try runAllSizes([]const u8, V, str_keys, str_miss, str_order, allocator);
        }
    }
}

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    std.debug.print("\n================================================================================\n", .{});
    std.debug.print("                      TheHashTable Benchmark Suite v2                          \n", .{});
    std.debug.print("                                                                                \n", .{});
    std.debug.print("  Comparing:                                                                    \n", .{});
    std.debug.print("  - TheHashTable (Zig) — \"This\"                                                 \n", .{});
    std.debug.print("  - Abseil (C++):  flat_hash_map                                                \n", .{});
    std.debug.print("  - Boost (C++):   unordered_flat_map                                           \n", .{});
    std.debug.print("  - Ankerl (C++):  unordered_dense                                              \n", .{});
    std.debug.print("  - std (Zig):     std.AutoHashMap / std.StringHashMap                          \n", .{});
    std.debug.print("================================================================================\n\n", .{});

    std.debug.print("Configuration:\n", .{});
    std.debug.print("  - Warmup iterations:    {d}\n", .{WARMUP_ITERATIONS});
    std.debug.print("  - Benchmark iterations: {d}\n", .{BENCHMARK_ITERATIONS});
    std.debug.print("  - Test sizes:           100, 3K, 100K (timing), 1K-1M (memory)\n\n", .{});

    std.debug.print("Warming up...\n", .{});
    for (0..WARMUP_ITERATIONS) |_| {
        var map = TheHashTable(u64, u64).init(allocator);
        defer map.deinit();
        for (0..SIZE_100K) |i| try map.put(i, i);
    }

    try runBenchmarks(allocator);

    // Print key-type average tables
    std.debug.print("\n╔══════════════════════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                         AVERAGE BY KEY TYPE                                  ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════════════════════╝\n", .{});

    g_acc_u32.printTable("u32");
    g_acc_u64.printTable("u64");
    g_acc_string.printTable("string");

    try runMemoryBenchmarks(allocator);
    std.debug.print("\nBenchmark complete.\n", .{});
}
