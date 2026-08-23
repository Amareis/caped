#!/usr/bin/env python3
"""E2E evaluation of the caped agent-facing instructions: real LLM agents get
only the AGENTS.md stub + the rules dump (exactly what an agent sees in an
adopting repo) and act in a fixture repo through a single `bash` tool. The
assertions check the produced ARTIFACTS (files, commit trailers), not the
model's prose — the instruction is good when the trajectory follows it.

Gated: runs only with CAPED_EVAL=1 and LLM_API_KEY set; otherwise skips with
exit 0 (the suite stays free and deterministic by default). Env:

  CAPED_EVAL=1        — enable
  LLM_API_KEY         — provider key (SiliconFlow; source kudach/.env locally)
  LLM_URL             — OpenAI-compatible base (default https://api.siliconflow.com)
  CAPED_EVAL_MODEL    — default deepseek-ai/DeepSeek-V4-Flash-0731 (cheap flash;
                        calibrate against a second model before trusting a failure)

Stdlib only. Transcripts (model-visible messages + tool calls) go to
tests/secretary/last-e2e/ (gitignored artifacts, not git history).

Covers the [#secretary-e2e] requirement (root README, "E2E-оценка агент-фейсинг
инструкций").
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

if os.environ.get("CAPED_EVAL") != "1":
    print("SKIP e2e instructions eval (set CAPED_EVAL=1 and LLM_API_KEY to run)")
    sys.exit(0)

API_KEY = os.environ.get("LLM_API_KEY")
if not API_KEY:
    print("SKIP e2e instructions eval (CAPED_EVAL=1 but LLM_API_KEY is not set)")
    sys.exit(0)

BASE_URL = os.environ.get("LLM_URL", "https://api.siliconflow.com").rstrip("/")
MODEL = os.environ.get("CAPED_EVAL_MODEL", "deepseek-ai/DeepSeek-V4-Flash-0731")
MAX_STEPS = 14
RETRIES = int(os.environ.get("CAPED_EVAL_RETRIES", "2"))  # pass@k: cheap models are flaky
TRANSCRIPT_DIR = REPO_ROOT / "tests" / "secretary" / "last-e2e"

BASH_TOOL = {
    "type": "function",
    "function": {
        "name": "bash",
        "description": "Run a bash command in the repository working directory. "
        "git is configured; commits go through the repo's commit-msg hook.",
        "parameters": {
            "type": "object",
            "properties": {"command": {"type": "string"}},
            "required": ["command"],
        },
    },
}


def chat(messages):
    req = urllib.request.Request(
        f"{BASE_URL}/v1/chat/completions",
        data=json.dumps(
            {"model": MODEL, "messages": messages, "tools": [BASH_TOOL], "temperature": 0}
        ).encode(),
        headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.load(resp)["choices"][0]["message"]


def run_bash(repo, command):
    try:
        out = subprocess.run(
            ["bash", "-c", command],
            cwd=repo,
            capture_output=True,
            text=True,
            timeout=60,
        )
        text = (out.stdout + out.stderr).strip()
        return f"exit={out.returncode}\n{text[:4000]}"
    except subprocess.TimeoutExpired:
        return "exit=124\ncommand timed out"


def build_fixture(setup):
    """Fresh repo with caped wired; `setup(repo)` adds scenario state via
    --no-verify commits (fixtures bypass the hook, the agent does not)."""
    repo = Path(tempfile.mkdtemp(prefix="caped-e2e-"))
    shutil.copytree(REPO_ROOT / "scripts", repo / "scripts")
    for f in ("caped.registry", "AGENTS.md", "README.md"):
        shutil.copy(REPO_ROOT / f, repo / f)
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.email", "eval@caped.dev"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "caped eval"], cwd=repo, check=True)
    subprocess.run(
        ["bash", "scripts/caped-init.sh"], cwd=repo, check=True, capture_output=True
    )
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-qm", "seed", "--no-verify"], cwd=repo, check=True)
    setup(repo)
    return repo


def setup_in_work_change(repo):
    idea = repo / "ideas" / "alpha.md"
    idea.parent.mkdir(exist_ok=True)
    idea.write_text(
        "---\nname: alpha\nsummary: tighten hook policy\nspawned_from: null\n---\n\n"
        "## Why\n\nz\n\n## Context\n\nk\n\n## Requirements\n\nt\n\n## Decisions\n\n"
        "## Rejected alternatives\n\n—\n\n## Provenance\n\np\n\n## Open questions\n\no\n",
        encoding="utf-8",
    )
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(
        ["git", "commit", "-qm", "идея alpha\n\nIdea: alpha", "--no-verify"],
        cwd=repo,
        check=True,
    )
    (repo / "changes").mkdir(exist_ok=True)
    subprocess.run(["git", "mv", "ideas/alpha.md", "changes/alpha.md"], cwd=repo, check=True)
    subprocess.run(
        ["git", "commit", "-qm", "в работу: alpha\n\nChange: alpha", "--no-verify"],
        cwd=repo,
        check=True,
    )


def setup_badly_named_idea(repo):
    idea = repo / "ideas" / "x.md"
    idea.parent.mkdir(exist_ok=True)
    idea.write_text(
        "---\nname: x\nsummary: pre-push hook support\nspawned_from: null\n---\n\n"
        "## Why\n\nz\n\n## Context\n\nk\n\n## Requirements\n\nt\n\n## Decisions\n\n"
        "## Rejected alternatives\n\n—\n\n## Provenance\n\np\n\n## Open questions\n\no\n",
        encoding="utf-8",
    )
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(
        ["git", "commit", "-qm", "идея x\n\nIdea: x", "--no-verify"], cwd=repo, check=True
    )


def system_prompt(repo):
    agents = (repo / "AGENTS.md").read_text(encoding="utf-8")
    dump = subprocess.run(
        ["bash", "scripts/caped.sh"], cwd=repo, capture_output=True, text=True, check=True
    ).stdout
    return (
        "You are a coding agent working in a git repository. The repository's "
        "AGENTS.md and the output of its rules command follow — they are the "
        "complete working rules; obey them exactly. When the task is complete, "
        "reply with a short summary instead of calling more tools.\n\n=== AGENTS.md ===\n"
        f"{agents}\n=== scripts/caped.sh ===\n{dump}"
    )


def run_scenario(name, setup, task, check, attempt=1):
    repo = build_fixture(setup)
    messages = [
        {"role": "system", "content": system_prompt(repo)},
        {"role": "user", "content": task},
    ]
    trajectory = []
    try:
        for _ in range(MAX_STEPS):
            msg = chat(messages)
            messages.append(msg)
            calls = msg.get("tool_calls") or []
            if not calls:
                trajectory.append({"final": msg.get("content", "")[:500]})
                break
            for call in calls:
                fn = call["function"]["name"]
                args = json.loads(call["function"]["arguments"])
                trajectory.append({"tool": fn, "command": args.get("command", "")})
                result = (
                    run_bash(repo, args["command"]) if fn == "bash" else "unknown tool"
                )
                messages.append(
                    {"role": "tool", "tool_call_id": call["id"], "content": result}
                )
        # The artifacts are the contract, not the model's final word: a cheap
        # model may keep exploring past the finished work — evaluate the repo
        # state regardless of how the loop ended.
        ok, why = check(repo, trajectory)
        if not ok and not any("final" in t for t in trajectory):
            why = f"step budget exhausted; {why}"
        return ok, repo, trajectory, why
    finally:
        TRANSCRIPT_DIR.mkdir(exist_ok=True)
        (TRANSCRIPT_DIR / f"{name}-{attempt}.json").write_text(
            json.dumps({"trajectory": trajectory}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )


def git_log_body(repo, n=3):
    out = subprocess.run(
        ["git", "log", f"-{n}", "--format=%B%x1e"], cwd=repo, capture_output=True,
        text=True, check=True,
    ).stdout
    return out


def check_spawned_idea(repo, _trajectory):
    """A new idea file with spawned_from: alpha, born in a commit carrying
    both Idea: <child> and Change: alpha."""
    new = [f for f in (repo / "ideas").glob("*.md") if f.stem != "alpha"]
    if not new:
        return False, "no new idea file in ideas/"
    for f in new:
        text = f.read_text(encoding="utf-8")
        if re.search(r"^spawned_from:\s*alpha\s*$", text, re.M):
            break
    else:
        return False, "no new idea carries spawned_from: alpha"
    body = git_log_body(repo)
    if not re.search(rf"^Idea:\s*{re.escape(new[0].stem)}\s*$", body, re.M) and not re.search(
        r"^Idea:\s*\S+\s*$", body, re.M
    ):
        return False, "no Idea: trailer in recent commits"
    if not re.search(r"^Change:\s*alpha\s*$", body, re.M):
        return False, "the birth commit lacks Change: alpha (parent change)"
    return True, "ok"


def check_renamed_idea(repo, _trajectory):
    """ideas/pre-push-hooks.md exists with a fixed name: field, ideas/x.md is
    gone, and the rename is one commit (rename detection sees it)."""
    target = repo / "ideas" / "pre-push-hooks.md"
    if not target.exists():
        return False, "ideas/pre-push-hooks.md missing"
    if (repo / "ideas" / "x.md").exists():
        return False, "ideas/x.md still exists"
    if not re.search(r"^name:\s*pre-push-hooks\s*$", target.read_text(encoding="utf-8"), re.M):
        return False, "frontmatter name: not updated"
    out = subprocess.run(
        ["git", "log", "-1", "--name-status", "-M", "--format="],
        cwd=repo, capture_output=True, text=True, check=True,
    ).stdout
    if not re.search(r"^R\d+\s+ideas/x\.md\s+ideas/pre-push-hooks\.md", out, re.M):
        return False, f"last commit is not a clean rename: {out}"
    return True, "ok"


def check_surveyed_plan(repo, trajectory):
    """Arriving agent surveyed the territory (ran render) and did not
    duplicate the in-flight change alpha: no new idea or change files.
    [#render-first]"""
    ran_render = any(
        "render" in t.get("command", "") for t in trajectory if "tool" in t
    )
    if not ran_render:
        return False, "agent never ran render"
    new_ideas = list((repo / "ideas").glob("*.md"))
    if new_ideas:
        return False, f"duplicate idea spawned: {new_ideas}"
    extra = [f for f in (repo / "changes").glob("*.md") if f.stem != "alpha"]
    if extra:
        return False, f"duplicate change spawned: {extra}"
    return True, "ok"


SCENARIOS = [
    (
        "mid-change-spawn",
        setup_in_work_change,
        "We are in the middle of the change alpha. It just became clear that "
        "pre-push hook support is also needed — a separate big topic, NOT part "
        "of alpha. Do exactly what this repository's rules require for such a "
        "finding, and nothing else. Do not implement pre-push support itself.",
        check_spawned_idea,
    ),
    (
        "idea-rename",
        setup_badly_named_idea,
        "The idea x is badly named. Rename it to pre-push-hooks following this "
        "repository's rules, and nothing else.",
        check_renamed_idea,
    ),
    (  # [#render-first]
        "render-first-arrival",
        setup_in_work_change,
        "I want to start work on tightening this repo's hook policy. Before "
        "doing anything, figure out what the repo's tracker already has about "
        "that and tell me the right next step. Do NOT do the work itself.",
        check_surveyed_plan,
    ),
]


def main():
    print(f"e2e instructions eval — model {MODEL}, pass@{RETRIES}")
    failed = 0
    for name, setup, task, check in SCENARIOS:
        ok, why, steps, attempts = False, "", 0, 0
        for attempt in range(1, RETRIES + 1):
            attempts = attempt
            ok, repo, trajectory, why = run_scenario(name, setup, task, check, attempt)
            shutil.rmtree(repo, ignore_errors=True)
            steps = sum(1 for t in trajectory if "tool" in t)
            if ok:
                break
        if ok:
            print(f"PASS {name} ({steps} tool calls, attempt {attempts})")
        else:
            failed += 1
            print(f"FAIL {name} — {why} (transcripts: tests/secretary/last-e2e/{name}-*.json)")
    print(f"e2e: {len(SCENARIOS) - failed}/{len(SCENARIOS)} scenarios passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
