// C wrapper for Verstable to be used in Zig benchmarks
// This file instantiates the Verstable template for u64->u64 maps

#include <stdint.h>
#include <stddef.h>

// Instantiate the Verstable template
#define NAME vt_u64_map_internal
#define KEY_TY uint64_t
#define VAL_TY uint64_t
#define HASH_FN vt_hash_integer
#define CMPR_FN vt_cmpr_integer
#include "verstable.h"

// Use the header's types
#include "verstable_wrapper.h"

// Wrapper functions with C linkage for Zig

void vt_wrapper_init(vt_u64_map *table) {
    vt_u64_map_internal_init((vt_u64_map_internal*)table);
}

void vt_wrapper_cleanup(vt_u64_map *table) {
    vt_u64_map_internal_cleanup((vt_u64_map_internal*)table);
}

// Returns 1 on success, 0 on failure (memory allocation)
int vt_wrapper_insert(vt_u64_map *table, uint64_t key, uint64_t val) {
    vt_u64_map_internal_itr itr = vt_u64_map_internal_insert((vt_u64_map_internal*)table, key, val);
    return !vt_u64_map_internal_is_end(itr);
}

// Returns pointer to value if found, NULL otherwise
uint64_t* vt_wrapper_get(vt_u64_map *table, uint64_t key) {
    vt_u64_map_internal_itr itr = vt_u64_map_internal_get((vt_u64_map_internal*)table, key);
    if (vt_u64_map_internal_is_end(itr)) {
        return NULL;
    }
    return &itr.data->val;
}

// Returns 1 if key was erased, 0 otherwise
int vt_wrapper_erase(vt_u64_map *table, uint64_t key) {
    return vt_u64_map_internal_erase((vt_u64_map_internal*)table, key) ? 1 : 0;
}

size_t vt_wrapper_size(vt_u64_map *table) {
    return vt_u64_map_internal_size((vt_u64_map_internal*)table);
}

size_t vt_wrapper_bucket_count(vt_u64_map *table) {
    return vt_u64_map_internal_bucket_count((vt_u64_map_internal*)table);
}

// Iterator support - use internal iterator type
vt_wrapper_iter vt_wrapper_first(vt_u64_map *table) {
    vt_u64_map_internal_itr internal_itr = vt_u64_map_internal_first((vt_u64_map_internal*)table);
    vt_wrapper_iter iter;
    iter.itr_data = internal_itr.data;
    iter.metadatum = internal_itr.metadatum;
    iter.metadata_end = internal_itr.metadata_end;
    iter.home_bucket = internal_itr.home_bucket;
    return iter;
}

int vt_wrapper_is_end(vt_wrapper_iter iter) {
    return iter.metadatum == iter.metadata_end ? 1 : 0;
}

vt_wrapper_iter vt_wrapper_next(vt_wrapper_iter iter) {
    vt_u64_map_internal_itr internal_itr;
    internal_itr.data = (vt_u64_map_internal_bucket*)iter.itr_data;
    internal_itr.metadatum = iter.metadatum;
    internal_itr.metadata_end = iter.metadata_end;
    internal_itr.home_bucket = iter.home_bucket;
    
    vt_u64_map_internal_itr next_internal = vt_u64_map_internal_next(internal_itr);
    
    vt_wrapper_iter next_iter;
    next_iter.itr_data = next_internal.data;
    next_iter.metadatum = next_internal.metadatum;
    next_iter.metadata_end = next_internal.metadata_end;
    next_iter.home_bucket = next_internal.home_bucket;
    return next_iter;
}

uint64_t vt_wrapper_iter_val(vt_wrapper_iter iter) {
    vt_u64_map_internal_bucket *bucket = (vt_u64_map_internal_bucket*)iter.itr_data;
    return bucket->val;
}

