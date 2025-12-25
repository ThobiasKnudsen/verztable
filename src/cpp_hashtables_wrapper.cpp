// C++ wrapper for Abseil, Boost, and Ankerl hash tables
// Provides extern "C" interface for use in Zig benchmarks

#include <cstdint>
#include <cstddef>
#include <cstring>
#include <string>
#include <string_view>

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
// Value Types (matching Zig's Value4, Value64, Value56)
// ============================================================================

struct Val4 {
    uint8_t data[4] = {};
};

struct Val64 {
    uint8_t data[64] = {};
};

struct Val56 {
    uint8_t data[56] = {};
};

// ============================================================================
// Type aliases to avoid comma issues in macros
// ============================================================================

// Abseil types
using AbslU64Set = absl::flat_hash_set<uint64_t>;
using AbslU64Val4Map = absl::flat_hash_map<uint64_t, Val4>;
using AbslU64Val64Map = absl::flat_hash_map<uint64_t, Val64>;
using AbslU64Val56Map = absl::flat_hash_map<uint64_t, Val56>;

using AbslU16Set = absl::flat_hash_set<uint16_t>;
using AbslU16Val4Map = absl::flat_hash_map<uint16_t, Val4>;
using AbslU16Val64Map = absl::flat_hash_map<uint16_t, Val64>;
using AbslU16Val56Map = absl::flat_hash_map<uint16_t, Val56>;

using AbslStrSet = absl::flat_hash_set<std::string>;
using AbslStrVal4Map = absl::flat_hash_map<std::string, Val4>;
using AbslStrVal64Map = absl::flat_hash_map<std::string, Val64>;
using AbslStrVal56Map = absl::flat_hash_map<std::string, Val56>;

// Boost types
using BoostU64Set = boost::unordered_flat_set<uint64_t>;
using BoostU64Val4Map = boost::unordered_flat_map<uint64_t, Val4>;
using BoostU64Val64Map = boost::unordered_flat_map<uint64_t, Val64>;
using BoostU64Val56Map = boost::unordered_flat_map<uint64_t, Val56>;

using BoostU16Set = boost::unordered_flat_set<uint16_t>;
using BoostU16Val4Map = boost::unordered_flat_map<uint16_t, Val4>;
using BoostU16Val64Map = boost::unordered_flat_map<uint16_t, Val64>;
using BoostU16Val56Map = boost::unordered_flat_map<uint16_t, Val56>;

using BoostStrSet = boost::unordered_flat_set<std::string>;
using BoostStrVal4Map = boost::unordered_flat_map<std::string, Val4>;
using BoostStrVal64Map = boost::unordered_flat_map<std::string, Val64>;
using BoostStrVal56Map = boost::unordered_flat_map<std::string, Val56>;

// Ankerl types
using AnkerlU64Set = ankerl::unordered_dense::set<uint64_t>;
using AnkerlU64Val4Map = ankerl::unordered_dense::map<uint64_t, Val4>;
using AnkerlU64Val64Map = ankerl::unordered_dense::map<uint64_t, Val64>;
using AnkerlU64Val56Map = ankerl::unordered_dense::map<uint64_t, Val56>;

using AnkerlU16Set = ankerl::unordered_dense::set<uint16_t>;
using AnkerlU16Val4Map = ankerl::unordered_dense::map<uint16_t, Val4>;
using AnkerlU16Val64Map = ankerl::unordered_dense::map<uint16_t, Val64>;
using AnkerlU16Val56Map = ankerl::unordered_dense::map<uint16_t, Val56>;

using AnkerlStrSet = ankerl::unordered_dense::set<std::string>;
using AnkerlStrVal4Map = ankerl::unordered_dense::map<std::string, Val4>;
using AnkerlStrVal64Map = ankerl::unordered_dense::map<std::string, Val64>;
using AnkerlStrVal56Map = ankerl::unordered_dense::map<std::string, Val56>;

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
    }

// String key - void value (set)
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
        return m->find(std::string(key, len)) != m->end() ? 1 : 0; \
    } \
    extern "C" int prefix##_erase(cpp_map_handle h, const char* key, size_t len) { \
        auto* m = static_cast<SetType*>(h); \
        auto it = m->find(std::string(key, len)); \
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
    }

// String key - map value
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
        auto it = m->find(std::string(key, len)); \
        if (it == m->end()) return nullptr; \
        return it->second.data; \
    } \
    extern "C" int prefix##_erase(cpp_map_handle h, const char* key, size_t len) { \
        auto* m = static_cast<MapType*>(h); \
        auto it = m->find(std::string(key, len)); \
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
    }

// ============================================================================
// Abseil Implementations
// ============================================================================

