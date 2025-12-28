//! verztable - A high-performance hash table for Zig
//!
//! A Zig port of Verstable (https://github.com/JacksonAllan/Verstable),
//! bringing the speed and memory efficiency of state-of-the-art C++ hash tables to Zig.
//!
//! ## Features
//! - **Unified Map/Set**: `HashMap(K, V)` is a map; `HashMap(K, void)` is a set
//! - **Fast operations**: O(1) average for insert, lookup, and delete
//! - **Tombstone-free deletion**: No performance degradation after many deletes
//! - **Low memory overhead**: Only 2 bytes per bucket
//! - **SIMD-accelerated iteration**: Vectorized metadata scanning
//!
//! ## Algorithm
//! Open-addressing with linear probing and linked chains per home bucket.
//! Linear probing provides excellent cache locality while chains enable tombstone-free deletion.
//! Each bucket has 16-bit metadata: 4-bit hash fragment | 1-bit home flag | 11-bit displacement.

const std = @import("std");
const Allocator = std.mem.Allocator;
const math = std.math;

// ============================================================================
// Metadata Constants
// ============================================================================

/// Metadata type - u16 is compact and cache-efficient
const MetaType = u16;
const META_BITS = 16;

/// Empty bucket marker
const EMPTY: MetaType = 0x0000;

/// User-configurable trade-off: number of hash fragment bits.
/// Higher values → better collision filtering (fewer expensive key equality checks, especially good for string keys)
/// Lower values → longer possible chains (fewer premature rehashes, better for large values or small tables)
/// Recommended range: 4–10
pub const HASH_FRAG_SIZE_BITS: usize = 4; // Change this single value to tune!

/// Derived metadata masks (do not edit these directly)
pub const HASH_FRAG_MASK: MetaType = @as(MetaType, ((@as(u32, 1) << HASH_FRAG_SIZE_BITS) - 1) << (META_BITS - HASH_FRAG_SIZE_BITS));

pub const IN_HOME_BUCKET_MASK: MetaType = @as(MetaType, 1) << (META_BITS - 1 - HASH_FRAG_SIZE_BITS);

pub const DISPLACEMENT_MASK: MetaType = (@as(MetaType, 1) << (META_BITS - 1 - HASH_FRAG_SIZE_BITS)) - 1;

/// Minimum non-zero bucket count (must be power of two)
const MIN_NONZERO_BUCKET_COUNT: usize = 16;

/// Default maximum load factor (87.5% - matches Abseil/Swiss Tables)
const DEFAULT_MAX_LOAD: f32 = 0.875;

// ============================================================================
// Hash Functions
// ============================================================================

/// Fast-hash for integers (64-bit mixer)
/// Based on fast-hash by Zilong Tan - proven faster than splitmix64/Murmur3.
/// See: https://jonkagstrom.com/bit-mixer-construction
/// This matches Verstable's vt_hash_integer for consistent performance.
pub fn hashInteger(key: u64) u64 {
    var x = key;
    x ^= x >> 23;
    x *%= 0x2127599bf4325c37;
    x ^= x >> 47;
    return x;
}

/// Wyhash for byte slices - high quality, fast string hash
/// Based on https://github.com/wangyi-fudan/wyhash
pub fn wyhash(key: []const u8) u64 {
    const secret0: u64 = 0x8bb84b93962eacc9;
    const secret1: u64 = 0x4b33a62ed433d4a3;
    const secret2: u64 = 0x4d5a2da51de1aa47;
    const secret3: u64 = 0x2d358dccaa6c78a5;

    var seed: u64 = 0xca813bf4c7abf0a9;
    const len = key.len;
    var p = key.ptr;
    var a: u64 = undefined;
    var b: u64 = undefined;

    if (len <= 16) {
        if (len >= 4) {
            a = (@as(u64, wyr4(p)) << 32) | wyr4(p + ((len >> 3) << 2));
            b = (@as(u64, wyr4(p + len - 4)) << 32) | wyr4(p + len - 4 - ((len >> 3) << 2));
        } else if (len > 0) {
            a = wyr3(p, len);
            b = 0;
        } else {
            a = 0;
            b = 0;
        }
    } else {
        var i = len;
        if (i >= 48) {
            var see1 = seed;
            var see2 = seed;
            while (i >= 48) {
                seed = wymix(wyr8(p) ^ secret0, wyr8(p + 8) ^ seed);
                see1 = wymix(wyr8(p + 16) ^ secret1, wyr8(p + 24) ^ see1);
                see2 = wymix(wyr8(p + 32) ^ secret2, wyr8(p + 40) ^ see2);
                p += 48;
                i -= 48;
            }
            seed ^= see1 ^ see2;
        }

        while (i > 16) {
            seed = wymix(wyr8(p) ^ secret0, wyr8(p + 8) ^ seed);
            i -= 16;
            p += 16;
        }

        a = wyr8(p + i - 16);
        b = wyr8(p + i - 8);
    }

    a ^= secret0;
    b ^= seed;
    const mum_result = wymum(a, b);
    return wymix(mum_result[0] ^ secret3 ^ len, mum_result[1] ^ secret0);
}

fn wymum(a: u64, b: u64) [2]u64 {
    const r: u128 = @as(u128, a) * @as(u128, b);
    return .{ @truncate(r), @truncate(r >> 64) };
}

fn wymix(a: u64, b: u64) u64 {
    const result = wymum(a, b);
    return result[0] ^ result[1];
}

fn wyr8(p: [*]const u8) u64 {
    return std.mem.readInt(u64, p[0..8], .little);
}

fn wyr4(p: [*]const u8) u32 {
    return std.mem.readInt(u32, p[0..4], .little);
}

fn wyr3(p: [*]const u8, k: usize) u64 {
    return (@as(u64, p[0]) << 16) | (@as(u64, p[k >> 1]) << 8) | p[k - 1];
}

// ============================================================================
// Default Hash/Eql Functions
// ============================================================================

