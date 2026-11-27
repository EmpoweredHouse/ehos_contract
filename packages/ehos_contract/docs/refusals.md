# Compile refusals

This page lists each refusal of the compiler, with its code. It is for a developer who has a
compiler message and must find what the message refuses. To write a model that compiles, read
[Write a domain, a contract and a process module](contract.md).

## How to read a refusal

Each refusal starts with its code, for example `A3: …`. The letter of the code gives its family.
The codes do not change between versions. The sentence after the code can change.

The compiler checks a model at layers 1 to 4 of
["What is checked at which time?"](contract.md#what-is-checked-at-which-time). The column
"Checked in" gives the layer that refuses the code.

| # | Layer | When | What it checks |
| --- | --- | --- | --- |
| 1 | Schema | when the module compiles | the keys of the DSL: a key that is not known, a required key that is missing, a value of the wrong type. Spark gives these messages. They have no code. |
| 2 | One module | when the module compiles | the rules of one domain, contract or process module. The message gives the file and the line. |
| 3 | Implementation | when the implementation compiles | the macros of an implementation, at the `use` or the call that breaks a rule |
| 4 | Between modules | after Elixir compiles the project | a contract against its domain and its sibling contracts. The `:ehos_contract` compiler does this check. |

Layer 5, `mix ehos_contract.check`, is a task that you run. It reports errors, warnings and notices
by the names of its rules. Without the compiler `:ehos_contract`, it also repeats the rules between
modules as errors, with their codes. [The rules of the check](rules.md) lists them.

## The families

- [`N`: names](#refusals-n)
- [`F`: fields](#refusals-f)
- [`A`: units, commands and events](#refusals-a)
- [`T`: lifecycles](#refusals-t)
- [`U`: upcasts, the older versions of an event](#refusals-u)
- [`C`: who can issue a command](#refusals-c)
- [`P`: reactions, read models and queries](#refusals-p)
- [`R`: the process](#refusals-r)
- [`K`: consumed contracts](#refusals-k)
- [`S`: scenarios](#refusals-s)
- [`D`: the domain, and the names and scopes that a contract builds on it](#refusals-d)
- [`X`: a contract against its domain and its siblings](#refusals-x)
- [`I`: implementations](#refusals-i)

<a id="refusals-n"></a>

### `N`: names

| Code | Checked in | What is refused |
| --- | --- | --- |
| `N1` | One module | a name not snake_case; a name twice among: declarations of one kind; a unit's invariants; a command's, query's, policy's or effect's constraints; a process manager's constraints and invariants together; a process module's stages, promises or included events, an event included twice from one contract or two; a service's functions; a function's rules; commands, events, timers and consumed events together; a query named like a command or an event an actor records; two names that camelize alike among units, reactions, read models, queries or services of one kind, or among commands, events and consumed events; a label given and blank |
| `N2` | One module | a command, query, event, timer, consumed event or service function whose callback would be a reserved word, clash with `Kernel` or with `module_info`/`__info__`/`behaviour_info` at its arity, or take `evolve`; a command, query, event or consumed event named `state` or `row` |

<a id="refusals-f"></a>

### `F`: fields

| Code | Checked in | What is refused |
| --- | --- | --- |
| `F1` | One module, Between modules | a field named twice in one struct, starting with `__`, or otherwise not snake_case; an identity field typed by a built-in type other than `:id`, or typed `{:id, name}` or by a domain value in a generated identity; an identity field typed by a domain value that does not rest on `:id` (between modules) |
| `F2` | One module | a malformed field type; an enum that is empty, has a member that is not an atom or `{atom, label}`, repeats one, or labels one blank; a domain service function without `returns`, or with a malformed return type |
| `F3` | One module | `default:` on a field outside a `state`, including a domain value's field |
| `F4` | One module | an `optional:` or `personal:` event field that the `correlate` of a process manager handling the event names |
| `F5` | One module, Between modules | `personal:` naming what is not a required, non-personal `:id` field with `subject:` in the same struct; a domain value's field naming an undeclared subject; a personal field whose type holds personal data of its own |
| `F6` | One module | a unit's identity field declared again in its state, a command or an event |
| `F7` | One module, Between modules | a process manager's state field, or a command's or query's scope field, that is `personal:` (one module) or of a domain value holding personal data (between modules) |
| `F8` | One module, Between modules | a field a process manager's record is told by (an event's field its `correlate` names, a process manager's state field its `correlate` names, or the first local event's field an undeclared one takes its type from) that is not an `:id`, `{:id, entity}` or a domain value resting on `:id` (between modules) |
| `F9` | One module | a unit's identity, a process module's `correlate` or a process manager's `correlate` of more than 6 fields |
| `F10` | One module | `supplied_by: :host` on a field no request fills (a state's, a read model's row, an event no actor records), or on a command's `scope` field |

<a id="refusals-a"></a>

### `A`: units, commands and events

| Code | Checked in | What is refused |
| --- | --- | --- |
| `A1` | One module | a command with an empty `emits:`, or one naming an event of another unit |
| `A2` | One module | an event no command of its unit emits and that declares no `recorded_by:` |
| `A3` | One module | `rejects:` naming what is neither an invariant of the unit nor a constraint of the command |
| `A4` | One module, Between modules | a boundary consulting nothing; consulting an event neither local nor consumed, or one received from another application; a consult without `match:` or `where:`; `match:` naming a field twice, or on a field outside the boundary's identity, or one a local event lacks as a required, non-personal `:id` or domain value; a matched field of a local event typed by a domain value that does not rest on `:id` (between modules) |
| `A5` | One module | a unit or a process manager declaring `state` twice |
| `A6` | One module | a generated identity of more than one field, or with no command that `creates:` it; `creates:` on a command whose unit's identity is not generated |
| `A7` | One module | a command's constraint with the name of an invariant of its unit, or missing from the command's `rejects:` |
| `A8` | One module, Between modules | a command's `reads:` naming a field it does not have, a field of its unit's identity, an optional field or one not typed `{:id, entity}`; a name given twice; a command that reads, issued by a policy or a process manager; a field that identifies a unit (between modules) |
| `A9` | One module | a command's `actor_is` naming its unit's identity, which the caller fills, or a field outside its unit's state, not an `:id`, or personal; an `or_rejects:` that is not an invariant of the unit in the command's `rejects:`; on a command that `creates:` its aggregate or names nobody in `by:`; given twice |

<a id="refusals-t"></a>

### `T`: lifecycles

| Code | Checked in | What is refused |
| --- | --- | --- |
| `T1` | One module | an aggregate declaring `lifecycle` twice; a lifecycle without a status or an `initial`; a status named twice or not snake_case |
| `T2` | One module | a `transition` leaving no status; `initial` or `transition` naming a status the lifecycle does not declare or an event not of the aggregate; one event starting the aggregate in two statuses; one status and one event moving it twice |
| `T3` | One module | a status no `initial` reaches; a `final:` status a transition leaves; a status that is not final with no transition out |
| `T4` | One module | `from:` without `or_rejects:` or the other way round; `from:` naming an undeclared or final status, on an aggregate without a lifecycle, or on a command that `creates:` its aggregate; a command that `creates:` its aggregate and emits none of its initial events; `or_rejects:` naming what is not an invariant of the unit, or missing from `rejects:`; an emitted event no transition moves out of a status in `from:`; a status in `from:` none of the command's events leaves, when `rejects:` names no rule but `or_rejects:` |

<a id="refusals-u"></a>

### `U`: upcasts, the older versions of an event

| Code | Checked in | What is refused |
| --- | --- | --- |
| `U1` | One module | an event at `schema_version` n without exactly one `upcast from:` for each version below n, or with an `upcast` from n or later |
| `U2` | One module | an `upcast` renaming a field to the name of no field the event will have, to what is not a name, to itself, one field twice, or two fields to one; a `default:` for a field the event will not have, or one field given two; a step naming a `function:` and renaming or giving defaults too |
| `U3` | One module, Between modules | an `upcast` renaming the unit's identity, or renaming onto or giving a default to a field the log tags rows with (a required, non-personal `:id`, `:date` or `:timestamp`, or a domain value resting on one); a default for a personal field, or for a domain value holding personal data |
| `U4` | One module, Between modules | an `upcast` default that is not a value of its field's type, or is nil |

The compiler reads only the current declaration of an event. It cannot see that the fields of a
recorded version changed. `mix ehos_contract.schema --check` refuses that change. It compares the
fields with the fields that `ehos_contract.lock` recorded for each version.
[Change an event that already has rows](event-versions.md) tells how to do it.

<a id="refusals-c"></a>

### `C`: who can issue a command

| Code | Checked in | What is refused |
| --- | --- | --- |
| `C1` | One module | a command nobody can issue: no `by:`, and no policy or process manager of the contract issues it |

<a id="refusals-p"></a>

### `P`: reactions, read models and queries

| Code | Checked in | What is refused |
| --- | --- | --- |
| `P1` | One module | a policy or an effect handling an event neither local nor consumed; a policy or an effect handling no event (`handles: []`); a policy issuing a command not of this contract |
| `P2` | One module | an effect with `calls:` delivered `:in_transaction` |
| `P3` | One module | a policy or an effect delivered `:at_least_once` without `idempotency`; an `idempotency` owned `:downstream` outside an effect, owned `:infrastructure` by an effect or on a key other than `:event_id` |
| `P4` | One module | a process manager starting on nothing, with `correlate: []` or a field named twice in it, or `:in_transaction`; a trigger neither a local or consumed event nor (for `on`) its own timer; `sets`/`cancels` naming another timer; a timer without exactly one of `wait`/`at`, or `at` not a `:timestamp` state field; issuing a foreign command |
| `P5` | One module | a read model projecting an event neither local nor consumed; a query reading what is not a read model of this contract |
| `P6` | One module, Between modules | a read model with `table:` and no `key:`, or `key:` without `table:`; a table that is not a plain SQL name, is longer than 63 bytes, is the engine's or Oban's, or is shared by two read models; a key field that is not a row field, is named twice, is optional, personal or a list, or is typed by a domain value made of fields or a list |
| `P7` | Between modules | a query's param that a query string cannot carry: a list of values made of fields, a list of lists, or a value with a field that is a list or is made of fields, through a domain value's alias as well |

<a id="refusals-r"></a>

### `R`: the process

| Code | Checked in | What is refused |
| --- | --- | --- |
| `R1` | One module | a contract declaring nothing at all |
| `R2` | One module | a process module without `correlate`, with an empty one, with two, or naming a field twice |
| `R3` | One module | a process module with no stage, a stage that includes no event, or an `include:` entry naming no event or no contract module |
| `R5` | One module | a process module's promise whose `from`, `eventually` or `or_else`, or an `ends_on` event, the module does not include; `ends_on` declared twice |
| `R6` | One module | a duration that is not `{count, unit}`, counts a negative or non-integer number, has an unknown unit, or is longer than 100 years (a year counted as 366 days, a month as a twelfth of that): a process manager's timer's `wait`, a process module's `within` or `deadline`; a calendar unit in `within` or `deadline` (a timer's `wait` may use one); a process module's `deadline` declared twice, or without `ends_on` |

<a id="refusals-k"></a>

### `K`: consumed contracts

| Code | Checked in | What is refused |
| --- | --- | --- |
| `K1` | One module | `consumes` given a published name, which is `subscribe`d to; a sibling `consumes` of the contract itself, naming no events, renaming an event it does not consume, giving `as:` other than `[old: :new]`, or declaring fields |

<a id="refusals-s"></a>

### `S`: scenarios

| Code | Checked in | What is refused |
| --- | --- | --- |
| `S1` | One module | a scenario with no trigger or several; a trigger naming no command or query of the contract, an event nothing handles, or a recording of an event no actor records (`recorded_by:`); several handlers and no `target`, or a `target` that does not handle it; two scenarios with one description; a process module's scenario judging no promise, several, or one the module does not make |
| `S2` | One module | `given` outside the target's state: not the unit's own or consulted events, not a process manager's handled events, not events the query's read model projects; any `given` for a policy; in a process module, a `given` of an event the process does not include |
| `S3` | One module | scenario data naming undeclared fields or of the wrong built-in type; a `given` or a trigger missing a required field (identity excepted); an `at:` that is no ISO 8601 timestamp with an offset, or a given's earlier than the given before it; a given without `at:` before one with it |
| `S4` | One module, Between modules | `rejected` naming what the command does not `rejects:`, nor, where its fields or its identity hold a domain value, an invariant of one (between modules); a recording's naming no invariant of a domain value the event's fields hold (between modules) |
| `S5` | One module | `expect` naming an event outside the command's `emits:`; after a recording, any event but the one recorded |
| `S6` | One module | an outcome unfit for the target: a command or a recording without exactly one of `expect`/`rejected`; a reaction with no outcome, or issuing, setting, cancelling or ending what it does not; a `state` said twice, or of anything but a process manager; a query without one `answers` shaped as it returns; another kind's outcome; an effect or read model as target |
| `S7` | One module | an `actor` outside the command's `by:`, or on a scenario whose trigger is neither a command nor a recording; a recording without an `actor`, or with one outside the event's `recorded_by:`; an `as` without an `actor`, or on a scenario whose trigger is not a command |
| `S8` | One module | an invariant, or a command's constraint, that no `rejected` scenario (of that command, for a constraint) covers |
| `S9` | One module | a domain service's rule without examples; an example not `{[argument, …], result}` of the function's arity, with an argument or result of the wrong built-in type or `nil` where not optional; an example given twice |
| `S10` | One module | `illustrates:` naming what is not a constraint of the scenario's policy, process manager or query, nor an invariant of its process manager, or naming one twice; any `illustrates:` on a command's or a recording's scenario, which shows its rules with `rejected` |
| `S11` | One module | a process module's scenario without a `verdict:` or with one outside `:satisfied`, `:violated`, `:pending`, `:suspended`; `via:` on another verdict than `:satisfied`, outside `:eventually` and `:or_else`, or `:or_else` for a promise without one; `:violated` or `:suspended` for a promise without `within`, or `:suspended` without an `outage`; no given of the promise's `from`; a given or an outage after the moment of judgement |
| `S12` | One module | a scenario of a command that `reads:` an entity without a `given_entity` of it; a `given_entity` of an entity the command does not read, or in a scenario of anything else |

<a id="refusals-d"></a>

### `D`: the domain, and the names and scopes that a contract builds on it

| Code | Checked in | What is refused |
| --- | --- | --- |
| `D1` | One module | a subdomain's, context's, subject's, value's, entity's or external's name not snake_case; two values that camelize alike; a value named after a type Elixir builds in or a built-in field type; two subdomains, contexts, actors, subjects, values, entities or externals of one name; an external's operation or an actor's responsibility not snake_case or declared twice; a term defined twice in a context; a relation declared twice; a name that is both a context and an external; a label given and blank |
| `D2` | One module | two translations of a term into one language, or one into the context's own |
| `D3` | One module | a value with both or neither of a type and fields; `unit` on a value that is not numeric; `code: true` on a value that is not text, or with no invariant of its own or of a value it names; an undeclared `context:`; a malformed or unknown type, or a bad enum, a member's blank label included; values in a cycle; a value's field not snake_case, or named twice |
| `D4` | One module | an actor's name not snake_case; a human actor or the seed with `backed_by`; `backed_by` naming no external; an actor's `context:` the domain does not declare; `may_grant:` on a system actor or the seed, or naming the actor itself, a system, the seed, an undeclared actor or one twice; `may_grant:` rules that lead back to an actor; `not_seeded:` on an actor that is not the `:seed`, or naming a declaration twice |
| `D5` | One module | a relation whose roles do not fit its type (directed or symmetric); an end the domain does not declare; an external in a symmetric relation; a directed one with no context end; a context related to itself; a word of a relation's `terms` pair that its context's glossary does not define |
| `D6` | One module | `{:id, entity}` naming an undeclared entity; an entity with an undeclared context, an `identity` not in snake_case or declared again as a field, or with a field twice, not snake_case, malformed, of an undeclared subject, with `default:` or `personal:`, or holding personal data |
| `D7` | One module | a context in a subdomain the domain does not declare |
| `D8` | One module | a value's or entity's field `issued_by:`, or an entity's own, naming what is not an external of the domain |
| `D9` | One module | a value invariant not snake_case, clashing with Elixir at arity 1, named `:required`/`:type`/`:generated`/`:supplied`/`:unknown`, or twice; no `violated_by:` or `satisfied_by:` example; an example `nil`, not of the value's type, in both lists or twice in one; a satisfying example another invariant lists as violating |
| `D10` | One module, Between modules | a query without `by:`; a query scope not a same-typed read-model field and param; a command scope without `by:`, not its field or identity, optional, or a generated identity it creates; a list scope, or a value with fields; a `by:` actor not carrying the scope |
| `D11` | One module, Between modules | a domain's `name:` that is not one lowercase segment of letters, digits, `_` and `-`, starting with a letter and not ending with a dash; a publication from no local event, with no fields, unknown, personal or personal-data fields, or `idempotent_on:` outside them; a publication's name not snake_case, or shared in the application; a publication that writes `as:`; a `subscribe` named by a string, by a key that is not a namespace, a snake_case publication and a version, without `as:`, or listing no fields; a contract without an `id:`; a contract's or a process module's `id:` that is not the namespace and dotted snake_case segments, is versioned or is over 100 bytes; a contract's or a process module's outside the domain's `name:` |
| `D12` | One module | a read model, an effect or a process manager taking an event received from another application, which only a policy takes, in its inbox |
| `D13` | One module | a domain's `time_zone:` the time zone database Elixir is configured with does not know |
| `D14` | Between modules | two commands, queries or recorded events of one domain with the same name, and so the same capability |

<a id="refusals-x"></a>

### `X`: a contract against its domain and its siblings

| Code | Checked in | What is refused |
| --- | --- | --- |
| `X1` | Between modules | a contract's or a process module's `domain:` naming a module that is not a compiled domain, or a contract's `context:` naming none of its contexts |
| `X2` | Between modules | `by:`, `recorded_by:` or a scenario's `actor` naming no actor of the domain, or an actor of another context; a process module's `accountable` naming no actor of the domain (of any context, since the module crosses them), or its seed; a command with `actor_is` whose `by:` names no `:human` actor; its scenario by a person without `as`; `as` beside a `:system` actor, or on a command without `actor_is` |
| `X3` | Between modules | a field, identity or return type that is neither built in nor a value of the domain; `{:id, name}` naming neither an entity of the domain nor a unit of its contracts compiled in the same project (a domain's contracts compile in one project), or more than one of them, in a field, an identity or a domain service's result; a `subject:` the domain does not declare |
| `X4` | Between modules | `depends_on`, `calls` or a field's `issued_by` naming no external of the domain; a call naming an operation its external does not declare, or naming none of an external that declares some; a process module's promise whose `waits_on` names no external of the domain, one its `eventually` or `or_else` already depends on, or one no contract the process includes depends on or calls; a process module's scenario with an `outage` of no external the promise's `eventually` or `or_else` depends on or the promise `waits_on` |
| `X5` | Between modules | `consumes` naming what is not a compiled contract, a contract of another domain, or an event the sibling does not declare; a process module's `include:` naming the same, or an event the contract receives from another application or consumes from a sibling rather than declares |
| `X6` | Between modules | a sibling event's field that a process manager's `correlate` (on an event it handles) or a boundary's `match` relies on, missing there, of another type (an `:id` where no local event types it), optional or personal; a process module's `correlate` field missing in an included event, optional or personal there, not an `:id`, or another identifier than in the other included events |
| `X7` | Between modules | two process modules of the system with one `id:`, which keys their runs; two contracts with one `id:`, which types their events; two contracts that publish one publication name, which builds one published name |
| `X8` | Between modules | a declaration with two implementations |
| `X9` | Between modules | a scenario value or a rule example not fitting its domain type; a sibling event's scenario data with unknown fields, missing required ones (in `given` or the trigger) or ill-typed values; a `given_entity` row with a field its entity lacks, missing its identity or a required field, or with an ill-typed value; a process module's `given` with data the event its contract declares does not fit, in the same ways, or leaving out its unit's identity |
| `X10` | Between modules | a policy or a read model taking an event of a sibling contract of another context without declaring `delivery` |
| `X11` | Between modules | a reference from one context into another against the relation between them: from the upstream context of a directed relation into its downstream one, or across `separate_ways`; a reference is consuming a contract, naming an entity or a unit (`{:id, name}`), or using a value declared with `context:` |
| `X12` | Between modules | a read model, an effect or a process manager taking an event of a sibling contract, or a boundary consulting one, across an `anticorruption_layer`, where only a policy takes it |
| `X13` | Between modules | consuming an event a sibling contract does not `publish` across an `open_host_service` or a `published_language` |

<a id="refusals-i"></a>

### `I`: implementations

| Code | Checked in | What is refused |
| --- | --- | --- |
| `I1` | Implementation | `use` with an unknown kind, no declaration or several, or naming one that does not exist, is of another kind, or is a value without invariants; a module binding a second declaration |
| `I2` | Implementation | a callback the declaration needs and the module does not define |
| `I3` | Implementation | `evolve` without a clause for an event its state is kept from, and no unguarded catch-all |
| `I4` | Implementation | `emit` or `issue` given something other than a struct literal, a list of them, or a `for` producing them (one with `into:` or `reduce:` produces something else); `emit` of an event the enclosing command, or outside a command any command of the unit, does not emit |
| `I5` | Implementation | `reject` given no atom literal, or one the enclosing command (outside one, any command of the unit) does not `rejects:` |
| `I6` | Implementation | `issue` of a command outside the `issues:` of the enclosing reaction, or outside a reaction of any |
| `I7` | Implementation | a macro where its kind does not allow it: `emit` and `reject` outside a unit, `issue` outside a policy or process manager |


## Next steps

- [Write a domain, a contract and a process module](contract.md): how to write a model that compiles.
- [The rules of the check](rules.md): what `mix ehos_contract.check` reports about a model that compiles.
- [The glossary](glossary.md): the words of the contract language.

## Background

The reason for each rule is in section 6 of
[the design record of the contract language](https://github.com/EmpoweredHouse/ehos_contract/blob/main/docs/adr/contract-v2.md),
in the repository.
