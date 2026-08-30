#include "line_matcher.h"
#include "utils.h"
#include <stdlib.h>
#include <string.h>

typedef struct {
  const unsigned char *text;
  int length;
  int frequency[256];
  // Each distinct byte is recorded once so overlap can scan only the sparser line.
  unsigned char frequency_bytes[256];
  int frequency_count;
} LineMetadata;

typedef struct {
  int original_start;
  int original_end;
  int modified_start;
  int modified_end;
} MatchRange;

typedef struct {
  int original_index;
  int modified_index;
  double score;
  bool found;
} BestPair;

typedef struct {
  MatchRange *items;
  int count;
  int capacity;
} RangeStack;

static bool deadline_expired(const Timeout *timeout) {
  return timeout->timeout_ms > 0 &&
         get_current_time_ms() - timeout->start_time_ms >= timeout->timeout_ms;
}

static SequenceDiffArray *create_matches(void) {
  SequenceDiffArray *result = (SequenceDiffArray *)malloc(sizeof(SequenceDiffArray));
  if (!result) {
    return NULL;
  }
  result->diffs = NULL;
  result->count = 0;
  result->capacity = 0;
  return result;
}

static bool append_match(SequenceDiffArray *matches, int original_index,
                         int modified_index) {
  if (matches->count >= matches->capacity) {
    int capacity = matches->capacity == 0 ? 8 : matches->capacity * 2;
    SequenceDiff *items = (SequenceDiff *)realloc(
        matches->diffs, (size_t)capacity * sizeof(SequenceDiff));
    if (!items) {
      return false;
    }
    matches->diffs = items;
    matches->capacity = capacity;
  }
  matches->diffs[matches->count++] = (SequenceDiff){
      .seq1_start = original_index,
      .seq1_end = original_index + 1,
      .seq2_start = modified_index,
      .seq2_end = modified_index + 1,
  };
  return true;
}

static LineMetadata *create_metadata(const char **lines, int start, int end) {
  int count = end - start;
  LineMetadata *metadata =
      count > 0 ? (LineMetadata *)calloc((size_t)count, sizeof(LineMetadata)) : NULL;
  if (count > 0 && !metadata) {
    return NULL;
  }
  for (int index = 0; index < count; index++) {
    const unsigned char *text = (const unsigned char *)lines[start + index];
    metadata[index].text = text;
    metadata[index].length = (int)strlen((const char *)text);
    for (int offset = 0; offset < metadata[index].length; offset++) {
      unsigned char byte = text[offset];
      if (metadata[index].frequency[byte]++ == 0) {
        metadata[index].frequency_bytes[metadata[index].frequency_count++] = byte;
      }
    }
  }
  return metadata;
}

static int frequency_overlap(const LineMetadata *left,
                             const LineMetadata *right) {
  const LineMetadata *sparse = left->frequency_count < right->frequency_count
                                   ? left
                                   : right;
  int overlap = 0;
  for (int index = 0; index < sparse->frequency_count; index++) {
    unsigned char byte = sparse->frequency_bytes[index];
    overlap += left->frequency[byte] < right->frequency[byte]
                   ? left->frequency[byte]
                   : right->frequency[byte];
  }
  return overlap;
}

