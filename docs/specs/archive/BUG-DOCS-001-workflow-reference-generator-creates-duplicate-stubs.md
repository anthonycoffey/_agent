---
id: BUG-DOCS-001
title: "Workflow reference generator creates duplicate stub docs on Windows"
status: complete
severity: P3
created: 2026-05-18
completed: 2026-05-18
author: Anthony Coffey
reviewers: []
affected_repos: [_agent]
---

<!--
2026-05-18 — Fix shipped: readFrontmatter() in
agent/n8n/scripts/generate-workflow-reference.mjs is now CRLF-tolerant
(\r? added to opening/closing fence regex + split). Verified by deleting
the five stub files and re-running the generator: all 9 workflows route
correctly to their hand-written docs and no stubs are recreated.

Spec marked complete and moved to specs/archive/.
-->


## Reviewer Notes

<!-- Leave empty until code review. Reviewer adds feedback here when requesting changes. -->

---

# Bug: Workflow reference generator creates duplicate stub docs on Windows

## Symptom

After running `node agent/n8n/scripts/generate-workflow-reference.mjs` on Windows, five new untracked stub markdown files appear in `docs/workflows/`:

```
docs/workflows/bugsy.md
docs/workflows/bugsy-rag-ingest.md
docs/workflows/bugsy-rag-query.md
docs/workflows/bugsy-job-board-fetcher.md
docs/workflows/bugsy-job-board-ui.md
```

Each is a freshly-generated stub with the placeholder body `_Add a hand-written summary of what this workflow does and why._`, even though the corresponding workflows are **already claimed** by existing hand-written docs:

| Stub (created in error) | Already covered by |
|---|---|
| `bugsy.md` | `bugsy-unified.md` (claims `bugsy`) |
| `bugsy-rag-ingest.md` | `rag-ingest.md` (claims `bugsy-rag-ingest`) |
| `bugsy-rag-query.md` | `rag-query.md` (claims `bugsy-rag-query`) |
| `bugsy-job-board-fetcher.md` | `job-board.md` (claims `bugsy-job-board-fetcher`, `bugsy-job-board-ui`) |
| `bugsy-job-board-ui.md` | `job-board.md` (same as above) |

Net effect: every workflow now has two `.md` files. The hand-written one has all the prose; the stub is a useless duplicate that gets refreshed on each generator run.

## Expected behavior

When a workflow is already claimed by an existing doc via `n8n_workflows: [...]` frontmatter, the generator should update the node-reference block inside that doc and **not** create a stub.

## Reproduction

1. Be on Windows (or any system where `.md` files have CRLF line endings).
2. Have hand-written workflow docs with proper `n8n_workflows:` frontmatter (e.g. `bugsy-unified.md` claiming `bugsy`).
3. Run `node agent/n8n/scripts/generate-workflow-reference.mjs`.
4. `git status` shows five new untracked `docs/workflows/<basename>.md` stubs.

**Frequency:** every run on a CRLF-checkout.
**Environment:** Windows + Node 20+. The repo has no `.gitattributes`, so git's default `core.autocrlf=true` on Windows checks out `.md` files with CRLF.

## Root cause

In [`agent/n8n/scripts/generate-workflow-reference.mjs`](../../../agent/n8n/scripts/generate-workflow-reference.mjs), `readFrontmatter()` uses regexes that require literal `\n`:

```js
function readFrontmatter(content) {
  const m = content.match(/^---\n([\s\S]*?)\n---\n?/);   // ← requires LF
  if (!m) return { fm: {}, body: content, rawHead: '' };
  const fm = {};
  for (const line of m[1].split('\n')) {                  // ← splits on LF only
    ...
  }
}
```

On a Windows-checkout file with CRLF endings, the bytes after `---` are `\r\n`, so `^---\n` **does not match at all**. The function returns `{ fm: {}, body: content }` — empty frontmatter.

