#ifndef UTILS_H
#define UTILS_H

#include "types.h"
#include <stdbool.h>
#include <stdint.h>

// Memory management helpers
void sequence_diff_array_free(SequenceDiffArray* arr);
void range_mapping_array_free(RangeMappingArray* arr);
void detailed_line_range_mapping_array_free(DetailedLineRangeMappingArray* arr);

// Unicode whitespace detection (matches JavaScript /\s/ regex)
bool is_unicode_whitespace(uint32_t ch);

// String utilities
char* trim_string(const char* str);

// Time utilities
int64_t get_current_time_ms(void);

#endif // UTILS_H
