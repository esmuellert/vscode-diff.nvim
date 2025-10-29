#include "utf8_utils.h"
#include <string.h>

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
