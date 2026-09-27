#!/usr/bin/env python3
"""Emit a citizen-developer test kit, and evaluate the result that comes back.

Two modes:

    --emit      write a plain-language task sheet and result sheet for a tester who did not
                build the skill
    --evaluate  read the returned result sheet, apply the eight validity checks, and print a
                verdict

The kit deliberately contains no script names, no flags, and no internals: the tester must be
able to succeed using the shipped documentation alone. Anything else invalidates the test.

Usage:
    python citizen_test_kit.py --emit --skill-name NAME --out DIR [--artifact-type TEXT]
    python citizen_test_kit.py --evaluate --result FILE [--json OUT]

Exit codes:
    0  emit succeeded, or evaluation returned PASS / PASS_WITH_FRICTION
    1  evaluation returned COACHED / FAIL / INVALID
    2  bad input
"""

import argparse
import json
import sys
from datetime import date
from pathlib import Path

VALIDITY_CHECKS = [
    ("tester_is_not_author", "The tester did not build or write the skill"),
    ("no_internals_access", "The tester did not read the skill's source files"),
    ("task_sheet_unmodified", "The task sheet was used as issued, not rewritten"),
    ("own_real_artifact", "The artifact came from the tester's own work, not a bundled sample"),
    ("raw_commands_recorded", "The exact commands run were recorded verbatim"),
    ("exit_code_recorded", "The exit code of each command was recorded"),
    ("help_requests_logged", "Every request for help was logged with the step that blocked"),
    ("output_compared_to_source", "The output was compared against the source artifact"),
]

TASK_SHEET = """# 公民開發者測試 — 任務單

你拿到的是一個你沒有參與開發的技能。請依照技能隨附的文件操作，完成下面的任務。
**測試過程中請不要閱讀技能的原始程式碼**，也不要詢問開發者「這一步該怎麼做」。
你需要的所有資訊都應該在文件裡。如果文件沒有寫，那本身就是我們要的答案。

## 你的任務

1. 用你自己的**真實檔案**（不要用範例檔）跑一次這個技能的完整流程。
2. 流程跑完後，把產出檔案打開，確認內容與你的原始檔案一致。
3. 記錄整個過程中所有讓你卡住、需要猜測、或來回嘗試的地方。

## 規則

- 用你自己的檔案。範例檔是被設計成會成功的，測不出真正的問題。
- 每一道指令都**原文照抄**記下來，包含畫面上印出的完整訊息與結束碼。
- 如果你卡住了，可以求助，但請**記下你卡在哪一步、你需要什麼才過得去**。
  受過協助才完成的測試，我們會另外標記，不會當成通過。
- 不順利的地方請照實寫。順利但很麻煩，也是重要的發現。

## 結果回報單

請把下面的欄位填完，存成 JSON 後交回。

```json
{
  "tester_name": "",
  "tester_role": "你平常做什麼工作、和這個技能的關係",
  "artifact_description": "你用的真實檔案是什麼（類型、頁數或大小）",
  "date": "",

  "validity": {
    "tester_is_not_author": true,
    "no_internals_access": true,
    "task_sheet_unmodified": true,
    "own_real_artifact": true,
    "raw_commands_recorded": true,
    "exit_code_recorded": true,
    "help_requests_logged": true,
    "output_compared_to_source": true
  },

  "attempts": [
    {
      "attempt": 1,
      "command": "你下的指令，原文照抄",
      "output": "畫面上印出的訊息，原文照抄",
      "exit_code": 0,
      "outcome": "success 或 blocked",
      "blocked_on": "如果卡住，卡在哪一步"
    }
  ],

  "help_requests": [
    { "at_step": "你在做什麼的時候", "needed": "你需要什麼才過得去" }
  ],

  "friction": [
    "任何讓你卡住、需要猜測、或來回嘗試的地方"
  ],

  "output_matches_source": true,
  "notes": "任何其他觀察"
}
```

## 我們會怎麼判斷

- 八項有效性檢查全部通過，任務完成且產出與原始檔案一致 → **通過**
- 同上，但過程中需要重試或猜測 → **通過（有摩擦）**，摩擦會記錄下來
- 只有接受額外協助才完成 → **受協助**，不算通過，但我們會補強文件
- 卡住，或產出與原始檔案不一致 → **失敗**
- 八項檢查有任何一項不通過 → **無效**，我們會重測

> 請注意：**「無效」是測試的問題，不是你的問題。** 它代表我們選錯了測試者或測試素材。
"""


