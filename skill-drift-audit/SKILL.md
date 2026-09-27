---
name: skill-drift-audit
description: 觸發詞：技能稽核、技能版本、技能漂移、技能檢查、技能測試、公民開發者測試、非開發者測試、倉庫同步確認、技能失效、技能行為不符。Audit whether an installed skill is the same code and documentation as its source of truth, whether its SKILL.md promises files that actually exist, whether it is usable by someone who did not build it, and whether a fresh clone can install and use it. Use when a skill behaves differently from its documentation, when a skill was installed in an earlier session and may be an older generation, before relying on a skill for an important deliverable, after pulling or pushing a skill repository, when a repository's commit and remote sync state must be confirmed, when a workflow "does not work" and a stale install could be the cause rather than a bug, when a skill must be validated by a non-developer, a citizen developer, or an end user rather than its author, or when a skill repository needs CI that verifies it on every push.
metadata:
  alias_zh-TW: 技能版本稽核
  short_alias_zh-TW: 技能稽核
  keywords_zh-TW: 技能稽核、技能版本稽核、技能版本、技能漂移、技能檢查、技能測試、公民開發者測試、非開發者測試、倉庫同步確認、技能失效、技能行為不符
---

# Skill Drift Audit

## Goal

Answer two questions before trusting a skill:

1. **Drift** — is the installed copy the same bytes as the source of truth?
2. **Contract** — does SKILL.md name resources that are actually present and runnable?

A skill that has silently fallen behind its repository is the most expensive kind of broken.
The documentation describes behaviour the installed code does not have, and nothing errors
out to say so. A capability that was never installed looks exactly like a capability that is
broken, so rule out drift before debugging behaviour.

## When to Run This

- A skill's output does not match what its documentation promises.
- A skill was installed in an earlier session and may be an older generation.
- Before relying on a skill for an important deliverable.
- After pulling, pushing, or re-packaging a skill repository.
- The user asks whether a repository's commits and remote are in sync.

## Workflow

### 1. Establish the source of truth

Drift is meaningless without a reference. Use, in order of preference:

1. A git checkout of the skill's repository — the strongest reference.
2. A packaged `.skill` or ZIP archive.
3. Another machine's copy.

If a git checkout exists, confirm it is itself current before treating it as truth. A stale
checkout compared against an installed copy proves nothing:

```bash
cd <repo>
git status -sb
git fetch origin
echo "local : $(git rev-parse HEAD)"
echo "remote: $(git rev-parse origin/main)"
echo "behind: $(git rev-list --count HEAD..origin/main)"   # 0 means in sync
```

Then verify the remote actually carries the newest content, not merely the newest commit id:

```bash
gh api repos/<owner>/<repo>/contents/<path-to-SKILL.md> --jq '.content' \
  | base64 -d | grep -c '<newest section title>'
```

A clean `git status` plus matching commit ids still does not prove the remote has the content
you expect. Read a distinctive string back out of the remote file.

### 2. Audit drift

```bash
python scripts/audit_skill_drift.py \
  --installed /home/ubuntu/skills/<skill-name> \
  --reference /home/ubuntu/repos/<repo>/<skill-name> \
  --json drift_report.json
```

Exit code 0 means no drift; 1 means missing, differing, or extra files. `EXTRA` files alone
are usually harmless local additions, but `MISSING` and `DIFFERING` mean the installed copy
is a different version.

### 3. Audit the contract

```bash
python scripts/check_skill_contract.py --skill /home/ubuntu/skills/<skill-name> \
  --json contract_report.json
```

This extracts every `scripts/…`, `references/…`, and `templates/…` path named in SKILL.md,
checks each against the tree, compiles every documented Python file, and flags leftover
scaffolding such as `example.py` or an unresolved placeholder marker.

### 4. Resolve drift by re-installing, never by hand-editing

Re-install from the source of truth so the copy stays reproducible. Most skill repositories
ship an `install.sh` that backs up the existing copy with a timestamp:

```bash
cd <repo> && ./install.sh
```

If there is no installer, move the old copy aside and copy the reference tree:

```bash
mv /home/ubuntu/skills/<name> /home/ubuntu/skills/<name>.backup.$(date +%Y%m%d%H%M%S)
cp -R <repo>/<name> /home/ubuntu/skills/<name>
find /home/ubuntu/skills/<name> -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null
```

