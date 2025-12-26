// Header file for Verstable wrapper functions
// Unified naming: vt_{keytype}_{valtype}_{operation}
// Key types: u64, str
// Val types: void (set), val4, val64

#ifndef VERSTABLE_WRAPPER_H
#define VERSTABLE_WRAPPER_H

#include <stdint.h>
#include <stddef.h>

// ============================================================================
// Common types
// ============================================================================

// Generic iterator (same layout for all map types)
typedef struct {
    void *itr_data;
    uint16_t *metadatum;
    uint16_t *metadata_end;
    size_t home_bucket;
} vt_generic_iter;

// Generic map structure (same layout for all)
typedef struct {
    size_t key_count;
    size_t buckets_mask;
    void *buckets;
    uint16_t *metadata;
} vt_generic_map;

// ============================================================================
// Type aliases for each key/value combination
// ============================================================================

// u64 key maps
typedef vt_generic_map vt_u64_void_map;
typedef vt_generic_map vt_u64_val4_map;
typedef vt_generic_map vt_u64_val64_map;

// string key maps
typedef vt_generic_map vt_str_void_map;
typedef vt_generic_map vt_str_val4_map;
typedef vt_generic_map vt_str_val64_map;

// ============================================================================
// u64 key - void value (set)
// ============================================================================

void vt_u64_void_init(vt_u64_void_map *table);
void vt_u64_void_cleanup(vt_u64_void_map *table);
int vt_u64_void_insert(vt_u64_void_map *table, uint64_t key);
int vt_u64_void_get(vt_u64_void_map *table, uint64_t key);
int vt_u64_void_erase(vt_u64_void_map *table, uint64_t key);
size_t vt_u64_void_size(vt_u64_void_map *table);
vt_generic_iter vt_u64_void_first(vt_u64_void_map *table);
int vt_u64_void_is_end(vt_generic_iter iter);
vt_generic_iter vt_u64_void_next(vt_generic_iter iter);

// ============================================================================
// u64 key - val4 value (4 bytes)
// ============================================================================

void vt_u64_val4_init(vt_u64_val4_map *table);
void vt_u64_val4_cleanup(vt_u64_val4_map *table);
int vt_u64_val4_insert(vt_u64_val4_map *table, uint64_t key, const uint8_t *val);
const uint8_t* vt_u64_val4_get(vt_u64_val4_map *table, uint64_t key);
int vt_u64_val4_erase(vt_u64_val4_map *table, uint64_t key);
size_t vt_u64_val4_size(vt_u64_val4_map *table);
vt_generic_iter vt_u64_val4_first(vt_u64_val4_map *table);
int vt_u64_val4_is_end(vt_generic_iter iter);
vt_generic_iter vt_u64_val4_next(vt_generic_iter iter);

// ============================================================================
// u64 key - val64 value (64 bytes)
// ============================================================================

void vt_u64_val64_init(vt_u64_val64_map *table);
void vt_u64_val64_cleanup(vt_u64_val64_map *table);
int vt_u64_val64_insert(vt_u64_val64_map *table, uint64_t key, const uint8_t *val);
const uint8_t* vt_u64_val64_get(vt_u64_val64_map *table, uint64_t key);
int vt_u64_val64_erase(vt_u64_val64_map *table, uint64_t key);
size_t vt_u64_val64_size(vt_u64_val64_map *table);
vt_generic_iter vt_u64_val64_first(vt_u64_val64_map *table);
int vt_u64_val64_is_end(vt_generic_iter iter);
vt_generic_iter vt_u64_val64_next(vt_generic_iter iter);

// ============================================================================
// string key - void value (set)
// ============================================================================

void vt_str_void_init(vt_str_void_map *table);
void vt_str_void_cleanup(vt_str_void_map *table);
int vt_str_void_insert(vt_str_void_map *table, const char *key, size_t len);
int vt_str_void_get(vt_str_void_map *table, const char *key, size_t len);
int vt_str_void_erase(vt_str_void_map *table, const char *key, size_t len);
size_t vt_str_void_size(vt_str_void_map *table);
vt_generic_iter vt_str_void_first(vt_str_void_map *table);
int vt_str_void_is_end(vt_generic_iter iter);
vt_generic_iter vt_str_void_next(vt_generic_iter iter);

// ============================================================================
// string key - val4 value (4 bytes)
// ============================================================================

void vt_str_val4_init(vt_str_val4_map *table);
void vt_str_val4_cleanup(vt_str_val4_map *table);
int vt_str_val4_insert(vt_str_val4_map *table, const char *key, size_t len, const uint8_t *val);
const uint8_t* vt_str_val4_get(vt_str_val4_map *table, const char *key, size_t len);
int vt_str_val4_erase(vt_str_val4_map *table, const char *key, size_t len);
size_t vt_str_val4_size(vt_str_val4_map *table);
vt_generic_iter vt_str_val4_first(vt_str_val4_map *table);
int vt_str_val4_is_end(vt_generic_iter iter);
vt_generic_iter vt_str_val4_next(vt_generic_iter iter);

// ============================================================================
// string key - val64 value (64 bytes)
// ============================================================================

void vt_str_val64_init(vt_str_val64_map *table);
void vt_str_val64_cleanup(vt_str_val64_map *table);
int vt_str_val64_insert(vt_str_val64_map *table, const char *key, size_t len, const uint8_t *val);
const uint8_t* vt_str_val64_get(vt_str_val64_map *table, const char *key, size_t len);
int vt_str_val64_erase(vt_str_val64_map *table, const char *key, size_t len);
size_t vt_str_val64_size(vt_str_val64_map *table);
vt_generic_iter vt_str_val64_first(vt_str_val64_map *table);
int vt_str_val64_is_end(vt_generic_iter iter);
vt_generic_iter vt_str_val64_next(vt_generic_iter iter);

#endif // VERSTABLE_WRAPPER_H