def emit(skill_name: str, out_dir: Path, artifact_type: str) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    sheet = out_dir / "公民測試_任務單.md"
    sheet.write_text(TASK_SHEET, encoding="utf-8")

    template = {
        "_comment": "由公民開發者填寫後交回，交給 citizen_test_kit.py --evaluate 判定",
        "skill_under_test": skill_name,
        "artifact_type_hint": artifact_type,
        "issued": date.today().isoformat(),
        "tester_name": "",
        "tester_role": "",
        "artifact_description": "",
        "date": "",
        "validity": {key: None for key, _ in VALIDITY_CHECKS},
        "attempts": [
            {"attempt": 1, "command": "", "output": "", "exit_code": None,
             "outcome": "", "blocked_on": ""}
        ],
        "help_requests": [{"at_step": "", "needed": ""}],
        "friction": [],
        "output_matches_source": None,
        "notes": "",
    }
    result_file = out_dir / "公民測試_結果回報單.json"
    result_file.write_text(json.dumps(template, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"skill under test : {skill_name}")
    print(f"task sheet       : {sheet}")
    print(f"result sheet     : {result_file}")
    print()
    print("Issue the task sheet to a tester who did not build this skill.")
    print("Do not explain the pipeline, name scripts, or suggest flags.")
    print(f"Evaluate the returned result with:  --evaluate --result {result_file.name}")
    return 0


def evaluate(result_path: Path, json_out: Path | None) -> int:
    data = json.loads(result_path.read_text(encoding="utf-8"))
    problems = []

    validity = data.get("validity") or {}
    failed = [key for key, _ in VALIDITY_CHECKS if validity.get(key) is not True]
    for key, label in VALIDITY_CHECKS:
        if validity.get(key) is not True:
            problems.append(f"validity check failed: {key} — {label}")

    attempts = data.get("attempts") or []
    if not attempts:
        problems.append("no attempts recorded")

    for a in attempts:
        if not (a.get("command") or "").strip():
            problems.append(f"attempt {a.get('attempt')}: command not recorded")
        if not (a.get("output") or "").strip():
            problems.append(f"attempt {a.get('attempt')}: output not recorded")
        if a.get("exit_code") is None:
            problems.append(f"attempt {a.get('attempt')}: exit code not recorded")

    help_requests = [h for h in (data.get("help_requests") or [])
                     if (h.get("at_step") or "").strip() or (h.get("needed") or "").strip()]
    friction = [f for f in (data.get("friction") or []) if str(f).strip()]
    completed = any((a.get("outcome") or "").strip().lower() == "success" for a in attempts)
    matches = data.get("output_matches_source") is True

    if failed:
        verdict = "INVALID"
    elif not completed or not matches:
        verdict = "FAIL"
    elif help_requests:
        verdict = "COACHED"
    elif len(attempts) > 1 or friction:
        verdict = "PASS_WITH_FRICTION"
    else:
        verdict = "PASS"

    report = {
        "skill_under_test": data.get("skill_under_test"),
        "tester": data.get("tester_name"),
        "tester_role": data.get("tester_role"),
        "artifact": data.get("artifact_description"),
        "attempts": len(attempts),
        "help_requests": len(help_requests),
        "friction_count": len(friction),
        "validity_failures": failed,
        "problems": problems,
        "verdict": verdict,
    }

    print(f"skill under test : {report['skill_under_test']}")
    print(f"tester           : {report['tester']}  ({report['tester_role']})")
    print(f"artifact         : {report['artifact']}")
    print(f"attempts         : {len(attempts)}   help requests: {len(help_requests)}"
          f"   friction items: {len(friction)}")
    print()
    print("validity checks:")
    for key, label in VALIDITY_CHECKS:
        mark = "ok  " if validity.get(key) is True else "FAIL"
        print(f"  [{mark}] {key}")
    print()
    if problems:
        print(f"problems ({len(problems)}):")
        for p in problems:
            print(f"  - {p}")
        print()
    if friction:
        print(f"friction recorded ({len(friction)}) — treat repeated friction as a documentation defect:")
        for f in friction:
            print(f"  * {f}")
        print()
    print(f"VERDICT: {verdict}")
    if verdict == "INVALID":
        print("  Fix the test, not the skill: re-run with a different tester or artifact.")
    elif verdict == "COACHED":
        print("  Add the step that needed help to the documentation, then re-run with a fresh tester.")
    elif verdict == "PASS_WITH_FRICTION":
        print("  Record the friction; two testers hitting it means a documentation defect.")
    elif verdict == "FAIL":
        print("  Reproduce it, then follow references/drift-failure-modes.md.")
    else:
        print("  Record tester, artifact type, and date as evidence the skill works unaided.")

    if json_out:
        json_out.parent.mkdir(parents=True, exist_ok=True)
        json_out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"report: {json_out}")

    return 0 if verdict in ("PASS", "PASS_WITH_FRICTION") else 1


def main() -> int:
    ap = argparse.ArgumentParser(description="Citizen-developer test kit and evaluator.")
    ap.add_argument("--emit", action="store_true", help="write the task sheet and result sheet")
    ap.add_argument("--evaluate", action="store_true", help="judge a returned result sheet")
    ap.add_argument("--skill-name", default="(unnamed skill)")
    ap.add_argument("--artifact-type", default="(any real artifact of the relevant type)")
    ap.add_argument("--out", type=Path, default=Path("."))
    ap.add_argument("--result", type=Path)
    ap.add_argument("--json", type=Path)
    args = ap.parse_args()

    if args.emit and args.evaluate:
        print("error: choose one of --emit or --evaluate", file=sys.stderr)
        return 2
    if args.evaluate:
        if not args.result or not args.result.is_file():
            print(f"error: result file not found: {args.result}", file=sys.stderr)
            return 2
        return evaluate(args.result, args.json)
    if args.emit:
        return emit(args.skill_name, args.out, args.artifact_type)

    print("error: choose --emit or --evaluate", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())