#include "utf8_utils.h"
#include <string.h>
#include <stdlib.h>
#include <utf8proc.h>

// Get the number of bytes in a UTF-8 character starting at the given byte
int utf8_char_bytes(const char* str, int byte_pos) {
    if (!str) return 0;
    
    utf8proc_int32_t codepoint;
    utf8proc_ssize_t bytes = utf8proc_iterate(
        (const utf8proc_uint8_t*)(str + byte_pos),
        -1,  // Read until null terminator
        &codepoint
    );
    
    return bytes > 0 ? (int)bytes : 1;
}

// Convert byte position to UTF-8 character position (column)
int utf8_byte_to_column(const char* str, int byte_pos) {
    if (!str || byte_pos < 0) return 0;
    
    int column = 0;
    int i = 0;
    const utf8proc_uint8_t* ustr = (const utf8proc_uint8_t*)str;
    
    while (i < byte_pos && str[i] != '\0') {
        utf8proc_int32_t codepoint;
        utf8proc_ssize_t bytes = utf8proc_iterate(ustr + i, -1, &codepoint);
        if (bytes <= 0) break;
        i += bytes;
        column++;
    }
    
    return column;
}

// Convert UTF-8 character position (column) to byte position
int utf8_column_to_byte(const char* str, int column) {
    if (!str || column < 0) return 0;
    
    int byte_pos = 0;
    int col = 0;
    const utf8proc_uint8_t* ustr = (const utf8proc_uint8_t*)str;
    
    while (col < column && str[byte_pos] != '\0') {
        utf8proc_int32_t codepoint;
        utf8proc_ssize_t bytes = utf8proc_iterate(ustr + byte_pos, -1, &codepoint);
        if (bytes <= 0) break;
        byte_pos += bytes;
        col++;
    }
    
    return byte_pos;
}

// Count the number of UTF-8 characters in a string
int utf8_strlen(const char* str) {
    if (!str) return 0;
    
    int count = 0;
    int i = 0;
    const utf8proc_uint8_t* ustr = (const utf8proc_uint8_t*)str;
    
    while (str[i] != '\0') {
        utf8proc_int32_t codepoint;
        utf8proc_ssize_t bytes = utf8proc_iterate(ustr + i, -1, &codepoint);
        if (bytes <= 0) break;
        i += bytes;
        count++;
    }
    
    return count;
}

// Convert character position to byte offset in UTF-8 string
int utf8_char_to_byte_offset(const char* str, int char_pos) {
    return utf8_column_to_byte(str, char_pos);
}

// Convert byte offset to character position in UTF-8 string
int utf8_byte_to_char_offset(const char* str, int byte_offset) {
    return utf8_byte_to_column(str, byte_offset);
}

// Check if byte position is at a UTF-8 character boundary
int utf8_is_char_boundary(const char* str, int byte_pos) {
    if (!str || byte_pos < 0) return 0;
    if (str[byte_pos] == '\0') return 1;
    
    unsigned char c = (unsigned char)str[byte_pos];
    // A byte is at character boundary if it's:
    // - ASCII (0xxxxxxx)
    // - Start of multi-byte sequence (11xxxxxx)
    // NOT a continuation byte (10xxxxxx)
    return (c & 0x80) == 0 || (c & 0xC0) == 0xC0;
}

// Decode UTF-8 bytes at position to a Unicode code point
uint32_t utf8_decode_char(const char* str, int* byte_pos) {
    if (!str || !byte_pos || str[*byte_pos] == '\0') return 0;
    
    utf8proc_int32_t codepoint;
    const utf8proc_uint8_t* ustr = (const utf8proc_uint8_t*)str;
    utf8proc_ssize_t bytes = utf8proc_iterate(ustr + *byte_pos, -1, &codepoint);
    
    if (bytes <= 0) return 0;
    
    *byte_pos += bytes;
    return (uint32_t)codepoint;
}

/**
 * Count UTF-16 code units in a UTF-8 string
 * This matches JavaScript string.length behavior:
 * - BMP characters (U+0000-U+FFFF): 1 code unit
 * - Non-BMP characters (U+10000-U+10FFFF): 2 code units (surrogate pair)
 */
int utf8_to_utf16_length(const char* str) {
    if (!str) return 0;
    
    int utf16_len = 0;
    int i = 0;
    const utf8proc_uint8_t* ustr = (const utf8proc_uint8_t*)str;
    
    while (str[i] != '\0') {
        utf8proc_int32_t codepoint;
        utf8proc_ssize_t bytes = utf8proc_iterate(ustr + i, -1, &codepoint);
        if (bytes <= 0) break;
        
        i += bytes;
        
        // Count UTF-16 code units for this codepoint
        if (codepoint <= 0xFFFF) {
            utf16_len += 1;  // BMP: single code unit
        } else {
            utf16_len += 2;  // Non-BMP: surrogate pair
        }
    }
    
    return utf16_len;
}

/**
 * Convert UTF-8 string to UTF-16 code units array
 * Returns malloc'd array that must be freed by caller
 */
uint16_t* utf8_to_utf16(const char* str, int* out_length) {
    if (!str || !out_length) return NULL;
    
    // First pass: count UTF-16 code units
    int utf16_len = utf8_to_utf16_length(str);
    *out_length = utf16_len;
    
    if (utf16_len == 0) return NULL;
    
    // Allocate array
    uint16_t* utf16 = (uint16_t*)malloc(utf16_len * sizeof(uint16_t));
    if (!utf16) {
        *out_length = 0;
        return NULL;
    }
    
    // Second pass: convert to UTF-16
    int i = 0;
    int utf16_pos = 0;
    const utf8proc_uint8_t* ustr = (const utf8proc_uint8_t*)str;
    
    while (str[i] != '\0' && utf16_pos < utf16_len) {
        utf8proc_int32_t codepoint;
        utf8proc_ssize_t bytes = utf8proc_iterate(ustr + i, -1, &codepoint);
        if (bytes <= 0) break;
        
        i += bytes;
        
        // Encode as UTF-16
        if (codepoint <= 0xFFFF) {
            // BMP: single code unit
            utf16[utf16_pos++] = (uint16_t)codepoint;
        } else {
            // Non-BMP: surrogate pair
            // Formula: codepoint = 0x10000 + (H - 0xD800) * 0x400 + (L - 0xDC00)
            // Where H is high surrogate, L is low surrogate
            uint32_t offset = codepoint - 0x10000;
            utf16[utf16_pos++] = (uint16_t)(0xD800 + (offset >> 10));
            utf16[utf16_pos++] = (uint16_t)(0xDC00 + (offset & 0x3FF));
        }
    }
    
    return utf16;
}

/**
 * Convert UTF-16 code unit position to UTF-8 byte position
 * This is critical for column mapping between JS (UTF-16) and C (UTF-8)
 */
int utf16_pos_to_utf8_byte(const char* str, int utf16_pos) {
    if (!str || utf16_pos < 0) return 0;
    
    int utf8_byte = 0;
    int current_utf16_pos = 0;
    const utf8proc_uint8_t* ustr = (const utf8proc_uint8_t*)str;
    
    while (str[utf8_byte] != '\0' && current_utf16_pos < utf16_pos) {
        utf8proc_int32_t codepoint;
        utf8proc_ssize_t bytes = utf8proc_iterate(ustr + utf8_byte, -1, &codepoint);
        if (bytes <= 0) break;
        
        utf8_byte += bytes;
        
        // Count UTF-16 code units for this character
        if (codepoint <= 0xFFFF) {
            current_utf16_pos += 1;
        } else {
            current_utf16_pos += 2;
        }
    }
    
    return utf8_byte;
}
