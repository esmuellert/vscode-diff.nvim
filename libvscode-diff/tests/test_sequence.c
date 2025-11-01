/**
 * Infrastructure Tests - ISequence Interface
 * 
 * Tests the new ISequence infrastructure including:
 * - LineSequence with whitespace handling
 * - Hash-based comparison
 * - Boundary scoring
 * - Timeout support
 */

#include "sequence.h"
#include "string_hash_map.h"
#include "myers.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>

void test_whitespace_handling() {
    printf("\n=== Test: Whitespace Handling ===\n");
    
    const char* lines_a[] = {
        "hello",
        "  world  ",  // Extra whitespace
        "test"
    };
    const char* lines_b[] = {
        "hello",
        "world",      // Trimmed
        "test"
    };
    
    // Create shared hash map for consistent hashing
    StringHashMap* shared_map = string_hash_map_create();
    
    // Without whitespace trimming: should see difference
    ISequence* seq_a1 = line_sequence_create(lines_a, 3, false, shared_map);
    ISequence* seq_b1 = line_sequence_create(lines_b, 3, false, shared_map);
    
    bool hit_timeout = false;
    SequenceDiffArray* result1 = myers_nd_diff_algorithm(seq_a1, seq_b1, 0, &hit_timeout);
    
    printf("  Without trim: %d diff(s)\n", result1->count);
    assert(result1->count >= 1);  // Should detect whitespace difference
    printf("  ✓ Detected whitespace difference\n");
    
    seq_a1->destroy(seq_a1);
    seq_b1->destroy(seq_b1);
    free(result1->diffs);
    free(result1);
    
    // With whitespace trimming: should be identical
    ISequence* seq_a2 = line_sequence_create(lines_a, 3, true, shared_map);
    ISequence* seq_b2 = line_sequence_create(lines_b, 3, true, shared_map);
    
    SequenceDiffArray* result2 = myers_nd_diff_algorithm(seq_a2, seq_b2, 0, &hit_timeout);
    
    printf("  With trim: %d diff(s)\n", result2->count);
    assert(result2->count == 0);  // Should ignore whitespace
    printf("  ✓ Ignored whitespace difference\n");
    
    seq_a2->destroy(seq_a2);
    seq_b2->destroy(seq_b2);
    free(result2->diffs);
    free(result2);
    
    string_hash_map_destroy(shared_map);
    
    printf("✓ PASSED\n");
}

void test_boundary_scoring() {
    printf("\n=== Test: Boundary Scoring ===\n");
    
    const char* lines[] = {
        "code",           // No indentation
        "",               // Blank line - no indentation
        "    {",          // Indented 4 spaces
        "        content",// Indented 8 spaces  
        "    }"           // Indented 4 spaces
    };
    
    ISequence* seq = line_sequence_create(lines, 5, false, NULL);
    
    // Test boundary scores - based on indentation
    // Formula: 1000 - (indent_before + indent_after)
    
    // Boundary at 1 (after "code", before ""):
    // indent_before = 0 (code), indent_after = 0 (blank) => 1000 - 0 = 1000
    int score1 = seq->getBoundaryScore(seq, 1);
    
    // Boundary at 2 (after "", before "    {"):
    // indent_before = 0 (blank), indent_after = 4 ({) => 1000 - 4 = 996
    int score2 = seq->getBoundaryScore(seq, 2);
    
    // Boundary at 3 (after "    {", before "        content"):
    // indent_before = 4 ({), indent_after = 8 (content) => 1000 - 12 = 988
    int score3 = seq->getBoundaryScore(seq, 3);
    
    printf("  Score at boundary 1 (after 'code'): %d\n", score1);
    printf("  Score at boundary 2 (after blank line): %d\n", score2);
    printf("  Score at boundary 3 (after '    {'): %d\n", score3);
    
    // Higher score = better boundary = less indentation
    assert(score1 > score2);  // No indentation better than some indentation
    assert(score2 > score3);  // Less indentation better than more indentation
    
    printf("  ✓ Boundary scores correctly ordered by indentation\n");
    
    seq->destroy(seq);
    printf("✓ PASSED\n");
}

