// ============================================================================
// VSCode DefaultLinesDiffComputer - Main Orchestrator
// ============================================================================
// 
// C port of VSCode's DefaultLinesDiffComputer class with 100% parity.
// 
// VSCode Reference:
//   src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.ts
//
// VSCode Parity: 100% (excluding computeMoves)
//
// ============================================================================

#include "default_lines_diff_computer.h"
#include "char_level.h"
#include "compute_moved_lines.h"
#include "line_level.h"
#include "line_matcher.h"
#include "string_hash_map.h"
#include "utils.h"
#include <limits.h>
#include <stdlib.h>
#include <string.h>

static bool arrays_equal(const char **left, int left_count, const char **right,
                         int right_count) {
  if (left_count != right_count) {
    return false;
  }
  for (int index = 0; index < left_count; index++) {
    if (strcmp(left[index], right[index]) != 0) {
      return false;
    }
  }
  return true;
}

static LinesDiff *create_empty_lines_diff(void) {
  LinesDiff *result = (LinesDiff *)calloc(1, sizeof(LinesDiff));
  return result;
}

static bool timeout_expired(const Timeout *timeout) {
  return timeout->timeout_ms > 0 &&
         get_current_time_ms() - timeout->start_time_ms >= timeout->timeout_ms;
}

static int remaining_timeout_ms(const Timeout *timeout) {
  if (timeout->timeout_ms <= 0) {
    return 0;
  }
  int64_t remaining = timeout->timeout_ms -
                      (get_current_time_ms() - timeout->start_time_ms);
  if (remaining <= 0) {
    return -1;
  }
  return remaining > INT_MAX ? INT_MAX : (int)remaining;
}

static bool grow_changes(DetailedLineRangeMappingArray *changes) {
  if (changes->count < changes->capacity) {
    return true;
  }
  int capacity = changes->capacity == 0 ? 8 : changes->capacity * 2;
  DetailedLineRangeMapping *mappings =
      (DetailedLineRangeMapping *)realloc(
          changes->mappings,
          (size_t)capacity * sizeof(DetailedLineRangeMapping));
  if (!mappings) {
    return false;
  }
  changes->mappings = mappings;
  changes->capacity = capacity;
  return true;
}

static bool append_change(DetailedLineRangeMappingArray *changes,
                          const SequenceDiff *block, int *change_index) {
  int original_start = block->seq1_start + 1;
  int original_end = block->seq1_end + 1;
  int modified_start = block->seq2_start + 1;
  int modified_end = block->seq2_end + 1;
  if (changes->count > 0) {
    DetailedLineRangeMapping *previous = &changes->mappings[changes->count - 1];
    if (previous->original.end_line >= original_start &&
        previous->modified.end_line >= modified_start) {
      if (original_end > previous->original.end_line) {
        previous->original.end_line = original_end;
      }
      if (modified_end > previous->modified.end_line) {
        previous->modified.end_line = modified_end;
      }
      *change_index = changes->count - 1;
      return true;
    }
  }

  if (!grow_changes(changes)) {
    return false;
  }
  DetailedLineRangeMapping *change = &changes->mappings[changes->count];
  memset(change, 0, sizeof(*change));
  change->original =
      (LineRange){.start_line = original_start, .end_line = original_end};
  change->modified =
      (LineRange){.start_line = modified_start, .end_line = modified_end};
  *change_index = changes->count++;
  return true;
}

static bool grow_line_mappings(DetailedLineRangeMapping *change) {
  if (change->line_mapping_count < change->line_mapping_capacity) {
    return true;
  }
  int capacity =
      change->line_mapping_capacity == 0 ? 4 : change->line_mapping_capacity * 2;
  LineMapping *mappings = (LineMapping *)realloc(
      change->line_mappings, (size_t)capacity * sizeof(LineMapping));
  if (!mappings) {
    return false;
  }
  change->line_mappings = mappings;
  change->line_mapping_capacity = capacity;
  return true;
}

static bool append_inner_changes(DetailedLineRangeMapping *change,
                                 const RangeMappingArray *refined) {
  if (refined->count == 0) {
    return true;
  }
  int count = change->inner_change_count + refined->count;
  RangeMapping *inner_changes = (RangeMapping *)realloc(
      change->inner_changes, (size_t)count * sizeof(RangeMapping));
  if (!inner_changes) {
    return false;
  }
  change->inner_changes = inner_changes;
  memcpy(change->inner_changes + change->inner_change_count, refined->mappings,
         (size_t)refined->count * sizeof(RangeMapping));
  change->inner_change_count = count;
  return true;
}

