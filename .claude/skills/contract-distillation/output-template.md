# Output Template - Contract Distillation

Use this exact markdown structure for each process the material describes.

Do not invent missing details. Mark unknowns explicitly. Every important claim needs a source
(transcript timestamp, speaker, whiteboard/photo reference, event-storming board reference) or an
explicit `unverified`.

---

```markdown
## [Process name, in the client's words]

**Input used:** [process-extraction output / raw transcripts / mixed — state which]
**Evidence quality:** [observed | stakeholder-stated | inferred | hypothesis | unclear]

### Event candidates

| # | Event (client's words, past tense) | Proposed technical name | **What depends on it having happened** | Verdict | Evidence |
|---|-------------------------------------|--------------------------|-----------------------------------------|---------|----------|
| 1 | [...] | `snake_case_name` | [a policy, an actor waiting, a deadline running, a terminal state, the fallback of a promise — or **nothing**] | fact / **field** | [source] |

*An empty dependency cell means `field`, and a field does not go into the contract. Keep the rejected
rows: they are what stops the next reader re-adding them, and the ratio of facts to fields is worth
knowing — on the run this column was added after, it was 7 to 15.*

### Payload shape, per event

| Event | Field | What it means (plain language) | Closest DSL type fit | Evidence |
|-------|-------|----------------------------------|------------------------|----------|
| [event] | [field] | [meaning] | [:id / :string / :integer / :timestamp / :enum / does not fit — say why] | [source] |

### Identity

- **Same-fact-twice rule:** [what the material says distinguishes a genuine duplicate from a new
  fact, or "not addressed" / "unclear"]
- **Evidence:** [source]

### Instance

- **What is "one case":** [description]
- **Can two run in parallel for the same actor:** [yes/no/unclear] — **what distinguishes them if so:** [...]
- **Evidence:** [source]

### Repeated events within one instance

| Event | Happens more than once per case? | What distinguishes occurrence 2 from occurrence 1 | Evidence |
|-------|-----------------------------------|----------------------------------------------------|----------|
| [event] | [yes/no/unclear] | [...] | [source] |

### Terminal states

| Ending | Good/bad | Evidence |
|--------|----------|----------|
| [...] | [good/bad/neutral] | [source] |

### Stages / gates

| Gate | What it blocks | Evidence |
|------|-----------------|----------|
| [X must happen before Y is possible] | [...] | [source] |

*Note if the material only supports "no claim about order" — do not invent a linear sequence.*

### Rejected as fields, not facts

| Candidate | Why nothing depends on it | Evidence |
|-----------|----------------------------|----------|
| [...] | [...] | [source] |

*Not a leftovers list — this is where a later reader checks whether a "missing" event was
overlooked or deliberately excluded, and absence cannot distinguish those two.*

### Trace candidates

| # | After (event) | Within (N, unit) | Then (event) | Or else (event) | Does timing bind the fallback too? | Who is this promised to | Evidence |
|---|----------------|--------------------|--------------|-------------------|-------------------------------------|--------------------------|----------|
| 1 | [...] | [...] | [...] | [...] | [yes/no/not stated] | [patient/payer/regulator/internal] | [source] |

### Cadence

- **Recurring on a schedule, or purely event-triggered:** [schedule / event-driven / unclear]
- **If scheduled, how often:** [...]
- **Evidence:** [source]

### Retain / sensitive data

| Field | Category | Handler needs raw value? | Suggested policy | Evidence |
|-------|----------|----------------------------|--------------------|----------|
| [field] | [health data / other PII / not sensitive] | [yes/no/unclear] | [persist/hash/drop — tentative] | [source] |

### External dependencies

| Dependency (business fact, not vendor name) | What "unavailable" looks like, in the client's words | Does "no answer" mean the same as "answered no"? | Evidence |
|-----------------------------------------------|--------------------------------------------------------|-----------------------------------------------------|----------|
| [...] | [...] | [...] | [source] |

### Rules and examples

| Rule ("when X then Y") | Example that worked (real numbers) | Example that went wrong (real numbers) | Evidence |
|--------------------------|--------------------------------------|-------------------------------------------|----------|
| [...] | [...] | [...] | [source] |

### Source / unverified summary

| Claim or number | Source | Or: unverified (team's own placeholder) |
|-------------------|--------|--------------------------------------------|
| [...] | [...] | [...] |

### Open questions for this process

| Question | Blocks | Evidence gap |
|----------|--------|----------------|
| [...] | [contract-writing / a specific DSL key] | [what's missing] |
```

---

After all processes, add:

```markdown
## Summary across processes

| # | Process | Claimed orderings (gates) | Terminal states | Trace candidates | Payload fields not fitting the closed type set | Biggest gap |
|---|---------|----------------------------|------------------|-------------------|---------------------------------------------------|-------------|
| 1 | [name] | [count] | [count, incl. bad endings] | [count] | [list, or none] | [...] |

*The first three columns are what the overlay verifies without a clock. The fourth is the timed
half, and it is normal for it to be small.*

## Cross-process findings

### Shared identity/instance patterns
- [...]

### Fields repeatedly not fitting the closed type set
- [field kind]: [which processes, and what workaround was considered]

### Processes with zero trace candidates
- [name]: [a fact about the domain, not a verdict on the process. Say what it verifies
  structurally instead — claimed orderings, gates, terminal states — and whether any of those
  orderings is one nobody enforces today, which is what the overlay exists to surface]

### Promises anchored backwards from a scheduled moment
- [name]: [not expressible as `trace`, which runs forwards from an observed fact. Say so, and say
  it belongs to the client application's reminder mechanism rather than to the contract]

### Readiness signal
- **Processes ready for a first contract draft:** [...]
- **Processes needing another confirmation pass with the client:** [...]
- **Judge readiness on structure first.** A process with clear instance, ordered stages and
  honest terminal states is ready whether or not it has a single `trace`.
```
