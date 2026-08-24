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

Решение принято (2026-08-24, человек): ретайрим. Убираем `test_calibration.sh`,
единственным ростром секретарских e2e остаётся `caped-context/tests/scenario-adopt.mjs`.

## Requirements

- Решить на нашей стороне, что делать с `tests/secretary/test_calibration.sh`:
  удалить, либо сжать до «резервного гарда без ключа» — главное не держать второй
  компилятор секретарских сценариев с другим семантическим набором. (Решено: удалить.)
- Если убираем — сослаться в удаляющем коммите на `caped-context/tests/scenario-adopt.mjs`
  (ростер проверки остаётся один).

## Decisions

- Retire: удалить `tests/secretary/test_calibration.sh`; в удаляющем коммите — ссылка
  на `caped-context/tests/scenario-adopt.mjs` как на единственный ростер.
- `tests/secretary/test_e2e.sh` (CAPED_EVAL-гейт, локальные инструкции) НЕ трогаем —
  это другой гейт; убирается только кросс-репо гард.

## Rejected alternatives

- Сжать до «резервного гарда без ключа»: оставило бы второй компилятор сценариев с
  другим семантическим набором — именно то, чего не хотим. Отклонено.

## Provenance

Передано человеком: «А тому агенту передал что можно е2е там полностью убирать?
Через идею так же» (2026-08-24, caped-context сессия).

Хэндофф в новую сессию: «Так. Запиши хэндофф — в новую сессию передам со
стандартными тулами а не кодовыми» (2026-08-24).

## Open questions

—

## Handoff

Назначение: новая сессия со СТАНДАРТНЫМИ тулами (git + файлы, без кодового харнесса).

0. Репо: `/Users/joe/work/caped` (тул caped). Сосед: `/Users/joe/work/caped-context`
   (плагин; код соседа НЕ меняем — только ссылки).
1. Правила: запусти `caped` без аргументов (или `bash scripts/caped.sh`) и следуй
   выводу — трейлеры коммитов (Behavior/Idea/Change/Archives/Adhoc), лайфцикл,
   гейт. Хук commit-msg сам не пустит нарушение.
2. Проверь состояние: `caped plan`, `caped trace`, `bash scripts/run-tests.sh`
   (или `just test`). Гейт должен быть зелёным до архива.
3. Возьми в работу: `caped work e2e-guard-retire` (git mv ideas/ → changes/ +
   коммит Change:).
4. Удали `tests/secretary/test_calibration.sh` отдельным коммитом: Behavior: internal,
   Change: e2e-guard-retire, в теле — ссылка на `caped-context/tests/scenario-adopt.mjs`
   (единственный ростер). Не трогай `test_e2e.sh`, `e2e_instructions.py`, README.
5. Прогони `bash scripts/run-tests.sh`: сьюты подхватываются по глoбу, отдельной
   регистрации нет; проверь, что trace не остался с висячим [#secretary-e2e]
   (деф в README, рефы были в тесте и в e2e_instructions.py).
6. Архив: `caped archive e2e-guard-retire` — сам прогонит полный гейт (на красном
   откажет), git rm + коммит Change:/Archives:.
7. Не делай ничего сверх задачи: это разовое ретайр-решение, отрепортуй итог.