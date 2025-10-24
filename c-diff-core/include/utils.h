#ifndef UTILS_H
#define UTILS_H

#include "types.h"

// Memory management helpers
void sequence_diff_array_free(SequenceDiffArray* arr);
void range_mapping_array_free(RangeMappingArray* arr);
void detailed_line_range_mapping_array_free(DetailedLineRangeMappingArray* arr);

#endif // UTILS_H