static int lcs_length(const LineMetadata *left, const LineMetadata *right,
                      int *row, double minimum_score, const Timeout *timeout,
                      bool *hit_timeout) {
  int prefix = 0;
  int shorter_length = left->length < right->length ? left->length : right->length;
  while (prefix < shorter_length && left->text[prefix] == right->text[prefix]) {
    prefix++;
  }
  int suffix = 0;
  while (suffix < shorter_length - prefix &&
         left->text[left->length - suffix - 1] ==
             right->text[right->length - suffix - 1]) {
    suffix++;
  }

  const unsigned char *left_middle = left->text + prefix;
  const unsigned char *right_middle = right->text + prefix;
  int left_length = left->length - prefix - suffix;
  int right_length = right->length - prefix - suffix;
  const unsigned char *rows = left_middle;
  const unsigned char *columns = right_middle;
  int row_count = left_length;
  int column_count = right_length;
  if (column_count > row_count) {
    rows = right_middle;
    columns = left_middle;
    row_count = right_length;
    column_count = left_length;
  }

  memset(row, 0, (size_t)(column_count + 1) * sizeof(int));
  int common = prefix + suffix;
  int total_length = left->length + right->length;
  for (int row_index = 0; row_index < row_count; row_index++) {
    int diagonal = 0;
    for (int column = 1; column <= column_count; column++) {
      int previous = row[column];
      if (rows[row_index] == columns[column - 1]) {
        row[column] = diagonal + 1;
      } else if (row[column - 1] > row[column]) {
        row[column] = row[column - 1];
      }
      diagonal = previous;
    }

    int remaining = row_count - row_index - 1;
    int upper_lcs = common + row[column_count] + remaining;
    int maximum_lcs = common + column_count;
    if (upper_lcs > maximum_lcs) {
      upper_lcs = maximum_lcs;
    }
    if (2.0 * upper_lcs / total_length < minimum_score) {
      return -1;
    }
    if ((row_index & 31) == 31 && deadline_expired(timeout)) {
      *hit_timeout = true;
      return -1;
    }
  }
  return common + row[column_count];
}

static BestPair find_best_pair(const MatchRange *range,
                               const LineMetadata *original,
                               const LineMetadata *modified,
                               int original_base, int modified_base,
                               double threshold, int *row,
                               const Timeout *timeout, bool *hit_timeout) {
  BestPair best = {0};
  int candidate_count = 0;
  for (int original_index = range->original_start;
       original_index < range->original_end; original_index++) {
    int expected_modified =
        range->modified_start + original_index - range->original_start;
    int modified_start = expected_modified - 10;
    int modified_end = expected_modified + 10;
    if (modified_start < range->modified_start) {
      modified_start = range->modified_start;
    }
    if (modified_end >= range->modified_end) {
      modified_end = range->modified_end - 1;
    }

    for (int modified_index = modified_start; modified_index <= modified_end;
         modified_index++) {
      if ((candidate_count++ & 31) == 31 && deadline_expired(timeout)) {
        *hit_timeout = true;
        return best;
      }
      const LineMetadata *left = &original[original_index - original_base];
      const LineMetadata *right = &modified[modified_index - modified_base];
      double score;
      if (left->length == right->length &&
          memcmp(left->text, right->text, (size_t)left->length) == 0) {
        score = 1.0;
      } else if (left->length == 0 || right->length == 0) {
        score = 0.0;
      } else {
        int total_length = left->length + right->length;
        int upper_lcs = left->length < right->length ? left->length : right->length;
        int overlap = frequency_overlap(left, right);
        if (overlap < upper_lcs) {
          upper_lcs = overlap;
        }
        double upper_score = 2.0 * upper_lcs / total_length;
        double minimum_score = best.found && best.score > threshold ? best.score : threshold;
        if (upper_score < threshold || (best.found && upper_score <= best.score)) {
          continue;
        }
        int lcs = lcs_length(left, right, row, minimum_score, timeout, hit_timeout);
        if (*hit_timeout) {
          return best;
        }
        if (lcs < 0) {
          continue;
        }
        score = 2.0 * lcs / total_length;
      }
      if (score >= threshold && (!best.found || score > best.score)) {
        best = (BestPair){
            .original_index = original_index,
            .modified_index = modified_index,
            .score = score,
            .found = true,
        };
      }
    }
  }
  return best;
}

static bool push_range(RangeStack *stack, MatchRange range) {
  if (range.original_start >= range.original_end ||
      range.modified_start >= range.modified_end) {
    return true;
  }
  if (stack->count >= stack->capacity) {
    int capacity = stack->capacity == 0 ? 16 : stack->capacity * 2;
    MatchRange *items = (MatchRange *)realloc(
        stack->items, (size_t)capacity * sizeof(MatchRange));
    if (!items) {
      return false;
    }
    stack->items = items;
    stack->capacity = capacity;
  }
  stack->items[stack->count++] = range;
  return true;
}

