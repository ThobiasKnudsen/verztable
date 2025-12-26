# TheHashTable

A high-performance hash table for Zig, inspired by [Verstable](https://github.com/JacksonAllan/Verstable).

## Features

- **Unified Map/Set**: `TheHashTable(K, V)` is a map; `TheHashTable(K, void)` is a set
- **Fast operations**: O(1) average for insert, lookup, and delete
- **Tombstone-free deletion**: No performance degradation after many deletes
- **Low memory overhead**: Only 2 bytes of metadata per bucket
- **SIMD-accelerated iteration**: Vectorized metadata scanning for fast iteration
- **Zero-cost generics**: Comptime-specialized for each key/value type

## Algorithm

Open-addressing with quadratic probing and linked chains per home bucket:
- **16-bit metadata per bucket**: 4-bit hash fragment | 1-bit home flag | 11-bit displacement
- Keys belonging to the same bucket form traversable chains
- Chains always start at their home bucket (evicting non-belonging keys if needed)
- Fast lookups impervious to load factor due to hash fragment filtering

## Usage

### Map (key -> value)

```zig
const std = @import("std");
const TheHashTable = @import("TheHashTable").TheHashTable;

var map = TheHashTable(u32, []const u8).init(allocator);
defer map.deinit();

// Insert
try map.put(42, "answer");

// Lookup
if (map.get(42)) |val| {
    std.debug.print("{s}\n", .{val}); // "answer"
}

// Update
try map.put(42, "new answer");

// Remove
_ = map.remove(42);
```

### Set (V = void)

When V is `void`, TheHashTable becomes a set with zero value storage overhead:

```zig
var set = TheHashTable([]const u8, void).init(allocator);
defer set.deinit();

// Add elements
try set.add("apple");
try set.add("banana");

// Check membership
if (set.contains("apple")) {
    std.debug.print("found!\n", .{});
}

// Remove
_ = set.remove("apple");
```

### Accumulation with getOrPut

```zig
var freq = TheHashTable([]const u8, u32).init(allocator);
defer freq.deinit();

for (words) |word| {
    const result = try freq.getOrPut(word);
    if (!result.found_existing) {
        result.value_ptr.* = 0;
    }
    result.value_ptr.* += 1;
}
```

### Iteration

```zig
// Over buckets (key + value)
var iter = map.iterator();
while (iter.next()) |bucket| {
    std.debug.print("{}: {}\n", .{ bucket.key, bucket.val });
}

// Over keys only
var key_iter = map.keyIterator();
while (key_iter.next()) |key| {
    // ...
}

// Over values only
var val_iter = map.valueIterator();
while (val_iter.next()) |val| {
    // ...
}
```

### Configuration

```zig
var map = TheHashTable(u32, u32).init(allocator);

// Adjust load factor (default: 0.875)
map.setMaxLoadFactor(0.75);

// Pre-allocate for expected size
try map.reserve(1000);

// Shrink to fit current size
try map.shrink();

// Clone
var map2 = try map.clone();
```

### Custom Hash Functions

```zig
const TheHashTableWithFns = @import("TheHashTable").TheHashTableWithFns;

const MyHash = struct {
    fn hash(key: MyKey) u64 { ... }
};
const MyEql = struct {
    fn eql(a: MyKey, b: MyKey) bool { ... }
};

var map = TheHashTableWithFns(MyKey, MyValue, MyHash.hash, MyEql.eql).init(allocator);
```

## API Reference

### Types
- `TheHashTable(K, V)` - Hash table with auto-detected hash/eql functions
- `TheHashTableWithFns(K, V, hashFn, eqlFn)` - Hash table with custom functions

### Map Methods (V != void)
| Method | Description |
|--------|-------------|
| `put(key, value)` | Insert or update |
| `putNoClobber(key, value)` | Insert only if not exists, returns bool |
| `get(key)` | Returns `?V` |
| `getPtr(key)` | Returns `?*V` for modification |
| `getOrPut(key)` | Returns `{value_ptr, found_existing}` |
| `getEntry(key)` | Returns `?{key_ptr, value_ptr}` |

### Set Methods (V == void)
| Method | Description |
|--------|-------------|
| `add(key)` | Add to set |
| `contains(key)` | Returns bool |

### Common Methods
| Method | Description |
|--------|-------------|
| `remove(key)` | Remove, returns bool |
| `clear()` | Remove all entries |
| `count()` | Number of entries |
| `capacity()` | Current capacity |
| `bucketCount()` | Number of buckets |
| `reserve(n)` | Pre-allocate for n entries |
| `shrink()` | Shrink to fit |
| `clone()` | Deep copy |
| `iterator()` | Iterate over buckets |
| `keyIterator()` | Iterate over keys |
| `valueIterator()` | Iterate over values (maps only) |
| `setMaxLoadFactor(f)` | Set load factor (0.1 - 0.99) |

## Performance

TheHashTable provides:
- **Fast lookups impervious to load factor**: Hash fragments allow skipping non-matching keys without accessing bucket data
- **Fast insertions**: Only moves at most one existing key
- **Fast, tombstone-free deletions**: Only moves at most one existing key
- **Fast iteration**: Separate metadata array enables SIMD-accelerated scanning

### Benchmarks

Run the benchmark suite comparing TheHashTable against Abseil, Boost, Ankerl, and Zig's std hash maps:

```bash
zig build benchmark
```

See [BENCHMARKS.md](BENCHMARKS.md) for detailed benchmark results.

## License

MIT License - see [LICENSE](LICENSE)

## Credits

Algorithm design inspired by [Verstable](https://github.com/JacksonAllan/Verstable) by Jackson Allan.
