#include "line_matcher.h"
#include "utils.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ASSERT(condition, message)                                             \
  do {                                                                         \
    if (!(condition)) {                                                        \
      fprintf(stderr, "%s\n", message);                                      \
      return false;                                                            \
    }                                                                          \
  } while (0)

typedef struct {
  const char *name;
  LineMatcherStrategy strategy;
  const char **original;
  int original_count;
  const char **modified;
  int modified_count;
  double threshold;
  int expected_count;
} MatchCase;

static SequenceDiffArray *run_case(const MatchCase *test_case,
                                   bool *hit_timeout) {
  SequenceDiff block = {
      .seq1_start = 0,
      .seq1_end = test_case->original_count,
      .seq2_start = 0,
      .seq2_end = test_case->modified_count,
  };
  Timeout timeout = {.timeout_ms = 1000,
                     .start_time_ms = get_current_time_ms()};
  return compute_line_matches(&block, test_case->original, test_case->modified,
                              test_case->strategy, test_case->threshold,
                              &timeout, hit_timeout);
}

static bool test_strategies(void) {
  const char *equal_original[] = {"old one", "old two"};
  const char *equal_modified[] = {"new one", "new two"};
  const char *unequal_modified[] = {"new one"};
  const char *similar_original[] = {"local old_name = 1", "removed"};
  const char *similar_modified[] = {"local new_name = 1", "unrelated"};
  const char *unicode_original[] = {"caf\xC3\xA9"};
  const char *unicode_modified[] = {"cafe"};
  MatchCase cases[] = {
      {"vscode complete block", LINE_MATCHER_VSCODE, equal_original, 2,
       unequal_modified, 1, 0.75, 1},
      {"equal counts", LINE_MATCHER_EQUAL_LINE_COUNT, equal_original, 2,
       equal_modified, 2, 0.75, 2},
      {"unequal counts", LINE_MATCHER_EQUAL_LINE_COUNT, equal_original, 2,
       unequal_modified, 1, 0.75, 0},
      {"similar lines", LINE_MATCHER_SIMILARITY, similar_original, 2,
       similar_modified, 2, 0.75, 1},
      {"unicode byte score", LINE_MATCHER_SIMILARITY, unicode_original, 1,
       unicode_modified, 1, 0.6, 1},
  };

  int count = (int)(sizeof(cases) / sizeof(cases[0]));
  for (int index = 0; index < count; index++) {
    bool hit_timeout = false;
    SequenceDiffArray *matches = run_case(&cases[index], &hit_timeout);
    ASSERT(matches != NULL, cases[index].name);
    ASSERT(!hit_timeout, cases[index].name);
    ASSERT(matches->count == cases[index].expected_count, cases[index].name);
    sequence_diff_array_free(matches);
  }
  return true;
}

static bool test_threshold_boundary(void) {
  const char *original[] = {"cat"};
  const char *modified[] = {"cut"};
  MatchCase accepted = {"accepted boundary", LINE_MATCHER_SIMILARITY, original,
                        1, modified, 1, 2.0 / 3.0, 1};
  MatchCase rejected = {"rejected boundary", LINE_MATCHER_SIMILARITY, original,
                        1, modified, 1, 0.667, 0};
  MatchCase cases[] = {accepted, rejected};
  for (int index = 0; index < 2; index++) {
    bool hit_timeout = false;
    SequenceDiffArray *matches = run_case(&cases[index], &hit_timeout);
    ASSERT(matches != NULL, cases[index].name);
    ASSERT(matches->count == cases[index].expected_count, cases[index].name);
    sequence_diff_array_free(matches);
  }
  return true;
}

static bool test_high_entropy_boundary(void) {
  unsigned char left[256];
  unsigned char right[256];
  for (int index = 0; index < 255; index++) {
    left[index] = (unsigned char)(index + 1);
    right[index] = (unsigned char)(index < 254 ? index + 1 : 1);
  }
  left[255] = '\0';
  right[255] = '\0';
  const char *left_lines[] = {(const char *)left};
  const char *right_lines[] = {(const char *)right};
  MatchCase cases[] = {
      {"high entropy right sparse", LINE_MATCHER_SIMILARITY, left_lines, 1,
       right_lines, 1, 508.0 / 510.0, 1},
      {"high entropy left sparse", LINE_MATCHER_SIMILARITY, right_lines, 1,
       left_lines, 1, 508.0 / 510.0, 1},
  };
  for (int index = 0; index < 2; index++) {
    bool hit_timeout = false;
    SequenceDiffArray *matches = run_case(&cases[index], &hit_timeout);
    ASSERT(matches != NULL, cases[index].name);
    ASSERT(!hit_timeout, cases[index].name);
    ASSERT(matches->count == cases[index].expected_count, cases[index].name);
    sequence_diff_array_free(matches);
  }
  return true;
}

static bool test_tie_order(void) {
  const char *original[] = {"same", "same"};
  const char *modified[] = {"same", "same"};
  MatchCase test_case = {"tie order", LINE_MATCHER_SIMILARITY, original, 2,
                         modified, 2, 0.75, 2};
  bool hit_timeout = false;
  SequenceDiffArray *matches = run_case(&test_case, &hit_timeout);
  ASSERT(matches != NULL, "tie order allocation");
  ASSERT(matches->count == 2, "tie order count");
  ASSERT(matches->diffs[0].seq1_start == 0 &&
             matches->diffs[0].seq2_start == 0,
         "tie order first");
  ASSERT(matches->diffs[1].seq1_start == 1 &&
             matches->diffs[1].seq2_start == 1,
         "tie order second");
  sequence_diff_array_free(matches);
  return true;
}

static bool test_timeout(void) {
  int length = 15000;
  char *left = (char *)malloc((size_t)length + 1);
  char *right = (char *)malloc((size_t)length + 1);
  ASSERT(left && right, "timeout allocation");
  for (int index = 0; index < length; index++) {
    left[index] = (char)('a' + index % 23);
    right[index] = (char)('a' + (index * 7) % 23);
  }
  left[length] = '\0';
  right[length] = '\0';
  const char *original[] = {left};
  const char *modified[] = {right};
  SequenceDiff block = {.seq1_start = 0,
                        .seq1_end = 1,
                        .seq2_start = 0,
                        .seq2_end = 1};
  Timeout timeout = {.timeout_ms = 1, .start_time_ms = get_current_time_ms()};
  bool hit_timeout = false;
  SequenceDiffArray *matches = compute_line_matches(
      &block, original, modified, LINE_MATCHER_SIMILARITY, 0.75, &timeout,
      &hit_timeout);
  ASSERT(matches != NULL, "timeout result");
  ASSERT(hit_timeout, "timeout flag");
  sequence_diff_array_free(matches);
  free(left);
  free(right);
  return true;
}

int main(void) {
  bool passed = test_strategies() && test_threshold_boundary() &&
                test_high_entropy_boundary() && test_tie_order() &&
                test_timeout();
  return passed ? 0 : 1;
}