static bool append_line_mapping(DetailedLineRangeMapping *change,
                                const SequenceDiff *match,
                                const char **original_lines,
                                int original_count,
                                const char **modified_lines,
                                int modified_count,
                                bool consider_whitespace_changes,
                                const DiffOptions *options,
                                const Timeout *timeout, bool *hit_timeout) {
  if (!grow_line_mappings(change)) {
    return false;
  }
  LineMapping *line_mapping =
      &change->line_mappings[change->line_mapping_count];
  memset(line_mapping, 0, sizeof(*line_mapping));
  line_mapping->original = (LineRange){
      .start_line = match->seq1_start + 1,
      .end_line = match->seq1_end + 1,
  };
  line_mapping->modified = (LineRange){
      .start_line = match->seq2_start + 1,
      .end_line = match->seq2_end + 1,
  };
  change->line_mapping_count++;

  bool empty_buffer =
      (original_count == 1 && original_lines[0][0] == '\0') ||
      (modified_count == 1 && modified_lines[0][0] == '\0');
  if (empty_buffer) {
    RangeMapping full_file = {
        .original = {.start_line = 1,
                     .start_col = 1,
                     .end_line = original_count,
                     .end_col = original_count > 0
                                    ? (int)strlen(original_lines[original_count - 1]) + 1
                                    : 1},
        .modified = {.start_line = 1,
                     .start_col = 1,
                     .end_line = modified_count,
                     .end_col = modified_count > 0
                                    ? (int)strlen(modified_lines[modified_count - 1]) + 1
                                    : 1},
    };
    RangeMappingArray refined = {
        .mappings = &full_file,
        .count = 1,
        .capacity = 1,
    };
    return append_inner_changes(change, &refined);
  }

  int remaining = remaining_timeout_ms(timeout);
  if (remaining < 0) {
    *hit_timeout = true;
    return true;
  }
  CharLevelOptions char_options = {
      .consider_whitespace_changes = consider_whitespace_changes,
      .extend_to_subwords = options->extend_to_subwords,
      .timeout_ms = remaining,
  };
  bool local_timeout = false;
  RangeMappingArray *refined = refine_diff_char_level(
      match, original_lines, original_count, modified_lines, modified_count,
      &char_options, &local_timeout);
  if (!refined) {
    return false;
  }
  bool success = append_inner_changes(change, refined);
  range_mapping_array_free(refined);
  if (local_timeout) {
    *hit_timeout = true;
  }
  return success;
}

static bool process_block(DetailedLineRangeMappingArray *changes,
                          const SequenceDiff *block,
                          const char **original_lines, int original_count,
                          const char **modified_lines, int modified_count,
                          bool consider_whitespace_changes,
                          const DiffOptions *options, const Timeout *timeout,
                          bool *hit_timeout) {
  int change_index;
  if (!append_change(changes, block, &change_index)) {
    return false;
  }
  if (*hit_timeout || timeout_expired(timeout)) {
    *hit_timeout = true;
    return true;
  }

  bool matcher_timeout = false;
  SequenceDiffArray *matches = compute_line_matches(
      block, original_lines, modified_lines, options->line_matcher_strategy,
      options->line_matcher_threshold, timeout, &matcher_timeout);
  if (!matches) {
    return false;
  }
  if (matcher_timeout) {
    *hit_timeout = true;
  }
  for (int index = 0; index < matches->count; index++) {
    if (!append_line_mapping(&changes->mappings[change_index],
                             &matches->diffs[index], original_lines,
                             original_count, modified_lines, modified_count,
                             consider_whitespace_changes, options, timeout,
                             hit_timeout)) {
      sequence_diff_array_free(matches);
      return false;
    }
    if (*hit_timeout) {
      break;
    }
  }
  sequence_diff_array_free(matches);
  return true;
}