fn AutoHashFn(comptime K: type) type {
    return struct {
        fn hash(key: K) u64 {
            const info = @typeInfo(K);
            return switch (info) {
                .int, .comptime_int => hashInteger(@as(u64, @intCast(key))),
                .pointer => |ptr| if (ptr.size == .slice and ptr.child == u8)
                    hashString(key)
                else
                    hashInteger(@intFromPtr(key)),
                .array => |arr| if (arr.child == u8)
                    hashString(&key)
                else
                    @compileError("Unsupported key type for auto hash: " ++ @typeName(K)),
                .@"enum" => hashInteger(@intFromEnum(key)),
                else => @compileError("Unsupported key type for auto hash: " ++ @typeName(K)),
            };
        }
    };
}

/// Hash function for strings with fast path for short strings.
/// For strings <= 8 bytes, we pack into u64 and use the integer hash.
/// For longer strings, we use the full wyhash.
fn hashString(key: []const u8) u64 {
    // Fast path: short strings can be packed into a u64
    if (key.len <= 8) {
        var k: u64 = 0;
        const dest: *[8]u8 = @ptrCast(&k);
        @memcpy(dest[0..key.len], key);
        // Mix in the length to differentiate e.g. "a\x00" from "a"
        return hashInteger(k ^ (@as(u64, key.len) << 56));
    }
    return wyhash(key);
}

fn AutoEqlFn(comptime K: type) type {
    return struct {
        fn eql(a: K, b: K) bool {
            const info = @typeInfo(K);
            return switch (info) {
                .int, .comptime_int, .@"enum" => a == b,
                .pointer => |ptr| if (ptr.size == .slice)
                    std.mem.eql(ptr.child, a, b)
                else
                    a == b,
                .array => std.mem.eql(@typeInfo(K).array.child, &a, &b),
                else => a == b,
            };
        }
    };
}

// ============================================================================
// Metadata Helpers
// ============================================================================

/// Extracts the high HASH_FRAG_SIZE_BITS bits of the hash and places them into the fragment position.
inline fn hashFrag(hash: u64) MetaType {
    return @as(MetaType, @truncate(hash >> (64 - HASH_FRAG_SIZE_BITS))) << (16 - HASH_FRAG_SIZE_BITS);
}

/// Linear probing - displacement IS the offset.
/// Better cache locality than quadratic, and with chain-based design we avoid clustering issues.
inline fn probeOffset(displacement: MetaType) usize {
    return displacement;
}

/// Find the first non-zero u16 in a group of 4 (64 bits).
/// Used for fast iteration over metadata.
inline fn firstNonZeroMeta(val: u64) u32 {
    if (val == 0) return 4;
    return @ctz(val) / 16;
}

/// SIMD-accelerated version: find first non-zero u16 in 8 metadata entries
inline fn firstNonZeroMetax8(metadata: [*]const MetaType) u32 {
    const vec: @Vector(8, MetaType) = metadata[0..8].*;
    const zero: @Vector(8, MetaType) = @splat(0);
    const mask = vec != zero;
    const bits = @as(u8, @bitCast(mask));
    if (bits == 0) return 8;
    return @ctz(bits);
}

// ============================================================================
// HashMap
// ============================================================================

/// A high-performance hash table that can function as either a map or a set.
///
/// When `V` is `void`, it operates as a set with zero value storage overhead.
/// Otherwise, it operates as a map associating keys with values.
///
/// ## Example (Map)
/// ```zig
/// var map = HashMap(u32, []const u8).init(allocator);
/// defer map.deinit();
/// try map.put(42, "hello");
/// if (map.get(42)) |val| std.debug.print("{s}\n", .{val});
/// ```
///
/// ## Example (Set)
/// ```zig
/// var set = HashMap(u32, void).init(allocator);
/// defer set.deinit();
/// try set.add(42);
/// if (set.contains(42)) std.debug.print("found!\n", .{});
/// ```
pub fn HashMap(comptime K: type, comptime V: type) type {
    return HashMapWithFns(K, V, AutoHashFn(K).hash, AutoEqlFn(K).eql);
}

