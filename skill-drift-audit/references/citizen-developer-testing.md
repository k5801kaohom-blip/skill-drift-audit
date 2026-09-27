# Citizen Developer Testing

Read this when a skill must be proven usable by someone who did not build it. The static
audits in the main workflow prove the files are present and consistent. They cannot prove a
person who has never seen the skill can get a correct result from it.

A **citizen developer** here is a competent practitioner who works with the artifact type but
did not write the skill and is not a professional tester. They follow the documentation the
way a real user would and report what actually happened.

## Why this test is different

The author of a skill cannot perform this test. Authors supply knowledge the documentation
never wrote down — which flag matters, which sample file to use, which step to skip. That
unwritten knowledge is exactly what a real user lacks, so an author's clean run proves
nothing about usability.

> The test is only valid if the citizen developer could complete it using **nothing but the
> shipped documentation and their own real artifact**.

## The four norms

### 1. No internals, no coaching

Give the tester the task sheet and the artifact type. Do not explain the pipeline, do not
name scripts, do not suggest flags, do not answer "how do I…" during the run.

If the tester gets stuck and asks for help, record it as **friction** and let them continue.
A run completed only after coaching is marked `COACHED` and does not count as a pass — but the
point where coaching was needed is the most valuable finding in the whole exercise.

### 2. Their own real artifact

The tester must bring a real file from their own work, not the sample bundled with the skill.
Sample fixtures are authored to work; they never expose hardcoded assumptions about input
names, formats, or sizes. This is precisely how a pipeline that passed every internal check
still aborts with `no images` on real data.

### 3. Raw output kept, verbatim

The tester records the exact commands run, the exact messages printed, and the exit code. No
paraphrasing, no "it mostly worked". A smoothed-over report cannot be re-checked, and the
failure detail is usually in the wording the tester would have tidied away.

### 4. Friction is a finding, not a complaint

A run that succeeds but takes six attempts, or needs a guess about a path, is a **pass with
friction**. Record it. Friction is the leading indicator of the next drift report.

## Verification checklist

Run this against the returned result sheet. Any `no` makes the result `INVALID`.

| # | Check | Why it matters |
| --- | --- | --- |
| 1 | Tester is not the skill author | Authors carry unwritten knowledge |
| 2 | Tester had no access to skill internals | Reading the code substitutes for documentation |
| 3 | Task sheet was used unmodified | A rewritten sheet tests a different skill |
| 4 | Artifact came from the tester's own work | Fixtures hide input assumptions |
| 5 | Exact commands and messages recorded | Paraphrase cannot be re-checked |
| 6 | Exit code recorded | "It worked" without a code is unverifiable |
| 7 | Help requests logged with the blocking step | A coached run must be labelled |
| 8 | Output compared against the source artifact | Completion is not correctness |

Then judge the outcome:

| Outcome | Condition |
| --- | --- |
| `PASS` | All 8 checks pass, task completed, output matches the source artifact |
| `PASS_WITH_FRICTION` | All 8 checks pass, task completed, but the tester needed retries or guesses |
| `COACHED` | Completed only after the tester received help beyond the documentation |
| `FAIL` | Blocked, or output does not match the source artifact |
| `INVALID` | Any of the 8 checks fails |

## Acting on results

- **`INVALID`** — fix the test, not the skill. Re-run with a different tester or artifact.
- **`COACHED`** — the documentation is incomplete at the point help was needed. Add that step
  to SKILL.md, then re-run with a fresh tester.
- **`PASS_WITH_FRICTION`** — record the friction. If two testers hit the same friction, treat
  it as a documentation defect.
- **`FAIL`** — reproduce it yourself, then follow the failure modes reference.
- **`PASS`** — record the tester, artifact type, and date. This is the evidence that the
  skill works for someone who is not its author.

## Reporting

State the tester's relationship to the skill, the artifact type, the outcome, and the friction.
Never report a coached or invalid run as a pass. For example:

> Tester: field engineer, no prior exposure to the skill. Artifact: their own 15-page deck
> export. Outcome: `PASS_WITH_FRICTION`. Completed on the second attempt; the first attempt
> failed because the documentation never states which directory holds the generated images.
> Friction recorded; documentation updated.