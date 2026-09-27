#!/usr/bin/env python3
"""Compare an installed skill against its source of truth, file by file.

A skill that has silently drifted behind its repository is the most expensive kind of
broken: the documentation describes behaviour the installed code does not have, and
nothing errors out to tell you. Comparing two directories takes a second.

Usage:
    python audit_skill_drift.py --installed DIR --reference DIR [--json OUT]

Exit codes:
    0  no drift
    1  drift found (missing, extra, or differing files)
    2  bad input
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path

IGNORE_DIRS = {"__pycache__", ".git", ".pytest_cache", "node_modules"}
IGNORE_SUFFIXES = {".pyc", ".pyo"}
IGNORE_PREFIXES = ("._", ".DS_Store")


def skip(path: Path) -> bool:
    if any(part in IGNORE_DIRS for part in path.parts):
        return True
    if path.suffix in IGNORE_SUFFIXES:
        return True
    return path.name.startswith(IGNORE_PREFIXES)


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def index(root: Path) -> dict:
    out = {}
    for p in sorted(root.rglob("*")):
        if p.is_dir() or skip(p.relative_to(root)):
            continue
        rel = p.relative_to(root)
        out[str(rel)] = digest(p)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Audit skill drift between two copies.")
    ap.add_argument("--installed", type=Path, required=True)
    ap.add_argument("--reference", type=Path, required=True,
                    help="the source of truth: a git checkout, the packaged skill, ...")
    ap.add_argument("--json", type=Path)
    args = ap.parse_args()

    for label, root in (("installed", args.installed), ("reference", args.reference)):
        if not root.is_dir():
            print(f"error: {label} directory not found: {root}", file=sys.stderr)
            return 2

    installed = index(args.installed)
    reference = index(args.reference)

    missing = sorted(set(reference) - set(installed))     # documented but not installed
    extra = sorted(set(installed) - set(reference))       # installed but not in the source
    differing = sorted(f for f in set(installed) & set(reference)
                       if installed[f] != reference[f])

    report = {
        "installed": str(args.installed),
        "reference": str(args.reference),
        "counts": {"installed": len(installed), "reference": len(reference),
                   "missing": len(missing), "extra": len(extra), "differing": len(differing)},
        "missing": missing,
        "extra": extra,
        "differing": differing,
        "verdict": "IN_SYNC" if not (missing or differing) else "DRIFTED",
    }

    print(f"installed: {args.installed}  ({len(installed)} files)")
    print(f"reference: {args.reference}  ({len(reference)} files)")
    print()
    if missing:
        print(f"MISSING from the installed copy ({len(missing)}) — these capabilities are absent:")
        for f in missing:
            print(f"  - {f}")
    if differing:
        print(f"DIFFERING content ({len(differing)}) — installed copy is a different version:")
        for f in differing:
            print(f"  ~ {f}")
    if extra:
        print(f"EXTRA in the installed copy ({len(extra)}) — local edits or leftovers:")
        for f in extra:
            print(f"  + {f}")
    if not (missing or differing):
        print("No drift: every file in the source of truth is present and identical.")

    print()
    print(f"VERDICT: {report['verdict']}")

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"report: {args.json}")

    return 1 if (missing or differing) else 0


if __name__ == "__main__":
    raise SystemExit(main())