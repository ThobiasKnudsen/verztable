// C wrapper for Verstable to be used in Zig benchmarks
// Uses X-macros to generate wrapper functions for all key/value combinations

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdbool.h>

// ============================================================================
// Value Types (matching Zig's Value4, Value64, Value256)
// ============================================================================

typedef struct { uint8_t data[4]; } val4_t;
typedef struct { uint8_t data[64]; } val64_t;
typedef struct { uint8_t data[256]; } val256_t;

// String key type
typedef struct {
    const char *ptr;
    size_t len;
} str_key;

static inline size_t str_hash(str_key key) {
    size_t hash = 14695981039346656037ULL;
    for (size_t i = 0; i < key.len; i++) {
        hash ^= (unsigned char)key.ptr[i];
        hash *= 1099511628211ULL;
    }
    return hash;
}

static inline bool str_cmpr(str_key a, str_key b) {
    if (a.len != b.len) return false;
    return memcmp(a.ptr, b.ptr, a.len) == 0;
}

// ============================================================================
// Verstable Instantiations - Sets (no VAL_TY)
// ============================================================================

#define NAME vt_u64_void_internal
#define KEY_TY uint64_t
#define HASH_FN vt_hash_integer
#define CMPR_FN vt_cmpr_integer
#include "../Verstable/verstable.h"

#define NAME vt_u16_void_internal
#define KEY_TY uint16_t
#define HASH_FN vt_hash_integer
#define CMPR_FN vt_cmpr_integer
#include "../Verstable/verstable.h"

#define NAME vt_str_void_internal
#define KEY_TY str_key
#define HASH_FN str_hash
#define CMPR_FN str_cmpr
#include "../Verstable/verstable.h"

// ============================================================================
// Verstable Instantiations - Maps with val4_t
// ============================================================================

#define NAME vt_u64_val4_internal
#define KEY_TY uint64_t
#define VAL_TY val4_t
#define HASH_FN vt_hash_integer
#define CMPR_FN vt_cmpr_integer
#include "../Verstable/verstable.h"

#define NAME vt_u16_val4_internal
#define KEY_TY uint16_t
#define VAL_TY val4_t
#define HASH_FN vt_hash_integer
#define CMPR_FN vt_cmpr_integer
#include "../Verstable/verstable.h"

#define NAME vt_str_val4_internal
#define KEY_TY str_key
#define VAL_TY val4_t
#define HASH_FN str_hash
#define CMPR_FN str_cmpr
#include "../Verstable/verstable.h"

// ============================================================================
// Verstable Instantiations - Maps with val64_t
// ============================================================================

#define NAME vt_u64_val64_internal
#define KEY_TY uint64_t
#define VAL_TY val64_t
#define HASH_FN vt_hash_integer
#define CMPR_FN vt_cmpr_integer
#include "../Verstable/verstable.h"

#define NAME vt_u16_val64_internal
#define KEY_TY uint16_t
#define VAL_TY val64_t
#define HASH_FN vt_hash_integer
#define CMPR_FN vt_cmpr_integer
#include "../Verstable/verstable.h"

#define NAME vt_str_val64_internal
#define KEY_TY str_key
#define VAL_TY val64_t
#define HASH_FN str_hash
#define CMPR_FN str_cmpr
#include "../Verstable/verstable.h"

// ============================================================================
// Verstable Instantiations - Maps with val256_t
// ============================================================================

#define NAME vt_u64_val256_internal
#define KEY_TY uint64_t
#define VAL_TY val256_t
#define HASH_FN vt_hash_integer
#define CMPR_FN vt_cmpr_integer
#include "../Verstable/verstable.h"

#define NAME vt_u16_val256_internal
#define KEY_TY uint16_t
#define VAL_TY val256_t
#define HASH_FN vt_hash_integer
#define CMPR_FN vt_cmpr_integer
#include "../Verstable/verstable.h"

#define NAME vt_str_val256_internal
#define KEY_TY str_key
#define VAL_TY val256_t
#define HASH_FN str_hash
#define CMPR_FN str_cmpr
#include "../Verstable/verstable.h"

#include "verstable_wrapper.h"

// ============================================================================
// X-Macro for generating integer key wrapper functions (sets)
// ============================================================================

