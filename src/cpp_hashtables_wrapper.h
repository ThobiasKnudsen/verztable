// Header file for C++ hash table wrapper functions
// Provides extern "C" interface for Abseil, Boost, and Ankerl hash tables
// Unified naming: {lib}_{keytype}_{valtype}_{operation}
// Libraries: absl (Abseil flat_hash_map), boost (unordered_flat_map), ankerl (unordered_dense)
// Key types: u32, u64, str
// Val types: void (set), val4, val64

#ifndef CPP_HASHTABLES_WRAPPER_H
#define CPP_HASHTABLES_WRAPPER_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Opaque handle type for all C++ hash tables
// ============================================================================

typedef void* cpp_map_handle;

// ============================================================================
// Abseil flat_hash_map - u32 key
// ============================================================================

// u32 -> void (set)
cpp_map_handle absl_u32_void_init(void);
void absl_u32_void_cleanup(cpp_map_handle h);
int absl_u32_void_insert(cpp_map_handle h, uint32_t key);
int absl_u32_void_get(cpp_map_handle h, uint32_t key);
int absl_u32_void_erase(cpp_map_handle h, uint32_t key);
size_t absl_u32_void_size(cpp_map_handle h);
size_t absl_u32_void_iter_count(cpp_map_handle h);
size_t absl_u32_void_memory(cpp_map_handle h);

// u32 -> val4
cpp_map_handle absl_u32_val4_init(void);
void absl_u32_val4_cleanup(cpp_map_handle h);
int absl_u32_val4_insert(cpp_map_handle h, uint32_t key, const uint8_t* val);
const uint8_t* absl_u32_val4_get(cpp_map_handle h, uint32_t key);
int absl_u32_val4_erase(cpp_map_handle h, uint32_t key);
size_t absl_u32_val4_size(cpp_map_handle h);
size_t absl_u32_val4_iter_count(cpp_map_handle h);
size_t absl_u32_val4_memory(cpp_map_handle h);

// u32 -> val64
cpp_map_handle absl_u32_val64_init(void);
void absl_u32_val64_cleanup(cpp_map_handle h);
int absl_u32_val64_insert(cpp_map_handle h, uint32_t key, const uint8_t* val);
const uint8_t* absl_u32_val64_get(cpp_map_handle h, uint32_t key);
int absl_u32_val64_erase(cpp_map_handle h, uint32_t key);
size_t absl_u32_val64_size(cpp_map_handle h);
size_t absl_u32_val64_iter_count(cpp_map_handle h);
size_t absl_u32_val64_memory(cpp_map_handle h);

// ============================================================================
// Abseil flat_hash_map - u64 key
// ============================================================================

// u64 -> void (set)
cpp_map_handle absl_u64_void_init(void);
void absl_u64_void_cleanup(cpp_map_handle h);
int absl_u64_void_insert(cpp_map_handle h, uint64_t key);
int absl_u64_void_get(cpp_map_handle h, uint64_t key);
int absl_u64_void_erase(cpp_map_handle h, uint64_t key);
size_t absl_u64_void_size(cpp_map_handle h);
size_t absl_u64_void_iter_count(cpp_map_handle h);
size_t absl_u64_void_memory(cpp_map_handle h);

// u64 -> val4
cpp_map_handle absl_u64_val4_init(void);
void absl_u64_val4_cleanup(cpp_map_handle h);
int absl_u64_val4_insert(cpp_map_handle h, uint64_t key, const uint8_t* val);
const uint8_t* absl_u64_val4_get(cpp_map_handle h, uint64_t key);
int absl_u64_val4_erase(cpp_map_handle h, uint64_t key);
size_t absl_u64_val4_size(cpp_map_handle h);
size_t absl_u64_val4_iter_count(cpp_map_handle h);
size_t absl_u64_val4_memory(cpp_map_handle h);

// u64 -> val64
cpp_map_handle absl_u64_val64_init(void);
void absl_u64_val64_cleanup(cpp_map_handle h);
int absl_u64_val64_insert(cpp_map_handle h, uint64_t key, const uint8_t* val);
const uint8_t* absl_u64_val64_get(cpp_map_handle h, uint64_t key);
int absl_u64_val64_erase(cpp_map_handle h, uint64_t key);
size_t absl_u64_val64_size(cpp_map_handle h);
size_t absl_u64_val64_iter_count(cpp_map_handle h);
size_t absl_u64_val64_memory(cpp_map_handle h);

// ============================================================================
// Abseil flat_hash_map - string key
// ============================================================================