// u64 key
DEFINE_INT_SET_WRAPPERS(absl_u64_void, AbslU64Set, uint64_t)
DEFINE_INT_MAP_WRAPPERS(absl_u64_val4, AbslU64Val4Map, uint64_t, Val4, 4)
DEFINE_INT_MAP_WRAPPERS(absl_u64_val64, AbslU64Val64Map, uint64_t, Val64, 64)
DEFINE_INT_MAP_WRAPPERS(absl_u64_val56, AbslU64Val56Map, uint64_t, Val56, 56)

// u16 key
DEFINE_INT_SET_WRAPPERS(absl_u16_void, AbslU16Set, uint16_t)
DEFINE_INT_MAP_WRAPPERS(absl_u16_val4, AbslU16Val4Map, uint16_t, Val4, 4)
DEFINE_INT_MAP_WRAPPERS(absl_u16_val64, AbslU16Val64Map, uint16_t, Val64, 64)
DEFINE_INT_MAP_WRAPPERS(absl_u16_val56, AbslU16Val56Map, uint16_t, Val56, 56)

// string key
DEFINE_STR_SET_WRAPPERS(absl_str_void, AbslStrSet)
DEFINE_STR_MAP_WRAPPERS(absl_str_val4, AbslStrVal4Map, Val4, 4)
DEFINE_STR_MAP_WRAPPERS(absl_str_val64, AbslStrVal64Map, Val64, 64)
DEFINE_STR_MAP_WRAPPERS(absl_str_val56, AbslStrVal56Map, Val56, 56)

// ============================================================================
// Boost Implementations
// ============================================================================

// u64 key
DEFINE_INT_SET_WRAPPERS(boost_u64_void, BoostU64Set, uint64_t)
DEFINE_INT_MAP_WRAPPERS(boost_u64_val4, BoostU64Val4Map, uint64_t, Val4, 4)
DEFINE_INT_MAP_WRAPPERS(boost_u64_val64, BoostU64Val64Map, uint64_t, Val64, 64)
DEFINE_INT_MAP_WRAPPERS(boost_u64_val56, BoostU64Val56Map, uint64_t, Val56, 56)

// u16 key
DEFINE_INT_SET_WRAPPERS(boost_u16_void, BoostU16Set, uint16_t)
DEFINE_INT_MAP_WRAPPERS(boost_u16_val4, BoostU16Val4Map, uint16_t, Val4, 4)
DEFINE_INT_MAP_WRAPPERS(boost_u16_val64, BoostU16Val64Map, uint16_t, Val64, 64)
DEFINE_INT_MAP_WRAPPERS(boost_u16_val56, BoostU16Val56Map, uint16_t, Val56, 56)

// string key
DEFINE_STR_SET_WRAPPERS(boost_str_void, BoostStrSet)
DEFINE_STR_MAP_WRAPPERS(boost_str_val4, BoostStrVal4Map, Val4, 4)
DEFINE_STR_MAP_WRAPPERS(boost_str_val64, BoostStrVal64Map, Val64, 64)
DEFINE_STR_MAP_WRAPPERS(boost_str_val56, BoostStrVal56Map, Val56, 56)

// ============================================================================
// Ankerl Implementations
// ============================================================================

// u64 key
DEFINE_INT_SET_WRAPPERS(ankerl_u64_void, AnkerlU64Set, uint64_t)
DEFINE_INT_MAP_WRAPPERS(ankerl_u64_val4, AnkerlU64Val4Map, uint64_t, Val4, 4)
DEFINE_INT_MAP_WRAPPERS(ankerl_u64_val64, AnkerlU64Val64Map, uint64_t, Val64, 64)
DEFINE_INT_MAP_WRAPPERS(ankerl_u64_val56, AnkerlU64Val56Map, uint64_t, Val56, 56)

// u16 key
DEFINE_INT_SET_WRAPPERS(ankerl_u16_void, AnkerlU16Set, uint16_t)
DEFINE_INT_MAP_WRAPPERS(ankerl_u16_val4, AnkerlU16Val4Map, uint16_t, Val4, 4)
DEFINE_INT_MAP_WRAPPERS(ankerl_u16_val64, AnkerlU16Val64Map, uint16_t, Val64, 64)
DEFINE_INT_MAP_WRAPPERS(ankerl_u16_val56, AnkerlU16Val56Map, uint16_t, Val56, 56)

// string key
DEFINE_STR_SET_WRAPPERS(ankerl_str_void, AnkerlStrSet)
DEFINE_STR_MAP_WRAPPERS(ankerl_str_val4, AnkerlStrVal4Map, Val4, 4)
DEFINE_STR_MAP_WRAPPERS(ankerl_str_val64, AnkerlStrVal64Map, Val64, 64)
DEFINE_STR_MAP_WRAPPERS(ankerl_str_val56, AnkerlStrVal56Map, Val56, 56)
