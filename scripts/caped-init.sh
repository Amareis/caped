#!/usr/bin/env bash
# caped init — one-time wiring of a repository for the caped model.
# Idempotent: re-running only repairs what is missing and refreshes the report.
#
# What it does:
#   1. Installs the .git/hooks/commit-msg shim delegating to the versioned
#      scripts/caped.sh dispatcher (logic lives in the repo, shim is thin).
#   2. Seeds caped.registry if missing: root cap + auto-discovery of
#      src/features/*/ as legacy caps (for adopting repositories).
#   3. Adds .caped/ to .gitignore (derived views are never committed).
#   4. Creates ideas/ and changes/ with .gitkeep.
#   5. Prints (and writes to .caped/coverage.txt) the coverage report:
#      how many tracked files fall under enforced caps, legacy, or none.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

die() { echo "caped-init: $*" >&2; exit 1; }

[ -d .git ] || die "not a git repository: $ROOT"

# --- 1. commit-msg shim ---------------------------------------------------
SHIM=.git/hooks/commit-msg
[ -f scripts/caped.sh ] || die "scripts/caped.sh missing — the versioned dispatcher must exist first"
chmod +x scripts/caped.sh scripts/hooks/commit-msg 2>/dev/null || true
cat > "$SHIM" <<'EOF'
#!/bin/sh
# caped commit-msg shim — logic is versioned in scripts/ (caped.sh dispatcher)
exec "$(git rev-parse --show-toplevel)/scripts/caped.sh" hook commit-msg "$@"
EOF
chmod +x "$SHIM"
echo "ok: $SHIM -> scripts/caped.sh hook commit-msg"

# --- 2. caped.registry ----------------------------------------------------
if [ ! -f caped.registry ]; then
  {
    printf '# caped registry — name<TAB>path-prefix<TAB>state<TAB>spec-file\n'
    printf '# state: enforced | declared | legacy\n'
    printf 'root\tREADME.md\tenforced\tREADME.md\n'
    # auto-discovery: typical feature-sliced layout — existing features as legacy
    if [ -d src/features ]; then
      for d in src/features/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        printf '%s\t%s\tlegacy\t%sREADME.md\n' "$name" "$d" "$d"
      done
    fi
  } > caped.registry
  echo "ok: caped.registry seeded (src/features/* entered as legacy — flip to enforced one by one)"
else
  echo "ok: caped.registry already exists, untouched"
fi

# --- 3. .gitignore --------------------------------------------------------
touch .gitignore
if grep -qx '.caped/' .gitignore; then
  echo "ok: .caped/ already in .gitignore"
else
  printf '\n# caped derived views — generated on the fly, never committed\n.caped/\n' >> .gitignore
  echo "ok: .caped/ added to .gitignore"
fi

# --- 4. ideas/ + changes/ -------------------------------------------------
mkdir -p ideas changes .caped
for d in ideas changes; do
  [ -e "$d/.gitkeep" ] || { : > "$d/.gitkeep"; echo "ok: $d/.gitkeep"; }
done

# --- 5. coverage report -----------------------------------------------------
REPORT=.caped/coverage.txt
enforced_prefixes=$(awk -F'\t' '$1 !~ /^#/ && $3 == "enforced" {print $2}' caped.registry)
legacy_prefixes=$(awk -F'\t' '$1 !~ /^#/ && $3 != "enforced" {print $2}' caped.registry)

n_enforced=0; n_legacy=0; n_free=0
while IFS= read -r f; do
  covered=""
  for p in $enforced_prefixes; do
    case "$f" in "$p"*) covered=enforced; break ;; esac
  done
  if [ -z "$covered" ]; then
    for p in $legacy_prefixes; do
      case "$f" in "$p"*) covered=legacy; break ;; esac
    done
  fi
  case "${covered:-free}" in
    enforced) n_enforced=$((n_enforced + 1)) ;;
    legacy)   n_legacy=$((n_legacy + 1)) ;;
    free)     n_free=$((n_free + 1)) ;;
  esac
done < <(git ls-files)

{
  echo "# caped coverage — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "enforced: $n_enforced files"
  echo "legacy:   $n_legacy files"
  echo "free:     $n_free files (outside the registry — ignored by the hook)"
} | tee "$REPORT"

echo "caped init: done"