// str -> void (set)
cpp_map_handle absl_str_void_init(void);
void absl_str_void_cleanup(cpp_map_handle h);
int absl_str_void_insert(cpp_map_handle h, const char* key, size_t len);
int absl_str_void_get(cpp_map_handle h, const char* key, size_t len);
int absl_str_void_erase(cpp_map_handle h, const char* key, size_t len);
size_t absl_str_void_size(cpp_map_handle h);
size_t absl_str_void_iter_count(cpp_map_handle h);
size_t absl_str_void_memory(cpp_map_handle h);

// str -> val4
cpp_map_handle absl_str_val4_init(void);
void absl_str_val4_cleanup(cpp_map_handle h);
int absl_str_val4_insert(cpp_map_handle h, const char* key, size_t len, const uint8_t* val);
const uint8_t* absl_str_val4_get(cpp_map_handle h, const char* key, size_t len);
int absl_str_val4_erase(cpp_map_handle h, const char* key, size_t len);
size_t absl_str_val4_size(cpp_map_handle h);
size_t absl_str_val4_iter_count(cpp_map_handle h);
size_t absl_str_val4_memory(cpp_map_handle h);

// str -> val64
cpp_map_handle absl_str_val64_init(void);
void absl_str_val64_cleanup(cpp_map_handle h);
int absl_str_val64_insert(cpp_map_handle h, const char* key, size_t len, const uint8_t* val);
const uint8_t* absl_str_val64_get(cpp_map_handle h, const char* key, size_t len);
int absl_str_val64_erase(cpp_map_handle h, const char* key, size_t len);
size_t absl_str_val64_size(cpp_map_handle h);
size_t absl_str_val64_iter_count(cpp_map_handle h);
size_t absl_str_val64_memory(cpp_map_handle h);

// ============================================================================
// Boost unordered_flat_map - u32 key
// ============================================================================

// u32 -> void (set)
cpp_map_handle boost_u32_void_init(void);
void boost_u32_void_cleanup(cpp_map_handle h);
int boost_u32_void_insert(cpp_map_handle h, uint32_t key);
int boost_u32_void_get(cpp_map_handle h, uint32_t key);
int boost_u32_void_erase(cpp_map_handle h, uint32_t key);
size_t boost_u32_void_size(cpp_map_handle h);
size_t boost_u32_void_iter_count(cpp_map_handle h);
size_t boost_u32_void_memory(cpp_map_handle h);

// u32 -> val4
cpp_map_handle boost_u32_val4_init(void);
void boost_u32_val4_cleanup(cpp_map_handle h);
int boost_u32_val4_insert(cpp_map_handle h, uint32_t key, const uint8_t* val);
const uint8_t* boost_u32_val4_get(cpp_map_handle h, uint32_t key);
int boost_u32_val4_erase(cpp_map_handle h, uint32_t key);
size_t boost_u32_val4_size(cpp_map_handle h);
size_t boost_u32_val4_iter_count(cpp_map_handle h);
size_t boost_u32_val4_memory(cpp_map_handle h);

// u32 -> val64
cpp_map_handle boost_u32_val64_init(void);
void boost_u32_val64_cleanup(cpp_map_handle h);
int boost_u32_val64_insert(cpp_map_handle h, uint32_t key, const uint8_t* val);
const uint8_t* boost_u32_val64_get(cpp_map_handle h, uint32_t key);
int boost_u32_val64_erase(cpp_map_handle h, uint32_t key);
size_t boost_u32_val64_size(cpp_map_handle h);
size_t boost_u32_val64_iter_count(cpp_map_handle h);
size_t boost_u32_val64_memory(cpp_map_handle h);

// ============================================================================
// Boost unordered_flat_map - u64 key
// ============================================================================

// u64 -> void (set)
cpp_map_handle boost_u64_void_init(void);
void boost_u64_void_cleanup(cpp_map_handle h);
int boost_u64_void_insert(cpp_map_handle h, uint64_t key);
int boost_u64_void_get(cpp_map_handle h, uint64_t key);
int boost_u64_void_erase(cpp_map_handle h, uint64_t key);
size_t boost_u64_void_size(cpp_map_handle h);
size_t boost_u64_void_iter_count(cpp_map_handle h);
size_t boost_u64_void_memory(cpp_map_handle h);

