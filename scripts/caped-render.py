#!/usr/bin/env python3
"""caped render — derived views of the tracker, printed to stdout.

Every view is built as structured data first, then rendered as text (default,
for the eyes) or JSON (--json, for machines) — both forms share the one
generator. `--write` materialises BOTH forms into .caped/ (plan.md + plan.json,
history.md + history.json, coverage.txt + coverage.json), `--clean` removes
.caped/.

Views:
  plan     — in-work changes (last commit with subject, stalled marked) and
             ideas from frontmatter, sorted by phase then priority; ideas whose
             depends_on is not archived yet are marked BLOCKED
  history  — the change archive reconstructed from git trailers (Idea: born,
             Archives: archived) with dates, commits and summaries; live
             entities get their real status from the filesystem (ideas/ = idea,
             changes/ = in work), inconsistencies show as '?'; plus the
             fileless adhoc contract commits (Behavior: contract without a
             Change: trailer)
  coverage — tracked files vs caped.registry (enforced/legacy/declared/free,
             longest prefix wins), per-cap rows and the top free paths
  reqs     — the requirement index in one view: slug + first-line gist from
             the '## Requirements' of enforced spec files, and bullet gists
             (slug optional) from ideas/ and changes/
"""
import json
import re
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

RS, FS = "\x1e", "\x1f"
STALLED_DAYS = 7
TOP_FREE = 5

VIEW_FILES = {"plan": "plan.md", "history": "history.md", "coverage": "coverage.txt", "reqs": "reqs.md"}


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


def parse_list(value):
    """'[a, b]' -> ['a', 'b']; anything empty -> []."""
    if not value:
        return []
    v = value.strip()
    if v.startswith("[") and v.endswith("]"):
        v = v[1:-1]
    return [x.strip() for x in v.split(",") if x.strip()]


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


def last_commit(path):
    out = run(["git", "log", "-1", "--date=short", f"--format=%ad%x1f%h%x1f%s", "--", str(path)]).strip()
    if not out:
        return None, 0
    parts = (out.split(FS) + ["", "", ""])[:3]
    d, h, subject = parts
    try:
        age = (date.today() - date.fromisoformat(d)).days
    except ValueError:
        age = 0
    return {"date": d, "hash": h, "subject": subject}, age


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


# --- plan -----------------------------------------------------------------


def plan_data():
    _, archived = history_events()
    alias = rename_aliases()
    done = {resolve(n, alias) for n in archived}
    in_work, ideas = [], []
    for e in entities():
        lc, age = last_commit(e["_path"].relative_to(ROOT))
        deps = parse_list(e.get("depends_on"))
        sp = (e.get("spawned_from") or "").strip()
        row = {
            "name": e["name"],
            "status": e["_status"],
            "summary": e.get("summary", ""),
            "phase": e.get("phase", ""),
            "priority": e.get("priority", ""),
            "deps": deps,
            "spawned_from": None if sp.lower() in ("", "-", "null", "none", "~") else sp,
            "last_commit": lc,
            "age_days": age,
            "stalled": age > STALLED_DAYS,
            "blocked": [d for d in deps if resolve(d, alias) not in done],
        }
        (in_work if e["_status"] == "in-work" else ideas).append(row)
    prio_rank = {"high": 0, "medium": 1, "mid": 1, "low": 2}
    ideas.sort(key=lambda r: (r["phase"] or "—", prio_rank.get(r["priority"], 3), r["name"]))
    in_work.sort(key=lambda r: r["name"])
    return {"view": "plan", "in_work": in_work, "ideas": ideas}


def plan_row_line(r):
    marks = ""
    if r["blocked"]:
        marks += f"  BLOCKED (dep unarchived: {', '.join(r['blocked'])})"
    if r["stalled"]:
        marks += f"  STALLED >{STALLED_DAYS}d"
    lc = r["last_commit"]
    if lc:
        age = f" ({r['age_days']}d ago)" if r["age_days"] else " (today)"
        last = f"last: {lc['date']} {lc['hash']} «{lc['subject']}»{age}"
    else:
        last = "last: —"
    bits = " ".join(b for b in (r["phase"], r["priority"]) if b)
    deps = ", ".join(r["deps"]) if r["deps"] else "—"
    frm = r["spawned_from"] or "—"
    return f"{r['name']:<20} {bits:<14} {last}  deps: {deps}  from: {frm}{marks}"


def view_plan_text(data):
    lines = ["== plan ==", "-- in work --"]
    if not data["in_work"]:
        lines.append("  (none)")
    for r in data["in_work"]:
        lines.append("  " + plan_row_line(r))
        if r["summary"]:
            lines.append(f"      {r['summary']}")
    lines.append("-- ideas --")
    if not data["ideas"]:
        lines.append("  (none)")
    for r in data["ideas"]:
        lines.append("  " + plan_row_line(r))
        if r["summary"]:
            lines.append(f"      {r['summary']}")
    return "\n".join(lines)


# --- history ----------------------------------------------------------------


