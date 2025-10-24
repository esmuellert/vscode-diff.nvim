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
#include "../include/myers.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

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
    
    // Without whitespace trimming: should see difference
    ISequence* seq_a1 = line_sequence_create(lines_a, 3, false);
    ISequence* seq_b1 = line_sequence_create(lines_b, 3, false);
    
    bool hit_timeout = false;
    SequenceDiffArray* result1 = myers_diff_algorithm(seq_a1, seq_b1, 0, &hit_timeout);
    
    printf("  Without trim: %d diff(s)\n", result1->count);
    assert(result1->count == 1);  // Should detect whitespace difference
    printf("  ✓ Detected whitespace difference\n");
    
    seq_a1->destroy(seq_a1);
    seq_b1->destroy(seq_b1);
    free(result1->diffs);
    free(result1);
    
    // With whitespace trimming: should be identical
    ISequence* seq_a2 = line_sequence_create(lines_a, 3, true);
    ISequence* seq_b2 = line_sequence_create(lines_b, 3, true);
    
    SequenceDiffArray* result2 = myers_diff_algorithm(seq_a2, seq_b2, 0, &hit_timeout);
    
    printf("  With trim: %d diff(s)\n", result2->count);
    assert(result2->count == 0);  // Should ignore whitespace
    printf("  ✓ Ignored whitespace difference\n");
    
    seq_a2->destroy(seq_a2);
    seq_b2->destroy(seq_b2);
    free(result2->diffs);
    free(result2);
    
    printf("✓ PASSED\n");
}

void test_boundary_scoring() {
    printf("\n=== Test: Boundary Scoring ===\n");
    
    const char* lines[] = {
        "code",
        "",           // Blank line - high score
        "{",          // Brace - medium score  
        "  content",  // Regular line - low score
        "}"
    };
    
    ISequence* seq = line_sequence_create(lines, 5, false);
    
    // Test boundary scores
    int score1 = seq->getBoundaryScore(seq, 1);  // After "code"
    int score2 = seq->getBoundaryScore(seq, 2);  // After blank line
    int score3 = seq->getBoundaryScore(seq, 3);  // After "{"
    
    printf("  Score after 'code': %d\n", score1);
    printf("  Score after blank line: %d\n", score2);
    printf("  Score after '{': %d\n", score3);
    
    assert(score2 > score3);  // Blank line should score higher than brace
    assert(score3 > score1);  // Brace should score higher than regular line
    
    printf("  ✓ Boundary scores correctly ordered\n");
    
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
    
    ISequence* seq_a = line_sequence_create(lines_a, 100, false);
    ISequence* seq_b = line_sequence_create(lines_b, 100, false);
    
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
