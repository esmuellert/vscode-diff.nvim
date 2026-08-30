#ifndef LINE_MATCHER_H
#define LINE_MATCHER_H

#include "types.h"

SequenceDiffArray *compute_line_matches(const SequenceDiff *block,
                                        const char **original_lines,
                                        const char **modified_lines,
                                        LineMatcherStrategy strategy,
                                        double threshold,
                                        const Timeout *timeout,
                                        bool *hit_timeout);

#endif
