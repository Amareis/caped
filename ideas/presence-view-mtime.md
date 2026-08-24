---
name: presence-view-mtime
summary: render agents помечает живую сессию «завершена» по end-маркеру (kimi SessionEnd стреляет на /plugins reload) и режет fallback-идентичность до «session-» — живость по mtime, префикс срезать
phase: v0.1
priority: medium
depends_on: []
spawned_from: null
---

## Why

Живое наблюдение (kudach, kimi-cli, 2026-08-24): `caped render agents` показывает
мою живую сессию как «завершена» — в файле три `{"type":"end"}` от `/plugins
reload`, mtime при этом свежий. Рядом dsh-сессии без agent-поля рендерятся как
«session-» — fallback-усечение sid хватает префикс (класс бага kimi-sid-prefix).

## Context

- В kimi SessionEnd стреляет не только на реальное завершение — зафиксировано в
  спеке kimi-caped-plugin (#kimi-presence): end-маркер слабый сигнал, живость
  читается по mtime (heartbeat-тач на activity-хуках + SessionHeartbeat 60с).
- Файлы без agent-поля — легаси (заголовок до resident-header), их sid несёт
  префикс `session_`/`session-`.

## Requirements

- Живость сессии в presence-view определяется по mtime файла (с heartbeat-
  порогом), а не по наличию end-маркера; end-маркер — максимум пометка.
- Fallback-рендер идентичности (нет agent-поля) срезает префиксы `session_`/
  `session-` до усечения.

## Decisions

—

## Rejected alternatives

—

## Provenance

kimi-cli из живой сессии (2026-08-24): «подискавери через тул соседей» →
`caped render agents` в kudach показал оба дефекта на живых данных.

## Open questions

—

## Handoff

Доставлено вручную из kudach (kimi-cli/486d590e): `caped relay caped presence-view-mtime`
упал на коммите у соседа — хук требует change-class на enforced root (Behavior: …),
а relay-скрипт его не ставит. В kudach локальная копия снята (Archives:).
