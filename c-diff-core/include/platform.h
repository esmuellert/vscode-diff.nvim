/**
 * Cross-Platform Compatibility Layer
 * 
 * Provides portable abstractions for platform-specific functionality.
 * Supports: Windows (MSVC, MinGW), Linux, macOS, BSD
 */

#ifndef PLATFORM_H
#define PLATFORM_H

#include <stdlib.h>
#include <string.h>

// ============================================================================
// String Duplication (portable strdup)
// ============================================================================

/**
 * Portable string duplication function.
 * 
 * Platform differences:
 * - POSIX: strdup() available
 * - MSVC Windows: _strdup() available
 * - C89/C99: Not standard, need manual implementation
 * 
 * Returns: Allocated copy of string (caller must free), or NULL on failure
 */
static inline char* diff_strdup(const char* s) {
    if (!s) return NULL;
    size_t len = strlen(s) + 1;
    char* copy = (char*)malloc(len);
    if (copy) {
        memcpy(copy, s, len);
    }
    return copy;
}

// ============================================================================
// Terminal Detection (isatty/fileno)
// ============================================================================

#ifdef _WIN32
    // Windows platform
    #include <io.h>
    #define diff_isatty _isatty
    #define diff_fileno _fileno
#else
    // POSIX platforms (Linux, macOS, BSD, etc.)
    #include <unistd.h>
    #define diff_isatty isatty
    #define diff_fileno fileno
#endif

#endif // PLATFORM_H
