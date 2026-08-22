#!/usr/bin/env python3
"""Retroactive change-classification experiment.

Classifies every commit in a range by:
  - declared intent guessed from the subject (wip / internal / contract-ish)
  - what it actually touched (feature code, tests, specs/docs)

The interesting output is the "suspicious" bucket: commits that look like
behavior changes (feature code touched, contract-ish subject) but touched
neither tests nor any spec/docs — those would have been forced to declare
`Behavior: internal|contract` by the proposed commit-msg hook.

Read-only: only runs `git log`/`git show`.
"""

import re
import subprocess
import sys
from dataclasses import dataclass, field

SINCE = sys.argv[1] if len(sys.argv) > 1 else "2025-11-01"

WIP_RE = re.compile(
    r"^(wip|fix(e[sd])?|fixes|fixes for.*|fmt|clippy|fix warns?|warns|tests?|"
    r"tests? (better|working)|some fixes|fix$|all$|clean|cleanup|refac$|"
    r"fix compile|fixed.*warns?|мелоч|правки)\b",
    re.IGNORECASE,
)
CONTRACTISH_RE = re.compile(
    r"^(feat|add|support|implement|new\b|веб|web\b|vk\b|вк\b|feed|moderation|"
    r"digest|agent|ingress|pipeline|submission|recommendations|web-version)",
    re.IGNORECASE,
)


@dataclass
class Commit:
    sha: str
    date: str
    subject: str
    files: list[str] = field(default_factory=list)

    @property
    def feature_code(self) -> set[str]:
        out = set()
        for f in self.files:
            m = re.match(r"src/features/([^/]+)/.*\.rs$", f)
            if m:
                out.add(m.group(1))
            elif re.match(r"src/(app|entities|platform|ingress)/.*\.rs$", f):
                out.add(f.split("/")[1])
        return out

    @property
    def touches_tests(self) -> bool:
        return any(f.startswith("tests/") for f in self.files)

    @property
    def touches_specs(self) -> bool:
        return any(
            f.startswith(("openspec/", "docs/", "AGENTS.md")) for f in self.files
        )

    @property
    def guess(self) -> str:
        if WIP_RE.match(self.subject):
            return "wip"
        if CONTRACTISH_RE.match(self.subject):
            return "contract-ish"
        return "internal-ish"


def main() -> None:
    log = subprocess.run(
        ["git", "log", f"--since={SINCE}", "--format=%H%x1f%ad%x1f%s", "--date=short"],
        capture_output=True, text=True, check=True,
    ).stdout
    commits: list[Commit] = []
    for line in log.splitlines():
        sha, date, subject = line.split("\x1f")
        files = subprocess.run(
            ["git", "show", "--format=", "--name-only", sha],
            capture_output=True, text=True, check=True,
        ).stdout.split()
        commits.append(Commit(sha=sha[:8], date=date, subject=subject, files=files))

    buckets: dict[str, list[Commit]] = {
        "wip": [], "internal_ok": [], "contract_with_spec_or_tests": [],
        "SUSPICIOUS_undeclared_contract": [], "no_feature_code": [],
    }
    for c in commits:
        if not c.feature_code:
            buckets["no_feature_code"].append(c)
        elif c.guess == "wip":
            buckets["wip"].append(c)
        elif c.guess == "contract-ish" and (c.touches_tests or c.touches_specs):
            buckets["contract_with_spec_or_tests"].append(c)
        elif c.guess == "contract-ish":
            buckets["SUSPICIOUS_undeclared_contract"].append(c)
        else:
            buckets["internal_ok"].append(c)

    total = len(commits)
    print(f"since {SINCE}: {total} commits\n")
    for name, items in buckets.items():
        print(f"{name:36s} {len(items):4d}  ({100 * len(items) / total:.0f}%)")

    susp = buckets["SUSPICIOUS_undeclared_contract"]
    print(f"\n--- suspicious sample (up to 40 of {len(susp)}) ---")
    for c in susp[:40]:
        feats = ",".join(sorted(c.feature_code))
        print(f"{c.date} {c.sha} [{feats}] {c.subject[:100]}")


if __name__ == "__main__":
    main()
