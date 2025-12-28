// C++ wrapper for Abseil, Boost, and Ankerl hash tables
// Provides extern "C" interface for use in Zig benchmarks
//
// FAIR COMPARISON MODE:
// - String keys use std::string_view (non-owning, like Zig's []const u8)
// - All libraries use wyhash for string hashing (same as Zig's verztable)
// - No heap allocations on insert/lookup for string keys

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

// Ankerl unordered_dense (includes wyhash implementation)
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
// Wyhash - borrowed from ankerl::unordered_dense for consistent hashing
// This ensures all C++ libraries use the same fast hash as Zig's verztable
// ============================================================================

namespace wyhash {

inline void mum(std::uint64_t* a, std::uint64_t* b) {
#if defined(__SIZEOF_INT128__)
    __uint128_t r = static_cast<__uint128_t>(*a) * static_cast<__uint128_t>(*b);
    *a = static_cast<std::uint64_t>(r);
    *b = static_cast<std::uint64_t>(r >> 64U);
#else
    std::uint64_t ha = *a >> 32U;
    std::uint64_t hb = *b >> 32U;
    std::uint64_t la = static_cast<std::uint32_t>(*a);
    std::uint64_t lb = static_cast<std::uint32_t>(*b);
    std::uint64_t hi{};
    std::uint64_t lo{};
    std::uint64_t rh = ha * hb;
    std::uint64_t rm0 = ha * lb;
    std::uint64_t rm1 = hb * la;
    std::uint64_t rl = la * lb;
    std::uint64_t t = rl + (rm0 << 32U);
    auto c = static_cast<std::uint64_t>(t < rl);
    lo = t + (rm1 << 32U);
    c += static_cast<std::uint64_t>(lo < t);
    hi = rh + (rm0 >> 32U) + (rm1 >> 32U) + c;
    *a = lo;
    *b = hi;
#endif
}

[[nodiscard]] inline auto mix(std::uint64_t a, std::uint64_t b) -> std::uint64_t {
    mum(&a, &b);
    return a ^ b;
}

[[nodiscard]] inline auto r8(const std::uint8_t* p) -> std::uint64_t {
    std::uint64_t v{};
    std::memcpy(&v, p, 8U);
    return v;
}

[[nodiscard]] inline auto r4(const std::uint8_t* p) -> std::uint64_t {
    std::uint32_t v{};
    std::memcpy(&v, p, 4);
    return v;
}

[[nodiscard]] inline auto r3(const std::uint8_t* p, std::size_t k) -> std::uint64_t {
    return (static_cast<std::uint64_t>(p[0]) << 16U) | 
           (static_cast<std::uint64_t>(p[k >> 1U]) << 8U) | 
           p[k - 1];
}

[[nodiscard]] inline auto hash(void const* key, std::size_t len) -> std::uint64_t {
    static constexpr auto secret = std::array{
        std::uint64_t{0xa0761d6478bd642fU},
        std::uint64_t{0xe7037ed1a0b428dbU},
        std::uint64_t{0x8ebc6af09c88c6e3U},
        std::uint64_t{0x589965cc75374cc3U}
    };

    auto const* p = static_cast<std::uint8_t const*>(key);
    std::uint64_t seed = secret[0];
    std::uint64_t a{};
    std::uint64_t b{};
    if (len <= 16) {
        if (len >= 4) {
            a = (r4(p) << 32U) | r4(p + ((len >> 3U) << 2U));
            b = (r4(p + len - 4) << 32U) | r4(p + len - 4 - ((len >> 3U) << 2U));
        } else if (len > 0) {
            a = r3(p, len);
            b = 0;
        } else {
            a = 0;
            b = 0;
        }
    } else {
        std::size_t i = len;
        if (i > 48) {
            std::uint64_t see1 = seed;
            std::uint64_t see2 = seed;
            do {
                seed = mix(r8(p) ^ secret[1], r8(p + 8) ^ seed);
                see1 = mix(r8(p + 16) ^ secret[2], r8(p + 24) ^ see1);
                see2 = mix(r8(p + 32) ^ secret[3], r8(p + 40) ^ see2);
                p += 48;
                i -= 48;
            } while (i > 48);
            seed ^= see1 ^ see2;
        }
        while (i > 16) {
            seed = mix(r8(p) ^ secret[1], r8(p + 8) ^ seed);
            i -= 16;
            p += 16;
        }
        a = r8(p + i - 16);
        b = r8(p + i - 8);
    }

    return mix(secret[1] ^ len, mix(a ^ secret[1], b ^ seed));
}

[[nodiscard]] inline auto hash(std::uint64_t x) -> std::uint64_t {
    return mix(x, std::uint64_t{0x9E3779B97F4A7C15});
}

} // namespace wyhash

// ============================================================================
// Wyhash-based string_view hasher for all libraries
// ============================================================================

struct WyhashStringView {
    using is_transparent = void;  // Enable heterogeneous lookup
    using is_avalanching = void;  // For ankerl - indicates good hash distribution
    