void test_timeout() {
    printf("\n=== Test: Timeout Support ===\n");
    
    // Create large different sequences
    const char** lines_a = malloc(sizeof(char*) * 100);
    const char** lines_b = malloc(sizeof(char*) * 100);
    
    for (int i = 0; i < 100; i++) {
        char* buf_a = malloc(20);
        char* buf_b = malloc(20);
        snprintf(buf_a, 20, "line_a_%d", i);
        snprintf(buf_b, 20, "line_b_%d", i);
        lines_a[i] = buf_a;
        lines_b[i] = buf_b;
    }
    
    ISequence* seq_a = line_sequence_create(lines_a, 100, false, NULL);
    ISequence* seq_b = line_sequence_create(lines_b, 100, false, NULL);
    
    // Test with very short timeout (1ms)
    bool hit_timeout = false;
    SequenceDiffArray* result = myers_nd_diff_algorithm(seq_a, seq_b, 1, &hit_timeout);
    
    printf("  Timeout reached: %s\n", hit_timeout ? "yes" : "no");
    printf("  Result diff count: %d\n", result->count);
    
    // Timeout should have been hit, returning trivial diff
    if (hit_timeout) {
        printf("  ✓ Timeout protection working\n");
    } else {
        printf("  ⚠ Timeout not hit (algorithm was very fast)\n");
    }
    
    // Cleanup
    seq_a->destroy(seq_a);
    seq_b->destroy(seq_b);
    free(result->diffs);
    free(result);
    
    for (int i = 0; i < 100; i++) {
        free((void*)lines_a[i]);
        free((void*)lines_b[i]);
    }
    free(lines_a);
    free(lines_b);
    
    printf("✓ PASSED\n");
}

void test_column_translation_with_trimmed_whitespace() {
    printf("\n=== Test: Column Translation with Trimmed Whitespace ===\n");
    
    // Lines with leading/trailing whitespace
    const char* lines[] = {
        "    hello world    ",  // Line 0: 4 leading, content starts at col 4
        "  foo bar  ",          // Line 1: 2 leading, content starts at col 2
        "no trim",              // Line 2: 0 leading, content starts at col 0
    };
    
    // Create char sequence with whitespace trimming
    ISequence* seq = char_sequence_create(lines, 0, 3, false);
    CharSequence* char_seq = (CharSequence*)seq->data;
    
    printf("  Created char sequence (trimmed):\n");
    printf("    Line 0: \"    hello world    \" -> \"hello world\"\n");
    printf("    Line 1: \"  foo bar  \" -> \"foo bar\"\n");
    printf("    Line 2: \"no trim\" -> \"no trim\"\n");
    
    // The trimmed sequence should be: "hello world\nfoo bar\nno trim"
    // Offsets:
    //   Line 0: offset 0-10 ("hello world")
    //   Line 1: offset 12-18 ("foo bar")
    //   Line 2: offset 20-26 ("no trim")
    
    int line, col;
    
    // Test Line 0: offset 0 should translate to (0, 4) - start of "hello" after 4 leading spaces
    // Using RIGHT preference (default): should add trimmed whitespace even at line start
    char_sequence_translate_offset(char_seq, 0, OFFSET_PREFERENCE_RIGHT, &line, &col);
    printf("\n  Offset 0 (first char 'h' in trimmed) -> Line %d, Col %d\n", line, col);
    printf("    Expected: Line 0, Col 4 (after 4 leading spaces in original)\n");
    assert(line == 0);
    assert(col == 4);
    printf("  ✓ Correct\n");
    
    // Test Line 0: offset 5 should translate to (0, 9) - 'space' between hello and world
    char_sequence_translate_offset(char_seq, 5, OFFSET_PREFERENCE_RIGHT, &line, &col);
    printf("\n  Offset 5 (space in 'hello world') -> Line %d, Col %d\n", line, col);
    printf("    Expected: Line 0, Col 9\n");
    assert(line == 0);
    assert(col == 9);
    printf("  ✓ Correct\n");
    
    // Test Line 1: offset 12 should translate to (1, 2) - start of "foo" after 2 leading spaces
    char_sequence_translate_offset(char_seq, 12, OFFSET_PREFERENCE_RIGHT, &line, &col);
    printf("\n  Offset 12 (first char 'f' in 'foo bar') -> Line %d, Col %d\n", line, col);
    printf("    Expected: Line 1, Col 2 (after 2 leading spaces in original)\n");
    assert(line == 1);
    assert(col == 2);
    printf("  ✓ Correct\n");
    
    // Test Line 2: offset 20 should translate to (2, 0) - start of "no trim" with no leading space
    char_sequence_translate_offset(char_seq, 20, OFFSET_PREFERENCE_RIGHT, &line, &col);
    printf("\n  Offset 20 (first char 'n' in 'no trim') -> Line %d, Col %d\n", line, col);
    printf("    Expected: Line 2, Col 0 (no leading spaces)\n");
    assert(line == 2);
    assert(col == 0);
    printf("  ✓ Correct\n");
    
    seq->destroy(seq);
    printf("\n✓ PASSED\n");
}

