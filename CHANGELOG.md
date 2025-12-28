# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-12-26

### Added

- Initial release of verztable
- High-performance hash table implementation inspired by [Verstable](https://github.com/JacksonAllan/Verstable)
- Unified Map/Set API: `HashMap(K, V)` for maps, `HashMap(K, void)` for sets
- Tombstone-free deletion — no performance degradation after many deletes
- SIMD-accelerated iteration using vectorized metadata scanning
- 16-bit metadata per bucket: 4-bit hash fragment, 1-bit home flag, 11-bit displacement
- Custom hash function support via `HashMapWithFns`
- Comprehensive benchmark suite comparing against Abseil, Boost, Ankerl, and Zig std
- Full API including: `put`, `get`, `getPtr`, `getOrPut`, `remove`, `contains`, `add`, `reserve`, `shrink`, `clone`, iterators

### Performance

- Outperforms Abseil, Boost, and Ankerl on mixed read-heavy workloads (65% reads)
- Particularly strong on string key operations
- Consistent sub-10ns operations on integer keys at 1K elements

