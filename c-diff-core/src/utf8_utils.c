#include "utf8_utils.h"
#include <string.h>
#include <stdint.h>

// Get the number of bytes in a UTF-8 character starting at the given byte
int utf8_char_bytes(const char* str, int byte_pos) {
    if (!str) return 0;
    
    unsigned char c = (unsigned char)str[byte_pos];
    
    // Single-byte character (ASCII)
    if ((c & 0x80) == 0) return 1;
    
    // Multi-byte character
    if ((c & 0xE0) == 0xC0) return 2;  // 110xxxxx
    if ((c & 0xF0) == 0xE0) return 3;  // 1110xxxx
    if ((c & 0xF8) == 0xF0) return 4;  // 11110xxx
    
    // Invalid UTF-8 start byte, treat as 1 byte
    return 1;
}

// Convert byte position to UTF-8 character position (column)
int utf8_byte_to_column(const char* str, int byte_pos) {
    if (!str || byte_pos < 0) return 0;
    
    int column = 0;
    int i = 0;
    
    while (i < byte_pos && str[i] != '\0') {
        int char_bytes = utf8_char_bytes(str, i);
        i += char_bytes;
        column++;
    }
    
    return column;
}

// Convert UTF-8 character position (column) to byte position
int utf8_column_to_byte(const char* str, int column) {
    if (!str || column < 0) return 0;
    
    int byte_pos = 0;
    int col = 0;
    
    while (col < column && str[byte_pos] != '\0') {
        int char_bytes = utf8_char_bytes(str, byte_pos);
        byte_pos += char_bytes;
        col++;
    }
    
    return byte_pos;
}

// Convert character position to byte offset in UTF-8 string (alias for compatibility)
int utf8_char_to_byte_offset(const char* str, int char_pos) {
    if (!str || char_pos <= 0) return 0;
    
    int char_count = 0;
    const unsigned char* p = (const unsigned char*)str;
    const unsigned char* start = p;
    
    while (*p && char_count < char_pos) {
        if (*p < 0x80) {
            p++;
        } else if ((*p & 0xE0) == 0xC0) {
            if (p[1]) p += 2; else p++;
        } else if ((*p & 0xF0) == 0xE0) {
            if (p[1] && p[2]) p += 3; else p++;
        } else if ((*p & 0xF8) == 0xF0) {
            if (p[1] && p[2] && p[3]) p += 4; else p++;
        } else {
            p++;
        }
        char_count++;
    }
    
    return (int)(p - start);
}

// Convert byte offset to character position in UTF-8 string (alias for compatibility)
int utf8_byte_to_char_offset(const char* str, int byte_offset) {
    if (!str || byte_offset <= 0) return 0;
    
    int char_count = 0;
    const unsigned char* p = (const unsigned char*)str;
    const unsigned char* end = p + byte_offset;
    
    while (*p && p < end) {
        if (*p < 0x80) {
            p++;
        } else if ((*p & 0xE0) == 0xC0) {
            p += 2;
        } else if ((*p & 0xF0) == 0xE0) {
            p += 3;
        } else if ((*p & 0xF8) == 0xF0) {
            p += 4;
        } else {
            p++;
        }
        char_count++;
    }
    
    return char_count;
}

// Count UTF-8 characters (columns) in a string
int utf8_strlen(const char* str) {
    if (!str) return 0;
    
    int length = 0;
    int i = 0;
    
    while (str[i] != '\0') {
        int char_bytes = utf8_char_bytes(str, i);
        i += char_bytes;
        length++;
    }
    
    return length;
}

// Check if byte position is at a UTF-8 character boundary
int utf8_is_char_boundary(const char* str, int byte_pos) {
    if (!str || byte_pos < 0) return 1;
    
    unsigned char c = (unsigned char)str[byte_pos];
    
    // ASCII or start of multi-byte sequence
    if ((c & 0x80) == 0 || (c & 0xC0) == 0xC0) return 1;
    
    // Continuation byte (10xxxxxx)
    return 0;
}

// Decode UTF-8 bytes at position to a Unicode code point
// This matches JavaScript's charCodeAt() which returns UTF-16 code units
// For BMP characters (U+0000 to U+FFFF), code point == UTF-16 code unit
// For characters beyond BMP, we return the code point (VSCode handles as surrogate pairs in JS)
uint32_t utf8_decode_char(const char* str, int* byte_pos) {
    if (!str || !byte_pos || str[*byte_pos] == '\0') {
        return 0;
    }
    
    const unsigned char* p = (const unsigned char*)&str[*byte_pos];
    unsigned char c = *p;
    
    // 1-byte character (ASCII): 0xxxxxxx
    if ((c & 0x80) == 0) {
        (*byte_pos)++;
        return c;
    }
    
    // 2-byte character: 110xxxxx 10xxxxxx
    if ((c & 0xE0) == 0xC0) {
        if (!p[1] || (p[1] & 0xC0) != 0x80) {
            // Invalid UTF-8, return replacement character
            (*byte_pos)++;
            return 0xFFFD;
        }
        uint32_t codepoint = ((c & 0x1F) << 6) | (p[1] & 0x3F);
        (*byte_pos) += 2;
        return codepoint;
    }
    
    // 3-byte character: 1110xxxx 10xxxxxx 10xxxxxx
    if ((c & 0xF0) == 0xE0) {
        if (!p[1] || !p[2] || (p[1] & 0xC0) != 0x80 || (p[2] & 0xC0) != 0x80) {
            (*byte_pos)++;
            return 0xFFFD;
        }
        uint32_t codepoint = ((c & 0x0F) << 12) | ((p[1] & 0x3F) << 6) | (p[2] & 0x3F);
        (*byte_pos) += 3;
        return codepoint;
    }
    
    // 4-byte character: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
    if ((c & 0xF8) == 0xF0) {
        if (!p[1] || !p[2] || !p[3] || 
            (p[1] & 0xC0) != 0x80 || (p[2] & 0xC0) != 0x80 || (p[3] & 0xC0) != 0x80) {
            (*byte_pos)++;
            return 0xFFFD;
        }
        uint32_t codepoint = ((c & 0x07) << 18) | ((p[1] & 0x3F) << 12) | 
                             ((p[2] & 0x3F) << 6) | (p[3] & 0x3F);
        (*byte_pos) += 4;
        return codepoint;
    }
    
    // Invalid UTF-8 start byte
    (*byte_pos)++;
    return 0xFFFD;  // Replacement character
}