void test_column_translation_no_trimming() {
    printf("\n=== Test: Column Translation without Trimming ===\n");
    
    const char* lines[] = {
        "    hello world    ",
        "  foo bar  ",
    };
    
    // Create char sequence WITHOUT whitespace trimming
    ISequence* seq = char_sequence_create(lines, 0, 2, true);
    CharSequence* char_seq = (CharSequence*)seq->data;
    
    printf("  Created char sequence (no trimming):\n");
    printf("    Preserves all whitespace\n");
    
    int line, col;
    
    // Test offset 0 should translate to (0, 0) - first space character
    char_sequence_translate_offset(char_seq, 0, OFFSET_PREFERENCE_RIGHT, &line, &col);
    printf("\n  Offset 0 (first space) -> Line %d, Col %d\n", line, col);
    printf("    Expected: Line 0, Col 0\n");
    assert(line == 0);
    assert(col == 0);
    printf("  ✓ Correct\n");
    
    // Test offset 4 should translate to (0, 4) - 'h' in hello
    char_sequence_translate_offset(char_seq, 4, OFFSET_PREFERENCE_RIGHT, &line, &col);
    printf("\n  Offset 4 ('h' in hello) -> Line %d, Col %d\n", line, col);
    printf("    Expected: Line 0, Col 4\n");
    assert(line == 0);
    assert(col == 4);
    printf("  ✓ Correct\n");
    
    seq->destroy(seq);
    printf("\n✓ PASSED\n");
}

void test_translate_offset_left_right_preference() {
    printf("\n=== Test: translateOffset Left/Right Preference (VSCode Parity) ===\n");
    
    // Test case: Line with 4 spaces of leading whitespace
    // Original: "    code here"
    // Trimmed:  "code here"
    const char* lines[] = {
        "    code here"
    };
    
    // Create char sequence with whitespace trimming
    ISequence* seq = char_sequence_create(lines, 0, 1, false);
    CharSequence* char_seq = (CharSequence*)seq->data;
    
    printf("  Original line: \"%s\"\n", lines[0]);
    printf("  Trimmed whitespace: %d spaces\n", char_seq->trimmed_ws_lengths[0]);
    printf("  Sequence length: %d chars\n", char_seq->length);
    
    // Offset 0 is the start of "code" in the trimmed sequence
    int offset = 0;
    int line_left, col_left, line_right, col_right;
    
    // Test with LEFT preference (should NOT add trimmed whitespace at line start)
    char_sequence_translate_offset(char_seq, offset, OFFSET_PREFERENCE_LEFT, &line_left, &col_left);
    
    // Test with RIGHT preference (should ALWAYS add trimmed whitespace)
    char_sequence_translate_offset(char_seq, offset, OFFSET_PREFERENCE_RIGHT, &line_right, &col_right);
    
    printf("\n  Offset %d (at line start) translation:\n", offset);
    printf("    LEFT preference:  line=%d, col=%d (0-based) => col=%d (1-based)\n", 
           line_left, col_left, col_left + 1);
    printf("    RIGHT preference: line=%d, col=%d (0-based) => col=%d (1-based)\n", 
           line_right, col_right, col_right + 1);
    
    // Verify VSCode parity
    // VSCode with 'left': column = 1 + 0 + 0 + 0 = 1 (1-based) => 0 (0-based)
    // VSCode with 'right': column = 1 + 0 + 0 + 4 = 5 (1-based) => 4 (0-based)
    assert(col_left == 0);
    assert(col_right == 4);
    printf("    ✓ PASSED: Left returns col 0, Right returns col 4\n");
    
    // Test non-zero offset (should always add trimmed whitespace regardless of preference)
    int offset2 = 4; // Middle of "code"
    char_sequence_translate_offset(char_seq, offset2, OFFSET_PREFERENCE_LEFT, &line_left, &col_left);
    char_sequence_translate_offset(char_seq, offset2, OFFSET_PREFERENCE_RIGHT, &line_right, &col_right);
    
    printf("\n  Offset %d (not at line start) translation:\n", offset2);
    printf("    LEFT preference:  col=%d (0-based)\n", col_left);
    printf("    RIGHT preference: col=%d (0-based)\n", col_right);
    
    // Both should be 8 (4 spaces + 4 chars into "code")
    assert(col_left == 8);
    assert(col_right == 8);
    printf("    ✓ PASSED: Both preferences add trimmed whitespace when lineOffset > 0\n");
    
    seq->destroy(seq);
    printf("\n✓ PASSED\n");
}

