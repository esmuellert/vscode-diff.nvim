#ifndef MYERS_H
#define MYERS_H

#include "types.h"

// Myers Diff Algorithm - computes sequence diffs using O(ND) algorithm
// Returns array of SequenceDiff structures representing changed regions
SequenceDiffArray* myers_diff_algorithm(const char** seq_a, int len_a,
                                        const char** seq_b, int len_b);

#endif // MYERS_H