/// Create a hash table with custom hash and equality functions.
pub fn HashMapWithFns(
    comptime K: type,
    comptime V: type,
    comptime hashFn: fn (K) u64,
    comptime eqlFn: fn (K, K) bool,
) type {
    const is_set = V == void;

    return struct {
        const Self = @This();

        // For string keys, store full hash to avoid expensive comparisons
        const is_string = @typeInfo(K) == .pointer and @typeInfo(K).pointer.size == .slice and @typeInfo(K).pointer.child == u8;

        /// Bucket contains key and optionally value
        pub const Bucket = if (is_set) struct {
            key: K,
            // Store full hash for string keys to avoid expensive memcmp
            full_hash: if (is_string) u64 else void = if (is_string) 0 else {},
        } else struct {
            key: K,
            val: V,
            full_hash: if (is_string) u64 else void = if (is_string) 0 else {},
        };

        /// Iterator for traversing the table using SIMD-accelerated scanning.
        pub const Iterator = struct {
            table: *const Self,
            index: usize,
            end_index: usize,

            pub fn next(self: *Iterator) ?*const Bucket {
                if (self.index >= self.end_index) return null;

                // Fast-forward to next non-empty bucket using SIMD
                self.fastForward();

                if (self.index >= self.end_index) return null;

                const i = self.index;
                self.index += 1;
                return &self.table.buckets[i];
            }

            /// Mutable iterator for modifying values
            pub fn nextMut(self: *Iterator, table: *Self) ?*Bucket {
                if (self.index >= self.end_index) return null;

                // Fast-forward to next non-empty bucket using SIMD
                self.fastForward();

                if (self.index >= self.end_index) return null;

                const i = self.index;
                self.index += 1;
                return &table.buckets[i];
            }

            /// Fast scan for next occupied bucket.
            /// Scans 4 metadata entries at a time using u64 reads for efficiency.
            inline fn fastForward(self: *Iterator) void {
                const metadata = self.table.metadata;
                const end = self.end_index;

                // Scan 4 buckets at a time using u64 reads
                while (self.index + 4 <= end) {
                    const ptr: [*]const u8 = @ptrCast(metadata + self.index);
                    // Use unaligned read to avoid alignment issues
                    const group: u64 = std.mem.readInt(u64, ptr[0..8], .little);
                    const offset = firstNonZeroMeta(group);
                    if (offset < 4) {
                        self.index += offset;
                        return;
                    }
                    self.index += 4;
                }

                // Scan remaining buckets one at a time
                while (self.index < end) {
                    if (metadata[self.index] != EMPTY) return;
                    self.index += 1;
                }
            }

            /// Reset iterator to beginning
            pub fn reset(self: *Iterator) void {
                self.index = 0;
            }
        };

        // Fields
        key_count: usize,
        buckets_mask: usize, // bucket_count - 1 (for fast masking), or 0 if empty
        buckets: [*]Bucket,
        metadata: [*]MetaType,
        allocator: Allocator,
        max_load: f32,

        // Placeholder for empty tables (avoids null checks)
        var empty_placeholder: [1]MetaType = .{EMPTY};

        /// Initialize an empty hash table.
        pub fn init(allocator: Allocator) Self {
            return .{
                .key_count = 0,
                .buckets_mask = 0,
                .buckets = undefined,
                .metadata = &empty_placeholder,
                .allocator = allocator,
                .max_load = DEFAULT_MAX_LOAD,
            };
        }

        /// Deinitialize and free all memory.
        pub fn deinit(self: *Self) void {
            if (self.buckets_mask != 0) {
                const alloc_size = self.totalAllocSize();
                const ptr: [*]u8 = @ptrCast(self.buckets);
                self.allocator.free(ptr[0..alloc_size]);
            }
            self.* = Self.init(self.allocator);
        }

        /// Set the maximum load factor (0.0 to 1.0).
        /// Higher values use less memory but may slow down operations.
        pub fn setMaxLoadFactor(self: *Self, factor: f32) void {
            self.max_load = @max(0.1, @min(0.99, factor));
        }

        /// Returns the number of keys in the table.
        pub fn count(self: *const Self) usize {
            return self.key_count;
        }

        /// Returns the current bucket count.
        pub fn bucketCount(self: *const Self) usize {
            return if (self.buckets_mask == 0) 0 else self.buckets_mask + 1;
        }

        /// Returns the current capacity before rehashing is needed.
        pub fn capacity(self: *const Self) usize {
            return @intFromFloat(@as(f32, @floatFromInt(self.bucketCount())) * self.max_load);
        }

        // ====================================================================
        // Map operations (when V != void)
        // ====================================================================

        /// Insert or update a key-value pair. Returns error on allocation failure.
        pub fn put(self: *Self, key: K, value: V) !void {
            if (is_set) @compileError("Use add() for sets");
            _ = try self.insertInternal(key, value, false, true);
        }

        /// Insert a key-value pair only if the key doesn't exist.
        /// Returns true if inserted, false if key already existed.
        pub fn putNoClobber(self: *Self, key: K, value: V) !bool {
            if (is_set) @compileError("Use add() for sets");
            const result = try self.insertInternal(key, value, false, false);
            return result.inserted;
        }

        /// Get the value associated with a key, or null if not found.
        pub fn get(self: *const Self, key: K) ?V {
            if (is_set) @compileError("Use contains() for sets");
            const bucket = self.getBucket(key) orelse return null;
            return bucket.val;
        }

        /// Get a pointer to the value for modification.
        pub fn getPtr(self: *Self, key: K) ?*V {
            if (is_set) @compileError("Use contains() for sets");
            const bucket = self.getBucketMut(key) orelse return null;
            return &bucket.val;
        }

        /// Get or insert - returns a pointer to the value, inserting a default if not present.
        /// For maps, this is very useful for accumulation patterns.
        pub fn getOrPut(self: *Self, key: K) !GetOrPutResult {
            if (is_set) @compileError("Use add() for sets");
            const result = try self.insertInternal(key, undefined, false, false);
            return .{
                .value_ptr = &self.buckets[result.bucket_idx].val,
                .found_existing = !result.inserted,
            };
        }

        /// Result type for getOrPut
        pub const GetOrPutResult = struct {
            value_ptr: *V,
            found_existing: bool,
        };

        /// Get the key-value entry, or null if not found.
        pub fn getEntry(self: *const Self, key: K) ?Entry {
            if (is_set) @compileError("Use contains() for sets");
            const bucket = self.getBucket(key) orelse return null;
            return .{ .key_ptr = &bucket.key, .value_ptr = &bucket.val };
        }

        /// Entry type containing pointers to both key and value
        pub const Entry = struct {
            key_ptr: *const K,
            value_ptr: *const V,
        };

        // ====================================================================
        // Set operations (when V == void)
        // ====================================================================

        /// Add a key to the set. Returns error on allocation failure.
        pub fn add(self: *Self, key: K) !void {
            if (!is_set) @compileError("Use put() for maps");
            _ = try self.insertInternal(key, {}, false, true);
        }

        /// Check if a key exists in the set.
        pub fn contains(self: *const Self, key: K) bool {
            return self.getBucket(key) != null;
        }

        // ====================================================================
        // Common operations
        // ====================================================================

        /// Remove a key from the table. Returns true if the key was found and removed.
        pub fn remove(self: *Self, key: K) bool {
            const result = self.getInternal(key);
            if (result.bucket_idx == null) return false;
            self.eraseAtIndex(result.bucket_idx.?, result.home_bucket);
            return true;
        }

        /// Remove all keys from the table without deallocating.
        pub fn clear(self: *Self) void {
            if (self.key_count == 0) return;
            const bucket_count = self.bucketCount();
            for (0..bucket_count) |i| {
                self.metadata[i] = EMPTY;
            }
            self.key_count = 0;
        }

        /// Returns an iterator over the table's buckets.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .table = self, .index = 0, .end_index = self.bucketCount() };
        }

        /// Returns an iterator over the keys.
        pub fn keyIterator(self: *const Self) KeyIterator {
            return .{ .inner = self.iterator() };
        }

        /// Returns an iterator over the values (only for maps).
        pub fn valueIterator(self: *const Self) ValueIterator {
            if (is_set) @compileError("Sets don't have values");
            return .{ .inner = self.iterator() };
        }

        /// Iterator over keys only
        pub const KeyIterator = struct {
            inner: Iterator,

            pub fn next(self: *KeyIterator) ?K {
                if (self.inner.next()) |bucket| {
                    return bucket.key;
                }
                return null;
            }

            pub fn reset(self: *KeyIterator) void {
                self.inner.reset();
            }
        };

        /// Iterator over values only (for maps)
        pub const ValueIterator = if (is_set) void else struct {
            inner: Iterator,

            pub fn next(self: *ValueIterator) ?V {
                if (self.inner.next()) |bucket| {
                    return bucket.val;
                }
                return null;
            }

            pub fn reset(self: *ValueIterator) void {
                self.inner.reset();
            }
        };

        /// Ensure capacity for at least `size` keys without rehashing.
        pub fn reserve(self: *Self, size: usize) !void {
            const min_buckets = self.minBucketCountForSize(size);
            if (min_buckets > self.bucketCount()) {
                try self.rehash(min_buckets);
            }
        }

        /// Pre-allocate capacity for `new_capacity` total keys (including existing ones).
        /// This is useful before bulk insertions to avoid repeated rehashing.
        /// Example: `try map.ensureTotalCapacity(1000);` before inserting 1000 items.
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) !void {
            try self.reserve(new_capacity);
        }

        /// Pre-allocate capacity for `additional_count` more keys beyond current count.
        /// This is useful when you know how many more items you'll add.
        pub fn ensureUnusedCapacity(self: *Self, additional_count: usize) !void {
            try self.reserve(self.key_count + additional_count);
        }

        /// Shrink the table to fit the current number of keys.
        pub fn shrink(self: *Self) !void {
            const min_buckets = self.minBucketCountForSize(self.key_count);
            if (min_buckets < self.bucketCount()) {
                if (min_buckets == 0) {
                    self.deinit();
                } else {
                    try self.rehash(min_buckets);
                }
            }
        }

        /// Clone the hash table.
        pub fn clone(self: *const Self) !Self {
            if (self.buckets_mask == 0) {
                return Self.init(self.allocator);
            }

            const alloc_size = self.totalAllocSize();
            const new_mem = try self.allocator.alloc(u8, alloc_size);
            const src_ptr: [*]const u8 = @ptrCast(self.buckets);
            @memcpy(new_mem, src_ptr[0..alloc_size]);

            var result = self.*;
            result.buckets = @ptrCast(@alignCast(new_mem.ptr));
            result.metadata = @ptrCast(@alignCast(new_mem.ptr + self.metadataOffset()));
            return result;
        }

        // ====================================================================
        // Internal Implementation
        // ====================================================================

        const InsertResult = struct {
            bucket_idx: usize,
            inserted: bool,
        };

        inline fn insertInternal(self: *Self, key: K, value: V, unique: bool, replace: bool) !InsertResult {
            while (true) {
                if (self.insertRaw(key, value, unique, replace)) |r| {
                    return r;
                } else {
                    // Need to grow and rehash - unlikely path
                    @branchHint(.unlikely);
                    const new_count = if (self.buckets_mask != 0)
                        self.bucketCount() * 2
                    else
                        MIN_NONZERO_BUCKET_COUNT;
                    try self.rehash(new_count);
                }
            }
        }

        inline fn insertRaw(self: *Self, key: K, value: V, unique: bool, replace: bool) ?InsertResult {
            // Empty table - trigger allocation
            if (self.buckets_mask == 0) return null;

            const hash = hashFn(key);
            const frag = hashFrag(hash);
            const home_bucket = hash & self.buckets_mask;

            // Prefetch bucket data while we check metadata (hides memory latency)
            @prefetch(&self.buckets[home_bucket], .{});

            // Case 1: Home bucket is empty or occupied by non-belonging key
            if ((self.metadata[home_bucket] & IN_HOME_BUCKET_MASK) == 0) {
                // Load factor check - unlikely to trigger during normal operation
                if (self.key_count + 1 > self.capacity()) {
                    @branchHint(.unlikely);
                    return null;
                }

                // Evict if occupied by non-belonging key
                if (self.metadata[home_bucket] != EMPTY) {
                    if (!self.evict(home_bucket)) {
                        @branchHint(.unlikely);
                        return null;
                    }
                }

                self.buckets[home_bucket].key = key;
                if (!is_set) {
                    self.buckets[home_bucket].val = value;
                }
                if (is_string) {
                    self.buckets[home_bucket].full_hash = hash;
                }
                self.metadata[home_bucket] = frag | IN_HOME_BUCKET_MASK | DISPLACEMENT_MASK;
                self.key_count += 1;

                return .{ .bucket_idx = home_bucket, .inserted = true };
            }

            // Case 2: Home bucket contains beginning of a chain
            // Search the chain for existing key (unless unique)
            if (!unique) {
                var bucket = home_bucket;
                while (true) {
                    // For strings: compare full hash first (much cheaper than memcmp)
                    const hash_match = if (is_string)
                        self.buckets[bucket].full_hash == hash
                    else
                        (self.metadata[bucket] & HASH_FRAG_MASK) == frag;

                    if (hash_match and eqlFn(self.buckets[bucket].key, key)) {
                        if (replace) {
                            self.buckets[bucket].key = key;
                            if (!is_set) {
                                self.buckets[bucket].val = value;
                            }
                        }
                        return .{ .bucket_idx = bucket, .inserted = false };
                    }

                    const displacement = self.metadata[bucket] & DISPLACEMENT_MASK;
                    if (displacement == DISPLACEMENT_MASK) break;
                    bucket = (home_bucket + probeOffset(displacement)) & self.buckets_mask;
                }
            }

            // Load factor check - unlikely to trigger during normal operation
            if (self.key_count + 1 > self.capacity()) {
                @branchHint(.unlikely);
                return null;
            }

            // Find empty bucket - unlikely to fail
            const empty_result = self.findFirstEmpty(home_bucket) orelse {
                @branchHint(.unlikely);
                return null;
            };
            const empty = empty_result.index;
            const displacement = empty_result.displacement;

            // Find insert location in chain
            const prev = self.findInsertLocationInChain(home_bucket, displacement);

            // Insert
            self.buckets[empty].key = key;
            if (!is_set) {
                self.buckets[empty].val = value;
            }
            if (is_string) {
                self.buckets[empty].full_hash = hash;
            }
            self.metadata[empty] = frag | (self.metadata[prev] & DISPLACEMENT_MASK);
            self.metadata[prev] = (self.metadata[prev] & ~DISPLACEMENT_MASK) | displacement;
            self.key_count += 1;

            return .{ .bucket_idx = empty, .inserted = true };
        }

        fn getBucket(self: *const Self, key: K) ?*const Bucket {
            const result = self.getInternal(key);
            if (result.bucket_idx) |idx| {
                return &self.buckets[idx];
            }
            return null;
        }

        fn getBucketMut(self: *Self, key: K) ?*Bucket {
            const result = self.getInternal(key);
            if (result.bucket_idx) |idx| {
                return &self.buckets[idx];
            }
            return null;
        }

        const GetResult = struct {
            bucket_idx: ?usize,
            home_bucket: usize,
        };

        inline fn getInternal(self: *const Self, key: K) GetResult {
            // Empty table - not found
            if (self.buckets_mask == 0) {
                return .{ .bucket_idx = null, .home_bucket = 0 };
            }

            const hash = hashFn(key);
            const home_bucket = hash & self.buckets_mask;

            // Prefetch the home bucket (we will definitely access it)
            @prefetch(&self.buckets[home_bucket], .{ .rw = .read });

            // If home bucket is empty or contains a non-home key, miss
            if ((self.metadata[home_bucket] & IN_HOME_BUCKET_MASK) == 0) {
                @branchHint(.unlikely);
                return .{ .bucket_idx = null, .home_bucket = home_bucket };
            }

            const frag = hashFrag(hash);
            var bucket = home_bucket;

            while (true) {
                // Check current bucket for match
                // For strings: compare full hash first (much cheaper than memcmp)
                const hash_match = if (is_string)
                    self.buckets[bucket].full_hash == hash
                else
                    (self.metadata[bucket] & HASH_FRAG_MASK) == frag;

                if (hash_match and eqlFn(self.buckets[bucket].key, key)) {
                    return .{ .bucket_idx = bucket, .home_bucket = home_bucket };
                }

                // Get displacement of current bucket
                const displacement = self.metadata[bucket] & DISPLACEMENT_MASK;

                // End of chain?
                if (displacement == DISPLACEMENT_MASK) {
                    @branchHint(.unlikely);
                    return .{ .bucket_idx = null, .home_bucket = home_bucket };
                }

                // Compute the *next* bucket in the chain
                const next_bucket = (home_bucket + probeOffset(displacement)) & self.buckets_mask;

                // Prefetch the next bucket (we will access it next iteration)
                @prefetch(&self.buckets[next_bucket], .{ .rw = .read, .locality = 1 });

                // Advance to next bucket
                bucket = next_bucket;
            }
        }

        fn eraseAtIndex(self: *Self, bucket_idx: usize, home_bucket: usize) void {
            self.key_count -= 1;

            // Case 1: Only key in chain
            if ((self.metadata[bucket_idx] & IN_HOME_BUCKET_MASK) != 0 and
                (self.metadata[bucket_idx] & DISPLACEMENT_MASK) == DISPLACEMENT_MASK)
            {
                self.metadata[bucket_idx] = EMPTY;
                return;
            }

            // Determine home bucket if not in home position
            var home = home_bucket;
            if ((self.metadata[bucket_idx] & IN_HOME_BUCKET_MASK) == 0) {
                home = hashFn(self.buckets[bucket_idx].key) & self.buckets_mask;
            }

            // Case 2: Last key in multi-key chain
            if ((self.metadata[bucket_idx] & DISPLACEMENT_MASK) == DISPLACEMENT_MASK) {
                // Find penultimate key
                var bucket = home;
                while (true) {
                    const displacement = self.metadata[bucket] & DISPLACEMENT_MASK;
                    const next = (home + probeOffset(displacement)) & self.buckets_mask;
                    if (next == bucket_idx) {
                        self.metadata[bucket] |= DISPLACEMENT_MASK;
                        self.metadata[bucket_idx] = EMPTY;
                        return;
                    }
                    bucket = next;
                }
            }

            // Case 3: Not the last key - swap with last and remove last
            var bucket = bucket_idx;
            while (true) {
                const displacement = self.metadata[bucket] & DISPLACEMENT_MASK;
                const prev = bucket;
                bucket = (home + probeOffset(displacement)) & self.buckets_mask;

                if ((self.metadata[bucket] & DISPLACEMENT_MASK) == DISPLACEMENT_MASK) {
                    // Found last - swap it to bucket_idx
                    self.buckets[bucket_idx] = self.buckets[bucket];
                    self.metadata[bucket_idx] = (self.metadata[bucket_idx] & ~HASH_FRAG_MASK) |
                        (self.metadata[bucket] & HASH_FRAG_MASK);
                    self.metadata[prev] |= DISPLACEMENT_MASK;
                    self.metadata[bucket] = EMPTY;
                    return;
                }
            }
        }

        const FindEmptyResult = struct {
            index: usize,
            displacement: MetaType,
        };

        inline fn findFirstEmpty(self: *Self, home_bucket: usize) ?FindEmptyResult {
            // Linear probing: check consecutive slots for cache efficiency
            var displacement: MetaType = 1;

            while (displacement < DISPLACEMENT_MASK) {
                const empty = (home_bucket +% displacement) & self.buckets_mask;
                if (self.metadata[empty] == EMPTY) {
                    return .{ .index = empty, .displacement = displacement };
                }
                displacement += 1;
            }

            // Displacement limit reached - extremely rare, triggers rehash
            return null;
        }

        inline fn findInsertLocationInChain(self: *Self, home_bucket: usize, displacement_to_empty: MetaType) usize {
            var candidate = home_bucket;
            while (true) {
                const displacement = self.metadata[candidate] & DISPLACEMENT_MASK;
                if (displacement > displacement_to_empty) {
                    return candidate;
                }
                candidate = (home_bucket + probeOffset(displacement)) & self.buckets_mask;
            }
        }

        inline fn evict(self: *Self, bucket: usize) bool {
            // Find home bucket of occupying key
            const home_bucket = hashFn(self.buckets[bucket].key) & self.buckets_mask;

            // Find previous key in chain
            var prev = home_bucket;
            while (true) {
                const displacement = self.metadata[prev] & DISPLACEMENT_MASK;
                const next = (home_bucket + probeOffset(displacement)) & self.buckets_mask;
                if (next == bucket) break;
                prev = next;
            }

            // Disconnect from chain
            self.metadata[prev] = (self.metadata[prev] & ~DISPLACEMENT_MASK) |
                (self.metadata[bucket] & DISPLACEMENT_MASK);

            // Find new empty bucket
            const empty_result = self.findFirstEmpty(home_bucket) orelse return false;
            const empty = empty_result.index;
            const displacement = empty_result.displacement;

            // Find insert location
            prev = self.findInsertLocationInChain(home_bucket, displacement);

            // Move key/value
            self.buckets[empty] = self.buckets[bucket];

            // Re-link
            self.metadata[empty] = (self.metadata[bucket] & HASH_FRAG_MASK) |
                (self.metadata[prev] & DISPLACEMENT_MASK);
            self.metadata[prev] = (self.metadata[prev] & ~DISPLACEMENT_MASK) | displacement;

            return true;
        }

        fn rehash(self: *Self, bucket_count: usize) !void {
            var new_count = bucket_count;
            while (true) {
                var new_table = Self{
                    .key_count = 0,
                    .buckets_mask = new_count - 1,
                    .buckets = undefined,
                    .metadata = undefined,
                    .allocator = self.allocator,
                    .max_load = self.max_load,
                };

                const alloc_size = new_table.totalAllocSizeForCount(new_count);
                const new_mem = try self.allocator.alloc(u8, alloc_size);
                errdefer self.allocator.free(new_mem);

                new_table.buckets = @ptrCast(@alignCast(new_mem.ptr));
                new_table.metadata = @ptrCast(@alignCast(new_mem.ptr + new_table.metadataOffsetForCount(new_count)));

                // Initialize metadata to empty
                @memset(new_table.metadata[0 .. new_count + 4], EMPTY);
                // Iteration stopper
                new_table.metadata[new_count] = 0x01;

                // Rehash all keys
                var success = true;
                if (self.buckets_mask != 0) {
                    for (0..self.bucketCount()) |i| {
                        if (self.metadata[i] != EMPTY) {
                            const value = if (is_set) {} else self.buckets[i].val;
                            const result = new_table.insertRaw(self.buckets[i].key, value, true, false);
                            if (result == null) {
                                success = false;
                                break;
                            }
                        }
                    }
                }

                if (!success) {
                    // Displacement limit hit - double and retry
                    self.allocator.free(new_mem);
                    new_count = new_count * 2;
                    continue;
                }

                // Free old allocation
                if (self.buckets_mask != 0) {
                    const old_size = self.totalAllocSize();
                    const old_ptr: [*]u8 = @ptrCast(self.buckets);
                    self.allocator.free(old_ptr[0..old_size]);
                }

                self.* = new_table;
                return;
            }
        }

        fn metadataOffset(self: *const Self) usize {
            return self.metadataOffsetForCount(self.bucketCount());
        }

        fn metadataOffsetForCount(self: *const Self, bucket_count: usize) usize {
            _ = self;
            const bucket_size = bucket_count * @sizeOf(Bucket);
            // Align to MetaType
            return std.mem.alignForward(usize, bucket_size, @alignOf(MetaType));
        }

        fn totalAllocSize(self: *const Self) usize {
            return self.totalAllocSizeForCount(self.bucketCount());
        }

        fn totalAllocSizeForCount(self: *const Self, bucket_count: usize) usize {
            return self.metadataOffsetForCount(bucket_count) + (bucket_count + 4) * @sizeOf(MetaType);
        }

        fn minBucketCountForSize(self: *const Self, size: usize) usize {
            if (size == 0) return 0;
            var bucket_count: usize = MIN_NONZERO_BUCKET_COUNT;
            while (size > @as(usize, @intFromFloat(@as(f32, @floatFromInt(bucket_count)) * self.max_load))) {
                bucket_count *= 2;
            }
            return bucket_count;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "basic map operations" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, []const u8).init(allocator);
    defer map.deinit();

    try map.put(1, "one");
    try map.put(2, "two");
    try map.put(3, "three");

    try std.testing.expectEqual(@as(usize, 3), map.count());
    try std.testing.expectEqualStrings("one", map.get(1).?);
    try std.testing.expectEqualStrings("two", map.get(2).?);
    try std.testing.expectEqualStrings("three", map.get(3).?);
    try std.testing.expect(map.get(4) == null);

    // Update
    try map.put(2, "TWO");
    try std.testing.expectEqualStrings("TWO", map.get(2).?);

    // Remove
    try std.testing.expect(map.remove(2));
    try std.testing.expect(map.get(2) == null);
    try std.testing.expectEqual(@as(usize, 2), map.count());

    // Remove non-existent
    try std.testing.expect(!map.remove(999));

    std.debug.print("HASH_FRAG_SIZE_BITS: {any}\n", .{HASH_FRAG_SIZE_BITS});
    std.debug.print("HASH_FRAG_MASK: {any}\n", .{HASH_FRAG_MASK});
    std.debug.print("IN_HOME_BUCKET_MASK: {any}\n", .{IN_HOME_BUCKET_MASK});
    std.debug.print("DISPLACEMENT_MASK: {any}\n", .{DISPLACEMENT_MASK});
}

