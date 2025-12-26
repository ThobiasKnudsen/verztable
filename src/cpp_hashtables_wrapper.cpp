// C++ wrapper for Abseil, Boost, and Ankerl hash tables
// Provides extern "C" interface for use in Zig benchmarks

#include <cstdint>
#include <cstddef>
#include <cstring>
#include <string>
#include <string_view>
#include <functional>

// Abseil flat_hash_map/set
#include "absl/container/flat_hash_map.h"
#include "absl/container/flat_hash_set.h"

// Boost unordered_flat_map/set
#include <boost/unordered/unordered_flat_map.hpp>
#include <boost/unordered/unordered_flat_set.hpp>

// Ankerl unordered_dense
#include "ankerl/unordered_dense.h"

#include "cpp_hashtables_wrapper.h"

// ============================================================================
// Value Types (matching Zig's Value4, Value64)
// ============================================================================

struct Val4 {
    uint8_t data[4] = {};
};

struct Val64 {
    uint8_t data[64] = {};
};

// ============================================================================
// Type aliases to avoid comma issues in macros
// ============================================================================

// Abseil types - u32 key
using AbslU32Set = absl::flat_hash_set<uint32_t>;
using AbslU32Val4Map = absl::flat_hash_map<uint32_t, Val4>;
using AbslU32Val64Map = absl::flat_hash_map<uint32_t, Val64>;

// Abseil types - u64 key
using AbslU64Set = absl::flat_hash_set<uint64_t>;
using AbslU64Val4Map = absl::flat_hash_map<uint64_t, Val4>;
using AbslU64Val64Map = absl::flat_hash_map<uint64_t, Val64>;

// Transparent string hash for heterogeneous lookup (works with string_view)
struct TransparentStringHash {
    using is_transparent = void;
    
    size_t operator()(std::string_view sv) const noexcept {
        return std::hash<std::string_view>{}(sv);
    }
    size_t operator()(const std::string& s) const noexcept {
        return std::hash<std::string_view>{}(s);
    }
    size_t operator()(const char* s) const noexcept {
        return std::hash<std::string_view>{}(s);
    }
};

// Abseil types - string key (with heterogeneous lookup)
using AbslStrSet = absl::flat_hash_set<std::string, TransparentStringHash, std::equal_to<>>;
using AbslStrVal4Map = absl::flat_hash_map<std::string, Val4, TransparentStringHash, std::equal_to<>>;
using AbslStrVal64Map = absl::flat_hash_map<std::string, Val64, TransparentStringHash, std::equal_to<>>;

// Boost types - u32 key
using BoostU32Set = boost::unordered_flat_set<uint32_t>;
using BoostU32Val4Map = boost::unordered_flat_map<uint32_t, Val4>;
using BoostU32Val64Map = boost::unordered_flat_map<uint32_t, Val64>;

// Boost types - u64 key
using BoostU64Set = boost::unordered_flat_set<uint64_t>;
using BoostU64Val4Map = boost::unordered_flat_map<uint64_t, Val4>;
using BoostU64Val64Map = boost::unordered_flat_map<uint64_t, Val64>;

// Boost types - string key (with heterogeneous lookup using TransparentStringHash)
using BoostStrSet = boost::unordered_flat_set<std::string, TransparentStringHash, std::equal_to<>>;
using BoostStrVal4Map = boost::unordered_flat_map<std::string, Val4, TransparentStringHash, std::equal_to<>>;
using BoostStrVal64Map = boost::unordered_flat_map<std::string, Val64, TransparentStringHash, std::equal_to<>>;

// Ankerl types - u32 key
using AnkerlU32Set = ankerl::unordered_dense::set<uint32_t>;
using AnkerlU32Val4Map = ankerl::unordered_dense::map<uint32_t, Val4>;
using AnkerlU32Val64Map = ankerl::unordered_dense::map<uint32_t, Val64>;

