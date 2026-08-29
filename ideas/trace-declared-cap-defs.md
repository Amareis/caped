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

- Определить и зафиксировать семантику: либо trace загружает defs ВСЕХ кап
  реестра со spec-файлом (declared включены — coverage виден, enforcement
  остаётся прерогативой хука), либо документируется, что declared = «спека
  без trace», и маркеры на её требования запрещены/игнорируются.
- Если выбран вариант «declared без trace»: сообщение о dangling должно
  подсказывать, что реф указывает на declared-капу (сейчас текст «defined
  in no spec» вводит в заблуждение — спека есть).

## Provenance

Агент (kimi-cli/486d590e, kudach): фактический инцидент при флипе кластера
agent-mcp 2026-08-29 — trace RED с 5 dangling при существующей спеке;
решено флипом в enforced, но для крупных технических капов (entities,
platform, ingress) такой флип преждевременен, а разметка их тестов при
текущей семантике невозможна.

## Open questions

- Какой вариант семантики каноничен? От ответа зависит, можно ли размечать
  тесты технических капов до их флипа в enforced.

## Handoff

Релей из kudach@e306584 (`caped relay caped trace-declared-cap-defs`, 2026-08-29); происхождение — /Users/joe/work/kudach.

## Decisions

-

## Rejected alternatives

-