test "basic set operations" {
    const allocator = std.testing.allocator;
    var set = HashMap(u32, void).init(allocator);
    defer set.deinit();

    try set.add(1);
    try set.add(2);
    try set.add(3);

    try std.testing.expectEqual(@as(usize, 3), set.count());
    try std.testing.expect(set.contains(1));
    try std.testing.expect(set.contains(2));
    try std.testing.expect(set.contains(3));
    try std.testing.expect(!set.contains(4));

    // Remove
    try std.testing.expect(set.remove(2));
    try std.testing.expect(!set.contains(2));
    try std.testing.expectEqual(@as(usize, 2), set.count());
}

test "string keys" {
    const allocator = std.testing.allocator;
    var map = HashMap([]const u8, i32).init(allocator);
    defer map.deinit();

    try map.put("hello", 1);
    try map.put("world", 2);
    try map.put("foo", 3);

    try std.testing.expectEqual(@as(i32, 1), map.get("hello").?);
    try std.testing.expectEqual(@as(i32, 2), map.get("world").?);
    try std.testing.expectEqual(@as(i32, 3), map.get("foo").?);
    try std.testing.expect(map.get("bar") == null);
}

test "many insertions and removals" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, u32).init(allocator);
    defer map.deinit();

    // Insert many
    for (0..1000) |i| {
        try map.put(@intCast(i), @intCast(i * 2));
    }
    try std.testing.expectEqual(@as(usize, 1000), map.count());

    // Verify all
    for (0..1000) |i| {
        try std.testing.expectEqual(@as(u32, @intCast(i * 2)), map.get(@intCast(i)).?);
    }

    // Remove every third
    for (0..1000) |i| {
        if (i % 3 == 0) {
            try std.testing.expect(map.remove(@intCast(i)));
        }
    }

    // Verify remaining
    var remaining: usize = 0;
    for (0..1000) |i| {
        if (i % 3 != 0) {
            try std.testing.expectEqual(@as(u32, @intCast(i * 2)), map.get(@intCast(i)).?);
            remaining += 1;
        } else {
            try std.testing.expect(map.get(@intCast(i)) == null);
        }
    }
    try std.testing.expectEqual(remaining, map.count());
}