// Ankerl types - u64 key
using AnkerlU64Set = ankerl::unordered_dense::set<uint64_t>;
using AnkerlU64Val4Map = ankerl::unordered_dense::map<uint64_t, Val4>;
using AnkerlU64Val64Map = ankerl::unordered_dense::map<uint64_t, Val64>;

// Ankerl types - string key (with heterogeneous lookup using TransparentStringHash)
using AnkerlStrSet = ankerl::unordered_dense::set<std::string, TransparentStringHash, std::equal_to<>>;
using AnkerlStrVal4Map = ankerl::unordered_dense::map<std::string, Val4, TransparentStringHash, std::equal_to<>>;
using AnkerlStrVal64Map = ankerl::unordered_dense::map<std::string, Val64, TransparentStringHash, std::equal_to<>>;

// ============================================================================
// X-Macro Definitions for Wrapper Functions
// ============================================================================

// Integer key - void value (set)
#define DEFINE_INT_SET_WRAPPERS(prefix, SetType, key_type) \
    extern "C" cpp_map_handle prefix##_init(void) { \
        return new SetType(); \
    } \
    extern "C" void prefix##_cleanup(cpp_map_handle h) { \
        delete static_cast<SetType*>(h); \
    } \
    extern "C" int prefix##_insert(cpp_map_handle h, key_type key) { \
        auto* m = static_cast<SetType*>(h); \
        auto [it, inserted] = m->insert(key); \
        return inserted ? 1 : 0; \
    } \
    extern "C" int prefix##_get(cpp_map_handle h, key_type key) { \
        auto* m = static_cast<SetType*>(h); \
        return m->find(key) != m->end() ? 1 : 0; \
    } \
    extern "C" int prefix##_erase(cpp_map_handle h, key_type key) { \
        auto* m = static_cast<SetType*>(h); \
        return m->erase(key) > 0 ? 1 : 0; \
    } \
    extern "C" size_t prefix##_size(cpp_map_handle h) { \
        return static_cast<SetType*>(h)->size(); \
    } \
    extern "C" size_t prefix##_iter_count(cpp_map_handle h) { \
        auto* m = static_cast<SetType*>(h); \
        size_t count = 0; \
        for (auto it = m->begin(); it != m->end(); ++it) count++; \
        return count; \
    } \
    extern "C" size_t prefix##_memory(cpp_map_handle h) { \
        auto* m = static_cast<SetType*>(h); \
        return m->bucket_count() * sizeof(typename SetType::value_type) + sizeof(SetType); \
    }

// Integer key - map value
#define DEFINE_INT_MAP_WRAPPERS(prefix, MapType, key_type, val_type, val_size) \
    extern "C" cpp_map_handle prefix##_init(void) { \
        return new MapType(); \
    } \
    extern "C" void prefix##_cleanup(cpp_map_handle h) { \
        delete static_cast<MapType*>(h); \
    } \
    extern "C" int prefix##_insert(cpp_map_handle h, key_type key, const uint8_t* val) { \
        auto* m = static_cast<MapType*>(h); \
        val_type v; \
        std::memcpy(v.data, val, val_size); \
        auto [it, inserted] = m->insert_or_assign(key, v); \
        return 1; \
    } \
    extern "C" const uint8_t* prefix##_get(cpp_map_handle h, key_type key) { \
        auto* m = static_cast<MapType*>(h); \
        auto it = m->find(key); \
        if (it == m->end()) return nullptr; \
        return it->second.data; \
    } \
    extern "C" int prefix##_erase(cpp_map_handle h, key_type key) { \
        auto* m = static_cast<MapType*>(h); \
        return m->erase(key) > 0 ? 1 : 0; \
    } \
    extern "C" size_t prefix##_size(cpp_map_handle h) { \
        return static_cast<MapType*>(h)->size(); \
    } \
    extern "C" size_t prefix##_iter_count(cpp_map_handle h) { \
        auto* m = static_cast<MapType*>(h); \
        size_t count = 0; \
        for (auto it = m->begin(); it != m->end(); ++it) count++; \
        return count; \
    } \
    extern "C" size_t prefix##_memory(cpp_map_handle h) { \
        auto* m = static_cast<MapType*>(h); \
        return m->bucket_count() * sizeof(typename MapType::value_type) + sizeof(MapType); \
    }

