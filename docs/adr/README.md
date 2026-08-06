---
owner: operator
status: draft
last_updated: 2026-08-03
source_of_truth: generated-output
load_policy: reference
related:
  - /decisions/008-pns-runtime-architecture.md
  - /output/README.md
  - /wiki/pns/charter.md
---

> **Przeniesione z repozytorium kontekstu 6 sierpnia 2026, bez zmian w treści.**
>
> To jest dokument projektowy i jego przegląd — szczegóły, kształty kodu, odrzucone alternatywy.
> **Nie jest rekordem decyzji.** Rekord żyje w
> `~/Projects/ai/empowered-house-context/decisions/008-pns-runtime-architecture.md` i jest jednostronicową
> propozycją, która deleguje walidację tutaj. Decyzja wróci tam jako osobny rekord, kiedy będzie wynik.
>
> Odwołania `§N` w kodzie i w `PLAN.md` wskazują na numerowane decyzje w
> [008-pns-runtime-architecture.md](008-pns-runtime-architecture.md).

# PNS architecture ADR — working bundle

Working material behind [decision 008](../008-pns-runtime-architecture.md), which was
written out of the design sessions of 31 July and 1 August 2026 and reviewed by the team on 3 August.

**Three documents, split by the reader's question rather than by level of detail.** The earlier split — record
for decisions, notes for mechanics — put the "is this idea right" reader nowhere, which is why the record
kept growing and kept being unreadable.

| If your question is | Read | Size |
| --- | --- | --- |
| Is this idea right? Should we do it? | [decisions/008](../008-pns-runtime-architecture.md) — problem, approach, thirteen decisions with what each beat, the four bets, what would falsify it. Diagrams, no code | ~410 lines |
| Why is it like this? | [design-rationale.md](design-rationale.md) — the argument decision by decision, plus vocabulary, the DDD relationship, alternatives in full, and why the open questions are open | ~570 lines |
| How is it built? What does it look like? | [technology-notes.md](technology-notes.md) — contract DSL, compile-time enforcement, log schema, delivery, conformance, testing, generation, dashboard, adapters, configuration, prior art, libraries, packaging | ~800 lines |

Alongside them, [review-2026-08-03.md](~/Projects/ai/empowered-house-context/output/20260803-adr-008-review.md) holds the 3 August review and the deliberation
behind the nine decisions taken that evening — what was weighed and rejected, not a second copy of the
decisions.

Doctrine that outgrew this bundle now lives in `wiki/pns/`:
[modular design](../~/Projects/ai/empowered-house-context/wiki/pns/modular-design.md) and
[event-driven doctrine](../~/Projects/ai/empowered-house-context/wiki/pns/event-driven-doctrine.md).

## Inputs

Repository context: `wiki/pns/charter.md`, `wiki/pns/ecosystem-bet.md` (accepted product boundary);
`wiki/pns/coherence-layer.md`, `wiki/pns/ears-requirements-format.md` (July drafts, now narrowed and
superseded respectively); `strategy/thesis.md`, `tradeoffs.md`, `questions.md`; decisions 004–007;
`output/drafts/RUNTIME-VARIANTS-ADR.md` (Rafał Ślósarz, 2026-07-09 — the isolation analysis in §3/§3.1);
`company/market/erp/competition.md`.

Talks, transcripts read 2026-08-01 — Maciej Kaszubowski, *Event-driven architectures in Elixir*
(ElixirConf EU 2018) and *Modular Design in Elixir* (ElixirConf EU 2019). Derived guides for both are in
`raw/20260803-kaszubowski-*.md` and compiled, with attribution separated by confidence level, into the
two `wiki/pns/` pages above.

Products read directly: Twenty, Open Mercato, Ash, Celonis.

Web research, 2026-08-01, deliberately weighted towards criticism of event-driven design rather than
advocacy:

- Kaszubowski, [A guide to event handling in Elixir](https://mkaszubowski.com/2021/01/09/elixir-event-handling.html) — six delivery approaches, sync-first recommendation, outbox as the at-least-once mechanism
- AppSignal, [A Guide to Event-Driven Architecture in Elixir](https://blog.appsignal.com/2022/05/10/a-guide-to-event-driven-architecture-in-elixir.html) — delivery guarantees and failure modes per mechanism
- David Boyne, [How to Stop Your Event-Driven Architecture from Turning Into Chaos](https://boyney123.substack.com/p/how-to-stop-your-event-driven-architecture) — three governance failure modes
- Saša Jurić, [Towards Maintainable Elixir: Boundaries](https://medium.com/very-big-things/towards-maintainable-elixir-boundaries-ba013c731c0a) and [sasa1977/boundary](https://github.com/sasa1977/boundary)
- [allocator-one/oban-events](https://github.com/allocator-one/oban-events), [bitcrowd/carbonite](https://github.com/bitcrowd/carbonite)
- Zarar, [Trade-offs in Aggregate Design when implementing CQRS in Elixir](https://zarar.dev/elixir-cqrs-commanded/)
- [State of Elixir 2025](https://elixir-hub.com/surveys/2025) — monolith plus DDD is the norm; event sourcing and CQRS are a minority
- [Encore — Event-Driven Architecture in 2026](https://encore.dev/resources/event-driven-architecture); [Oban to implement the Outbox pattern](https://elixirforum.com/t/oban-to-implement-the-outbox-pattern/58274)

## Follow-ups this bundle created and nothing else tracks

- **The EventStorming workshop is architecturally load-bearing and has no canonical home.** §1 makes the
  contract's legitimacy depend on it, but the five-day structure exists only as draft landing-page copy in
  `output/2026-06-01 EH LandingPage/14-Service-Domain-Driven-Process-Modeling.md`, and `run/processes.md`
  is still a starter placeholder. It needs a playbook in `wiki/pns/` and a process in `run/`, not sales
  copy. Facilitation capacity (decision 007) should be tracked against it. **Largest open gap in the
  bundle.**
- **`company/market/erp/competition.md` has no Ash Framework row.** Ash is the closest competitor to this
  leg and is absent from the competitor file.
- **The OSS/commercial split touches `strategy/questions.md` items 1 and 2** — revenue architecture and
  open-source boundaries. Resolving the split should retire or narrow those questions.
- **`## Review triggers` is a proposed extension to `.templates/decision.md`.** Provisional decisions
  currently have nowhere to record what would reopen them, and this record has two sets of triggers that
  are doing real work.

## Status notes

Written in English to match the `decisions/` convention. A Polish walkthrough for the team session can be
generated from it.

The record is `proposed`, not accepted, and author and accepter are the same person — so the review is the
only independent gate. Three of four reviewers have been through it; Karol has not, and the three
questions for him are in [review-2026-08-03](~/Projects/ai/empowered-house-context/output/20260803-adr-008-review.md).
