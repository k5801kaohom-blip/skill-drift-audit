# CI Integration

Read this when a skill repository should verify itself on every push instead of relying on
someone remembering to run the check.

## What belongs in CI, and why

A skill repository has one failure mode that a normal test suite does not catch: **SKILL.md
is a promise the repository cannot keep on its own**. It names scripts and references the
agent will try to run. If one of those files was never committed, the skill looks complete,
the contract check passes locally on the author's machine (which still has the file), and
everyone who clones it gets a skill that documents a pipeline it does not contain.

CI is the only place this is caught reliably, because CI starts from a clean clone.

## The four stages

| Stage | Question | Fails when |
| --- | --- | --- |
| Contract | Does every documented resource exist, compile, and run? | SKILL.md names a file that is missing |
| Structure | Is the frontmatter valid and is SKILL.md within budget? | `name` does not match the directory; SKILL.md drifts past 500 lines |
| Content equality | Does the remote carry the same bytes as the working tree? | A change was committed in one place and not the other |
| Clone reproducibility | Can a fresh clone install and pass its own contract check? | The install path depends on files that are not committed |

The last stage is the one that matters most, and the one most often skipped. It is the only
stage that tests what a consumer actually experiences.

## Events worth wiring

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:
  schedule:
    - cron: "0 1 * * 1"     # weekly
```

The weekly run catches drift that no push caused — a file deleted on the remote, or a
dependency of the checks disappearing.

## The pull_request trap

On a `pull_request` event the checked-out `HEAD` is a **merge commit**, not `origin/main`.
A verification script that asserts `HEAD == origin/main` will therefore report a false failure
on every pull request.

Either skip the sync stages on pull requests, or run them offline:

```yaml
run: |
  if [ "${{ github.event_name }}" = "push" ]; then
    ./verify_sync.sh --json verify-report.json
  else
    ./verify_sync.sh --offline --json verify-report.json
  fi
```

Make this a flag on the script (`--offline`, `--skip-clone`) rather than a workflow-only
special case, so the same script stays usable on a developer machine.

## The YAML block-scalar trap

Inline heredocs inside a `run:` step break the YAML block scalar when their content is not
indented to the step's indentation level:

```yaml
      - name: Build fixtures
        run: |
          python3 - <<'PY'
import json          # <-- column 0 ends the block scalar here
          PY
```

The parser then reports `could not find expected ':'` at a line far below the real cause.
**Put helper scripts in `scripts/` and call them by path.** They become locally testable,
which is how you find the failing assertion before pushing rather than from a CI log.

## Do not depend on a separately installed skill

A CI runner has the repository and nothing else. If the verification script calls a tool from
another skill (`skill-creator`'s validator, for example), that stage fails off-sandbox. Inline
what you need, or vendor it into the repository.

The same applies to absolute sandbox paths and to authenticated CLIs. Gate anything requiring
credentials behind an explicit opt-in flag (`--api`) so the default path runs unauthenticated.

## Prove the checker discriminates

A check that always passes is worse than no check, because it manufactures confidence. Assert
the negative case explicitly:

```yaml
# A coached result must exit non-zero — this proves the evaluator discriminates
# rather than merely runs.
set +e
python3 "$KIT" --evaluate --result "$OUT/coached.json" > "$OUT/coached.out" 2>&1
RC=$?
set -e
test "$RC" -eq 1 || { echo "expected exit 1, got $RC"; cat "$OUT/coached.out"; exit 1; }
grep -q "VERDICT: COACHED" "$OUT/coached.out"
```

Pair every positive assertion with the negative case it is supposed to separate from.

## Machine-readable output

Have the script emit JSON (`--json report.json`) and render the summary from that file rather
than from stdout. The job summary then stays readable, and the same report can be uploaded as
an artifact for later inspection.

```yaml
      - name: Summary
        if: always()
        run: |
          echo "## Repository verification" >> "$GITHUB_STEP_SUMMARY"
          python3 scripts/ci_summary.py verify-report.json >> "$GITHUB_STEP_SUMMARY"
```

`if: always()` matters: when the verification step fails, the summary is exactly what you need
to read.