def adhoc_events():
    """Fileless contract commits: Behavior: contract without a Change: trailer.

    Newest first, straight from git log. Carries an excerpt of the body —
    the first substantive rationale line, ~140 chars — so the listing is a
    window into the reasoning without git show. [#render-history-adhoc]
    """
    log = run(["git", "log", "--date=short", f"--format={RS}%H{FS}%ad{FS}%B"])
    out = []
    for rec in log.split(RS):
        rec = rec.strip("\n")
        if not rec:
            continue
        parts = rec.split(FS, 2)
        if len(parts) < 3:
            continue
        h, d, body = parts
        if not re.search(r"^Behavior:\s*contract\s*$", body, re.M):
            continue
        if re.search(r"^Change:\s*\S+\s*$", body, re.M):
            continue
        lines = body.strip().splitlines()
        subject = lines[0] if lines else ""
        excerpt = ""
        for line in lines[1:]:
            line = line.strip()
            if not line or re.match(r"^[A-Z][A-Za-z0-9-]*:\s", line):
                continue
            excerpt = line
            break
        if len(excerpt) > 140:
            excerpt = excerpt[:139] + "…"
        out.append({"date": d, "hash": h[:8], "subject": subject, "excerpt": excerpt})
    return out


def history_data():
    born, archived = history_events()
    alias = rename_aliases()
    live = {}
    for d, st in (("ideas", "idea"), ("changes", "in work")):
        dd = ROOT / d
        if dd.is_dir():
            for f in dd.glob("*.md"):
                live[f.stem] = st
    merged = {}
    for n, v in born.items():
        merged.setdefault(resolve(n, alias), {})["born"] = (*v, n)
    for n, v in archived.items():
        merged.setdefault(resolve(n, alias), {})["arch"] = v
    rows = []
    for n, ev in merged.items():
        b = ev.get("born")
        a = ev.get("arch")
        if a:
            status = "archived"
        else:
            status = live.get(n, "?")
        rows.append(
            {
                "name": n,
                "born": {"date": b[0], "hash": b[1]} if b else None,
                "archived": {"date": a[0], "hash": a[1]} if a else None,
                "status": status,
                "was": b[2] if b and b[2] != n else None,
                "summary": archived_summary(n, a[2]) if a else "",
            }
        )
    rows.sort(key=lambda r: (r["archived"] or r["born"] or {"date": ""})["date"], reverse=True)
    return {"view": "history", "rows": rows, "adhoc": adhoc_events()}


def view_history_text(data):
    lines = ["== history (from git trailers) ==", f"  {'change':<22} {'born':<19} {'archived':<19} summary"]
    if not data["rows"]:
        lines.append("  (no archived or born entities yet)")
    for r in data["rows"]:
        bcell = f"{r['born']['date']} {r['born']['hash']}" if r["born"] else "-"
        if r["archived"]:
            acell = f"{r['archived']['date']} {r['archived']['hash']}"
        else:
            acell = f"- {r['status']}"  # idea / in work / ? (drift, visible by design)
        old = f" (was: {r['was']})" if r["was"] else ""
        lines.append(f"  {r['name']:<22} {bcell:<19} {acell:<19} {r['summary']}{old}")
    lines.append("-- adhoc decisions (fileless contract commits) --")
    if not data["adhoc"]:
        lines.append("  (none)")
    for a in data["adhoc"]:
        lines.append(f"  {a['date']} {a['hash']}  {a['subject']}")
        if a.get("excerpt"):
            lines.append(f"      {a['excerpt']}")
    return "\n".join(lines)


# --- coverage ---------------------------------------------------------------


def coverage_data():
    caps = []
    reg = ROOT / "caped.registry"
    if reg.exists():
        for line in reg.read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) >= 3:
                caps.append({"name": parts[0], "prefix": parts[1], "state": parts[2]})
    caps.sort(key=lambda c: -len(c["prefix"]))  # longest prefix wins, as in the hook

    by_state = {}
    per_cap = {c["name"]: 0 for c in caps}
    free_top = {}
    for f in run(["git", "ls-files"]).splitlines():
        cap = next((c for c in caps if f.startswith(c["prefix"])), None)
        if cap is None:
            by_state["free"] = by_state.get("free", 0) + 1
            top = f.split("/", 1)[0] + ("/" if "/" in f else "")
            free_top[top] = free_top.get(top, 0) + 1
        else:
            by_state[cap["state"]] = by_state.get(cap["state"], 0) + 1
            per_cap[cap["name"]] += 1
    for c in caps:
        c["files"] = per_cap[c["name"]]
    top_free = [
        {"path": p, "files": n} for p, n in sorted(free_top.items(), key=lambda kv: -kv[1])[:TOP_FREE]
    ]
    total = sum(by_state.values())
    return {"view": "coverage", "total": total, "by_state": by_state, "caps": caps, "top_free": top_free}