static bool process_whitespace_changes(
    DetailedLineRangeMappingArray *changes, int count, int original_start,
    int modified_start, const char **original_lines, int original_count,
    const char **modified_lines, int modified_count,
    bool consider_whitespace_changes, const DiffOptions *options,
    const Timeout *timeout, bool *hit_timeout) {
  if (!consider_whitespace_changes) {
    return true;
  }
  for (int offset = 0; offset < count; offset++) {
    int original_index = original_start + offset;
    int modified_index = modified_start + offset;
    if (strcmp(original_lines[original_index], modified_lines[modified_index]) ==
        0) {
      continue;
    }
    SequenceDiff block = {
        .seq1_start = original_index,
        .seq1_end = original_index + 1,
        .seq2_start = modified_index,
        .seq2_end = modified_index + 1,
    };
    int change_index;
    if (!append_change(changes, &block, &change_index)) {
      return false;
    }
    if (*hit_timeout || timeout_expired(timeout)) {
      *hit_timeout = true;
    } else if (!append_line_mapping(
                   &changes->mappings[change_index], &block, original_lines,
                   original_count, modified_lines, modified_count,
                   consider_whitespace_changes, options, timeout,
                   hit_timeout)) {
      return false;
    }
  }
  return true;
}

static void free_change_contents(DetailedLineRangeMapping *change) {
  free(change->inner_changes);
  free(change->line_mappings);
}

static void free_changes(DetailedLineRangeMappingArray *changes) {
  if (!changes) {
    return;
  }
  for (int index = 0; index < changes->count; index++) {
    free_change_contents(&changes->mappings[index]);
  }
  free(changes->mappings);
  changes->mappings = NULL;
  changes->count = 0;
  changes->capacity = 0;
}

static bool compute_moves(const DetailedLineRangeMappingArray *changes,
                          const char **original_lines, int original_count,
                          const char **modified_lines, int modified_count,
                          const Timeout *timeout, MovedTextArray *moves,
                          bool *hit_timeout) {
  int remaining = remaining_timeout_ms(timeout);
  if (remaining < 0) {
    *hit_timeout = true;
    return true;
  }
  StringHashMap *hash_map = string_hash_map_create();
  uint32_t *original_hashes = original_count > 0
                                  ? (uint32_t *)malloc((size_t)original_count *
                                                       sizeof(uint32_t))
                                  : NULL;
  uint32_t *modified_hashes = modified_count > 0
                                  ? (uint32_t *)malloc((size_t)modified_count *
                                                       sizeof(uint32_t))
                                  : NULL;
  if (!hash_map || (original_count > 0 && !original_hashes) ||
      (modified_count > 0 && !modified_hashes)) {
    free(original_hashes);
    free(modified_hashes);
    string_hash_map_destroy(hash_map);
    return false;
  }

  for (int index = 0; index < original_count; index++) {
    char *trimmed = trim_string(original_lines[index]);
    if (!trimmed) {
      free(original_hashes);
      free(modified_hashes);
      string_hash_map_destroy(hash_map);
      return false;
    }
    original_hashes[index] = string_hash_map_get_or_create(hash_map, trimmed);
    free(trimmed);
  }
  for (int index = 0; index < modified_count; index++) {
    char *trimmed = trim_string(modified_lines[index]);
    if (!trimmed) {
      free(original_hashes);
      free(modified_hashes);
      string_hash_map_destroy(hash_map);
      return false;
    }
    modified_hashes[index] = string_hash_map_get_or_create(hash_map, trimmed);
    free(trimmed);
  }

  compute_moved_lines(changes->mappings, changes->count, original_lines,
                      original_count, modified_lines, modified_count,
                      original_hashes, modified_hashes, remaining, moves);
  free(original_hashes);
  free(modified_hashes);
  string_hash_map_destroy(hash_map);
  if (timeout_expired(timeout)) {
    *hit_timeout = true;
  }
  return true;
}

/**
 * Compute diff between two files.
 * 
 * This is the main entry point, implementing VSCode's computeDiff() method
 * with 100% algorithmic parity.
 * 
 * @param original_lines Original file lines
 * @param original_count Number of lines in original
 * @param modified_lines Modified file lines
 * @param modified_count Number of lines in modified
 * @param options Diff computation options
 * @return LinesDiff structure containing changes and metadata
 * 
 * VSCode Reference: defaultLinesDiffComputer.ts computeDiff() lines 31-174
 * VSCode Parity: 100% (excluding computeMoves)
 * 
 * Notable differences from VSCode:
 * - No computeMoves implementation (Neovim UI limitation)
 * - No assertion validation (can be added later if needed)
 */