test "iterator" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, u32).init(allocator);
    defer map.deinit();

    try map.put(1, 10);
    try map.put(2, 20);
    try map.put(3, 30);

    var sum: u32 = 0;
    var iter = map.iterator();
    while (iter.next()) |bucket| {
        sum += bucket.val;
    }
    try std.testing.expectEqual(@as(u32, 60), sum);
}

test "clone" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, u32).init(allocator);
    defer map.deinit();

    try map.put(1, 10);
    try map.put(2, 20);

    var map2 = try map.clone();
    defer map2.deinit();

    try std.testing.expectEqual(@as(u32, 10), map2.get(1).?);
    try std.testing.expectEqual(@as(u32, 20), map2.get(2).?);

    // Modify original shouldn't affect clone
    try map.put(1, 100);
    try std.testing.expectEqual(@as(u32, 10), map2.get(1).?);
}

test "reserve and shrink" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, u32).init(allocator);
    defer map.deinit();

    try map.reserve(100);
    try std.testing.expect(map.capacity() >= 100);

    for (0..50) |i| {
        try map.put(@intCast(i), @intCast(i));
    }

    try map.shrink();
    try std.testing.expectEqual(@as(usize, 50), map.count());
}

test "ensureTotalCapacity and ensureUnusedCapacity" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, u32).init(allocator);
    defer map.deinit();

    // Pre-allocate for 1000 items
    try map.ensureTotalCapacity(1000);
    try std.testing.expect(map.capacity() >= 1000);

    // Insert 500 items - should not cause any rehash
    const initial_bucket_count = map.bucketCount();
    for (0..500) |i| {
        try map.put(@intCast(i), @intCast(i));
    }
    try std.testing.expectEqual(initial_bucket_count, map.bucketCount());

    // ensureUnusedCapacity for 500 more - should not grow since we have room
    try map.ensureUnusedCapacity(500);
    try std.testing.expectEqual(initial_bucket_count, map.bucketCount());
}

