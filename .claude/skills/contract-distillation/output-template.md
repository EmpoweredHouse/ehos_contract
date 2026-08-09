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

| # | Event (client's words, past tense) | Proposed technical name | Belongs to this process because | Evidence |
|---|-------------------------------------|--------------------------|----------------------------------|----------|
| 1 | [...] | `snake_case_name` | [...] | [source] |

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

| # | Process | Trace candidates found | Payload fields not fitting the closed type set | Biggest gap |
|---|---------|--------------------------|---------------------------------------------------|-------------|
| 1 | [name] | [count] | [list, or none] | [...] |

## Cross-process findings

### Shared identity/instance patterns
- [...]

### Fields repeatedly not fitting the closed type set
- [field kind]: [which processes, and what workaround was considered]

### Processes with zero trace candidates
- [name]: [this is a real finding — a process with no falsifiable promise is not
  verification-worthy yet, not a gap in this skill]

### Readiness signal
- **Processes ready for a first contract draft:** [...]
- **Processes needing another confirmation pass with the client:** [...]
```
