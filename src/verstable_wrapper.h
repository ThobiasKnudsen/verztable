// Header file for Verstable wrapper functions
// Used by Zig to import the C function signatures

#ifndef VERSTABLE_WRAPPER_H
#define VERSTABLE_WRAPPER_H

#include <stdint.h>
#include <stddef.h>

// Opaque type representing the Verstable map
typedef struct {
    size_t key_count;
    size_t buckets_mask;
    void *buckets;
    uint16_t *metadata;
} vt_u64_map;

// Iterator type
typedef struct {
    void *itr_data;
    uint16_t *metadatum;
    uint16_t *metadata_end;
    size_t home_bucket;
} vt_wrapper_iter;

// Initialize a new map
void vt_wrapper_init(vt_u64_map *table);

// Clean up and free the map
void vt_wrapper_cleanup(vt_u64_map *table);

// Insert a key-value pair. Returns 1 on success, 0 on failure
int vt_wrapper_insert(vt_u64_map *table, uint64_t key, uint64_t val);

// Get value for a key. Returns pointer to value if found, NULL otherwise
uint64_t* vt_wrapper_get(vt_u64_map *table, uint64_t key);

// Erase a key. Returns 1 if erased, 0 if not found
int vt_wrapper_erase(vt_u64_map *table, uint64_t key);

// Get current size
size_t vt_wrapper_size(vt_u64_map *table);

// Get bucket count
size_t vt_wrapper_bucket_count(vt_u64_map *table);

// Iteration
vt_wrapper_iter vt_wrapper_first(vt_u64_map *table);
int vt_wrapper_is_end(vt_wrapper_iter iter);
vt_wrapper_iter vt_wrapper_next(vt_wrapper_iter iter);
uint64_t vt_wrapper_iter_val(vt_wrapper_iter iter);

#endif // VERSTABLE_WRAPPER_H