// String key - void value (set)
// Uses std::string_view for lookups (heterogeneous lookup) to avoid allocations
#define DEFINE_STR_SET_WRAPPERS(prefix, SetType) \
    extern "C" cpp_map_handle prefix##_init(void) { \
        return new SetType(); \
    } \
    extern "C" void prefix##_cleanup(cpp_map_handle h) { \
        delete static_cast<SetType*>(h); \
    } \
    extern "C" int prefix##_insert(cpp_map_handle h, const char* key, size_t len) { \
        auto* m = static_cast<SetType*>(h); \
        auto [it, inserted] = m->insert(std::string(key, len)); \
        return inserted ? 1 : 0; \
    } \
    extern "C" int prefix##_get(cpp_map_handle h, const char* key, size_t len) { \
        auto* m = static_cast<SetType*>(h); \
        return m->find(std::string_view(key, len)) != m->end() ? 1 : 0; \
    } \
    extern "C" int prefix##_erase(cpp_map_handle h, const char* key, size_t len) { \
        auto* m = static_cast<SetType*>(h); \
        auto it = m->find(std::string_view(key, len)); \
        if (it == m->end()) return 0; \
        m->erase(it); \
        return 1; \
    } \
    extern "C" size_t prefix##_size(cpp_map_handle h) { \
        return static_cast<SetType*>(h)->size(); \
    } \
    extern "C" size_t prefix##_iter_count(cpp_map_handle h) { \
        auto* m = static_cast<SetType*>(h); \
        size_t count = 0; \
        for (auto it = m->begin(); it != m->end(); ++it) count++; \
        return count; \
    } \
    extern "C" size_t prefix##_memory(cpp_map_handle h) { \
        auto* m = static_cast<SetType*>(h); \
        size_t mem = m->bucket_count() * sizeof(typename SetType::value_type) + sizeof(SetType); \
        for (const auto& s : *m) mem += s.capacity(); \
        return mem; \
    }

// String key - map value
// Uses std::string_view for lookups (heterogeneous lookup) to avoid allocations
#define DEFINE_STR_MAP_WRAPPERS(prefix, MapType, val_type, val_size) \
    extern "C" cpp_map_handle prefix##_init(void) { \
        return new MapType(); \
    } \
    extern "C" void prefix##_cleanup(cpp_map_handle h) { \
        delete static_cast<MapType*>(h); \
    } \
    extern "C" int prefix##_insert(cpp_map_handle h, const char* key, size_t len, const uint8_t* val) { \
        auto* m = static_cast<MapType*>(h); \
        val_type v; \
        std::memcpy(v.data, val, val_size); \
        auto [it, inserted] = m->insert_or_assign(std::string(key, len), v); \
        return 1; \
    } \
    extern "C" const uint8_t* prefix##_get(cpp_map_handle h, const char* key, size_t len) { \
        auto* m = static_cast<MapType*>(h); \
        auto it = m->find(std::string_view(key, len)); \
        if (it == m->end()) return nullptr; \
        return it->second.data; \
    } \
    extern "C" int prefix##_erase(cpp_map_handle h, const char* key, size_t len) { \
        auto* m = static_cast<MapType*>(h); \
        auto it = m->find(std::string_view(key, len)); \
        if (it == m->end()) return 0; \
        m->erase(it); \
        return 1; \
    } \
    extern "C" size_t prefix##_size(cpp_map_handle h) { \
        return static_cast<MapType*>(h)->size(); \
    } \
    extern "C" size_t prefix##_iter_count(cpp_map_handle h) { \
        auto* m = static_cast<MapType*>(h); \
        size_t count = 0; \
        for (auto it = m->begin(); it != m->end(); ++it) count++; \
        return count; \
    } \
    extern "C" size_t prefix##_memory(cpp_map_handle h) { \
        auto* m = static_cast<MapType*>(h); \
        size_t mem = m->bucket_count() * sizeof(typename MapType::value_type) + sizeof(MapType); \
        for (const auto& [k, v] : *m) mem += k.capacity(); \
        return mem; \
    }