LinesDiff *compute_diff(const char **original_lines, int original_count,
                        const char **modified_lines, int modified_count,
                        const DiffOptions *options) {
  if (arrays_equal(original_lines, original_count, modified_lines,
                   modified_count)) {
    return create_empty_lines_diff();
  }

  Timeout timeout = {
      .timeout_ms = options->max_computation_time_ms,
      .start_time_ms = get_current_time_ms(),
  };
  bool hit_timeout = false;
  int remaining = remaining_timeout_ms(&timeout);
  bool empty_buffer =
      (original_count == 1 && original_lines[0][0] == '\0') ||
      (modified_count == 1 && modified_lines[0][0] == '\0');
  SequenceDiffArray *line_alignments;
  if (empty_buffer) {
    line_alignments = (SequenceDiffArray *)malloc(sizeof(SequenceDiffArray));
    if (line_alignments) {
      line_alignments->diffs =
          (SequenceDiff *)malloc(sizeof(SequenceDiff));
      line_alignments->count = line_alignments->diffs ? 1 : 0;
      line_alignments->capacity = line_alignments->diffs ? 1 : 0;
      if (line_alignments->diffs) {
        line_alignments->diffs[0] = (SequenceDiff){
            .seq1_start = 0,
            .seq1_end = original_count,
            .seq2_start = 0,
            .seq2_end = modified_count,
        };
      }
    }
  } else {
    line_alignments = compute_line_alignments(
        original_lines, original_count, modified_lines, modified_count,
        remaining, &hit_timeout);
  }
  if (!line_alignments || (empty_buffer && !line_alignments->diffs)) {
    sequence_diff_array_free(line_alignments);
    return NULL;
  }

  DetailedLineRangeMappingArray changes = {0};
  bool consider_whitespace_changes = !options->ignore_trim_whitespace;
  int previous_original = 0;
  int previous_modified = 0;
  bool success = true;
  for (int index = 0; index < line_alignments->count && success; index++) {
    const SequenceDiff *block = &line_alignments->diffs[index];
    success = process_whitespace_changes(
                  &changes, block->seq1_start - previous_original,
                  previous_original, previous_modified, original_lines,
                  original_count, modified_lines, modified_count,
                  consider_whitespace_changes, options, &timeout,
                  &hit_timeout) &&
              process_block(&changes, block, original_lines, original_count,
                            modified_lines, modified_count,
                            consider_whitespace_changes, options, &timeout,
                            &hit_timeout);
    previous_original = block->seq1_end;
    previous_modified = block->seq2_end;
  }
  if (success) {
    int remaining_original = original_count - previous_original;
    int remaining_modified = modified_count - previous_modified;
    int remaining_equal = remaining_original < remaining_modified
                              ? remaining_original
                              : remaining_modified;
    success = process_whitespace_changes(
        &changes, remaining_equal, previous_original, previous_modified,
        original_lines, original_count, modified_lines, modified_count,
        consider_whitespace_changes, options, &timeout, &hit_timeout);
  }
  sequence_diff_array_free(line_alignments);
  if (!success) {
    free_changes(&changes);
    return NULL;
  }

  MovedTextArray moves = {0};
  if (options->compute_moves && changes.count > 0 &&
      !compute_moves(&changes, original_lines, original_count, modified_lines,
                     modified_count, &timeout, &moves, &hit_timeout)) {
    free_changes(&changes);
    return NULL;
  }

  LinesDiff *result = (LinesDiff *)malloc(sizeof(LinesDiff));
  if (!result) {
    free_changes(&changes);
    free(moves.moves);
    return NULL;
  }
  result->changes = changes;
  result->moves = moves;
  result->hit_timeout = hit_timeout;
  return result;
}

/**
 * Free LinesDiff structure.
 * 
 * @param diff LinesDiff to free (can be NULL)
 */
void free_lines_diff(LinesDiff *diff) {
  if (!diff) {
    return;
  }
  free_changes(&diff->changes);
  free(diff->moves.moves);
  free(diff);
}

/**
 * Get library version.
 * Version is embedded at build time from VERSION file.
 */
#include "version.h"
const char *get_version(void) { return VSCODE_DIFF_VERSION; }
