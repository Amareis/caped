#!/usr/bin/env python3
"""caped check — structural validation of ideas/ and changes/ files.

Checks (errors, exit 1):
  frontmatter — present, `name` and `summary` set, `name` == file stem
  sections    — Why / Context / Requirements / Decisions / Rejected
                alternatives / Provenance / Open questions all present
  spawned_from — if set, resolves to a live (ideas//changes/) or archived
                (Archives: trailer in git history) entity, renames stitched
  req-form    — enforced spec files: a '## Requirements' section must exist;
                inside it every bullet starts with a [#<slug>] marker
                ('- [#slug[ attrs]] Statement...'); a marker bullet outside
                the section is a misplaced definition
  entity-req-form — ideas/changes: inside '## Requirements' only bullets
                ('- ...'), never numbered lists; a [#<slug>] marker is
                optional but must lead the bullet when present

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

REQ_SECTION = "Requirements"
BULLET_RE = re.compile(r"^[-*]\s+")
REQ_DEF_RE = re.compile(r"^[-*]\s+\[#[a-z0-9][a-z0-9-]*(( (no-test|dump))*)\]\s")
H2_RE = re.compile(r"^## (?!#)(.*\S)\s*$")


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


def check_req_form(spec, rel, errors):
    lines = spec.read_text(encoding="utf-8").splitlines()
    in_req = False
    found = False
    for i, line in enumerate(lines, 1):
        h2 = H2_RE.match(line)
        if h2:
            in_req = h2.group(1) == REQ_SECTION
            found = found or in_req
            continue
        if in_req:
            if BULLET_RE.match(line) and not REQ_DEF_RE.match(line):
                errors.append(
                    f"{rel}:{i}: requirement bullet without a leading [#<slug>] marker — "
                    f"the form is '- [#<slug>] Statement...' (slug first, attributes inside "
                    f"the brackets); plain prose inside the section needs no marker"
                )
        elif REQ_DEF_RE.match(line):
            errors.append(
                f"{rel}:{i}: requirement definition outside '## {REQ_SECTION}' — "
                f"move the bullet into the section (### subgroups inside it are fine)"
            )
    if not found:
        errors.append(
            f"{rel}: no '## {REQ_SECTION}' section — requirements of an enforced cap live "
            f"only there (fixed literal, never translated)"
        )


def check_entity_req_form(f, rel, errors):
    """Ideas/changes: Requirements bullets only; an optional marker leads the bullet."""
    lines = f.read_text(encoding="utf-8").splitlines()
    in_req = False
    for i, line in enumerate(lines, 1):
        h2 = H2_RE.match(line)
        if h2:
            in_req = h2.group(1) == REQ_SECTION
            continue
        if not in_req:
            continue
        if re.match(r"^\s*\d+\.\s", line):
            errors.append(
                f"{rel}:{i}: numbered requirement in an idea/change — use bullets "
                f"('- ...'); requirements here are ephemeral, a slug is optional "
                f"but must lead the bullet when present"
            )
        elif BULLET_RE.match(line) and re.search(r"\[#[a-z0-9][a-z0-9-]*\]", re.sub(r"`[^`]*`", "", line)) and not REQ_DEF_RE.match(line):
            errors.append(
                f"{rel}:{i}: a [#<slug>] marker in an idea/change requirement must lead "
                f"the bullet ('- [#<slug>] ...') or be dropped — mid-text markers break the index"
            )


def main():
    errors = []
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
        check_entity_req_form(f, rel, errors)

    for spec in enforced_spec_files():
        check_req_form(spec, spec.relative_to(ROOT), errors)

    for e in errors:
        print(f"error {e}")
    print(f"caped check: {len(files)} file(s), {len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
