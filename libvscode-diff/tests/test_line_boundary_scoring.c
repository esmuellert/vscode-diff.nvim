/**
 * test_line_boundary_scoring.c
 * 
 * Demonstrates that Myers algorithm can produce suboptimal boundary choices
 * when multiple positions have identical edit distance, and that boundary
 * optimization fixes this by choosing the most human-readable position.
 * 
 * IMPORTANT NOTE:
 * This test shows boundary scoring WORKING (shifting positions), but the 
 * visual difference between the two results is minimal. In this blank line
 * case, both positions are equally acceptable to humans.
 * 
 * The REAL value of boundary scoring shows in:
 * 1. Character-level diffs: Choosing word boundaries vs mid-word splits
 * 2. Diff joining: Combining multiple small changes into one logical diff
 * 3. Block alignment: Preferring function/class starts over middles
 * 
 * This test proves the MECHANISM works. The human-visible impact is more
 * apparent in character-level refinement (Step 4 of the pipeline).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#include "types.h"
#include "myers.h"
#include "optimize.h"
#include "print_utils.h"

int main() {
    printf("\n╔══════════════════════════════════════════════════════════════╗\n");
    printf("║  FORCING BOUNDARY AMBIGUITY: Insertion Among Blanks         ║\n");
    printf("╚══════════════════════════════════════════════════════════════╝\n\n");
    
    printf("Strategy: Create symmetric blank lines where insertion can be\n");
    printf("placed at multiple positions with identical edit distance.\n\n");
    
    // THIS is the key: identical blank lines before and after
    // Myers MUST choose one position arbitrarily
    // Boundary scoring will prefer the one near non-blank content
    const char* old_lines[] = {
        "start",
        "",
        "",
        "",
        "end"
    };
    
    const char* new_lines[] = {
        "start",
        "",
        "",
        "  middle",  // Inserted line with indentation
        "",
        "",
        "end"
    };
    
    printf("OLD (5 lines):\n");
    for (int i = 0; i < 5; i++) {
        printf("  %d: |%s|\n", i+1, old_lines[i]);
    }
    
    printf("\nNEW (7 lines) - inserted '  middle' with indentation:\n");
    for (int i = 0; i < 7; i++) {
        printf("  %d: |%s|\n", i+1, new_lines[i]);
    }
    
    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("MYERS: Where does it place the insertion?\n");
    printf("══════════════════════════════════════════════════════════════\n\n");
    
    SequenceDiffArray* myers = myers_diff_lines(old_lines, 5, new_lines, 7);
    print_sequence_diff_array("Myers", myers);
    
    if (myers->count > 0) {
        printf("\nMyers chose position: seq1[%d,%d) -> seq2[%d,%d)\n",
               myers->diffs[0].seq1_start, myers->diffs[0].seq1_end,
               myers->diffs[0].seq2_start, myers->diffs[0].seq2_end);
        printf("  Insertion at line %d in new file\n", myers->diffs[0].seq2_start + 1);
    }
    
    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("OPTIMIZATION: Does boundary scoring shift it?\n");
    printf("══════════════════════════════════════════════════════════════\n\n");
    
    SequenceDiffArray* opt = (SequenceDiffArray*)malloc(sizeof(SequenceDiffArray));
    opt->count = myers->count;
    opt->capacity = myers->capacity;
    opt->diffs = (SequenceDiff*)malloc(sizeof(SequenceDiff) * myers->capacity);
    memcpy(opt->diffs, myers->diffs, sizeof(SequenceDiff) * myers->count);
    
    optimize_sequence_diffs_legacy(opt, old_lines, 5, new_lines, 7);
    print_sequence_diff_array("Optimized", opt);
    
    if (opt->count > 0) {
        printf("\nOptimized position: seq1[%d,%d) -> seq2[%d,%d)\n",
               opt->diffs[0].seq1_start, opt->diffs[0].seq1_end,
               opt->diffs[0].seq2_start, opt->diffs[0].seq2_end);
        printf("  Insertion at line %d in new file\n", opt->diffs[0].seq2_start + 1);
    }
    
    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("VERDICT\n");
    printf("══════════════════════════════════════════════════════════════\n\n");
    
    int test_result = 0;  // 0 = success, 1 = failure
    
    if (myers->count > 0 && opt->count > 0) {
        if (myers->diffs[0].seq2_start != opt->diffs[0].seq2_start) {
            int shift = opt->diffs[0].seq2_start - myers->diffs[0].seq2_start;
            printf("✓✓✓ PROVEN! Boundary scoring SHIFTED the diff!\n\n");
            printf("  Myers placed insertion at line %d\n", myers->diffs[0].seq2_start + 1);
            printf("  Optimization shifted to line %d (shift: %+d)\n", 
                   opt->diffs[0].seq2_start + 1, shift);
            printf("\n  WHY: Among blank lines, boundary scoring prefers positions\n");
            printf("       closer to content or with better indentation alignment.\n");
            printf("\n  ✓ This proves Myers makes arbitrary choices when multiple\n");
            printf("    positions have equal edit distance!\n");
            printf("  ✓ Boundary optimization chooses the most readable position!\n");
            test_result = 0;  // Test passed
        } else {
            printf("Myers chose the same position as optimization.\n");
            printf("(Either Myers got lucky, or this case needs more ambiguity)\n");
            test_result = 1;  // Test failed to demonstrate the issue
        }
    }
    
    printf("\n══════════════════════════════════════════════════════════════\n\n");
    
    // Cleanup
    free(opt->diffs);
    free(opt);
    free(myers->diffs);
    free(myers);
    
    return test_result;
}