static int compare_matches(const void *left_value, const void *right_value) {
  const SequenceDiff *left = (const SequenceDiff *)left_value;
  const SequenceDiff *right = (const SequenceDiff *)right_value;
  return left->seq1_start - right->seq1_start;
}

static bool collect_similarity_matches(SequenceDiffArray *matches,
                                       const SequenceDiff *block,
                                       const char **original_lines,
                                       const char **modified_lines,
                                       double threshold, const Timeout *timeout,
                                       bool *hit_timeout) {
  LineMetadata *original =
      create_metadata(original_lines, block->seq1_start, block->seq1_end);
  LineMetadata *modified =
      create_metadata(modified_lines, block->seq2_start, block->seq2_end);
  if ((block->seq1_end > block->seq1_start && !original) ||
      (block->seq2_end > block->seq2_start && !modified)) {
    free(original);
    free(modified);
    return false;
  }

  int maximum_length = 0;
  for (int index = block->seq1_start; index < block->seq1_end; index++) {
    int length = original[index - block->seq1_start].length;
    if (length > maximum_length) {
      maximum_length = length;
    }
  }
  for (int index = block->seq2_start; index < block->seq2_end; index++) {
    int length = modified[index - block->seq2_start].length;
    if (length > maximum_length) {
      maximum_length = length;
    }
  }
  int *row = (int *)malloc((size_t)(maximum_length + 1) * sizeof(int));
  RangeStack stack = {0};
  bool success = row && push_range(&stack, (MatchRange){
                                             .original_start = block->seq1_start,
                                             .original_end = block->seq1_end,
                                             .modified_start = block->seq2_start,
                                             .modified_end = block->seq2_end,
                                         });

  while (success && stack.count > 0 && !*hit_timeout) {
    MatchRange range = stack.items[--stack.count];
    BestPair best = find_best_pair(&range, original, modified, block->seq1_start,
                                   block->seq2_start, threshold, row, timeout,
                                   hit_timeout);
    if (!best.found || *hit_timeout) {
      continue;
    }
    success = append_match(matches, best.original_index, best.modified_index) &&
              push_range(&stack,
                         (MatchRange){
                             .original_start = best.original_index + 1,
                             .original_end = range.original_end,
                             .modified_start = best.modified_index + 1,
                             .modified_end = range.modified_end,
                         }) &&
              push_range(&stack,
                         (MatchRange){
                             .original_start = range.original_start,
                             .original_end = best.original_index,
                             .modified_start = range.modified_start,
                             .modified_end = best.modified_index,
                         });
  }

  if (matches->count > 1) {
    qsort(matches->diffs, (size_t)matches->count, sizeof(SequenceDiff),
          compare_matches);
  }
  free(stack.items);
  free(row);
  free(original);
  free(modified);
  return success;
}

SequenceDiffArray *compute_line_matches(const SequenceDiff *block,
                                        const char **original_lines,
                                        const char **modified_lines,
                                        LineMatcherStrategy strategy,
                                        double threshold,
                                        const Timeout *timeout,
                                        bool *hit_timeout) {
  *hit_timeout = false;
  SequenceDiffArray *matches = create_matches();
  if (!matches) {
    return NULL;
  }

  int original_count = block->seq1_end - block->seq1_start;
  int modified_count = block->seq2_end - block->seq2_start;
  bool success = true;
  if (strategy == LINE_MATCHER_VSCODE) {
    if (original_count > 0 || modified_count > 0) {
      success = append_match(matches, block->seq1_start, block->seq2_start);
      if (success) {
        matches->diffs[0] = *block;
      }
    }
  } else if (strategy == LINE_MATCHER_EQUAL_LINE_COUNT) {
    if (original_count == modified_count) {
      for (int index = 0; index < original_count && success; index++) {
        success = append_match(matches, block->seq1_start + index,
                               block->seq2_start + index);
      }
    }
  } else {
    success = collect_similarity_matches(matches, block, original_lines,
                                         modified_lines, threshold, timeout,
                                         hit_timeout);
  }

  if (!success) {
    sequence_diff_array_free(matches);
    return NULL;
  }
  return matches;
}