test "clear" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, u32).init(allocator);
    defer map.deinit();

    for (0..100) |i| {
        try map.put(@intCast(i), @intCast(i));
    }
    try std.testing.expectEqual(@as(usize, 100), map.count());

    map.clear();
    try std.testing.expectEqual(@as(usize, 0), map.count());
    try std.testing.expect(map.get(50) == null);

    // Can still use after clear
    try map.put(1, 1);
    try std.testing.expectEqual(@as(u32, 1), map.get(1).?);
}

test "putNoClobber" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, u32).init(allocator);
    defer map.deinit();

    try std.testing.expect(try map.putNoClobber(1, 10));
    try std.testing.expect(!try map.putNoClobber(1, 20));
    try std.testing.expectEqual(@as(u32, 10), map.get(1).?);
}

test "enum keys" {
    const Color = enum { red, green, blue };
    const allocator = std.testing.allocator;
    var map = HashMap(Color, []const u8).init(allocator);
    defer map.deinit();

    try map.put(.red, "rouge");
    try map.put(.green, "vert");
    try map.put(.blue, "bleu");

    try std.testing.expectEqualStrings("rouge", map.get(.red).?);
    try std.testing.expectEqualStrings("vert", map.get(.green).?);
    try std.testing.expectEqualStrings("bleu", map.get(.blue).?);
}

