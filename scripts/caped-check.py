#!/usr/bin/env python3
"""caped check — structural validation of ideas/ and changes/ files.

Checks (errors, exit 1):
  frontmatter — present, `name` and `summary` set, `name` == file stem
  sections    — Why / Context / Requirements / Decisions / Rejected
                alternatives / Provenance / Open questions all present
  spawned_from — if set, resolves to a live (ideas//changes/) or archived
                (Archives: trailer in git history) entity, renames stitched

Warnings (reported, exit unaffected):
  marker fullness — bold-lead bullets (`- **...**`) in enforced spec files
  without a [#<slug>] marker: a requirement someone forgot to mark

Output is English and every error carries its fix — same pattern as the hook.
No network, stdlib only.
"""
import re
import subprocess
import sys
from pathlib import Path

RS, FS = "\x1e", "\x1f"

REQUIRED_FRONTMATTER = ("name", "summary")
REQUIRED_SECTIONS = (
    "Why",
    "Context",
    "Requirements",
    "Decisions",
    "Rejected alternatives",
    "Provenance",
    "Open questions",
)
EMPTY_SPAWNED = {"", "-", "null", "none", "~"}


def run(args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


ROOT = Path(run(["git", "rev-parse", "--show-toplevel"]).strip())


def parse_frontmatter_text(text):
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    fm = {}
    for line in text[3:end].strip().splitlines():
        m = re.match(r"^(\w+):\s*(.*)$", line)
        if m:
            fm[m.group(1)] = m.group(2).strip()
    return fm


def known_entities():
    """Names that ever existed: live files, born/archived trailers, rename aliases."""
    log = run(["git", "log", f"--format={RS}%B"])
    born, archived = set(), set()
    for rec in log.split(RS):
        for m in re.finditer(r"^Idea:\s*(\S+)\s*$", rec, re.M):
            born.add(m.group(1))
        for m in re.finditer(r"^Archives:\s*(\S+)\s*$", rec, re.M):
            archived.add(m.group(1))
    alias = {}
    log = run(["git", "log", f"--format={RS}%H", "--name-status", "-M", "--", "ideas", "changes"])
    for rec in log.split(RS):
        for line in rec.split("\n"):
            if line.startswith("R"):
                parts = line.split("\t")
                if len(parts) == 3:
                    mo = re.match(r"(?:ideas|changes)/(.+)\.md$", parts[1])
                    mn = re.match(r"(?:ideas|changes)/(.+)\.md$", parts[2])
                    if mo and mn:
                        alias[mo.group(1)] = mn.group(1)
    live = {f.stem for d in ("ideas", "changes") for f in (ROOT / d).glob("*.md") if (ROOT / d).is_dir()}
    return live, born, archived, alias


def resolve(name, alias):
    seen = set()
    while name in alias and name not in seen:
        seen.add(name)
        name = alias[name]
    return name


def enforced_spec_files():
    reg = ROOT / "caped.registry"
    if not reg.exists():
        return []
    specs = []
    for line in reg.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 4 and parts[2] == "enforced":
            spec = ROOT / parts[3]
            if spec.is_file():
                specs.append(spec)
    return sorted(set(specs))


def main():
    errors, warnings = [], []
    live, born, archived, alias = known_entities()
    known = live | born | archived

    files = sorted(
        f for d in ("ideas", "changes") if (ROOT / d).is_dir() for f in (ROOT / d).glob("*.md")
    )
    for f in files:
        rel = f.relative_to(ROOT)
        text = f.read_text(encoding="utf-8")
        fm = parse_frontmatter_text(text)
        if fm is None:
            errors.append(
                f"{rel}: no frontmatter — the file must start with a ---/--- block "
                f"carrying at least name: and summary:"
            )
            continue
        for key in REQUIRED_FRONTMATTER:
            if not fm.get(key):
                errors.append(f"{rel}: frontmatter field '{key}' missing or empty — add '{key}: ...'")
        if fm.get("name") and fm["name"] != f.stem:
            errors.append(
                f"{rel}: frontmatter name '{fm['name']}' != file name '{f.stem}' — "
                f"rename the file or fix the field (renames are one commit: mv + name + referrers)"
            )
        spawned = fm.get("spawned_from", "")
        if spawned.lower() not in EMPTY_SPAWNED and resolve(spawned, alias) not in known:
            errors.append(
                f"{rel}: spawned_from '{spawned}' names no live or archived entity — "
                f"fix the reference or drop the field ('null' for a root idea)"
            )
        for section in REQUIRED_SECTIONS:
            if not re.search(rf"^## {re.escape(section)}\s*$", text, re.M):
                errors.append(
                    f"{rel}: section '{section}' missing — add '## {section}' "
                    f"(a fresh idea may leave Decisions empty, a rejected-alternatives list may be '—')"
                )

    for spec in enforced_spec_files():
        for i, line in enumerate(spec.read_text(encoding="utf-8").splitlines(), 1):
            if re.match(r"^\s*[-*]\s+\*\*", line) and "[#" not in line:
                warnings.append(
                    f"{spec.relative_to(ROOT)}:{i}: bold-lead bullet without a [#<slug>] marker — "
                    f"mark the requirement or reword it if it is prose"
                )

    for w in warnings:
        print(f"warning {w}")
    for e in errors:
        print(f"error {e}")
    print(f"caped check: {len(files)} file(s), {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
