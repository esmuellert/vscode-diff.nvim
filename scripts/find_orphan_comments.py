#!/usr/bin/env python3
"""Find comments that were separated from the function they document.

A comment becomes an orphan when something is inserted between it and its
function -- most often while lifting a nested function to module level. The
comment stays put, the function moves down, and the comment ends up describing
whatever landed in the gap. Nothing fails: the code runs, the tests pass, and
the docs quietly point at the wrong thing.

Orphaned comments read exactly like correct ones, so there is no text pattern
to look for. This looks for the *edit* that creates them instead, by walking
the diffs:

    a commit adds a `function` line,
    and the comment lines directly above it are context, not additions
    -> that function was inserted into someone else's comment block

Two other shapes are checked the same way: a function removed or moved with its
comment left behind, and a function renamed under a comment that stayed.

Usage:
    scripts/find_orphan_comments.py                  # every commit touching lua/
    scripts/find_orphan_comments.py --since "1 day ago"
    scripts/find_orphan_comments.py --rev main..HEAD  # one branch

Exits non-zero when anything is found, so it can gate a commit if you want it
to. It is not wired into CI.
"""

import argparse
import re
import subprocess
import sys

ADDED_FUNC = re.compile(r"^\+((?:local )?function\s+([\w.:]+))")
REMOVED_FUNC = re.compile(r"^-((?:local )?function\s+([\w.:]+))")

KINDS = {
    "inserted": "a function was inserted into another function's comment block",
    "left": "a function was removed or moved, leaving its comment behind",
    "renamed": "a function was renamed under a comment that stayed put",
}


def commits(args):
    cmd = ["git", "log", "--no-merges", "--format=%H %ad %s", "--date=short"]
    if args.since:
        cmd += ["--since", args.since]
    if args.rev:
        cmd += [args.rev]
    cmd += ["--", args.path]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    return [l for l in out.strip().split("\n") if l]


def comment_lines_above(lines, index):
    """Comment lines directly above `index`, split by how the diff marks them.

    Returns (context, added, removed): lines that were already there, lines
    this commit added, and lines it removed.
    """
    context, added, removed = [], [], []
    i = index - 1
    while i >= 0 and lines[i][:1] in " +-" and lines[i][1:].strip().startswith("--"):
        marker, text = lines[i][0], lines[i][1:]
        {" ": context, "+": added, "-": removed}[marker].append(text)
        i -= 1
    return context, added, removed


def scan(commit_line, path):
    sha, date, subject = commit_line.split(" ", 2)
    show = subprocess.run(
        ["git", "show", sha, "--unified=6", "--", path],
        capture_output=True, text=True, check=True).stdout

    found = []
    for block in show.split("\ndiff --git ")[1:]:
        path_match = re.search(r"b/(\S+)", block)
        if not path_match:
            continue
        file_path = path_match.group(1)
        lines = block.split("\n")

        for i, line in enumerate(lines):
            add = ADDED_FUNC.match(line)
            remove = REMOVED_FUNC.match(line)
            if not (add or remove):
                continue

            context, added, removed = comment_lines_above(lines, i)
            if not context:
                continue

            if add and added:
                kind = "inserted"
                name = add.group(2)
            elif remove and not removed:
                # Renamed if another function definition appears right after.
                following = next(
                    (lines[k] for k in range(i + 1, min(i + 40, len(lines)))
                     if ADDED_FUNC.match(lines[k]) or REMOVED_FUNC.match(lines[k])),
                    "")
                kind = "renamed" if ADDED_FUNC.match(following) else "left"
                name = remove.group(2)
            else:
                continue

            found.append({
                "kind": kind, "date": date, "sha": sha[:8], "subject": subject[:52],
                "file": file_path, "function": name, "comment": context[-1].strip(),
            })
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--since", help='git --since, e.g. "1 day ago"')
    parser.add_argument("--rev", help="revision range, e.g. main..HEAD")
    parser.add_argument("--path", default="lua/", help="path to scan (default: lua/)")
    parser.add_argument("--kind", choices=sorted(KINDS), action="append",
                        help="kinds to report (repeatable). Default: inserted, "
                             "the only one with no false positives. `renamed` "
                             "mostly catches a function moved with its comment, "
                             "which is fine.")
    args = parser.parse_args()

    log = commits(args)
    hits = [h for c in log for h in scan(c, args.path)]
    hits = [h for h in hits if h["kind"] in (args.kind or ["inserted", "left"])]

    for kind in sorted(KINDS):
        rows = [h for h in hits if h["kind"] == kind]
        if not rows:
            continue
        print(f"{KINDS[kind]}: {len(rows)}")
        for h in rows:
            print(f"  {h['date']} {h['sha']}  {h['file']}")
            print(f"      {h['function']}")
            print(f"      comment above: {h['comment'][:64]}")
        print()

    print(f"scanned {len(log)} commits under {args.path}")
    if hits:
        print(f"found {len(hits)} -- check whether the comment still describes "
              f"the function below it")
    else:
        print("nothing found")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