// u64 -> val4
cpp_map_handle boost_u64_val4_init(void);
void boost_u64_val4_cleanup(cpp_map_handle h);
int boost_u64_val4_insert(cpp_map_handle h, uint64_t key, const uint8_t* val);
const uint8_t* boost_u64_val4_get(cpp_map_handle h, uint64_t key);
int boost_u64_val4_erase(cpp_map_handle h, uint64_t key);
size_t boost_u64_val4_size(cpp_map_handle h);
size_t boost_u64_val4_iter_count(cpp_map_handle h);
size_t boost_u64_val4_memory(cpp_map_handle h);

// u64 -> val64
cpp_map_handle boost_u64_val64_init(void);
void boost_u64_val64_cleanup(cpp_map_handle h);
int boost_u64_val64_insert(cpp_map_handle h, uint64_t key, const uint8_t* val);
const uint8_t* boost_u64_val64_get(cpp_map_handle h, uint64_t key);
int boost_u64_val64_erase(cpp_map_handle h, uint64_t key);
size_t boost_u64_val64_size(cpp_map_handle h);
size_t boost_u64_val64_iter_count(cpp_map_handle h);
size_t boost_u64_val64_memory(cpp_map_handle h);

// ============================================================================
// Boost unordered_flat_map - string key
// ============================================================================

// str -> void (set)
cpp_map_handle boost_str_void_init(void);
void boost_str_void_cleanup(cpp_map_handle h);
int boost_str_void_insert(cpp_map_handle h, const char* key, size_t len);
int boost_str_void_get(cpp_map_handle h, const char* key, size_t len);
int boost_str_void_erase(cpp_map_handle h, const char* key, size_t len);
size_t boost_str_void_size(cpp_map_handle h);
size_t boost_str_void_iter_count(cpp_map_handle h);
size_t boost_str_void_memory(cpp_map_handle h);

// str -> val4
cpp_map_handle boost_str_val4_init(void);
void boost_str_val4_cleanup(cpp_map_handle h);
int boost_str_val4_insert(cpp_map_handle h, const char* key, size_t len, const uint8_t* val);
const uint8_t* boost_str_val4_get(cpp_map_handle h, const char* key, size_t len);
int boost_str_val4_erase(cpp_map_handle h, const char* key, size_t len);
size_t boost_str_val4_size(cpp_map_handle h);
size_t boost_str_val4_iter_count(cpp_map_handle h);
size_t boost_str_val4_memory(cpp_map_handle h);

// str -> val64
cpp_map_handle boost_str_val64_init(void);
void boost_str_val64_cleanup(cpp_map_handle h);
int boost_str_val64_insert(cpp_map_handle h, const char* key, size_t len, const uint8_t* val);
const uint8_t* boost_str_val64_get(cpp_map_handle h, const char* key, size_t len);
int boost_str_val64_erase(cpp_map_handle h, const char* key, size_t len);
size_t boost_str_val64_size(cpp_map_handle h);
size_t boost_str_val64_iter_count(cpp_map_handle h);
size_t boost_str_val64_memory(cpp_map_handle h);

// ============================================================================
// Ankerl unordered_dense - u32 key
// ============================================================================

// u32 -> void (set)
cpp_map_handle ankerl_u32_void_init(void);
void ankerl_u32_void_cleanup(cpp_map_handle h);
int ankerl_u32_void_insert(cpp_map_handle h, uint32_t key);
int ankerl_u32_void_get(cpp_map_handle h, uint32_t key);
int ankerl_u32_void_erase(cpp_map_handle h, uint32_t key);
size_t ankerl_u32_void_size(cpp_map_handle h);
size_t ankerl_u32_void_iter_count(cpp_map_handle h);
size_t ankerl_u32_void_memory(cpp_map_handle h);

// u32 -> val4
cpp_map_handle ankerl_u32_val4_init(void);
void ankerl_u32_val4_cleanup(cpp_map_handle h);
int ankerl_u32_val4_insert(cpp_map_handle h, uint32_t key, const uint8_t* val);
const uint8_t* ankerl_u32_val4_get(cpp_map_handle h, uint32_t key);
int ankerl_u32_val4_erase(cpp_map_handle h, uint32_t key);
size_t ankerl_u32_val4_size(cpp_map_handle h);
size_t ankerl_u32_val4_iter_count(cpp_map_handle h);
size_t ankerl_u32_val4_memory(cpp_map_handle h);

