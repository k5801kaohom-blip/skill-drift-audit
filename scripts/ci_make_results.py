#!/usr/bin/env python3
"""Build a PASS result and a COACHED result from an emitted citizen-test template.

Used by CI to assert that the evaluator discriminates between verdicts rather than
merely running. Keeping the fixtures in a script rather than inline in the workflow
avoids the YAML block-scalar indentation trap that breaks heredocs in `run:` steps.

Usage:
    python ci_make_results.py <dir containing 公民測試_結果回報單.json>
"""

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: ci_make_results.py <out-dir>", file=sys.stderr)
        return 2

    out = Path(sys.argv[1])
    template = out / "公民測試_結果回報單.json"
    if not template.is_file():
        print(f"error: template not found: {template}", file=sys.stderr)
        return 2

    d = json.loads(template.read_text(encoding="utf-8"))
    d["tester_name"] = "ci"
    d["tester_role"] = "automated fixture"
    d["artifact_description"] = "ci fixture"
    d["date"] = "2026-01-01"
    d["validity"] = {k: True for k in d["validity"]}
    d["attempts"] = [{
        "attempt": 1,
        "command": "run the documented pipeline",
        "output": "completed",
        "exit_code": 0,
        "outcome": "success",
        "blocked_on": "",
    }]
    d["help_requests"] = []
    d["friction"] = []
    d["output_matches_source"] = True

    (out / "pass.json").write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")

    coached = json.loads(json.dumps(d))
    coached["help_requests"] = [{
        "at_step": "step 2",
        "needed": "someone to explain where the output goes",
    }]
    (out / "coached.json").write_text(
        json.dumps(coached, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"wrote {out/'pass.json'} and {out/'coached.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
