#!/usr/bin/env bash
# caped init — разово подготавливает репозиторий к жизни по caped-модели.
# Идемпотентен: повторный запуск только чинит отсутствующее и обновляет отчёт.
#
# Что делает:
#   1. Ставит шим .git/hooks/commit-msg, делегирующий версионируемому
#      scripts/hooks/commit-msg (логика — в репо, шим — тонкий и стабильный).
#   2. Сеет caped.registry, если его нет: root-кап + auto-discovery
#      src/features/*/ как legacy-капы (для adopting-репозиториев).
#   3. Добавляет .caped/ в .gitignore (derived views не коммитим).
#   4. Создаёт ideas/ и changes/ с .gitkeep.
#   5. Печатает (и пишет в .caped/coverage.txt) отчёт покрытия:
#      сколько tracked-файлов под enforced-капами, под legacy и не покрыто.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

die() { echo "caped-init: $*" >&2; exit 1; }

[ -d .git ] || die "не git-репозиторий: $ROOT"

# --- 1. commit-msg shim ---------------------------------------------------
SHIM=.git/hooks/commit-msg
if [ ! -f scripts/hooks/commit-msg ]; then
  die "нет scripts/hooks/commit-msg — положи версионируемый хук туда первым"
fi
chmod +x scripts/hooks/commit-msg
cat > "$SHIM" <<'EOF'
#!/bin/sh
# caped commit-msg shim — логика версионируется в scripts/hooks/commit-msg
exec "$(git rev-parse --show-toplevel)/scripts/hooks/commit-msg" "$@"
EOF
chmod +x "$SHIM"
echo "ok: $SHIM -> scripts/hooks/commit-msg"

# --- 2. caped.registry ----------------------------------------------------
if [ ! -f caped.registry ]; then
  {
    printf '# caped registry — name<TAB>path-prefix<TAB>state<TAB>spec-file\n'
    printf '# state: enforced | legacy\n'
    printf 'root\tREADME.md\tenforced\tREADME.md\n'
    # auto-discovery: типовой feature-sliced layout — существующие фичи как legacy
    if [ -d src/features ]; then
      for d in src/features/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        printf '%s\t%s\tlegacy\t%sREADME.md\n' "$name" "$d" "$d"
      done
    fi
  } > caped.registry
  echo "ok: caped.registry создан (src/features/* посеяны как legacy — переводи в enforced по одному)"
else
  echo "ok: caped.registry уже есть, не трогаю"
fi

# --- 3. .gitignore --------------------------------------------------------
touch .gitignore
if grep -qx '.caped/' .gitignore; then
  echo "ok: .caped/ уже в .gitignore"
else
  printf '\n# caped derived views — генерятся на лету, не коммитим\n.caped/\n' >> .gitignore
  echo "ok: .caped/ добавлен в .gitignore"
fi

# --- 4. ideas/ + changes/ -------------------------------------------------
mkdir -p ideas changes .caped
for d in ideas changes; do
  [ -e "$d/.gitkeep" ] || { : > "$d/.gitkeep"; echo "ok: $d/.gitkeep"; }
done

# --- 5. отчёт покрытия -----------------------------------------------------
REPORT=.caped/coverage.txt
enforced_prefixes=$(awk -F'\t' '$1 !~ /^#/ && $3 == "enforced" {print $2}' caped.registry)
legacy_prefixes=$(awk -F'\t' '$1 !~ /^#/ && $3 == "legacy" {print $2}' caped.registry)

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
  echo "enforced: $n_enforced файлов"
  echo "legacy:   $n_legacy файлов"
  echo "свободно: $n_free файлов (вне реестра — хук игнорирует)"
} | tee "$REPORT"

echo "caped init: готово"