Downstream, `buildOwnership()` reads `fm.n8n_workflows`, finds nothing, and never registers the doc as a claim owner. In `main()` the `owners.get(basename)` lookup returns `undefined`, the script falls to the "create stub" branch, and writes `docs/workflows/<basename>.md` (with LF endings, since Node's default `\n` strings are LF on every platform).

On subsequent runs the stub is read successfully (it has LF), recognized as a claimer, and updated in place rather than recreated — so the bug only manifests as a one-time generation, but the duplicate sits in the working tree forever and `git status` shows it as untracked noise.

Evidence captured 2026-05-18:

```bash
$ head -c 30 docs/workflows/bugsy-unified.md | xxd
00000000: 2d2d 2d0d 0a74 6974 6c65 3a20 4275 6773  ---..title: Bugs
                  ^^ ^^ CRLF

$ head -c 30 docs/workflows/bugsy.md | xxd
00000000: 2d2d 2d0a 7469 746c 653a 2042 7567 7379  ---.title: Bugsy
                  ^^ LF only
```

## Fix

Make the frontmatter regex CRLF-tolerant. Two edits in `readFrontmatter()`:

```js
// Before
const m = content.match(/^---\n([\s\S]*?)\n---\n?/);
...
for (const line of m[1].split('\n')) {

// After
const m = content.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
...
for (const line of m[1].split(/\r?\n/)) {
```

The `\r?` makes the carriage return optional in three places: after the opening `---`, before the closing `---`, and as a line separator inside the block. Files with pure LF (the script's own output, the stubs, and any unix-checkout file) still parse correctly because `\r?` matches zero or one `\r`.

No other regexes in the script need changes — `ensureWorkflowClaim()`'s `/^n8n_workflows:.*$/m` regex already works on CRLF (the `.` matches `\r` since `\r` is not the line terminator for `.`), and `insertOrReplace()`'s marker regex is anchored on the literal comment text which is the script's own LF output.

### Out of scope for this fix

- **Not adding `.gitattributes`.** That's a structural decision affecting line endings across the whole repo, deserves its own ADR, and isn't required to fix this bug. The regex tolerance alone makes the script work correctly regardless of whether files are CRLF or LF.
- **Not renormalizing existing CRLF files to LF.** Leaves the working tree as-is; the script tolerates either.
- **Not deduping the existing five stub files.** Those are untracked, and after the fix they should be deleted as part of verification (they're duplicates of the hand-written docs, not new content).

## Verification

1. **Pre-fix baseline.** Confirm the five stub files exist and the hand-written docs have proper `n8n_workflows:` claims (already verified above).
2. **Apply the regex fix.**
3. **Add diagnostic logging temporarily** — none needed; the bug surfaces directly in `git status`.
4. **Delete the five stubs** (they're untracked, no history to lose):
   ```bash
   rm docs/workflows/bugsy.md \
      docs/workflows/bugsy-rag-ingest.md \
      docs/workflows/bugsy-rag-query.md \
      docs/workflows/bugsy-job-board-fetcher.md \
      docs/workflows/bugsy-job-board-ui.md
   ```
5. **Run the generator:**
   ```bash
   node agent/n8n/scripts/generate-workflow-reference.mjs
   ```
6. **Confirm `git status` shows no new untracked `docs/workflows/*.md` files.** The expected modifications are: the existing hand-written docs may show date-line refreshes (`Auto-generated on YYYY-MM-DD`), nothing else.

## Regression test

This bug class would have been caught by a simple unit test on `readFrontmatter()` with a CRLF input. Future enhancement: add a small test script (e.g. `agent/n8n/scripts/__test__/`) that exercises the frontmatter parser with both LF and CRLF fixtures. Deferred — out of scope for this fix.

## Notes

- The hand-written docs that lost their claim status (`bugsy-unified.md`, `rag-ingest.md`, `rag-query.md`, `job-board.md`) were never *actually* corrupted by the bug — their frontmatter is intact, just unreadable to the buggy regex. The fix restores correct interpretation on Windows without touching the doc files at all.
- This is the second n8n / Node.js parser quirk hit in 24 hours; the previous was the `}}` greedy match in n8n's HTTP-body template parser (see [BUG-AGENT-001](BUG-AGENT-001-...) — archived). Pattern: when a script seems to work on one machine but produces ghost files on another, suspect line endings or template-parser greedy matches first.
