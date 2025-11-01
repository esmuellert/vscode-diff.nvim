/**
 * Specialized String-to-Sequential-ID Hash Map Implementation
 * 
 * This is NOT a general-purpose hash table. It's optimized for the specific use case
 * of assigning unique sequential integers to unique strings during diff computation.
 * 
 * Implementation details:
 * - FNV-1a hash for bucket selection (same performance as TypeScript Map's internal hash)
 * - Chaining for collision resolution
 * - Dynamic resizing at 75% load factor
 * - Collision-free values: sequential IDs guarantee no value collisions
 * 
 * Performance: O(1) average lookup/insert, matching TypeScript Map
 * VSCode Parity: 100% - Exactly matches perfectHashes Map behavior
 */

#include "string_hash_map.h"
#include "platform.h"
#include <stdlib.h>
#include <string.h>

#define INITIAL_CAPACITY 16
#define LOAD_FACTOR 0.75

typedef struct HashEntry {
    char* key;              // Owned string copy
    uint32_t value;         // Sequential integer (0, 1, 2, ...)
    struct HashEntry* next; // Chaining for collision resolution
} HashEntry;

struct StringHashMap {
    HashEntry** buckets;
    int capacity;
    int size;              // Number of unique strings
};

/**
 * FNV-1a hash for bucket selection
 * 
 * NOTE: This is ONLY used to choose which bucket to place an entry in.
 * The value returned to the caller is a sequential ID (0, 1, 2, ...),
 * NOT this hash value. This ensures perfect collision-free behavior.
 */
static uint32_t hash_for_bucket(const char* str) {
    uint32_t hash = 2166136261u;
    while (*str) {
        hash ^= (uint32_t)(unsigned char)(*str);
        hash *= 16777619u;
        str++;
    }
    return hash;
}

StringHashMap* string_hash_map_create(void) {
    StringHashMap* map = (StringHashMap*)malloc(sizeof(StringHashMap));
    map->capacity = INITIAL_CAPACITY;
    map->size = 0;
    map->buckets = (HashEntry**)calloc(map->capacity, sizeof(HashEntry*));
    return map;
}

/**
 * Resize the hash table when load factor exceeds threshold
 */
static void resize_if_needed(StringHashMap* map) {
    if ((double)map->size / map->capacity < LOAD_FACTOR) {
        return;
    }
    
    int new_capacity = map->capacity * 2;
    HashEntry** new_buckets = (HashEntry**)calloc(new_capacity, sizeof(HashEntry*));
    
    // Rehash all entries
    for (int i = 0; i < map->capacity; i++) {
        HashEntry* entry = map->buckets[i];
        while (entry) {
            HashEntry* next = entry->next;
            
            // Recompute bucket for new capacity
            uint32_t bucket = hash_for_bucket(entry->key) % new_capacity;
            entry->next = new_buckets[bucket];
            new_buckets[bucket] = entry;
            
            entry = next;
        }
    }
    
    free(map->buckets);
    map->buckets = new_buckets;
    map->capacity = new_capacity;
}

uint32_t string_hash_map_get_or_create(StringHashMap* map, const char* str) {
    uint32_t bucket = hash_for_bucket(str) % map->capacity;
    
    // Search for existing entry
    HashEntry* entry = map->buckets[bucket];
    while (entry) {
        if (strcmp(entry->key, str) == 0) {
            return entry->value;  // Found existing
        }
        entry = entry->next;
    }
    
    // Not found - create new entry with sequential value
    resize_if_needed(map);
    
    // Recompute bucket after potential resize
    bucket = hash_for_bucket(str) % map->capacity;
    
    HashEntry* new_entry = (HashEntry*)malloc(sizeof(HashEntry));
    new_entry->key = diff_strdup(str);
    new_entry->value = map->size;  // Sequential: 0, 1, 2, ...
    new_entry->next = map->buckets[bucket];
    map->buckets[bucket] = new_entry;
    
    map->size++;
    return new_entry->value;
}

int string_hash_map_size(const StringHashMap* map) {
    return map->size;
}

void string_hash_map_destroy(StringHashMap* map) {
    if (!map) return;
    
    for (int i = 0; i < map->capacity; i++) {
        HashEntry* entry = map->buckets[i];
        while (entry) {
            HashEntry* next = entry->next;
            free(entry->key);
            free(entry);
            entry = next;
        }
    }
    
    free(map->buckets);
    free(map);
}