test "getOrPut" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, u32).init(allocator);
    defer map.deinit();

    // First insert
    const result1 = try map.getOrPut(1);
    try std.testing.expect(!result1.found_existing);
    result1.value_ptr.* = 10;

    // Second access - should find existing
    const result2 = try map.getOrPut(1);
    try std.testing.expect(result2.found_existing);
    try std.testing.expectEqual(@as(u32, 10), result2.value_ptr.*);

    // Modify via pointer
    result2.value_ptr.* = 20;
    try std.testing.expectEqual(@as(u32, 20), map.get(1).?);
}

test "getEntry" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, []const u8).init(allocator);
    defer map.deinit();

    try map.put(42, "answer");

    const entry = map.getEntry(42).?;
    try std.testing.expectEqual(@as(u32, 42), entry.key_ptr.*);
    try std.testing.expectEqualStrings("answer", entry.value_ptr.*);

    try std.testing.expect(map.getEntry(999) == null);
}

test "key iterator" {
    const allocator = std.testing.allocator;
    var set = HashMap(u32, void).init(allocator);
    defer set.deinit();

    try set.add(10);
    try set.add(20);
    try set.add(30);

    var sum: u32 = 0;
    var iter = set.keyIterator();
    while (iter.next()) |key| {
        sum += key;
    }
    try std.testing.expectEqual(@as(u32, 60), sum);
}

