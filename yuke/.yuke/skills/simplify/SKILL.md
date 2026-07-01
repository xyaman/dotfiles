---
name: simplify
description: Review changed code for reuse, simplification, efficiency, and altitude issues, then apply the fixes. Use when the user says "simplify", asks to clean up, reduce duplication, streamline, or refactor recently changed code, or after finishing a feature before committing.
---

# Simplify changed code

You are improving the **quality** of changed code, not hunting for correctness
bugs. Review the diff for reuse, simplification, efficiency, and altitude
issues, then fix what you find. Do not look for correctness bugs; that is what
code review is for.

## Phase 0: Gather the diff

Run one of these to get the unified diff under review (try in order, use the
first that returns content):

```sh
git diff @{upstream}...HEAD      # tracked branch
git diff main...HEAD             # main-based
git diff HEAD~1                  # last commit
```

If there are uncommitted changes, or the range diff is empty, also run:

```sh
git diff HEAD                    # working-tree changes
```

If the user passed a PR number, branch name, or file path, review that target
instead. Save the full diff to a temp file so sub-agents can read it:

```sh
git diff ... > /tmp/simplify-diff.txt
```

Treat this diff as the review scope. If it's empty or tiny, tell the user there
is nothing to review and stop.

## Phase 1: Review (4 parallel sub-agents)

Launch **4 independent `yuke -p` agents** in a single message so they run
concurrently. Each agent gets the diff and one review angle. Each returns
findings as a list, where every finding has:

- `file`: the file path
- `line`: the line number (or range)
- `summary`: one-line description of the issue
- `cost`: what is duplicated, wasted, or harder to maintain

Build each prompt as a self-contained `yuke -p` command following the
`spawn-agent` skill pattern: start with `[sub-agent]`, inline the diff via
`$(cat /tmp/simplify-diff.txt)`, and ask for structured findings only (no
fixes). Use `--model zai-coding-plan/glm-5.2` as the default analyzer.

The four angles:

### Reuse

Check whether new code duplicates logic that already exists elsewhere in the
codebase: a utility function, a helper method, a constant, or an established
pattern. The diff added code that does X; does the codebase already have
something that does X (or close enough)? Flag duplicated logic and point to
the existing implementation (file + line) so it can be reused instead.

### Simplification

Flag code that is more complex than it needs to be: deeply nested conditionals
that flatten with early returns, multi-step transformations that collapse into
one, verbose patterns where an iterator method or language idiom is clearer,
dead branches or redundant checks that can be removed. The goal is fewer
moving parts with the same behavior. Name the simpler form.

### Efficiency

Flag wasted work the diff introduces: redundant computation or repeated I/O,
independent operations run sequentially, blocking work added to startup or hot
paths. Also flag long-lived objects built from closures or captured
environments: they keep the entire enclosing scope alive for the object's
lifetime (a memory leak when that scope holds large values); prefer a
class/struct that copies only the fields it needs. Name the cheaper
alternative.

### Altitude

Check that each change is implemented at the right depth, not as a fragile
bandaid. Special cases layered on shared infrastructure are a sign the fix
isn't deep enough. Prefer generalizing the underlying mechanism over adding
special cases.

### Example sub-agent invocation

```sh
yuke -p "[sub-agent] You are reviewing a code diff for SIMPLIFICATION opportunities only.

Rules:
- Do NOT look for correctness bugs.
- Flag code more complex than necessary: nested conditionals, multi-step transforms, verbose patterns, dead branches.
- For each finding give: file, line, summary (one line), and cost (what is harder to maintain).
- Return findings as a list. If nothing is wrong, say 'no findings'.

Diff:
$(cat /tmp/simplify-diff.txt)" --model zai-coding-plan/glm-5.2
```

Repeat for reuse, efficiency, and altitude, changing the angle text. Launch all
four in the same turn so they run concurrently.

## Phase 2: Apply the fixes

Wait for all four agents to complete, then:

1. **Dedup** findings that point at the same line or mechanism.
2. **Fix** each remaining one directly in the code.
3. **Skip** any finding whose fix would:
   - Change intended behavior
   - Require changes well outside the reviewed diff
   - Be a false positive

   Note the skip briefly rather than arguing with it.

4. **Summarize** what was fixed and what was skipped (or confirm the code was
   already clean). Keep the summary short: a few lines, not an essay.