#define DEFINE_INT_SET_WRAPPERS(prefix, key_type, internal_name) \
    void prefix##_init(prefix##_map *table) { \
        internal_name##_init((internal_name*)table); \
    } \
    void prefix##_cleanup(prefix##_map *table) { \
        internal_name##_cleanup((internal_name*)table); \
    } \
    int prefix##_insert(prefix##_map *table, key_type key) { \
        internal_name##_itr itr = internal_name##_insert((internal_name*)table, key); \
        return !internal_name##_is_end(itr); \
    } \
    int prefix##_get(prefix##_map *table, key_type key) { \
        internal_name##_itr itr = internal_name##_get((internal_name*)table, key); \
        return !internal_name##_is_end(itr); \
    } \
    int prefix##_erase(prefix##_map *table, key_type key) { \
        return internal_name##_erase((internal_name*)table, key) ? 1 : 0; \
    } \
    size_t prefix##_size(prefix##_map *table) { \
        return internal_name##_size((internal_name*)table); \
    } \
    vt_generic_iter prefix##_first(prefix##_map *table) { \
        internal_name##_itr itr = internal_name##_first((internal_name*)table); \
        vt_generic_iter result = { itr.data, itr.metadatum, itr.metadata_end, itr.home_bucket }; \
        return result; \
    } \
    int prefix##_is_end(vt_generic_iter iter) { \
        return iter.metadatum == iter.metadata_end ? 1 : 0; \
    } \
    vt_generic_iter prefix##_next(vt_generic_iter iter) { \
        internal_name##_itr itr = { (internal_name##_bucket*)iter.itr_data, iter.metadatum, iter.metadata_end, iter.home_bucket }; \
        internal_name##_itr next = internal_name##_next(itr); \
        vt_generic_iter result = { next.data, next.metadatum, next.metadata_end, next.home_bucket }; \
        return result; \
    }

// ============================================================================
// X-Macro for generating integer key wrapper functions (maps with data array)
// ============================================================================

#define DEFINE_INT_MAP_WRAPPERS(prefix, key_type, val_type, val_size, internal_name) \
    void prefix##_init(prefix##_map *table) { \
        internal_name##_init((internal_name*)table); \
    } \
    void prefix##_cleanup(prefix##_map *table) { \
        internal_name##_cleanup((internal_name*)table); \
    } \
    int prefix##_insert(prefix##_map *table, key_type key, const uint8_t *val) { \
        val_type v; \
        memcpy(v.data, val, val_size); \
        internal_name##_itr itr = internal_name##_insert((internal_name*)table, key, v); \
        return !internal_name##_is_end(itr); \
    } \
    const uint8_t* prefix##_get(prefix##_map *table, key_type key) { \
        internal_name##_itr itr = internal_name##_get((internal_name*)table, key); \
        if (internal_name##_is_end(itr)) return NULL; \
        return itr.data->val.data; \
    } \
    int prefix##_erase(prefix##_map *table, key_type key) { \
        return internal_name##_erase((internal_name*)table, key) ? 1 : 0; \
    } \
    size_t prefix##_size(prefix##_map *table) { \
        return internal_name##_size((internal_name*)table); \
    } \
    vt_generic_iter prefix##_first(prefix##_map *table) { \
        internal_name##_itr itr = internal_name##_first((internal_name*)table); \
        vt_generic_iter result = { itr.data, itr.metadatum, itr.metadata_end, itr.home_bucket }; \
        return result; \
    } \
    int prefix##_is_end(vt_generic_iter iter) { \
        return iter.metadatum == iter.metadata_end ? 1 : 0; \
    } \
    vt_generic_iter prefix##_next(vt_generic_iter iter) { \
        internal_name##_itr itr = { (internal_name##_bucket*)iter.itr_data, iter.metadatum, iter.metadata_end, iter.home_bucket }; \
        internal_name##_itr next = internal_name##_next(itr); \
        vt_generic_iter result = { next.data, next.metadatum, next.metadata_end, next.home_bucket }; \
        return result; \
    }

// ============================================================================
// X-Macro for generating string key wrapper functions (sets)
// ============================================================================

#define DEFINE_STR_SET_WRAPPERS(prefix, internal_name) \
    void prefix##_init(prefix##_map *table) { \
        internal_name##_init((internal_name*)table); \
    } \
    void prefix##_cleanup(prefix##_map *table) { \
        internal_name##_cleanup((internal_name*)table); \
    } \
    int prefix##_insert(prefix##_map *table, const char *key, size_t len) { \
        str_key k = { key, len }; \
        internal_name##_itr itr = internal_name##_insert((internal_name*)table, k); \
        return !internal_name##_is_end(itr); \
    } \
    int prefix##_get(prefix##_map *table, const char *key, size_t len) { \
        str_key k = { key, len }; \
        internal_name##_itr itr = internal_name##_get((internal_name*)table, k); \
        return !internal_name##_is_end(itr); \
    } \
    int prefix##_erase(prefix##_map *table, const char *key, size_t len) { \
        str_key k = { key, len }; \
        return internal_name##_erase((internal_name*)table, k) ? 1 : 0; \
    } \
    size_t prefix##_size(prefix##_map *table) { \
        return internal_name##_size((internal_name*)table); \
    } \
    vt_generic_iter prefix##_first(prefix##_map *table) { \
        internal_name##_itr itr = internal_name##_first((internal_name*)table); \
        vt_generic_iter result = { itr.data, itr.metadatum, itr.metadata_end, itr.home_bucket }; \
        return result; \
    } \
    int prefix##_is_end(vt_generic_iter iter) { \
        return iter.metadatum == iter.metadata_end ? 1 : 0; \
    } \
    vt_generic_iter prefix##_next(vt_generic_iter iter) { \
        internal_name##_itr itr = { (internal_name##_bucket*)iter.itr_data, iter.metadatum, iter.metadata_end, iter.home_bucket }; \
        internal_name##_itr next = internal_name##_next(itr); \
        vt_generic_iter result = { next.data, next.metadatum, next.metadata_end, next.home_bucket }; \
        return result; \
    }