test "value iterator" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, u32).init(allocator);
    defer map.deinit();

    try map.put(1, 100);
    try map.put(2, 200);
    try map.put(3, 300);

    var sum: u32 = 0;
    var iter = map.valueIterator();
    while (iter.next()) |val| {
        sum += val;
    }
    try std.testing.expectEqual(@as(u32, 600), sum);
}

test "empty table operations" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, u32).init(allocator);
    defer map.deinit();

    try std.testing.expectEqual(@as(usize, 0), map.count());
    try std.testing.expectEqual(@as(usize, 0), map.bucketCount());
    try std.testing.expect(map.get(1) == null);
    try std.testing.expect(!map.remove(1));

    var iter = map.iterator();
    try std.testing.expect(iter.next() == null);
}

test "set with many collisions" {
    const allocator = std.testing.allocator;
    var set = HashMap(u32, void).init(allocator);
    defer set.deinit();

    // Insert values that might have hash collisions
    for (0..500) |i| {
        try set.add(@intCast(i * 8)); // Multiples of 8
    }
    try std.testing.expectEqual(@as(usize, 500), set.count());

    // Verify all exist
    for (0..500) |i| {
        try std.testing.expect(set.contains(@intCast(i * 8)));
    }

    // Remove half
    for (0..250) |i| {
        try std.testing.expect(set.remove(@intCast(i * 8)));
    }
    try std.testing.expectEqual(@as(usize, 250), set.count());

    // Verify remaining
    for (250..500) |i| {
        try std.testing.expect(set.contains(@intCast(i * 8)));
    }
}

test "max load factor adjustment" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, u32).init(allocator);
    defer map.deinit();

    // Set low load factor
    map.setMaxLoadFactor(0.5);

    for (0..100) |i| {
        try map.put(@intCast(i), @intCast(i));
    }

    // With 0.5 load factor, bucket count should be >= 200
    try std.testing.expect(map.bucketCount() >= 200);
}

test "getPtr modification" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, u32).init(allocator);
    defer map.deinit();

    try map.put(1, 10);

    const ptr = map.getPtr(1).?;
    ptr.* = 999;

    try std.testing.expectEqual(@as(u32, 999), map.get(1).?);
}

test "custom hash function" {
    const MyHashFn = struct {
        fn hash(key: u32) u64 {
            return key; // Identity hash for testing
        }
    };
    const MyEqlFn = struct {
        fn eql(a: u32, b: u32) bool {
            return a == b;
        }
    };

    const allocator = std.testing.allocator;
    var map = HashMapWithFns(u32, u32, MyHashFn.hash, MyEqlFn.eql).init(allocator);
    defer map.deinit();

    try map.put(1, 10);
    try map.put(2, 20);

    try std.testing.expectEqual(@as(u32, 10), map.get(1).?);
    try std.testing.expectEqual(@as(u32, 20), map.get(2).?);
}

test "stress test - many operations" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, u32).init(allocator);
    defer map.deinit();

    // Insert 10000 items
    for (0..10000) |i| {
        try map.put(@intCast(i), @intCast(i * 3));
    }
    try std.testing.expectEqual(@as(usize, 10000), map.count());

    // Remove every other
    for (0..10000) |i| {
        if (i % 2 == 0) {
            _ = map.remove(@intCast(i));
        }
    }
    try std.testing.expectEqual(@as(usize, 5000), map.count());

    // Re-insert removed ones
    for (0..10000) |i| {
        if (i % 2 == 0) {
            try map.put(@intCast(i), @intCast(i * 5));
        }
    }
    try std.testing.expectEqual(@as(usize, 10000), map.count());

    // Verify
    for (0..10000) |i| {
        const expected: u32 = if (i % 2 == 0) @intCast(i * 5) else @intCast(i * 3);
        try std.testing.expectEqual(expected, map.get(@intCast(i)).?);
    }
}

test "iterator reset" {
    const allocator = std.testing.allocator;
    var map = HashMap(u32, u32).init(allocator);
    defer map.deinit();

    try map.put(1, 10);
    try map.put(2, 20);

    var iter = map.iterator();

    // First pass
    var count1: u32 = 0;
    while (iter.next()) |_| count1 += 1;
    try std.testing.expectEqual(@as(u32, 2), count1);

    // After reset
    iter.reset();
    var count2: u32 = 0;
    while (iter.next()) |_| count2 += 1;
    try std.testing.expectEqual(@as(u32, 2), count2);
}
