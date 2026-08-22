#!/usr/bin/env python3
"""caped render — derived views of the tracker, printed to stdout.

Views:
  plan     — in-work changes (with last-commit age, stalled marked) and ideas
             from frontmatter, ideas grouped by priority
  history  — the change archive reconstructed from git trailers (Idea: born,
             Archives: archived) with dates, commits and summaries
  coverage — tracked files vs caped.registry (enforced/legacy/declared/free,
             longest prefix wins)

Default is read-only: nothing is written. `--write` materialises the views
into .caped/ (plan.md, history.md, coverage.txt), `--clean` removes .caped/.
"""
import re
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

RS, FS = "\x1e", "\x1f"
STALLED_DAYS = 7

VIEW_FILES = {"plan": "plan.md", "history": "history.md", "coverage": "coverage.txt"}


def die(msg):
    print(f"caped render: {msg}", file=sys.stderr)
    sys.exit(2)


def run(args, check=True):
    return subprocess.run(args, capture_output=True, text=True, check=check).stdout


ROOT = Path(run(["git", "rev-parse", "--show-toplevel"]).strip())


def parse_frontmatter_text(text):
    """Flat 'key: value' frontmatter; no YAML library on purpose."""
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}
    fm = {}
    for line in text[3:end].strip().splitlines():
        m = re.match(r"^(\w+):\s*(.*)$", line)
        if m:
            fm[m.group(1)] = m.group(2).strip()
    return fm


def entities():
    out = []
    for status, d in (("in-work", "changes"), ("idea", "ideas")):
        dd = ROOT / d
        if not dd.is_dir():
            continue
        for f in sorted(dd.glob("*.md")):
            fm = parse_frontmatter_text(f.read_text(encoding="utf-8"))
            fm["name"] = fm.get("name") or f.stem
            fm["_status"] = status
            fm["_path"] = f
            out.append(fm)
    return out


def last_commit_info(path):
    out = run(["git", "log", "-1", "--date=short", "--format=%ad%x1f%h", "--", str(path)]).strip()
    if not out:
        return "", 0
    d, h = out.split(FS)
    try:
        age = (date.today() - date.fromisoformat(d)).days
    except ValueError:
        age = 0
    return f"{d} {h}", age


def view_plan():
    lines = ["== plan =="]
    ents = entities()
    in_work = [e for e in ents if e["_status"] == "in-work"]
    ideas = [e for e in ents if e["_status"] == "idea"]

    lines.append("-- in work --")
    if not in_work:
        lines.append("  (none)")
    for e in in_work:
        info, age = last_commit_info(e["_path"].relative_to(ROOT))
        stalled = f"  STALLED >{STALLED_DAYS}d" if age > STALLED_DAYS else ""
        lines.append(f"  {e['name']:<20} last: {info} ({age}d ago){stalled}")
        if e.get("summary"):
            lines.append(f"      {e['summary']}")

    lines.append("-- ideas --")
    if not ideas:
        lines.append("  (none)")
    prio_rank = {"high": 0, "medium": 1, "mid": 1, "low": 2}
    ideas.sort(key=lambda e: (prio_rank.get(e.get("priority", ""), 3), e["name"]))
    for e in ideas:
        bits = [b for b in (e.get("phase"), e.get("priority")) if b]
        deps = e.get("depends_on") or "[]"
        spawned = e.get("spawned_from") or "-"
        head = " ".join(bits)
        lines.append(f"  {e['name']:<20} {head:<14} deps: {deps:<36} from: {spawned}")
        if e.get("summary"):
            lines.append(f"      {e['summary']}")
    return "\n".join(lines)


def history_events():
    log = run(["git", "log", "--date=short", f"--format={RS}%H{FS}%ad{FS}%B"])
    born, archived = {}, {}
    for rec in log.split(RS):
        rec = rec.strip("\n")
        if not rec:
            continue
        parts = rec.split(FS, 2)
        if len(parts) < 3:
            continue
        h, d, body = parts
        for m in re.finditer(r"^Idea:\s*(\S+)\s*$", body, re.M):
            born[m.group(1)] = (d, h[:8])  # log is newest-first: last write wins = oldest = birth
        for m in re.finditer(r"^Archives:\s*(\S+)\s*$", body, re.M):
            archived.setdefault(m.group(1), (d, h[:8], h))
    return born, archived