Re-run both audits afterwards; both must come back clean.

### 5. Prove the capability, do not assume it

Drift and contract audits are static. They prove the files are present, not that the pipeline
works. Run the skill's documented pipeline once against a real artifact and inspect the
output. See `references/drift-failure-modes.md` for the failures that appear only at this
stage — hardcoded input names, crops that hide part of the input, defaults that contradict
the values you set.

For Office deliverables, finish with
`/home/ubuntu/skills/office-delivery-gate/scripts/delivery_gate.py <file>`, which validates,
repairs, re-validates, and confirms content survived.

### 6. Prove it works for someone who did not build it

Steps 1–5 are self-checks. A skill can pass all of them and still be unusable by anyone else,
because the author supplies knowledge the documentation never wrote down — which flag matters,
which sample file to use, which step to skip. That unwritten knowledge is exactly what a real
user lacks.

Run a **citizen developer test**: a competent practitioner who works with the artifact type,
did not write the skill, and is not a professional tester follows the shipped documentation
with their own real file.

```bash
python scripts/citizen_test_kit.py --emit --skill-name <name> \
  --artifact-type "<a real artifact of the relevant type>" --out ./citizen_test
```

Issue the task sheet. Do not explain the pipeline, name scripts, or suggest flags. Evaluate
what comes back:

```bash
python scripts/citizen_test_kit.py --evaluate --result ./citizen_test/公民測試_結果回報單.json
```

The four norms, the eight validity checks, and the five verdicts are in
`references/citizen-developer-testing.md`. Read it before issuing a task sheet.

The three things that most often invalidate a run:

- the tester used the skill's own sample file instead of their own artifact — fixtures are
  authored to work and never expose hardcoded input assumptions;
- the tester read the source code, which substitutes for the documentation being tested;
- the tester was coached through a step — a coached run is not a pass, but the point where
  help was needed is the single most valuable finding, so record it rather than discard it.

Report a coached or invalid run honestly. Never present one as a pass.

### 7. Automate the audit so it cannot be skipped

Everything above depends on someone remembering to run it. Wire it into CI so a clean clone
proves the repository works, on every push.

The stage that matters most is **clone reproducibility**: CI is the only place the
"SKILL.md documents a file that was never committed" failure is caught reliably, because CI
starts from a clean clone while an author's machine still has the file.

Four stages belong in CI — contract, structure, content equality, clone reproducibility — plus
one assertion most people omit: **prove the checker discriminates**. Pair every positive
assertion with the negative case it separates from, or the check manufactures confidence
instead of removing risk.

`references/ci-integration.md` covers the workflow shape, the two traps that break a first
attempt (the pull-request merge-commit trap, and heredocs breaking the YAML block scalar), and
why a CI script must not depend on a separately installed skill.

Keep the script usable on a developer machine by making CI differences explicit flags
(`--offline`, `--skip-clone`, `--api`) rather than workflow-only branches.

## Reporting Drift

Report the specific files, not a general impression. Name what is missing and what the
consequence is. For example:

> The installed skill holds 3 scripts; the repository holds 7. The four missing scripts are
> the editable-heading pipeline, and SKILL.md has no `Editable Headings` section, so decks
> produced from the installed copy had zero editable text boxes.

Distinguish the three severities:

| Severity | Meaning | Action |
| --- | --- | --- |
| `MISSING` | Documented capability absent from the install | Re-install before using the skill |
| `DIFFERING` | Installed file is a different version | Re-install; compare the backup if behaviour changed |
| `EXTRA` | Present locally, absent upstream | Usually harmless; confirm it is not an obsolete file masking a renamed one |

## Bundled Resources

- `scripts/audit_skill_drift.py` — compare an installed skill against a reference copy, file by file.
- `scripts/check_skill_contract.py` — verify SKILL.md's documented resources exist, compile, and are executable.
- `scripts/citizen_test_kit.py` — emit a citizen-developer task sheet and judge the returned result.
- `references/drift-failure-modes.md` — five concrete drift and contract failures, with detection and fix.
- `references/citizen-developer-testing.md` — the four norms, eight validity checks, and five verdicts for non-developer testing.
- `references/ci-integration.md` — workflow shape, the pull-request and block-scalar traps, and proving the checker discriminates.
- `templates/audit_report.example.json` — the JSON shape both scripts emit.
