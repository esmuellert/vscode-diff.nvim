#ifndef UTF8_UTILS_H
#define UTF8_UTILS_H

// Get the number of bytes in a UTF-8 character starting at the given byte
int utf8_char_bytes(const char* str, int byte_pos);

// Convert byte position to UTF-8 character position (column)
int utf8_byte_to_column(const char* str, int byte_pos);

// Convert UTF-8 character position (column) to byte position
int utf8_column_to_byte(const char* str, int column);

// Count UTF-8 characters (columns) in a string
int utf8_strlen(const char* str);

// Check if byte position is at a UTF-8 character boundary
int utf8_is_char_boundary(const char* str, int byte_pos);

#endif // UTF8_UTILS_H
