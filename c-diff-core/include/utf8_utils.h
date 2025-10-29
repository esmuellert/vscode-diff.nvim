#ifndef UTF8_UTILS_H
#define UTF8_UTILS_H

#include <stdint.h>

/**
 * Get the number of bytes in a UTF-8 character starting at the given byte
 */
int utf8_char_bytes(const char* str, int byte_pos);

/**
 * Convert byte position to UTF-8 character position (column)
 */
int utf8_byte_to_column(const char* str, int byte_pos);

/**
 * Convert UTF-8 character position (column) to byte position
 */
int utf8_column_to_byte(const char* str, int column);

/**
 * Count the number of UTF-8 characters in a string
 * @param str The UTF-8 encoded string
 * @return Number of characters (not bytes)
 */
int utf8_strlen(const char* str);

/**
 * Convert character position to byte offset in UTF-8 string
 * @param str The UTF-8 string
 * @param char_pos Character position (0-based)
 * @return Byte offset (0-based)
 */
int utf8_char_to_byte_offset(const char* str, int char_pos);

/**
 * Convert byte offset to character position in UTF-8 string
 * @param str The UTF-8 string
 * @param byte_offset Byte offset (0-based)
 * @return Character position (0-based)
 */
int utf8_byte_to_char_offset(const char* str, int byte_offset);

/**
 * Check if byte position is at a UTF-8 character boundary
 */
int utf8_is_char_boundary(const char* str, int byte_pos);

/**
 * Decode UTF-8 bytes at position to a Unicode code point (for UTF-16 code unit)
 * Returns the code point and advances *byte_pos by the number of bytes consumed
 * Returns 0 and doesn't advance on invalid UTF-8
 */
uint32_t utf8_decode_char(const char* str, int* byte_pos);

/**
 * Count UTF-16 code units in a UTF-8 string
 * (matches JavaScript string.length behavior)
 * - BMP characters (U+0000-U+FFFF): 1 code unit each
 * - Non-BMP characters (U+10000-U+10FFFF): 2 code units each (surrogate pair)
 */
int utf8_to_utf16_length(const char* str);

/**
 * Convert UTF-8 string to UTF-16 code units array
 * Returns malloc'd array of uint16_t that must be freed by caller
 * Sets *out_length to the number of UTF-16 code units
 */
uint16_t* utf8_to_utf16(const char* str, int* out_length);

/**
 * Convert UTF-16 code unit position to UTF-8 byte position in string
 * Useful for reporting positions in original UTF-8 text
 */
int utf16_pos_to_utf8_byte(const char* str, int utf16_pos);

#endif // UTF8_UTILS_H