// u32 -> val64
cpp_map_handle ankerl_u32_val64_init(void);
void ankerl_u32_val64_cleanup(cpp_map_handle h);
int ankerl_u32_val64_insert(cpp_map_handle h, uint32_t key, const uint8_t* val);
const uint8_t* ankerl_u32_val64_get(cpp_map_handle h, uint32_t key);
int ankerl_u32_val64_erase(cpp_map_handle h, uint32_t key);
size_t ankerl_u32_val64_size(cpp_map_handle h);
size_t ankerl_u32_val64_iter_count(cpp_map_handle h);
size_t ankerl_u32_val64_memory(cpp_map_handle h);

// ============================================================================
// Ankerl unordered_dense - u64 key
// ============================================================================

// u64 -> void (set)
cpp_map_handle ankerl_u64_void_init(void);
void ankerl_u64_void_cleanup(cpp_map_handle h);
int ankerl_u64_void_insert(cpp_map_handle h, uint64_t key);
int ankerl_u64_void_get(cpp_map_handle h, uint64_t key);
int ankerl_u64_void_erase(cpp_map_handle h, uint64_t key);
size_t ankerl_u64_void_size(cpp_map_handle h);
size_t ankerl_u64_void_iter_count(cpp_map_handle h);
size_t ankerl_u64_void_memory(cpp_map_handle h);

// u64 -> val4
cpp_map_handle ankerl_u64_val4_init(void);
void ankerl_u64_val4_cleanup(cpp_map_handle h);
int ankerl_u64_val4_insert(cpp_map_handle h, uint64_t key, const uint8_t* val);
const uint8_t* ankerl_u64_val4_get(cpp_map_handle h, uint64_t key);
int ankerl_u64_val4_erase(cpp_map_handle h, uint64_t key);
size_t ankerl_u64_val4_size(cpp_map_handle h);
size_t ankerl_u64_val4_iter_count(cpp_map_handle h);
size_t ankerl_u64_val4_memory(cpp_map_handle h);

// u64 -> val64
cpp_map_handle ankerl_u64_val64_init(void);
void ankerl_u64_val64_cleanup(cpp_map_handle h);
int ankerl_u64_val64_insert(cpp_map_handle h, uint64_t key, const uint8_t* val);
const uint8_t* ankerl_u64_val64_get(cpp_map_handle h, uint64_t key);
int ankerl_u64_val64_erase(cpp_map_handle h, uint64_t key);
size_t ankerl_u64_val64_size(cpp_map_handle h);
size_t ankerl_u64_val64_iter_count(cpp_map_handle h);
size_t ankerl_u64_val64_memory(cpp_map_handle h);

// ============================================================================
// Ankerl unordered_dense - string key
// ============================================================================

// str -> void (set)
cpp_map_handle ankerl_str_void_init(void);
void ankerl_str_void_cleanup(cpp_map_handle h);
int ankerl_str_void_insert(cpp_map_handle h, const char* key, size_t len);
int ankerl_str_void_get(cpp_map_handle h, const char* key, size_t len);
int ankerl_str_void_erase(cpp_map_handle h, const char* key, size_t len);
size_t ankerl_str_void_size(cpp_map_handle h);
size_t ankerl_str_void_iter_count(cpp_map_handle h);
size_t ankerl_str_void_memory(cpp_map_handle h);

// str -> val4
cpp_map_handle ankerl_str_val4_init(void);
void ankerl_str_val4_cleanup(cpp_map_handle h);
int ankerl_str_val4_insert(cpp_map_handle h, const char* key, size_t len, const uint8_t* val);
const uint8_t* ankerl_str_val4_get(cpp_map_handle h, const char* key, size_t len);
int ankerl_str_val4_erase(cpp_map_handle h, const char* key, size_t len);
size_t ankerl_str_val4_size(cpp_map_handle h);
size_t ankerl_str_val4_iter_count(cpp_map_handle h);
size_t ankerl_str_val4_memory(cpp_map_handle h);

// str -> val64
cpp_map_handle ankerl_str_val64_init(void);
void ankerl_str_val64_cleanup(cpp_map_handle h);
int ankerl_str_val64_insert(cpp_map_handle h, const char* key, size_t len, const uint8_t* val);
const uint8_t* ankerl_str_val64_get(cpp_map_handle h, const char* key, size_t len);
int ankerl_str_val64_erase(cpp_map_handle h, const char* key, size_t len);
size_t ankerl_str_val64_size(cpp_map_handle h);
size_t ankerl_str_val64_iter_count(cpp_map_handle h);
size_t ankerl_str_val64_memory(cpp_map_handle h);

#ifdef __cplusplus
}
#endif

#endif // CPP_HASHTABLES_WRAPPER_H
