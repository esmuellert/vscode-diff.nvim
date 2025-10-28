#!/usr/bin/env bash
# Script to extract and bundle VSCode's diff algorithm into a standalone executable

set -e

# Remember where we started
START_DIR="$(pwd)"

WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

echo "Working directory: $WORK_DIR"
cd "$WORK_DIR"

echo "Cloning VSCode repository (sparse checkout)..."
git clone --depth 1 --filter=blob:none --sparse https://github.com/microsoft/vscode.git

cd vscode
git sparse-checkout set src/vs/editor/common/diff src/vs/base/common src/vs/editor/common/core

cd "$WORK_DIR"

echo "Creating wrapper script..."
cat > vscode-diff-wrapper.ts << 'EOF'
#!/usr/bin/env node
import { readFileSync } from 'fs';
import { DefaultLinesDiffComputer } from './vscode/src/vs/editor/common/diff/defaultLinesDiffComputer/defaultLinesDiffComputer.js';

function main() {
    const args = process.argv.slice(2);
    
    if (args.length < 2) {
        console.error('Usage: node vscode-diff.js <file1> <file2>');
        process.exit(1);
    }

    const file1Path = args[0];
    const file2Path = args[1];

    const file1Content = readFileSync(file1Path, 'utf-8');
    const file2Content = readFileSync(file2Path, 'utf-8');

    const file1Lines = file1Content.split('\n');
    const file2Lines = file2Content.split('\n');

    // Print header
    console.log('=================================================================');
    console.log('Diff Tool - Computing differences');
    console.log('=================================================================');
    console.log(`Original: ${file1Path} (${file1Lines.length} lines)`);
    console.log(`Modified: ${file2Path} (${file2Lines.length} lines)`);
    console.log('=================================================================\n');

    const diffComputer = new DefaultLinesDiffComputer();
    
    const result = diffComputer.computeDiff(file1Lines, file2Lines, {
        ignoreTrimWhitespace: false,
        maxComputationTimeMs: 0,
        computeMoves: false,
    });

    // Print results
    console.log('Diff Results:');
    console.log('=================================================================');
    console.log(`Number of changes: ${result.changes.length}`);
    console.log(`Hit timeout: ${result.hitTimeout ? 'yes' : 'no'}`);
    console.log('');
    
    if (!result.changes || result.changes.length === 0) {
        console.log('No differences found - files are identical.');
    } else {
        console.log(`  Changes: ${result.changes.length} line mapping(s)`);
        
        for (let i = 0; i < result.changes.length; i++) {
            const change = result.changes[i];
            const originalRange = change.original;
            const modifiedRange = change.modified;
            
            if (!originalRange || !modifiedRange) {
                console.error('Invalid change object:', change);
                continue;
            }
            
            const innerChanges = change.innerChanges || [];
            const innerCount = innerChanges.length;
            
            // Print line range mapping with inclusive end
            console.log(`    [${i}] Lines ${originalRange.startLineNumber}-${originalRange.endLineNumberExclusive - 1} -> Lines ${modifiedRange.startLineNumber}-${modifiedRange.endLineNumberExclusive - 1}${innerCount > 0 ? ` (${innerCount} inner change${innerCount === 1 ? '' : 's'})` : ' (no inner changes)'}`);
            
            // Print inner changes (character-level)
            for (const inner of innerChanges) {
                const orig = inner.originalRange;
                const mod = inner.modifiedRange;
                console.log(`         Inner: L${orig.startLineNumber}:C${orig.startColumn}-L${orig.endLineNumber}:C${orig.endColumn} -> L${mod.startLineNumber}:C${mod.startColumn}-L${mod.endLineNumber}:C${mod.endColumn}`);
            }
        }
    }
    
    console.log('\n=================================================================');
}

main();
EOF

echo "Installing bundler..."
npm init -y > /dev/null 2>&1
npm install --no-save esbuild > /dev/null 2>&1

echo "Bundling TypeScript code into single JavaScript file..."
npx esbuild vscode-diff-wrapper.ts --bundle --platform=node --format=esm --outfile=vscode-diff.mjs

OUTPUT_FILE="${1:-vscode-diff.mjs}"
OUTPUT_PATH="$START_DIR/$OUTPUT_FILE"

echo "Copying output to: $OUTPUT_PATH"
cp vscode-diff.mjs "$OUTPUT_PATH"

echo ""
echo "✅ Successfully generated: $OUTPUT_PATH"
echo ""
echo "Usage: node $OUTPUT_PATH <file1> <file2>"
echo ""
echo "Test it with:"
echo "  echo 'line1' > test1.txt"
echo "  echo 'line2' > test2.txt"
echo "  node $OUTPUT_PATH test1.txt test2.txt"
