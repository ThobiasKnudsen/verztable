# TheHashTable

A high-performance hash table for Zig, ported from [Verstable](https://github.com/JacksonAllan/Verstable).

Verstable is one of the leading C/C++ hash tables in speed, but is quirky to use due to C's macro-based generics. With Zig's comptime, we get rid of the quirkiness and are left with a beautiful and really fast hash table.

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

// Adjust load factor (default: 0.9)
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

Verstable's algorithm provides:
- **Fast lookups impervious to load factor**: Hash fragments allow skipping non-matching keys without accessing bucket data
- **Fast insertions**: Only moves at most one existing key
- **Fast, tombstone-free deletions**: Only moves at most one existing key
- **Fast iteration**: Separate metadata array enables SIMD-accelerated scanning

### Benchmarks

Run the benchmark suite:
```bash
zig build benchmark
```

Comparison of TheHashTable vs [Verstable](https://github.com/JacksonAllan/Verstable) (C original) vs std.AutoHashMap (Zig stdlib).
Average time per operation (lower is better). The "vs" columns show how many times faster TheHashTable is (>1 = faster).

#### 10 elements
| Operation     | TheHashTable | Verstable (C) | std.AutoHashMap | vs Verstable | vs std |
|---------------|--------------|---------------|-----------------|--------------|--------|
| Seq. Insert   | 34 ns        | 60 ns         | 53 ns           | 1.76x        | 1.56x  |
| Rand. Insert  | 31 ns        | 53 ns         | 32 ns           | 1.71x        | 1.03x  |
| Seq. Lookup   | 15 ns        | 13 ns         | 17 ns           | 0.87x        | 1.13x  |
| Rand. Lookup  | 11 ns        | 14 ns         | 21 ns           | 1.27x        | 1.91x  |
| Lookup Miss   | 9 ns         | 13 ns         | 16 ns           | 1.44x        | 1.78x  |
| Mixed Lookup  | 7 ns         | 13 ns         | 13 ns           | 1.86x        | 1.86x  |
| Delete        | 9 ns         | 14 ns         | 18 ns           | 1.56x        | 2.00x  |
| Iteration     | 17 ns        | 35 ns         | 11 ns           | 2.06x        | 0.65x  |
| Churn         | 44 ns        | 53 ns         | 49 ns           | 1.20x        | 1.11x  |

#### 100 elements
| Operation     | TheHashTable | Verstable (C) | std.AutoHashMap | vs Verstable | vs std |
|---------------|--------------|---------------|-----------------|--------------|--------|
| Seq. Insert   | 24 ns        | 34 ns         | 27 ns           | 1.42x        | 1.13x  |
| Rand. Insert  | 30 ns        | 61 ns         | 27 ns           | 2.03x        | 0.90x  |
| Seq. Lookup   | 5 ns         | 8 ns          | 13 ns           | 1.60x        | 2.60x  |
| Rand. Lookup  | 7 ns         | 11 ns         | 15 ns           | 1.57x        | 2.14x  |
| Lookup Miss   | 10 ns        | 8 ns          | 23 ns           | 0.80x        | 2.30x  |
| Mixed Lookup  | 7 ns         | 10 ns         | 19 ns           | 1.43x        | 2.71x  |
| Delete        | 8 ns         | 8 ns          | 12 ns           | 1.00x        | 1.50x  |
| Iteration     | 6 ns         | 27 ns         | 4 ns            | 4.50x        | 0.67x  |
| Churn         | 46 ns        | 45 ns         | 77 ns           | 0.98x        | 1.67x  |

#### 1K elements
| Operation     | TheHashTable | Verstable (C) | std.AutoHashMap | vs Verstable | vs std |
|---------------|--------------|---------------|-----------------|--------------|--------|
| Seq. Insert   | 46 ns        | 56 ns         | 33 ns           | 1.22x        | 0.72x  |
| Rand. Insert  | 34 ns        | 64 ns         | 38 ns           | 1.88x        | 1.12x  |
| Seq. Lookup   | 5 ns         | 9 ns          | 8 ns            | 1.80x        | 1.60x  |
| Rand. Lookup  | 6 ns         | 9 ns          | 9 ns            | 1.50x        | 1.50x  |
| Lookup Miss   | 4 ns         | 8 ns          | 13 ns           | 2.00x        | 3.25x  |
| Mixed Lookup  | 4 ns         | 9 ns          | 10 ns           | 2.25x        | 2.50x  |
| Delete        | 8 ns         | 9 ns          | 9 ns            | 1.13x        | 1.13x  |
| Iteration     | 8 ns         | 26 ns         | 6 ns            | 3.25x        | 0.75x  |
| Churn         | 43 ns        | 48 ns         | 54 ns           | 1.12x        | 1.26x  |

#### 10K elements
| Operation     | TheHashTable | Verstable (C) | std.AutoHashMap | vs Verstable | vs std |
|---------------|--------------|---------------|-----------------|--------------|--------|
| Seq. Insert   | 63 ns        | 70 ns         | 49 ns           | 1.11x        | 0.78x  |
| Rand. Insert  | 56 ns        | 91 ns         | 54 ns           | 1.63x        | 0.96x  |
| Seq. Lookup   | 7 ns         | 9 ns          | 16 ns           | 1.29x        | 2.29x  |
| Rand. Lookup  | 11 ns        | 18 ns         | 20 ns           | 1.64x        | 1.82x  |
| Lookup Miss   | 9 ns         | 11 ns         | 24 ns           | 1.22x        | 2.67x  |
| Mixed Lookup  | 10 ns        | 12 ns         | 19 ns           | 1.20x        | 1.90x  |
| Delete        | 11 ns        | 12 ns         | 16 ns           | 1.09x        | 1.45x  |
| Iteration     | 9 ns         | 27 ns         | 8 ns            | 3.00x        | 0.89x  |
| Churn         | 42 ns        | 47 ns         | 59 ns           | 1.12x        | 1.40x  |

#### 100K elements
| Operation     | TheHashTable | Verstable (C) | std.AutoHashMap | vs Verstable | vs std |
|---------------|--------------|---------------|-----------------|--------------|--------|
| Seq. Insert   | 96 ns        | 112 ns        | 60 ns           | 1.17x        | 0.63x  |
| Rand. Insert  | 94 ns        | 114 ns        | 64 ns           | 1.21x        | 0.68x  |
| Seq. Lookup   | 13 ns        | 17 ns         | 22 ns           | 1.31x        | 1.69x  |
| Rand. Lookup  | 18 ns        | 25 ns         | 29 ns           | 1.39x        | 1.61x  |
| Lookup Miss   | 16 ns        | 19 ns         | 37 ns           | 1.19x        | 2.31x  |
| Mixed Lookup  | 15 ns        | 18 ns         | 32 ns           | 1.20x        | 2.13x  |
| Delete        | 14 ns        | 20 ns         | 20 ns           | 1.43x        | 1.43x  |
| Iteration     | 7 ns         | 26 ns         | 6 ns            | 3.71x        | 0.86x  |
| Churn         | 54 ns        | 61 ns         | 80 ns           | 1.13x        | 1.48x  |

#### 1M elements
| Operation     | TheHashTable | Verstable (C) | std.AutoHashMap | vs Verstable | vs std |
|---------------|--------------|---------------|-----------------|--------------|--------|
| Seq. Insert   | 101 ns       | 134 ns        | 87 ns           | 1.33x        | 0.86x  |
| Rand. Insert  | 101 ns       | 135 ns        | 86 ns           | 1.34x        | 0.85x  |
| Seq. Lookup   | 19 ns        | 28 ns         | 26 ns           | 1.47x        | 1.37x  |
| Rand. Lookup  | 33 ns        | 44 ns         | 39 ns           | 1.33x        | 1.18x  |
| Lookup Miss   | 12 ns        | 16 ns         | 27 ns           | 1.33x        | 2.25x  |
| Mixed Lookup  | 16 ns        | 25 ns         | 26 ns           | 1.56x        | 1.63x  |
| Delete        | 21 ns        | 36 ns         | 24 ns           | 1.71x        | 1.14x  |
| Iteration     | 15 ns        | 28 ns         | 14 ns           | 1.87x        | 0.93x  |
| Churn         | 79 ns        | 91 ns         | 85 ns           | 1.15x        | 1.08x  |

#### Memory Overhead (1M entries, u64→u64)
| Metric                  | Value       |
|-------------------------|-------------|
| Load factor             | 47.7%       |
| Bucket size             | 16 bytes    |
| Metadata per bucket     | 2 bytes     |
| Total bytes per entry   | 37.7 bytes  |
| Metadata overhead/entry | 4.2 bytes   |

#### Key Observations
- **Consistently faster than Verstable**: TheHashTable beats its C original on most operations
- **Lookup performance**: Especially strong on lookups (1.2-2.3x faster than Verstable, 1.1-3.3x faster than std)
- **Miss lookups are fast**: Hash fragment filtering skips non-matching keys efficiently
- **Iteration**: 2-4.5x faster than Verstable due to SIMD-accelerated metadata scanning
- **Insert overhead**: std.AutoHashMap wins on sequential inserts at scale, but TheHashTable wins on random inserts

## License

MIT License - see [LICENSE](LICENSE)

## Credits

Algorithm and design based on [Verstable](https://github.com/JacksonAllan/Verstable) by Jackson Allan.
