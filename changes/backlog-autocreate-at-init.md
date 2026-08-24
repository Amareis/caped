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

## Context

Кейс 2026-08-24: архивация первого чейнджа kudach — файл пришлось заводить
руками отдельным коммитом (a539f35). Наш init (`caped-init.sh`) пишет
реестр/хуки/ideas-каталог, но `_backlog.md` не создаёт; наш архивный гейт
(che жизненного цикла) требует его наличия (`die "ideas/_backlog.md missing"`).

## Requirements

- `caped init` создаёт `ideas/_backlog.md` скелетом (псевдоидея с пустым
  `## Requirements`, шапкой про формат записей и политикой forward-only) —
  как минимум в linked/full режиме, где commit-msg шим с question-gate активен.
- Rules-дамп (bare `caped`) упоминает `_backlog` одной строкой в секции
  архивации: «депозиты отложенных вопросов падают в ideas/_backlog.md
  (создаётся init'ом)».

## Decisions

- Скелет в init — без навязчивости: пустая витрина + форматная шапка;
  наполнение политикой — по образцу нашей идеи (backlog-future-only).
- Упоминание в дампе — одна строка рядом с life-cycle gate (не целая секция:
  псевдоидея уже описана в SPAWNING).

## Rejected alternatives

- Чинить только на стороне `caped archive` (создавать файл при первом
  архиве): молчаливое порождение инфраструктуры в момент отказа хуже, чем
  явный скелет при init. Отклонено.

## Provenance

Человек (2026-08-24): «Про бэклог кстати тоже надо фидбек отправить — пусть
он автоматом создается при init, ну и инструкция про него нужна по идее».
Релей из kudach@6e1171d (`caped relay caped backlog-autocreate-at-init`,
2026-08-24, Agent: kimi-cli/486d590e@kudach).

## Open questions

—