void test_translate_range_preferences() {
    printf("\n=== Test: translateRange (uses RIGHT for start, LEFT for end) ===\n");
    
    const char* lines[] = {
        "    line one",
        "    line two"
    };
    
    ISequence* seq = char_sequence_create(lines, 0, 2, false);
    CharSequence* char_seq = (CharSequence*)seq->data;
    
    printf("  Line 0: \"%s\" (trimmed_ws=%d)\n", lines[0], char_seq->trimmed_ws_lengths[0]);
    printf("  Line 1: \"%s\" (trimmed_ws=%d)\n", lines[1], char_seq->trimmed_ws_lengths[1]);
    printf("  Sequence length: %d\n", char_seq->length);
    
    // Create a range from start of line 0 to start of line 1
    int start_offset = 0; // Start of "line one"
    int end_offset = char_seq->line_start_offsets[1]; // Start of "line two"
    
    printf("\n  Range: offset %d to %d\n", start_offset, end_offset);
    
    int start_line, start_col, end_line, end_col;
    char_sequence_translate_range(char_seq, start_offset, end_offset,
                                  &start_line, &start_col, &end_line, &end_col);
    
    printf("  Translated range:\n");
    printf("    Start: line=%d, col=%d (0-based) => col=%d (1-based)\n", 
           start_line, start_col, start_col + 1);
    printf("    End:   line=%d, col=%d (0-based) => col=%d (1-based)\n", 
           end_line, end_col, end_col + 1);
    
    // VSCode translateRange uses:
    // - 'right' for start: should add trimmed ws => col = 4 (0-based)
    // - 'left' for end at line start: should NOT add trimmed ws => col = 0 (0-based)
    assert(start_col == 4); // RIGHT preference
    assert(end_col == 0);   // LEFT preference at line start
    printf("    ✓ PASSED: Start uses RIGHT (col=4), End uses LEFT (col=0)\n");
    
    seq->destroy(seq);
    printf("\n✓ PASSED\n");
}

void test_translate_range_collapsed() {
    printf("\n=== Test: translateRange Collapsed Range Handling ===\n");
    
    const char* lines[] = {
        "    test"
    };
    
    ISequence* seq = char_sequence_create(lines, 0, 1, false);
    CharSequence* char_seq = (CharSequence*)seq->data;
    
    // Create a zero-length range (start == end)
    int start_offset = 0;
    int end_offset = 0;
    
    printf("  Testing collapsed range: offset %d to %d\n", start_offset, end_offset);
    
    int start_line, start_col, end_line, end_col;
    char_sequence_translate_range(char_seq, start_offset, end_offset,
                                  &start_line, &start_col, &end_line, &end_col);
    
    printf("  Result:\n");
    printf("    Start: line=%d, col=%d\n", start_line, start_col);
    printf("    End:   line=%d, col=%d\n", end_line, end_col);
    
    // VSCode: if (pos2.isBefore(pos1)) return Range.fromPositions(pos2, pos2)
    // With LEFT preference at offset 0, end_col = 0
    // With RIGHT preference at offset 0, start_col = 4
    // Since end < start, should collapse to end position
    assert(start_line == end_line);
    assert(start_col == end_col);
    assert(end_col == 0); // Should collapse to LEFT preference (end position)
    printf("    ✓ PASSED: Collapsed to end position (LEFT preference)\n");
    
    seq->destroy(seq);
    printf("\n✓ PASSED\n");
}

void test_column_translation_edge_cases() {
    printf("\n=== Test: Column Translation Edge Cases ===\n");
    
    const char* lines[] = {
        "        ",  // Only whitespace - will be trimmed to empty
        "  x  ",    // Single char with whitespace
        "",         // Empty line
    };
    
    ISequence* seq = char_sequence_create(lines, 0, 3, false);
    CharSequence* char_seq = (CharSequence*)seq->data;
    
    int line, col;
    
    // Test translation in line with only whitespace (trimmed to empty)
    char_sequence_translate_offset(char_seq, 0, OFFSET_PREFERENCE_RIGHT, &line, &col);
    printf("  Offset 0 in trimmed sequence -> Line %d, Col %d\n", line, col);
    // Should map to line 1 (the "x" line) since line 0 is empty after trimming
    printf("  (Line with single 'x' char)\n");
    
    seq->destroy(seq);
    printf("\n✓ PASSED\n");
}

int main() {
    printf("\n========================================\n");
    printf("Infrastructure Tests - ISequence\n");
    printf("========================================\n");
    
    test_whitespace_handling();
    test_boundary_scoring();
    test_timeout();
    
    printf("\n========================================\n");
    printf("Column Translation Tests\n");
    printf("VSCode Parity: linesSliceCharSequence.translateOffset()\n");
    printf("========================================\n");
    
    test_column_translation_with_trimmed_whitespace();
    test_column_translation_no_trimming();
    test_column_translation_edge_cases();
    
    printf("\n========================================\n");
    printf("Translate Preference Tests (Parity Fix)\n");
    printf("VSCode Parity: translateOffset() left/right preference\n");
    printf("VSCode Parity: translateRange() preference handling\n");
    printf("========================================\n");
    
    test_translate_offset_left_right_preference();
    test_translate_range_preferences();
    test_translate_range_collapsed();
    
    printf("\n========================================\n");
    printf("All infrastructure tests passed! ✓\n");
    printf("========================================\n\n");
    
    return 0;
}
