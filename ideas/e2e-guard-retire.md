---
name: e2e-guard-retire
summary: Релей из caped-context: их tests/secretary/test_calibration.sh можно убирать — наш scenario-adopt.mjs уже гоняет секретарский корпус на реальном dsh (pass@N, git-ассерты фикстурной репы)
phase: v0.1
priority: low
depends_on: []
spawned_from: e2e-harness-realism
---

## Why

Двунаправленное принятие секретарских e2e закрылось на нашей стороне:
caped-context принял идею e2e-scenario-adopt (передано из нашего e2e-harness-realism,
superseded) и в плагинной сьюте теперь есть `tests/scenario-adopt.mjs` — он создаёт
фикстурную капед-репу, гоняет реальный headless dsh с промптом сценария и ассертит
ИТОГ в git (файл идеи, трейлер Idea:, зелёный `caped check`), pass@N через
`CAPED_E2E_N`, ключ-маппинг `LLM_API_KEY → SILICON_FLOW_API_KEY`. Проверено
`pass@1 = 1/1`.

Значит наш guard-пут — `tests/secretary/test_calibration.sh`, который из вашей репо
дёргал наш `apps/cli/lib/bin.js --profile headless <промпт>` по env
DSH_REPO/LLM_API_KEY — стал дубликатом с более бедными ассертами («вывод дошёл» без
git-проверок итога).

## Context

Цепочка передачи была и обратной — идеи к нам шли идея-коммитами, этот релей —
в ту же сторону, тем же форматом.

## Requirements

- Решить на нашей стороне, что делать с `tests/secretary/test_calibration.sh`:
  удалить, либо сжать до «резервного гарда без ключа» — главное не держать второй
  компилятор секретарских сценариев с другим семантическим набором.
- Если убираем — сослаться в удаляющем коммите на `caped-context/tests/scenario-adopt.mjs`
  (ростер проверки остаётся один).

## Decisions

—

## Rejected alternatives

—

## Provenance

Передано человеком: «А тому агенту передал что можно е2е там полностью убирать?
Через идею так же» (2026-08-24, caped-context сессия).

## Open questions

—