// ============================================================================
// Abseil Implementations
// ============================================================================

// u32 key
DEFINE_INT_SET_WRAPPERS(absl_u32_void, AbslU32Set, uint32_t)
DEFINE_INT_MAP_WRAPPERS(absl_u32_val4, AbslU32Val4Map, uint32_t, Val4, 4)
DEFINE_INT_MAP_WRAPPERS(absl_u32_val64, AbslU32Val64Map, uint32_t, Val64, 64)

// u64 key
DEFINE_INT_SET_WRAPPERS(absl_u64_void, AbslU64Set, uint64_t)
DEFINE_INT_MAP_WRAPPERS(absl_u64_val4, AbslU64Val4Map, uint64_t, Val4, 4)
DEFINE_INT_MAP_WRAPPERS(absl_u64_val64, AbslU64Val64Map, uint64_t, Val64, 64)

// string key
DEFINE_STR_SET_WRAPPERS(absl_str_void, AbslStrSet)
DEFINE_STR_MAP_WRAPPERS(absl_str_val4, AbslStrVal4Map, Val4, 4)
DEFINE_STR_MAP_WRAPPERS(absl_str_val64, AbslStrVal64Map, Val64, 64)

// ============================================================================
// Boost Implementations
// ============================================================================

// u32 key
DEFINE_INT_SET_WRAPPERS(boost_u32_void, BoostU32Set, uint32_t)
DEFINE_INT_MAP_WRAPPERS(boost_u32_val4, BoostU32Val4Map, uint32_t, Val4, 4)
DEFINE_INT_MAP_WRAPPERS(boost_u32_val64, BoostU32Val64Map, uint32_t, Val64, 64)

// u64 key
DEFINE_INT_SET_WRAPPERS(boost_u64_void, BoostU64Set, uint64_t)
DEFINE_INT_MAP_WRAPPERS(boost_u64_val4, BoostU64Val4Map, uint64_t, Val4, 4)
DEFINE_INT_MAP_WRAPPERS(boost_u64_val64, BoostU64Val64Map, uint64_t, Val64, 64)

// string key
DEFINE_STR_SET_WRAPPERS(boost_str_void, BoostStrSet)
DEFINE_STR_MAP_WRAPPERS(boost_str_val4, BoostStrVal4Map, Val4, 4)
DEFINE_STR_MAP_WRAPPERS(boost_str_val64, BoostStrVal64Map, Val64, 64)

// ============================================================================
// Ankerl Implementations
// ============================================================================

// u32 key
DEFINE_INT_SET_WRAPPERS(ankerl_u32_void, AnkerlU32Set, uint32_t)
DEFINE_INT_MAP_WRAPPERS(ankerl_u32_val4, AnkerlU32Val4Map, uint32_t, Val4, 4)
DEFINE_INT_MAP_WRAPPERS(ankerl_u32_val64, AnkerlU32Val64Map, uint32_t, Val64, 64)

// u64 key
DEFINE_INT_SET_WRAPPERS(ankerl_u64_void, AnkerlU64Set, uint64_t)
DEFINE_INT_MAP_WRAPPERS(ankerl_u64_val4, AnkerlU64Val4Map, uint64_t, Val4, 4)
DEFINE_INT_MAP_WRAPPERS(ankerl_u64_val64, AnkerlU64Val64Map, uint64_t, Val64, 64)

// string key
DEFINE_STR_SET_WRAPPERS(ankerl_str_void, AnkerlStrSet)
DEFINE_STR_MAP_WRAPPERS(ankerl_str_val4, AnkerlStrVal4Map, Val4, 4)
DEFINE_STR_MAP_WRAPPERS(ankerl_str_val64, AnkerlStrVal64Map, Val64, 64)
