---
name: trace-declared-cap-defs
summary: caped trace не загружает defs declared-капов — рефы на их требования падают dangling, хотя спека существует; либо загружать defs всех спек реестра, либо задокументировать границу
phase: v0
priority: low
depends_on: []
spawned_from: null
---

## Why

В kudach техническая капа `agent-mcp` была зарегистрирована как `declared`
(конвенция kudach-adoption: технические капы — advisory). Её README со
списком `- [#slug]` требований существовал, тесты с trace-маркерами были
расставлены — но `caped trace` падал с dangling на каждый реф: defs из спеки
declared-капы не загружаются вообще (defs count не менялся при добавлении
README). Пришлось флипать в enforced только ради trace, хотя enforcement
хука там не требовался по конвенции.

## Context

Реестр: `agent-mcp	src/app/mcp/	declared	src/app/mcp/README.md`.
`caped trace` при declared: refs по маркерам собираются глобально (56 refs
увидели новые маркеры), а defs берутся только из enforced-капов — любой
маркер на требование declared-капы = dangling. То есть declared-капа со
спекой фактически не может иметь trace-покрытия: либо не размечать тесты
(теряется навигация), либо enforced.

## Requirements

- Семантика зафиксирована: declared/legacy-капа = «спека без trace». Её
  spec-файл исключён из ref-скана (маркеры в нём — не рефы, как в
  enforced-спеках), defs грузятся только из enforced-капов.
- Dangling-реф на slug, чья спека принадлежит declared/legacy-капе, даёт
  ПОДСКАЗКУ в сообщении («spec belongs to a non-enforced cap — no trace
  coverage: flip to enforced or remove the marker»), а не вводящее в
  заблуждение «defined in no spec».
- Дельта в дампе/README + тесты: маркеры declared-спеки игнорируются (trace
  зелёный), тест-реф на declared-slug — RED с подсказкой.

## Provenance

Агент (kimi-cli/486d590e, kudach): фактический инцидент при флипе кластера
agent-mcp 2026-08-29 — trace RED с 5 dangling при существующей спеке;
решено флипом в enforced, но для крупных технических капов (entities,
platform, ingress) такой флип преждевременен, а разметка их тестов при
текущей семантике невозможна.

## Open questions

- ~~Какой вариант семантики каноничен?~~ — ОТВЕЧЕНО человеком 2026-08-24:
  «Declared = спека без trace» (второй вариант). Разметка тестов технических
  капов до флипа невозможна by design — flip to enforced и есть акт включения
  покрытия.

## Handoff

Релей из kudach@e306584 (`caped relay caped trace-declared-cap-defs`, 2026-08-29); происхождение — /Users/joe/work/kudach.

## Decisions

- Declared/legacy = «спека без trace»: coverage — атрибут enforced, один
  статус реестра включает и хук, и trace. Маркеры declared-спеки — не рефы
  (spec-файлы всех статусов исключены из ref-скана); рефы НА её slug'и из
  тестов — dangling с подсказкой про статус капы.
- Подсказка строится чтением не-enforced спек только для диагностики
  (slug→state), не как defs.

## Rejected alternatives

- Грузить defs всех кап со spec-файлом (declared в coverage, enforcement —
  только хук): размывает смысл статусов, «advisory»-капа молча получает
  обязательство покрытия. Отклонено человеком 2026-08-24.
- Середина «enforced + declared, не legacy»: третья семантика для двух
  не-enforced статусов без выигрыша. Отклонено.