def view_coverage_text(data):
    lines = [f"== coverage — {data['total']} tracked files, longest-prefix-wins =="]
    for state in ("enforced", "declared", "legacy", "free"):
        n = data["by_state"].get(state, 0)
        note = " (outside the registry — ignored by the hook)" if state == "free" else ""
        lines.append(f"  {state:<9} {n:>4} files{note}")
    lines.append("-- per cap --")
    if not data["caps"]:
        lines.append("  (no registry)")
    for c in data["caps"]:
        lines.append(f"  {c['name']:<16} {c['state']:<9} {c['files']:>4} files  ({c['prefix']})")
    if data["top_free"]:
        lines.append("-- top free paths --")
        for t in data["top_free"]:
            lines.append(f"  {t['path']:<24} {t['files']:>4} files")
    return "\n".join(lines)


# --- reqs -------------------------------------------------------------------

REQ_SECTION_RE = re.compile(r"^## Requirements\s*$")
H2_ANY_RE = re.compile(r"^## (?!#)")
IDEA_REQ_RE = re.compile(r"^[-*]\s+(?:\[#([a-z0-9][a-z0-9-]*)(?: (?:no-test|dump))*\]\s+)?(.*)")
BULLET_LINE_RE = re.compile(r"^[-*]\s+")


def req_rows(path):
    """Bullets of the '## Requirements' section: slug (optional) + first-line gist.

    The gist is the bullet's first physical line; a '…' marks a hard-wrapped
    legacy bullet whose first line is not a self-contained gist yet.
    """
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []
    rows, in_req = [], False
    for i, line in enumerate(lines):
        if REQ_SECTION_RE.match(line):
            in_req = True
            continue
        if in_req and H2_ANY_RE.match(line):
            break
        if in_req:
            m = IDEA_REQ_RE.match(line)
            if m and m.group(2).strip():
                gist = m.group(2).strip()
                nxt = lines[i + 1] if i + 1 < len(lines) else ""
                if nxt.strip() and not BULLET_LINE_RE.match(nxt) and not H2_ANY_RE.match(nxt) and not nxt.startswith("###"):
                    gist += " …"
                rows.append({"slug": m.group(1), "gist": gist})
    return rows


def reqs_data():
    spec_paths = []
    reg = ROOT / "caped.registry"
    if reg.exists():
        for line in reg.read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) >= 4 and parts[2] == "enforced":
                spec_paths.append(parts[3])
    specs, entities_rows = [], []
    for rel in sorted(set(spec_paths)):
        for r in req_rows(ROOT / rel):
            specs.append({**r, "source": rel})
    for status, d in (("in-work", "changes"), ("idea", "ideas")):
        dd = ROOT / d
        if not dd.is_dir():
            continue
        for f in sorted(dd.glob("*.md")):
            for r in req_rows(f):
                entities_rows.append({**r, "source": f.relative_to(ROOT).as_posix(), "status": status})
    return {"view": "reqs", "specs": specs, "entities": entities_rows}


def view_reqs_text(data):
    lines = ["== reqs — requirement index (slug + first-line gist) ==", "-- specs (enforced) --"]
    if not data["specs"]:
        lines.append("  (none)")
    for r in data["specs"]:
        lines.append(f"  [#{r['slug']}] {r['gist']}  ({r['source']})")
    lines.append("-- ideas / changes --")
    if not data["entities"]:
        lines.append("  (none)")
    for r in data["entities"]:
        slug = f"[#{r['slug']}] " if r["slug"] else ""
        lines.append(f"  {slug}{r['gist']}  ({r['source']})")
    return "\n".join(lines)


VIEW_DATA = {"plan": plan_data, "history": history_data, "coverage": coverage_data, "reqs": reqs_data}
VIEW_TEXT = {"plan": view_plan_text, "history": view_history_text, "coverage": view_coverage_text, "reqs": view_reqs_text}

GENERATED_HEADER = "<!-- generated by `caped render --write` — do not edit, regenerate instead -->\n\n"


def main(argv):
    if "--clean" in argv:
        shutil.rmtree(ROOT / ".caped", ignore_errors=True)
        print("caped render: .caped/ removed")
        return 0

    write = "--write" in argv
    as_json = "--json" in argv
    names = [a for a in argv if not a.startswith("-")]
    unknown = [a for a in argv if a.startswith("-") and a not in ("--write", "--json")]
    if unknown:
        die(f"unknown flag(s): {' '.join(unknown)} (have: --write, --clean, --json)")
    for n in names:
        if n not in VIEW_DATA:
            die(f"unknown view '{n}' (have: {', '.join(VIEW_DATA)})")
    if not names:
        names = list(VIEW_DATA)

    outdir = ROOT / ".caped"
    for n in names:
        data = VIEW_DATA[n]()
        text = VIEW_TEXT[n](data)
        print(json.dumps(data, ensure_ascii=False, indent=2) if as_json else text)
        if not as_json:
            print()
        if write:
            outdir.mkdir(exist_ok=True)
            (outdir / VIEW_FILES[n]).write_text(GENERATED_HEADER + text + "\n", encoding="utf-8")
            json_file = outdir / (VIEW_FILES[n].split(".", 1)[0] + ".json")
            json_file.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if write:
        print("caped render: written to .caped/ (" + ", ".join(VIEW_FILES[n] for n in names) + " + .json)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
