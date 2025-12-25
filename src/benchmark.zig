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

const cpp = @cImport({
    @cInclude("cpp_hashtables_wrapper.h");
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

const Value56 = extern struct {
    data: [56]u8 = .{0} ** 56,
    fn fromU64(v: u64) Value56 {
        var r: Value56 = .{};
        const bytes: [8]u8 = @bitCast(v);
        inline for (0..7) |j| {
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
    const val_name = if (V == void) "void" else if (V == Value4) "val4" else if (V == Value64) "val64" else if (V == Value56) "val56" else @compileError("Unsupported value type");
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
// C++ Hash Table Wrappers (Abseil, Boost, Ankerl)
// ============================================================================

fn CppWrapper(comptime lib_prefix: []const u8, comptime K: type, comptime V: type) type {
    const key_name = if (K == u64) "u64" else if (K == u16) "u16" else if (K == []const u8) "str" else @compileError("Unsupported key type");
    const val_name = if (V == void) "void" else if (V == Value4) "val4" else if (V == Value64) "val64" else if (V == Value56) "val56" else @compileError("Unsupported value type");
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

        pub fn init() Self {
            return .{ .handle = initFn() };
        }
        pub fn deinit(self: *Self) void {
            cleanupFn(self.handle);
        }
        pub fn insert(self: *Self, key: K, val: V) bool {
            if (K == []const u8) {
                return if (V == void) insertFn(self.handle, key.ptr, key.len) != 0 else insertFn(self.handle, key.ptr, key.len, &val.data) != 0;
            } else {
                return if (V == void) insertFn(self.handle, key) != 0 else insertFn(self.handle, key, &val.data) != 0;
            }
        }
        pub fn get(self: *Self, key: K) bool {
            return if (K == []const u8) getFn(self.handle, key.ptr, key.len) != 0 else getFn(self.handle, key) != 0;
        }
        pub fn erase(self: *Self, key: K) bool {
            return if (K == []const u8) eraseFn(self.handle, key.ptr, key.len) != 0 else eraseFn(self.handle, key) != 0;
        }
        pub fn iterCount(self: *Self) u64 {
            return iterCountFn(self.handle);
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
// Generic Benchmark Runner
// ============================================================================

const BenchOp = enum { insert, update, lookup, miss, delete, iter, churn, mixed };

fn Benchmarks(comptime K: type, comptime V: type) type {
    return struct {
        const is_set = V == void;
        const is_string = K == []const u8;

        fn keyToU64(key: K) u64 {
            return if (K == u16 or K == u64) key else 0;
        }

        // TheHashTable benchmarks
        fn benchOurs(comptime Op: BenchOp, comptime size: usize, keys: []const K, extra: anytype, alloc: std.mem.Allocator) !u64 {
            const Map = TheHashTable(K, V);
            var total: u64 = 0;

            for (0..BENCHMARK_ITERATIONS) |_| {
                var map = Map.init(alloc);
                defer map.deinit();

                // Setup (except for insert which measures this)
                // Churn starts half-full to stress add/remove cycles
                // Mixed starts full to simulate realistic steady-state usage
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
                    .update => for (keys[0..size]) |k| {
                        // Update existing keys with new values (table already full)
                        if (is_set) try map.add(k) else try map.put(k, makeValue(V, keyToU64(k) +% 1));
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
                    .mixed => {
                        // Realistic mixed workload: 65% hit, 10% miss, 10% update, 10% delete, 5% iter
                        // Pre-generated ops and indices are passed via extra
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        const ops = mixed_data.ops[0..size];
                        const indices = mixed_data.indices[0..size];
                        const hit_keys = mixed_data.hit_keys;
                        const miss_keys_ptr = mixed_data.miss_keys;
                        for (ops, indices) |op, idx| {
                            switch (op) {
                                0 => { // lookup hit
                                    if (is_set) {
                                        if (map.contains(hit_keys[idx])) found += 1;
                                    } else {
                                        if (map.get(hit_keys[idx]) != null) found += 1;
                                    }
                                },
                                1 => { // lookup miss
                                    if (is_set) {
                                        if (!map.contains(miss_keys_ptr[idx])) found += 1;
                                    } else {
                                        if (map.get(miss_keys_ptr[idx]) == null) found += 1;
                                    }
                                },
                                2 => { // update
                                    if (is_set) try map.add(hit_keys[idx]) else try map.put(hit_keys[idx], makeValue(V, keyToU64(hit_keys[idx])));
                                },
                                3 => { // delete
                                    _ = map.remove(hit_keys[idx]);
                                },
                                else => { // iter
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
                total += timer.read();
            }
            return total / BENCHMARK_ITERATIONS;
        }

        // std.HashMap benchmarks
        fn benchStd(comptime Op: BenchOp, comptime size: usize, keys: []const K, extra: anytype, alloc: std.mem.Allocator) !u64 {
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
                    .update => for (keys[0..size]) |k| {
                        // Update existing keys with new values (table already full)
                        try map.put(k, makeValue(V, keyToU64(k) +% 1));
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
                    .mixed => {
                        // Realistic mixed workload: 65% hit, 10% miss, 10% update, 10% delete, 5% iter
                        // Pre-generated ops and indices are passed via extra
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        const ops = mixed_data.ops[0..size];
                        const indices = mixed_data.indices[0..size];
                        const hit_keys = mixed_data.hit_keys;
                        const miss_keys_ptr = mixed_data.miss_keys;
                        for (ops, indices) |op, idx| {
                            switch (op) {
                                0 => { // lookup hit
                                    if (map.get(hit_keys[idx]) != null) found += 1;
                                },
                                1 => { // lookup miss
                                    if (map.get(miss_keys_ptr[idx]) == null) found += 1;
                                },
                                2 => { // update
                                    try map.put(hit_keys[idx], makeValue(V, keyToU64(hit_keys[idx])));
                                },
                                3 => { // delete
                                    _ = map.remove(hit_keys[idx]);
                                },
                                else => { // iter
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
                total += timer.read();
            }
            return total / BENCHMARK_ITERATIONS;
        }

        // Verstable benchmarks
        fn benchVt(comptime Op: BenchOp, comptime size: usize, keys: []const K, extra: anytype) !u64 {
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
                    .update => for (keys[0..size]) |k| {
                        // Update existing keys with new values (table already full)
                        _ = map.insert(k, makeValue(V, keyToU64(k) +% 1));
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
                    .mixed => {
                        // Realistic mixed workload: 65% hit, 10% miss, 10% update, 10% delete, 5% iter
                        // Pre-generated ops and indices are passed via extra
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        const ops = mixed_data.ops[0..size];
                        const indices = mixed_data.indices[0..size];
                        const hit_keys = mixed_data.hit_keys;
                        const miss_keys_ptr = mixed_data.miss_keys;
                        for (ops, indices) |op, idx| {
                            switch (op) {
                                0 => { // lookup hit
                                    if (map.get(hit_keys[idx])) found += 1;
                                },
                                1 => { // lookup miss
                                    if (!map.get(miss_keys_ptr[idx])) found += 1;
                                },
                                2 => { // update
                                    _ = map.insert(hit_keys[idx], makeValue(V, keyToU64(hit_keys[idx])));
                                },
                                3 => { // delete
                                    _ = map.erase(hit_keys[idx]);
                                },
                                else => { // iter
                                    var iter = VtMap.firstFn(&map.map);
                                    var steps: usize = 0;
                                    while (VtMap.is_endFn(iter) == 0) : (iter = VtMap.nextFn(iter)) {
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
                total += timer.read();
            }
            return total / BENCHMARK_ITERATIONS;
        }

        // Generic C++ wrapper benchmark (for Abseil, Boost, Ankerl)
        fn benchCpp(comptime WrapperFn: fn (type, type) type, comptime Op: BenchOp, comptime size: usize, keys: []const K, extra: anytype) !u64 {
            const CppMap = WrapperFn(K, V);
            var total: u64 = 0;

            for (0..BENCHMARK_ITERATIONS) |_| {
                var map = CppMap.init();
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
                    .update => for (keys[0..size]) |k| {
                        _ = map.insert(k, makeValue(V, keyToU64(k) +% 1));
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
                    .mixed => {
                        const mixed_data: *const MixedOpsData(K) = @ptrCast(@alignCast(extra));
                        var found: u64 = 0;
                        const ops = mixed_data.ops[0..size];
                        const indices = mixed_data.indices[0..size];
                        const hit_keys = mixed_data.hit_keys;
                        const miss_keys_ptr = mixed_data.miss_keys;
                        for (ops, indices) |op, idx| {
                            switch (op) {
                                0 => if (map.get(hit_keys[idx])) {
                                    found += 1;
                                },
                                1 => if (!map.get(miss_keys_ptr[idx])) {
                                    found += 1;
                                },
                                2 => {
                                    _ = map.insert(hit_keys[idx], makeValue(V, keyToU64(hit_keys[idx])));
                                },
                                3 => {
                                    _ = map.erase(hit_keys[idx]);
                                },
                                else => {
                                    // Note: C++ wrapper doesn't expose partial iteration,
                                    // so we just call iterCount which iterates all elements.
                                    // This is intentionally different from Zig implementations
                                    // which only iterate 10 steps - making this a full-iter test
                                    // for C++ libs. For fair comparison, we skip the iter op.
                                    found += 1; // Just count, don't iterate
                                },
                            }
                        }
                        std.mem.doNotOptimizeAway(found);
                    },
                }
                total += timer.read();
            }
            return total / BENCHMARK_ITERATIONS;
        }

        // Convenience functions for each C++ implementation
        fn benchAbsl(comptime Op: BenchOp, comptime size: usize, keys: []const K, extra: anytype) !u64 {
            return benchCpp(AbslWrapper, Op, size, keys, extra);
        }

        fn benchBoost(comptime Op: BenchOp, comptime size: usize, keys: []const K, extra: anytype) !u64 {
            return benchCpp(BoostWrapper, Op, size, keys, extra);
        }

        fn benchAnkerl(comptime Op: BenchOp, comptime size: usize, keys: []const K, extra: anytype) !u64 {
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
        std.debug.print("{d:>6.1} us", .{@as(f64, @floatFromInt(ns)) / 1000.0});
    } else if (ns < 1_000_000_000) {
        std.debug.print("{d:>6.1} ms", .{@as(f64, @floatFromInt(ns)) / 1_000_000.0});
    } else {
        std.debug.print("{d:>6.1} s ", .{@as(f64, @floatFromInt(ns)) / 1_000_000_000.0});
    }
}

const BenchResults = struct {
    ours: u64,
    vt: ?u64 = null,
    absl: ?u64 = null,
    boost: ?u64 = null,
    ankerl: ?u64 = null,
    std_val: u64,
};

fn printRowFull(name: []const u8, r: BenchResults) void {
    std.debug.print("  │ {s:<14} │", .{name});
    printTime(r.ours);
    std.debug.print(" │", .{});
    if (r.vt) |v| {
        printTime(v);
        std.debug.print(" │", .{});
    }
    if (r.absl) |v| {
        printTime(v);
        std.debug.print(" │", .{});
    }
    if (r.boost) |v| {
        printTime(v);
        std.debug.print(" │", .{});
    }
    if (r.ankerl) |v| {
        printTime(v);
        std.debug.print(" │", .{});
    }
    printTime(r.std_val);
    std.debug.print(" │\n", .{});
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
    return if (V == void) "void (set)" else if (V == Value4) "4B" else if (V == Value64) "64B" else if (V == Value56) "56B" else "?";
}

const Xoshiro = std.Random.Xoshiro256;
fn makeRng(seed: u64) Xoshiro {
    return Xoshiro.init(seed);
}

/// Pre-generated operation sequence for Mixed benchmark to exclude RNG overhead from timing
fn MixedOpsData(comptime K: type) type {
    return struct {
        ops: []u8, // 0=lookup_hit, 1=lookup_miss, 2=update, 3=delete, 4=iter
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
        if (op_roll < 65) {
            ops[i] = 0; // lookup hit
        } else if (op_roll < 75) {
            ops[i] = 1; // lookup miss
        } else if (op_roll < 85) {
            ops[i] = 2; // update
        } else if (op_roll < 95) {
            ops[i] = 3; // delete
        } else {
            ops[i] = 4; // iter
        }
    }
    return .{ .ops = ops, .indices = indices };
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
    const include_cpp = K == u64 or K == u16 or K == []const u8;

    // Pre-generate mixed ops data (RNG outside timing)
    const mixed_gen = try generateMixedOps(size, allocator);
    defer allocator.free(mixed_gen.ops);
    defer allocator.free(mixed_gen.indices);
    const mixed_data = MixedOpsData(K){
        .ops = mixed_gen.ops,
        .indices = mixed_gen.indices,
        .hit_keys = keys,
        .miss_keys = miss_keys,
    };

    std.debug.print("\n  {s} elements:\n", .{size_str});
    if (include_cpp) {
        std.debug.print("  ┌────────────────┬──────────┬──────────┬──────────┬──────────┬──────────┬──────────┐\n", .{});
        std.debug.print("  │ Operation      │ Ours     │ Verstab  │ Abseil   │ Boost    │ Ankerl   │ std      │\n", .{});
        std.debug.print("  ├────────────────┼──────────┼──────────┼──────────┼──────────┼──────────┼──────────┤\n", .{});
    } else {
        std.debug.print("  ┌────────────────┬──────────┬──────────┐\n", .{});
        std.debug.print("  │ Operation      │ Ours     │ std      │\n", .{});
        std.debug.print("  ├────────────────┼──────────┼──────────┤\n", .{});
    }

    const ops = [_]struct { name: []const u8, op: @TypeOf(.insert) }{
        .{ .name = "Rand. Insert", .op = .insert },
        .{ .name = "Update", .op = .update },
        .{ .name = "Rand. Lookup", .op = .lookup },
        .{ .name = "Lookup Miss", .op = .miss },
        .{ .name = "Delete", .op = .delete },
        .{ .name = "Iteration", .op = .iter },
        .{ .name = "Churn", .op = .churn },
        .{ .name = "Mixed", .op = .mixed },
    };

    inline for (ops) |o| {
        if (o.op == .mixed) {
            const ours = try B.benchOurs(.mixed, size, keys, &mixed_data, allocator) / size;
            const std_val = try B.benchStd(.mixed, size, keys, &mixed_data, allocator) / size;
            const vt_val: ?u64 = if (include_cpp) try B.benchVt(.mixed, size, keys, &mixed_data) / size else null;
            const absl_val: ?u64 = if (include_cpp) try B.benchAbsl(.mixed, size, keys, &mixed_data) / size else null;
            const boost_val: ?u64 = if (include_cpp) try B.benchBoost(.mixed, size, keys, &mixed_data) / size else null;
            const ankerl_val: ?u64 = if (include_cpp) try B.benchAnkerl(.mixed, size, keys, &mixed_data) / size else null;
            printRowFull(o.name, .{ .ours = ours, .vt = vt_val, .absl = absl_val, .boost = boost_val, .ankerl = ankerl_val, .std_val = std_val });
        } else {
            const op_extra = if (o.op == .miss) miss_keys else if (o.op == .lookup) lookup_order else {};
            const ours = try B.benchOurs(o.op, size, keys, op_extra, allocator) / size;
            const std_val = try B.benchStd(o.op, size, keys, op_extra, allocator) / size;
            const vt_val: ?u64 = if (include_cpp) try B.benchVt(o.op, size, keys, op_extra) / size else null;
            const absl_val: ?u64 = if (include_cpp) try B.benchAbsl(o.op, size, keys, op_extra) / size else null;
            const boost_val: ?u64 = if (include_cpp) try B.benchBoost(o.op, size, keys, op_extra) / size else null;
            const ankerl_val: ?u64 = if (include_cpp) try B.benchAnkerl(o.op, size, keys, op_extra) / size else null;
            printRowFull(o.name, .{ .ours = ours, .vt = vt_val, .absl = absl_val, .boost = boost_val, .ankerl = ankerl_val, .std_val = std_val });
        }
    }

    if (include_cpp) {
        std.debug.print("  └────────────────┴──────────┴──────────┴──────────┴──────────┴──────────┴──────────┘\n", .{});
    } else {
        std.debug.print("  └────────────────┴──────────┴──────────┘\n", .{});
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
    std.debug.print("  Value types: void (set), 4B, 64B, 56B                                        \n", .{});
    std.debug.print("  Sizes:       10, 1K, 65524 (u16) / 10, 1K, 100K (u64, string)                \n", .{});
    std.debug.print("  Operations:  Insert, Update, Lookup, Miss, Delete, Iter, Churn, Mixed       \n", .{});
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

        inline for (.{ void, Value4, Value64, Value56 }) |V| {
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

        inline for (.{ void, Value4, Value64, Value56 }) |V| {
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

        inline for (.{ void, Value4, Value64, Value56 }) |V| {
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
    std.debug.print("  - TheHashTable (Zig)                                                          \n", .{});
    std.debug.print("  - Verstable (C): https://github.com/JacksonAllan/Verstable                    \n", .{});
    std.debug.print("  - Abseil (C++):  https://github.com/abseil/abseil-cpp (flat_hash_map)         \n", .{});
    std.debug.print("  - Boost (C++):   https://github.com/boostorg/unordered (unordered_flat_map)   \n", .{});
    std.debug.print("  - Ankerl (C++):  https://github.com/martinus/unordered_dense                  \n", .{});
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
