---
name: backlog-autocreate-at-init
summary: ideas/_backlog.md должен создаваться автоматом при caped init + упоминание в rules-дампе — иначе первый же caped archive падает на отсутствии цели депозита
phase: v0
priority: low
depends_on: []
spawned_from: null
---

## Why

Первый `caped archive` в свежеподключённой репе (kudach, чейндж
web-version-cap-flip) упал: «ideas/_backlog.md missing — the deposit
target». Файл — обязательная инфраструктура архивного гейта (question-gate),
но init его не создаёт и rules-дамп про него молчит: узнаёшь о его
необходимости только из ошибки посреди архивации.

## Что предлагается

- `caped init` создаёт `ideas/_backlog.md` скелетом (псевдоидея с пустым
  `## Requirements` и шапкой про формат записей) — как минимум в linked/full
  режиме, где commit-msg шим с question-gate активен.
- Rules-дамп (bare `caped`) упоминает _backlog одной строкой там, где
  описана архивация: «депозиты отложенных вопросов падают в
  ideas/_backlog.md (создаётся init'ом)».

## Provenance

Человек (2026-08-24): «Про бэклог кстати тоже надо фидбек отправить — пусть
он автоматом создается при init, ну и инструкция про него нужна по идее».
Кейс: архивация первого чейнджа kudach (web-version-cap-flip), файл пришлось
заводить руками отдельным коммитом (a539f35). Отправлено релеем из kudach
(kimi-cli/486d590e).

## Handoff

Релей из kudach@6e1171d (`caped relay caped backlog-autocreate-at-init`, 2026-08-24); происхождение — /Users/joe/work/kudach.
