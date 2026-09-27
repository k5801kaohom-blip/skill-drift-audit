# Drift and Contract Failure Modes

Concrete cases, each observed in real use. Read this when an audit reports drift and you
need to decide how much it matters.

## 1. The installed copy is an older generation

**Symptom.** A skill's documentation describes a workflow, but running it produces output
that lacks the promised capability. Nothing errors.

**Real case.** `screenshot-to-comic-slides` was installed before its editable-heading
pipeline existed. The repository held four scripts (`locate_titles.py`, `refine_titles.py`,
`overlay_editable_titles.py`, `validate_pptx.py`) and a full `Editable Headings` section.
The installed copy held three scripts and no such section. Decks produced from it had zero
editable text boxes, while the user believed titles were editable.

**Detection.** `audit_skill_drift.py` reports four `MISSING` files and a differing `SKILL.md`.

**Fix.** Re-install from the source of truth. Keep the old copy as a timestamped backup so
the difference can be inspected later.

**Lesson.** A capability that was never installed looks exactly like a capability that is
broken. Rule out drift before debugging behaviour.

## 2. The documentation names files that were never installed

**Symptom.** SKILL.md reads as complete, but an agent following it fails partway with a
missing-file error.

**Detection.** `check_skill_contract.py` extracts every `scripts/…`, `references/…`, and
`templates/…` path from SKILL.md and checks each against the tree.

## 3. Hardcoded assumptions about input names

**Symptom.** A pipeline that works on the author's sample data aborts on real data with an
unhelpful message such as `no images`.

**Real case.** Three title scripts defaulted to `--pattern "slide_*.png"`. The slide
generator actually writes `s1_cover.webp`, `s2_pain.webp`, … so the pipeline found nothing
and exited. The default silently encoded one naming convention as if it were universal.

**Detection.** Run the documented pipeline against the artifact the workflow actually
produces, not against a hand-prepared sample. A happy-path fixture will never expose this.

**Fix.** Accept every common extension by default and sort naturally; keep `--pattern` as an
opt-in filter.

## 4. A crop or viewport that hides part of the input

**Symptom.** Output is plausible but incomplete — text stops mid-word, a value is cut off.

**Real case.** A refinement pass upscaled only the left 72% of each slide before asking a
vision model for tight text boxes. Wide, centred headings lost their trailing characters
and the model returned truncated text (`病灶解剖：重複的 a:la` instead of
`病灶解剖：重複的 a:latin`). Every structural check still passed.

**Detection.** Read the produced content back and compare it with the source. Structural
validation cannot catch a title that is simply missing its last two characters.

**Fix.** Derive the viewport from the first-pass boxes instead of a fixed constant, and fall
back to the longer reading when the refined text is a prefix of it.

## 5. A default that contradicts the value you set

**Symptom.** The file opens, but the consuming application lays it out wrongly.

**Real case.** `python-pptx`'s default template declares `sldSz type="screen4x3"`. Assigning
`slide_width` and `slide_height` updates `cx`/`cy` but leaves the attribute stale, so a 16:9
deck announced itself as 4:3.

**Detection.** Assert the invariant in a validator, not only in the generator. The generator
was fixed once the validator could see the defect.

**Fix.** Set the matching type whenever the size is set, and add a consistency check so the
defect cannot ship again.

## Triage order

1. **Drift** — is the installed copy the code you think it is?
2. **Contract** — does the documentation's promise match the files?
3. **Real input** — does it run on the artifact the workflow actually produces?
4. **Content** — does the output say what the source said?
5. **Invariants** — would a validator have caught this?