// ============================================================================
// X-Macro for generating string key wrapper functions (maps)
// ============================================================================

#define DEFINE_STR_MAP_WRAPPERS(prefix, val_type, val_size, internal_name) \
    void prefix##_init(prefix##_map *table) { \
        internal_name##_init((internal_name*)table); \
    } \
    void prefix##_cleanup(prefix##_map *table) { \
        internal_name##_cleanup((internal_name*)table); \
    } \
    int prefix##_insert(prefix##_map *table, const char *key, size_t len, const uint8_t *val) { \
        str_key k = { key, len }; \
        val_type v; \
        memcpy(v.data, val, val_size); \
        internal_name##_itr itr = internal_name##_insert((internal_name*)table, k, v); \
        return !internal_name##_is_end(itr); \
    } \
    const uint8_t* prefix##_get(prefix##_map *table, const char *key, size_t len) { \
        str_key k = { key, len }; \
        internal_name##_itr itr = internal_name##_get((internal_name*)table, k); \
        if (internal_name##_is_end(itr)) return NULL; \
        return itr.data->val.data; \
    } \
    int prefix##_erase(prefix##_map *table, const char *key, size_t len) { \
        str_key k = { key, len }; \
        return internal_name##_erase((internal_name*)table, k) ? 1 : 0; \
    } \
    size_t prefix##_size(prefix##_map *table) { \
        return internal_name##_size((internal_name*)table); \
    } \
    vt_generic_iter prefix##_first(prefix##_map *table) { \
        internal_name##_itr itr = internal_name##_first((internal_name*)table); \
        vt_generic_iter result = { itr.data, itr.metadatum, itr.metadata_end, itr.home_bucket }; \
        return result; \
    } \
    int prefix##_is_end(vt_generic_iter iter) { \
        return iter.metadatum == iter.metadata_end ? 1 : 0; \
    } \
    vt_generic_iter prefix##_next(vt_generic_iter iter) { \
        internal_name##_itr itr = { (internal_name##_bucket*)iter.itr_data, iter.metadatum, iter.metadata_end, iter.home_bucket }; \
        internal_name##_itr next = internal_name##_next(itr); \
        vt_generic_iter result = { next.data, next.metadatum, next.metadata_end, next.home_bucket }; \
        return result; \
    }

// ============================================================================
// Generate all wrapper functions using X-macros
// ============================================================================

// Sets (void values)
DEFINE_INT_SET_WRAPPERS(vt_u64_void, uint64_t, vt_u64_void_internal)
DEFINE_INT_SET_WRAPPERS(vt_u16_void, uint16_t, vt_u16_void_internal)
DEFINE_STR_SET_WRAPPERS(vt_str_void, vt_str_void_internal)

// Maps with 4-byte values
DEFINE_INT_MAP_WRAPPERS(vt_u64_val4, uint64_t, val4_t, 4, vt_u64_val4_internal)
DEFINE_INT_MAP_WRAPPERS(vt_u16_val4, uint16_t, val4_t, 4, vt_u16_val4_internal)
DEFINE_STR_MAP_WRAPPERS(vt_str_val4, val4_t, 4, vt_str_val4_internal)

// Maps with 64-byte values
DEFINE_INT_MAP_WRAPPERS(vt_u64_val64, uint64_t, val64_t, 64, vt_u64_val64_internal)
DEFINE_INT_MAP_WRAPPERS(vt_u16_val64, uint16_t, val64_t, 64, vt_u16_val64_internal)
DEFINE_STR_MAP_WRAPPERS(vt_str_val64, val64_t, 64, vt_str_val64_internal)

// Maps with 256-byte values
DEFINE_INT_MAP_WRAPPERS(vt_u64_val256, uint64_t, val256_t, 256, vt_u64_val256_internal)
DEFINE_INT_MAP_WRAPPERS(vt_u16_val256, uint16_t, val256_t, 256, vt_u16_val256_internal)
DEFINE_STR_MAP_WRAPPERS(vt_str_val256, val256_t, 256, vt_str_val256_internal)