def archived_summary(name, commit):
    res = subprocess.run(
        ["git", "show", f"{commit}^:changes/{name}.md"], capture_output=True, text=True, check=False
    )
    if res.returncode != 0:
        return ""
    return parse_frontmatter_text(res.stdout).get("summary", "")


def rename_aliases():
    """Entity renames (R ideas/A.md -> ideas/B.md) — history stitches old names to new."""
    log = run(["git", "log", f"--format={RS}%H", "--name-status", "-M", "--", "ideas", "changes"])
    alias = {}
    # NB: str.splitlines() would eat the RS control bytes as line breaks — split explicitly.
    for rec in log.split(RS):
        for line in rec.split("\n"):
            if line.startswith("R"):
                parts = line.split("\t")
                if len(parts) == 3:
                    mo = re.match(r"ideas/(.+)\.md$", parts[1])
                    mn = re.match(r"ideas/(.+)\.md$", parts[2])
                    if mo and mn:
                        alias[mo.group(1)] = mn.group(1)
    return alias


def resolve(name, alias):
    seen = set()
    while name in alias and name not in seen:
        seen.add(name)
        name = alias[name]
    return name


def view_history():
    born, archived = history_events()
    alias = rename_aliases()
    merged = {}
    for n, v in born.items():
        merged.setdefault(resolve(n, alias), {})["born"] = (*v, n)
    for n, v in archived.items():
        merged.setdefault(resolve(n, alias), {})["arch"] = v
    lines = ["== history (from git trailers) ==", f"  {'change':<22} {'born':<19} {'archived':<19} summary"]
    if not merged:
        lines.append("  (no archived or born entities yet)")
    rows = sorted(
        merged.items(),
        key=lambda kv: (kv[1].get("arch") or kv[1].get("born"))[0],
        reverse=True,
    )
    for n, ev in rows:
        b = ev.get("born")
        a = ev.get("arch")
        bcell = f"{b[0]} {b[1]}" if b else "-"
        acell = f"{a[0]} {a[1]}" if a else "- (in work or idea)"
        old = f" (was: {b[2]})" if b and b[2] != n else ""
        summary = archived_summary(n, a[2]) if a else ""
        lines.append(f"  {n:<22} {bcell:<19} {acell:<19} {summary}{old}")
    return "\n".join(lines)


def view_coverage():
    caps = []
    reg = ROOT / "caped.registry"
    if reg.exists():
        for line in reg.read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) >= 3:
                caps.append((parts[1], parts[2]))
    caps.sort(key=lambda c: -len(c[0]))  # longest prefix wins, as in the hook

    counts = {}
    for f in run(["git", "ls-files"]).splitlines():
        state = next((s for p, s in caps if f.startswith(p)), "free")
        counts[state] = counts.get(state, 0) + 1

    total = sum(counts.values())
    lines = [f"== coverage — {total} tracked files, longest-prefix-wins =="]
    for state in ("enforced", "declared", "legacy", "free"):
        n = counts.get(state, 0)
        note = " (outside the registry — ignored by the hook)" if state == "free" else ""
        lines.append(f"  {state:<9} {n:>4} files{note}")
    return "\n".join(lines)


VIEWS = {"plan": view_plan, "history": view_history, "coverage": view_coverage}

GENERATED_HEADER = "<!-- generated by `caped render --write` — do not edit, regenerate instead -->\n\n"


def main(argv):
    if "--clean" in argv:
        shutil.rmtree(ROOT / ".caped", ignore_errors=True)
        print("caped render: .caped/ removed")
        return 0

    write = "--write" in argv
    names = [a for a in argv if not a.startswith("-")]
    unknown = [a for a in argv if a.startswith("-") and a != "--write"]
    if unknown:
        die(f"unknown flag(s): {' '.join(unknown)} (have: --write, --clean)")
    for n in names:
        if n not in VIEWS:
            die(f"unknown view '{n}' (have: {', '.join(VIEWS)})")
    if not names:
        names = list(VIEWS)

    for n in names:
        text = VIEWS[n]()
        print(text)
        print()
        if write:
            outdir = ROOT / ".caped"
            outdir.mkdir(exist_ok=True)
            (outdir / VIEW_FILES[n]).write_text(GENERATED_HEADER + text + "\n", encoding="utf-8")
    if write:
        print("caped render: written to .caped/ (" + ", ".join(VIEW_FILES[n] for n in names) + ")")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
