# Output template — contract distillation

The domain once, then one section per process. Do not invent missing details; mark unknowns
explicitly. Every claim that matters carries a source (transcript timestamp, speaker, board
reference) or an explicit `unverified`.

---

```markdown
# [Client] — distillation, [date]

**Input used:** [process-extraction output / raw transcripts / mixed — say which]

## Domain

### Subdomains and contexts

| Context (client's words) | Technical name | Subdomain | Core / supporting / generic | Evidence |
|---|---|---|---|---|
| [...] | `snake_case` | [...] | [...] | [source] |

### Glossary, per context

| Context | Term | Definition, as people gave it | Words to avoid | Translation | Evidence |
|---|---|---|---|---|---|
| [...] | [...] | [...] | [...] | [or none] | [source] |

### Relations between contexts

| Upstream | Downstream | How (conforms / translates / separate ways / …) | Evidence |
|---|---|---|---|
| [...] | [...] | [...] | [source] |

### Actors

| Actor (client's words) | Human / system | Backed by (system only) | Context | Evidence |
|---|---|---|---|---|
| [...] | [...] | [external or —] | [...] | [source] |

### Subjects of personal data

| Subject | Identified by | Evidence |
|---|---|---|
| [patient / employee / …] | [which identifier — never a natural one such as a national id number as the key] | [source] |

### Values

| Value | Shape and unit | What makes one invalid | A valid example | An invalid example | Evidence |
|---|---|---|---|---|---|
| [money / period / tax number] | [integer, cents / "YYYY-MM" / …] | [...] | [...] | [...] | [source] |

### External systems

| System (what it does for the business, not the vendor) | Sends / receives / both | What "unavailable" looks like, in the client's words | "No answer" = "answered no"? | Evidence |
|---|---|---|---|---|
| [...] | [...] | [...] | [...] | [source] |

---

## [Process name, in the client's words]

**Context:** [...] · **Evidence quality:** [observed | stakeholder-stated | inferred | hypothesis | unclear]

### Events, and the candidates that are not

| # | Candidate (client's words, past tense) | Proposed name | **What depends on it having happened** | Verdict | Evidence |
|---|---|---|---|---|---|
| 1 | [...] | `snake_case` | [a rule refuses after it, a reaction takes it, an actor waits, a promise runs from it, it ends the run — or **nothing**] | event / **field** | [source] |

*An empty dependency cell means `field`, and a field is not an event. Keep the rejected rows: they
stop the next reader re-adding them, and the ratio is worth knowing — on the run this column was
added after, it was 7 events to 15 fields.*

### Decided or recorded

| Event | Decided by a command (its name, who may issue it) | Or recorded (observed by whom, answered by which system) | Can the asking be refused? | Evidence |
|---|---|---|---|---|
| [...] | [...] | [...] | [yes, by which rule / no] | [source] |

### What must stay true

| Rule (client's sentence) | Over one thing, or across several | Refused case, with real data | Evidence |
|---|---|---|---|
| [...] | [one visit / every visit of a payer in a period] | [...] | [source] |

*Rules on one command's own data (an amount is positive) are that command's constraints; mark them.*

### Fields

| Event or command | Field | What it means | Closest type | Personal, and whose | Evidence |
|---|---|---|---|---|---|
| [...] | [...] | [...] | [identifier / typed text / number / decimal / yes-no / date / time / one of / list / a domain value / does not fit — why] | [no / yes, the patient's] | [source] |

### The run

- **One case, start to end:** [...]
- **Two in parallel for one actor:** [yes / no / unclear] — **what tells them apart:** [...]
- **Events that repeat within one case**, and what distinguishes the second: [...]
- **Evidence:** [source]

### Terminal states

| Ending | Good / bad / neutral | Evidence |
|---|---|---|
| [...] | [...] | [source] |

### Stages and gates

| Gate (X must happen before Y is possible) | What it blocks | Claimed or merely typical | Evidence |
|---|---|---|---|
| [...] | [...] | [...] | [source] |

*If the material supports no claim about order, say so; do not invent a sequence.*

### Reactions

| When (event) | Then | Kind (automatic step / tell or ask a system / chase if not in time) | Together with the event, or may follow it | Evidence |
|---|---|---|---|---|
| [...] | [...] | [...] | [...] | [source] |

### What people read

| What (list, total) | Who reads it | Narrowed to what | Evidence |
|---|---|---|---|
| [...] | [...] | [their clinic / their clients / all] | [source] |

### Promises

| # | After (event) | Within (N, unit) | Then (event) | Or else (event) | Does the time bind the fallback? | Promised to whom | Evidence |
|---|---|---|---|---|---|---|---|
| 1 | [...] | [...] | [...] | [...] | [yes / no / not stated] | [patient / payer / regulator / internal] | [source] |

### Deadline, recurrence, accountability

- **Deadline on the whole case:** [N, unit / none stated] — [source]
- **Recurring on a schedule, or triggered:** [schedule, how often / triggered / unclear] — [source]
- **Who answers for the process:** [role] — [source]

### Scenarios

| Given (what had happened) | When (asked, or arrived) | Then (what followed, or which rule refused it) | Real case? | Evidence |
|---|---|---|---|---|
| [...] | [...] | [...] | [yes, from … / constructed] | [source] |

*Every rule above needs a row where it refused.*

### Source / unverified

| Claim or number | Source | Or: unverified (the team's placeholder) |
|---|---|---|
| [...] | [...] | [...] |

### Open questions

| Question | Blocks | What is missing |
|---|---|---|
| [...] | [a declaration, a promise, a field] | [...] |
```

---

After all processes:

```markdown
## Across processes

| Process | Events / fields rejected | Rules with refused cases | Gates | Terminal states | Promises | Fields not fitting a type |
|---|---|---|---|---|---|---|
| [name] | [n / n] | [n of n] | [n] | [n, bad endings included] | [n] | [list, or none] |

*Gates, terminal states and the declared paths are what the report verifies without a clock. The
promises are the timed half, and it is normal for that column to be small.*

### Values and identifiers several processes share
- [...]

### Processes with no promise
- [name]: [a fact about the domain, not a verdict. Say what it verifies structurally instead, and
  whether one of its orderings is one nobody enforces today — which is what the report surfaces]

### Reminders anchored before a scheduled moment
- [name]: [not a promise, which runs forward from an observed event; a timer, or the client's own
  scheduling]

### Readiness
- **Ready for a first domain and contract:** [...]
- **Needing another pass with the client:** [...]
- **Judge readiness on structure first.** A process with a clear run, ordered stages, honest
  terminal states and rules with refused cases is ready whether or not it has a promise.
```
