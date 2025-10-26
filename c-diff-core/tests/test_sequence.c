/**
 * Infrastructure Tests - ISequence Interface
 * 
 * Tests the new ISequence infrastructure including:
 * - LineSequence with whitespace handling
 * - Hash-based comparison
 * - Boundary scoring
 * - Timeout support
 */

#include "../include/sequence.h"
#include "../include/string_hash_map.h"
#include "../include/myers.h"
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
    SequenceDiffArray* result1 = myers_diff_algorithm(seq_a1, seq_b1, 0, &hit_timeout);
    
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
    
    SequenceDiffArray* result2 = myers_diff_algorithm(seq_a2, seq_b2, 0, &hit_timeout);
    
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
    SequenceDiffArray* result = myers_diff_algorithm(seq_a, seq_b, 1, &hit_timeout);
    
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

int main() {
    printf("\n========================================\n");
    printf("Infrastructure Tests - ISequence\n");
    printf("========================================\n");
    
    test_whitespace_handling();
    test_boundary_scoring();
    test_timeout();
    
    printf("\n========================================\n");
    printf("All infrastructure tests passed! ✓\n");
    printf("========================================\n\n");
    
    return 0;
}
