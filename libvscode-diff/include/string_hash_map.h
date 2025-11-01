/**
 * Specialized String-to-Sequential-ID Hash Map
 * 
 * NOT a general-purpose hash table. This is a specialized implementation for diff
 * computation that assigns unique sequential IDs (0, 1, 2, ...) to unique strings.
 * 
 * Supported operations:
 * - Insert/lookup via get_or_create() - assigns next ID if new, returns existing ID if seen
 * - Size query
 * - Destruction
 * 
 * NOT supported (not needed for diff):
 * - Delete, update, or iteration
 * 
 * Provides 100% parity with VSCode's perfectHashes Map<string, number> usage pattern.
 * 
 * Lifecycle: Created per diff computation, destroyed after completion.
 * Memory: ~O(unique_lines) - typically < 200KB for normal files.
 * 
 * VSCode Reference: defaultLinesDiffComputer.ts (perfectHashes Map + getOrCreateHash)
 */

#ifndef STRING_HASH_MAP_H
#define STRING_HASH_MAP_H

#include <stdint.h>
#include <stdbool.h>

typedef struct StringHashMap StringHashMap;

/**
 * Create a new string hash map
 * Initial capacity will be automatically adjusted
 */
StringHashMap* string_hash_map_create(void);

/**
 * Get or create hash for a string
 * 
 * This matches VSCode's getOrCreateHash():
 * - If string exists, return its hash
 * - If string is new, assign next sequential integer (0, 1, 2, ...)
 * - GUARANTEES no collisions (same as Map<string, number>)
 * 
 * @param map The hash map
 * @param str The string to hash (will be copied internally)
 * @return Unique integer for this string
 */
uint32_t string_hash_map_get_or_create(StringHashMap* map, const char* str);

/**
 * Get current size (number of unique strings)
 */
int string_hash_map_size(const StringHashMap* map);

/**
 * Destroy the hash map and free all memory
 */
void string_hash_map_destroy(StringHashMap* map);

#endif // STRING_HASH_MAP_H
