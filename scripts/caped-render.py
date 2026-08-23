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
  changelog — the free contract changelog, derived: Behavior: contract commits
             (filed work + fileless adhocs) with their Spec: — the bundled
             copy's FIRST LINE is the tool's version constant (#tool-version)
"""
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

RS, FS = "\x1e", "\x1f"
STALLED_DAYS = 7
TOP_FREE = 5
SUBJECT_MAX = 60

# Text views are laid out for the eye: entity name and status marks on their
# own line, the summary next, metadata last and dimmed. ANSI only on a TTY
# (NO_COLOR respected) — piped output stays plain for agents [#render-text-layout].
_COLOR = sys.stdout.isatty() and not os.environ.get("NO_COLOR")


def _paint(code, s):
    return f"\x1b[{code}m{s}\x1b[0m" if _COLOR else s


def bold(s):
    return _paint("1", s)


def dim(s):
    return _paint("2", s)


def red(s):
    return _paint("31", s)


def shorten(s, n=SUBJECT_MAX):
    return s if len(s) <= n else s[: n - 1] + "…"

VIEW_FILES = {"plan": "plan.md", "history": "history.md", "coverage": "coverage.txt", "reqs": "reqs.md", "changelog": "changelog.md"}


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
    recent = []
    for cl in adhoc_events()["clusters"]:
        for a in cl["commits"]:
            if len(recent) >= 5:
                break
            recent.append({"date": a["date"], "hash": a["hash"], "subject": a["subject"], "spec": a["spec"]})
        if len(recent) >= 5:
            break
    return {"view": "plan", "in_work": in_work, "ideas": ideas, "recent_adhoc": recent}


def plan_row_lines(r):
    marks = ""
    if r["blocked"]:
        marks += "  " + red(f"BLOCKED (dep unarchived: {', '.join(r['blocked'])})")
    if r["stalled"]:
        marks += "  " + red(f"STALLED >{STALLED_DAYS}d")
    lc = r["last_commit"]
    if lc:
        age = f"{r['age_days']}d ago" if r["age_days"] else "today"
        last = f"last: {lc['date']} {lc['hash']} «{shorten(lc['subject'])}» ({age})"
    else:
        last = "last: —"
    bits = " ".join(b for b in (r["phase"], r["priority"]) if b)
    deps = ", ".join(r["deps"]) if r["deps"] else "—"
    frm = r["spawned_from"] or "—"
    lines = [f"  {bold(r['name'])}  {dim(bits)}{marks}"]
    if r["summary"]:
        lines.append(f"    {r['summary']}")
    lines.append(dim(f"    {last} · deps: {deps} · from: {frm}"))
    return lines


def view_plan_text(data):
    lines = [bold("== plan =="), dim("-- in work --")]
    if not data["in_work"]:
        lines.append("  (none)")
    for r in data["in_work"]:
        lines.extend(plan_row_lines(r))
    lines.append(dim("-- ideas --"))
    if not data["ideas"]:
        lines.append("  (none)")
    for r in data["ideas"]:
        lines.extend(plan_row_lines(r))
    if data.get("recent_adhoc"):
        lines.append(dim("-- recent fileless decisions --"))
        for a in data["recent_adhoc"]:
            spec = f" (Spec: {a['spec']})" if a["spec"] else ""
            lines.append(f"  {dim(a['date'] + ' ' + a['hash'])}  {a['subject']}{dim(spec)}")
    return "\n".join(lines)


# --- history ----------------------------------------------------------------


def adhoc_events():
    """Fileless contract commits: Behavior: contract without a Change: trailer.

    Newest first, grouped by the `Adhoc: <name>` trailer — commits sharing a
    name form ONE fileless change; pre-naming fileless contracts fall under
    "(unnamed)". Idea-rename events (R ideas/A.md -> ideas/B.md in the diff)
    are excluded — they are events, not adhoc decisions. Each commit carries
    an excerpt of its body (first substantive rationale line) and its Spec:.
    [#render-history-adhoc] [#adhoc-id]
    """
    log = run(["git", "log", "--date=short", f"--format={RS}%H{FS}%ad{FS}%B"])

    def entry(h, d, body):
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
        spec = ""
        m = re.search(r"^Spec:\s*(\S+)\s*$", body, re.M)
        if m:
            spec = m.group(1)
        return {"date": d, "hash": h[:8], "subject": subject, "excerpt": excerpt, "spec": spec}

    clusters = {}
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
        names = run(["git", "show", "--name-status", "-M", "--format=", h], check=False)
        if re.search(r"^R\d*\tideas/[^\t]+\.md\tideas/[^\t]+\.md$", names, re.M):
            continue  # idea rename event — not an adhoc decision
        m = re.search(r"^Adhoc:\s*(\S+)\s*$", body, re.M)
        name = m.group(1) if m else "(unnamed)"
        clusters.setdefault(name, []).append(entry(h, d, body))
    ids = len(clusters)
    over2 = sum(1 for c in clusters.values() if len(c) > 2)
    return {"ids": ids, "over2": over2, "clusters": [{"name": n, "commits": c} for n, c in clusters.items()]}


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
            ns = run(["git", "show", "--name-status", "--format=", a[2]], check=False)
            if re.search(r"^D\tideas/" + re.escape(n) + r"\.md$", ns, re.M):
                status = "withdrawn"  # idea archived directly, never taken into work
            else:
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
    lines = [bold("== history (from git trailers) =="), dim(f"  {'change':<22} {'born':<19} {'archived':<19} summary")]
    if not data["rows"]:
        lines.append("  (no archived or born entities yet)")
    for r in data["rows"]:
        bcell = f"{r['born']['date']} {r['born']['hash']}" if r["born"] else "-"
        if r["archived"]:
            acell = f"{r['archived']['date']} {r['archived']['hash']}"
        else:
            acell = f"- {r['status']}"  # idea / in work / ? (drift, visible by design)
        old = f" (was: {r['was']})" if r["was"] else ""
        lines.append(f"  {bold(r['name'])}{' ' * max(1, 22 - len(r['name']))} {dim(bcell):<19} {dim(acell):<19} {r['summary']}{old}")
    lines.append(dim(f"-- adhoc decisions (fileless contract commits; {data['adhoc']['ids']} id(s), {data['adhoc']['over2']} cluster(s) over 2) --"))
    if not data["adhoc"]["clusters"]:
        lines.append("  (none)")
    for cl in data["adhoc"]["clusters"]:
        cnt = len(cl["commits"])
        lines.append(f"  Adhoc: {bold(cl['name'])} ({cnt} commit{'s' if cnt != 1 else ''})")
        for a in cl["commits"]:
            lines.append(f"    {dim(a['date'] + ' ' + a['hash'])}  {bold(a['subject'])}")
            if a.get("excerpt"):
                lines.append(dim(f"        {a['excerpt']}"))
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
    lines = [bold(f"== coverage — {data['total']} tracked files, longest-prefix-wins ==")]
    for state in ("enforced", "declared", "legacy", "free"):
        n = data["by_state"].get(state, 0)
        note = " (outside the registry — ignored by the hook)" if state == "free" else ""
        lines.append(f"  {state:<9} {n:>4} files{dim(note)}")
    lines.append(dim("-- per cap --"))
    if not data["caps"]:
        lines.append("  (no registry)")
    for c in data["caps"]:
        lines.append(f"  {bold(c['name'])}{' ' * max(1, 16 - len(c['name']))} {c['state']:<9} {c['files']:>4} files  {dim('(' + c['prefix'] + ')')}")
    if data["top_free"]:
        lines.append(dim("-- top free paths --"))
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
    lines = [bold("== reqs — requirement index (slug + first-line gist) ==")]
    groups = [("spec", r["source"], r) for r in data["specs"]]
    groups += (("idea" if r["status"] == "idea" else "in work", r["source"], r) for r in data["entities"])
    by_source = {}
    for kind, source, r in groups:
        by_source.setdefault((source, kind), []).append(r)
    if not by_source:
        lines.append("  (none)")
    for (source, kind), rows in by_source.items():
        lines.append(dim(f"-- {source} ({kind}) --"))
        for r in rows:
            slug = f"[#{r['slug']}] " if r["slug"] else ""
            lines.append(f"  {dim(slug)}{r['gist']}" if r["slug"] else f"  {r['gist']}")
    return "\n".join(lines)


def changelog_data():
    """Contract commits as a changelog: Behavior: contract (filed or fileless).

    The rendered FIRST LINE is the version constant of a bundled copy
    (`head <HEAD> · <date>`), consumed by the tool-updated check. [#tool-version]
    """
    log = run(["git", "log", "--date=short", f"--format={RS}%H{FS}%ad{FS}%B"])
    rows = []
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
        spec = ""
        m = re.search(r"^Spec:\s*(\S+)\s*$", body, re.M)
        if m:
            spec = m.group(1)
        subject = body.strip().splitlines()[0] if body.strip() else ""
        rows.append({"hash": h[:8], "date": d, "subject": subject, "spec": spec})
    head = run(["git", "rev-parse", "--short", "HEAD"]).strip() or "-"
    today = date.today().isoformat()
    return {"view": "changelog", "count": len(rows), "head": head, "date": today, "rows": rows}


def view_changelog_text(data):
    lines = [f"caped changelog: {data['count']} contract change(s) · head {data['head']} · {data['date']}"]
    if not data["rows"]:
        lines.append("  (no contract commits yet)")
    for r in data["rows"]:
        spec = f" (Spec: {r['spec']})" if r["spec"] else ""
        lines.append(f"  {dim(r['date'] + ' ' + r['hash'])}  {r['subject']}{dim(spec)}")
    return "\n".join(lines)


VIEW_DATA = {"plan": plan_data, "history": history_data, "coverage": coverage_data, "reqs": reqs_data, "changelog": changelog_data}
VIEW_TEXT = {"plan": view_plan_text, "history": view_history_text, "coverage": view_coverage_text, "reqs": view_reqs_text, "changelog": view_changelog_text}

GENERATED_HEADER = "<!-- generated by `caped render --write` — do not edit, regenerate instead -->\n\n"


def change_show(argv):
    """`caped change show <name>` — rebuild an entity in one call. [#change-show]

    Live text from the FS (idea/change), the final document from the
    Archives-commit parent for archived entities, or the concatenated
    commit messages of an Adhoc: cluster (its virtual file). Plus the
    event timeline and every commit carrying the entity trailer.
    Unknown names fail exit 2 with the closest candidates.
    """
    args = list(argv)
    if args and args[0] == "show":
        args = args[1:]
    as_json = "--json" in args
    args = [a for a in args if not a.startswith("-")]
    if not args:
        die("usage: caped change show <name>")
    name = args[0]

    live = {e["name"]: e for e in entities()}
    born, archived = history_events()
    alias = rename_aliases()
    rname = resolve(name, alias)
    doc, source, status = "", "", ""
    if rname in live:
        e = live[rname]
        doc = e["_path"].read_text(encoding="utf-8")
        source = "filesystem"
        status = "idea" if e["_status"] == "idea" else "in work"
    elif rname in archived:
        a = archived[rname]
        res = subprocess.run(["git", "show", f"{a[2]}^:changes/{rname}.md"], capture_output=True, text=True, check=False)
        doc = res.stdout if res.returncode == 0 else ""
        source = "archive parent " + a[1]
        status = "archived"
    else:
        adhoc = _adhoc_cluster(rname)
        if adhoc:
            status = "adhoc ({0} commit(s))".format(len(adhoc))
            parts = []
            for ((d, h), body) in adhoc:
                lns = body.strip().splitlines()
                subj = lns[0] if lns else ""
                rest = "\n".join(lns[1:]).strip()
                parts.append("[{0} {1}] {2}{3}".format(d, h, subj, ("\n" + rest) if rest else ""))
            doc = "\n\n".join(parts)
            source = "commit messages"
        else:
            cands = _show_candidates(name)
            hint = " — closest: " + ", ".join(cands) if cands else ""
            print("caped change show: no entity or adhoc named '" + name + "'" + hint, file=sys.stderr)
            return 2

    commits = _entity_commits(rname)
    born_ev = born.get(rname)
    arch_ev = archived.get(rname)
    if as_json:
        print(json.dumps({
            "view": "change", "name": rname, "status": status,
            "born": {"date": born_ev[0], "hash": born_ev[1]} if born_ev else None,
            "archived": {"date": arch_ev[0], "hash": arch_ev[1]} if arch_ev else None,
            "document": doc, "source": source,
            "commits": [{"date": c[0], "hash": c[1], "subject": c[2], "type": c[3]} for c in commits],
        }, ensure_ascii=False, indent=2))
        return 0

    lines = [bold("== change: " + rname + " =="), "  status: " + status]
    if born_ev:
        lines.append("  born: {0} {1}".format(born_ev[0], born_ev[1]))
    if arch_ev:
        lines.append("  archived: {0} {1}".format(arch_ev[0], arch_ev[1]))
    lines.append(dim("-- document (" + source + ") --"))
    lines.append(doc if doc else "(no document)")
    lines.append(dim("-- commits ({0}) --".format(len(commits))))
    for (d, h, subj, typ) in commits:
        lines.append("  " + dim(d + " " + h) + "  " + subj + "  (" + typ + ")")
    print("\n".join(lines))
    return 0


def _adhoc_cluster(name):
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
        if body and re.search(r"^Adhoc:\s*" + re.escape(name) + r"\s*$", body, re.M):
            out.append(((d, h[:8]), body))
    return list(reversed(out))


def _entity_commits(rname):
    """Oldest -> newest commits carrying Idea:/Change:/Archives:/Adhoc: for rname."""
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
        typ = ""
        rx = re.escape(rname)
        if body and re.search(r"^Archives:\s*" + rx + r"\s*$", body, re.M):
            typ = "archive"
        elif body and re.search(r"^Idea:\s*" + rx + r"\s*$", body, re.M):
            typ = "birth"
        elif body and re.search(r"^Change:\s*" + rx + r"\s*$", body, re.M):
            ns = run(["git", "show", "--name-status", "-M", "--format=", h], check=False)
            typ = "into work" if re.search(r"^R\d*\tideas/" + rx + r"\.md\tchanges/" + rx + r"\.md$", ns, re.M) else "work"
        elif body and re.search(r"^Adhoc:\s*" + rx + r"\s*$", body, re.M):
            typ = "adhoc"
        if typ:
            subj = body.strip().splitlines()[0] if body.strip() else ""
            out.append((d, h[:8], subj, typ))
    return out


def _show_candidates(name):
    import difflib
    known = {e["name"] for e in entities()}
    born, archived = history_events()
    known |= set(born) | set(archived)
    log = run(["git", "log", f"--format={RS}%B"])
    for rec in log.split(RS):
        for m in re.finditer(r"^Adhoc:\s*(\S+)\s*$", rec, re.M):
            known.add(m.group(1))
    return difflib.get_close_matches(name, sorted(known), n=3, cutoff=0.0)

def main(argv):
    if argv and argv[0] == "change":
        return change_show(argv[1:])
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