    std::uint64_t operator()(std::string_view sv) const noexcept {
        return wyhash::hash(sv.data(), sv.size());
    }
};

// ============================================================================
// Type aliases - Integer keys (unchanged)
// ============================================================================

// Abseil types - u32 key
using AbslU32Set = absl::flat_hash_set<uint32_t>;
using AbslU32Val4Map = absl::flat_hash_map<uint32_t, Val4>;
using AbslU32Val64Map = absl::flat_hash_map<uint32_t, Val64>;

// Abseil types - u64 key
using AbslU64Set = absl::flat_hash_set<uint64_t>;
using AbslU64Val4Map = absl::flat_hash_map<uint64_t, Val4>;
using AbslU64Val64Map = absl::flat_hash_map<uint64_t, Val64>;

// Boost types - u32 key
using BoostU32Set = boost::unordered_flat_set<uint32_t>;
using BoostU32Val4Map = boost::unordered_flat_map<uint32_t, Val4>;
using BoostU32Val64Map = boost::unordered_flat_map<uint32_t, Val64>;

// Boost types - u64 key
using BoostU64Set = boost::unordered_flat_set<uint64_t>;
using BoostU64Val4Map = boost::unordered_flat_map<uint64_t, Val4>;
using BoostU64Val64Map = boost::unordered_flat_map<uint64_t, Val64>;

// Ankerl types - u32 key
using AnkerlU32Set = ankerl::unordered_dense::set<uint32_t>;
using AnkerlU32Val4Map = ankerl::unordered_dense::map<uint32_t, Val4>;
using AnkerlU32Val64Map = ankerl::unordered_dense::map<uint32_t, Val64>;

// Ankerl types - u64 key
using AnkerlU64Set = ankerl::unordered_dense::set<uint64_t>;
using AnkerlU64Val4Map = ankerl::unordered_dense::map<uint64_t, Val4>;
using AnkerlU64Val64Map = ankerl::unordered_dense::map<uint64_t, Val64>;

// ============================================================================
// Type aliases - String keys using string_view (NON-OWNING, like Zig)
// All use wyhash for fair comparison
// ============================================================================

// Abseil types - string_view key with wyhash
using AbslStrSet = absl::flat_hash_set<std::string_view, WyhashStringView>;
using AbslStrVal4Map = absl::flat_hash_map<std::string_view, Val4, WyhashStringView>;
using AbslStrVal64Map = absl::flat_hash_map<std::string_view, Val64, WyhashStringView>;

// Boost types - string_view key with wyhash
using BoostStrSet = boost::unordered_flat_set<std::string_view, WyhashStringView>;
using BoostStrVal4Map = boost::unordered_flat_map<std::string_view, Val4, WyhashStringView>;
using BoostStrVal64Map = boost::unordered_flat_map<std::string_view, Val64, WyhashStringView>;

// Ankerl types - string_view key with wyhash
using AnkerlStrSet = ankerl::unordered_dense::set<std::string_view, WyhashStringView>;
using AnkerlStrVal4Map = ankerl::unordered_dense::map<std::string_view, Val4, WyhashStringView>;
using AnkerlStrVal64Map = ankerl::unordered_dense::map<std::string_view, Val64, WyhashStringView>;

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

// String key - void value (set) - NOW USES string_view (NO ALLOCATION!)
#define DEFINE_STR_SET_WRAPPERS(prefix, SetType) \
    extern "C" cpp_map_handle prefix##_init(void) { \
        return new SetType(); \
    } \
    extern "C" void prefix##_cleanup(cpp_map_handle h) { \
        delete static_cast<SetType*>(h); \
    } \
    extern "C" int prefix##_insert(cpp_map_handle h, const char* key, size_t len) { \
        auto* m = static_cast<SetType*>(h); \
        auto [it, inserted] = m->insert(std::string_view(key, len)); \
        return inserted ? 1 : 0; \
    } \
    extern "C" int prefix##_get(cpp_map_handle h, const char* key, size_t len) { \
        auto* m = static_cast<SetType*>(h); \
        return m->find(std::string_view(key, len)) != m->end() ? 1 : 0; \
    } \
    extern "C" int prefix##_erase(cpp_map_handle h, const char* key, size_t len) { \
        auto* m = static_cast<SetType*>(h); \
        return m->erase(std::string_view(key, len)) > 0 ? 1 : 0; \
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

// String key - map value - NOW USES string_view (NO ALLOCATION!)
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
        auto [it, inserted] = m->insert_or_assign(std::string_view(key, len), v); \
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
        return m->erase(std::string_view(key, len)) > 0 ? 1 : 0; \
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

// string key (now using string_view + wyhash)
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

// string key (now using string_view + wyhash)
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

// string key (now using string_view + wyhash)
DEFINE_STR_SET_WRAPPERS(ankerl_str_void, AnkerlStrSet)
DEFINE_STR_MAP_WRAPPERS(ankerl_str_val4, AnkerlStrVal4Map, Val4, 4)
DEFINE_STR_MAP_WRAPPERS(ankerl_str_val64, AnkerlStrVal64Map, Val64, 64)
