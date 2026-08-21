defmodule PNS.Check do
  @moduledoc """
  **Static** checks: the contract against the binary, without a single query
  against the log.

  The product plan separates the two halves of verification, and that separation
  has a consequence for the code: this half belongs to CI, is cheap and immediate,
  and **needs no interface**. The other half, the behavioural one, lives in
  `PNS.Conformance` and reads the log.

  The logic was moved here out of the mix task, where it was a private function —
  that is, **logic with no test**. A check nobody checks quietly stops working,
  and this happens to be the check the ADR §15 review trigger rests on. The rest
  of `mix pns.check` should follow the same route; recorded in `PLAN.md`.
  """

  @typedoc "One module subscribing upstream of where it publishes."
  @type backward_edge :: %{
          module: module(),
          process: atom(),
          publishes_in: atom(),
          subscribes_in: atom()
        }

  @doc """
  Backward edges: a module that **subscribes to an event from a later stage** than
  the one it publishes into.

  This is the signature of compensation smearing and an explicitly named review
  trigger from ADR §15: one backward edge is normal, a growing count means the
  decision "processes watched, not steered" is not holding.

  Counted **by stage, not by an event's position in a list**: within a stage the
  contract claims nothing about order, so two events of the same stage are never a
  backward edge. The version that counted by position produced false alarms
  exactly where the workshop talks about things happening in parallel.
  """
  @spec backward_edges() :: [backward_edge()]
  def backward_edges do
    stage_of = stage_index()

    PNS.Registry.handlers()
    |> Enum.group_by(& &1.module)
    |> Enum.flat_map(fn {module, handlers} ->
      subscribed = for h <- handlers, pos = stage_of[h.event], do: pos
      published = for h <- handlers, e <- h.publishes, pos = stage_of[e], do: pos

      for {process, sub_index, sub_stage} <- subscribed,
          {^process, pub_index, pub_stage} <- published,
          sub_index > pub_index do
        %{module: module, process: process, publishes_in: pub_stage, subscribes_in: sub_stage}
      end
    end)
    |> Enum.sort_by(&{to_string(&1.module), to_string(&1.process)})
  end

  @typedoc "An assertion whose subject is finer-grained than the run it is counted in."
  @type finer_than_its_run :: %{
          contract: module(),
          trace: atom(),
          from: atom(),
          identity: [atom()],
          process: atom(),
          instance: [atom()]
        }

  @doc """
  Assertions whose `from` event is identified by **more** than the run is —
  a promise made per item, evaluated once per run.

  ## Why this is worth a check rather than a paragraph

  `PNS.Trace` produces **one verdict per instance**: the window opens on the first
  `from` in the run and closes on the first hit after it. Where the run holds many
  of the thing being promised about, one fulfilment satisfies all of them, and the
  fulfilment need not even concern the same item — the evaluator never compares
  payloads.

  The compile gates already refuse a `trace` spanning two processes and a calendar
  unit in `within`, both loudly and at build time. This one compiles, emits,
  evaluates, and reports `satisfied`. **It is the only failure of the three that
  fails towards good news**, which is the direction that costs a report its
  credibility.

  ## The signal, and why it is static

  `identity` is what makes two occurrences the same fact; `instance` is what makes
  them the same run. When the first is strictly finer than the second, the contract
  has said, in its own vocabulary, that a run contains several of these — so an
  assertion anchored there is about the items and is being counted over the run.

  Found in a monthly settlement, where a run is one counterparty in one month and
  the invariant is about each delivered item in it. That case never reached a
  `trace`, because writing it by hand exposed the problem; the case that did reach
  one is `ProcessShapes.Rig`, and `test/trace_granularity_test.exs` pins the wrong
  answer it produces.

  ## What it does not catch

  An event with **no** `identity` at all, which is the common case: the contract
  then says nothing about repetition and this check has nothing to compare. An
  assertion anchored on a fact that happens once per run — a case closing, a
  service ending — needs no `identity` at all, so there is nothing to compare and
  nothing to report. Correct, and invisible to this check either way.

  Reported rather than refused. The honest fix is usually to key the process by the
  thing the promise is about, and that is a modelling decision; sometimes the
  anchoring fact already belongs to another process and there is currently nothing
  to write instead.

  ## Why it takes a list of contracts

  Every check here reads the registry, and the registry is the binary that runs — so
  a fixture built to be a modelling error would put a warning on every `mix pns.check`
  in this repository for the rest of its life. The argument exists so a deliberately
  wrong contract can be handed straight to the check without joining the registry.
  Omitted, it is the registry, which is what every caller outside a test wants.
  """
  @spec assertions_finer_than_their_run([module()] | nil) :: [finer_than_its_run()]
  def assertions_finer_than_their_run(contracts \\ nil) do
    for contract <- contracts || PNS.Registry.contracts(),
        trace <- contract.traces(),
        event = Enum.find(contract.events(), &(&1.name == trace.from)),
        identity = event && event.identity,
        process = contract.process_of(trace.from),
        process != nil,
        finer?(identity, process.instance) do
      %{
        contract: contract,
        trace: trace.name,
        from: trace.from,
        identity: identity,
        process: process.name,
        instance: process.instance
      }
    end
    |> Enum.sort_by(&{inspect(&1.contract), to_string(&1.trace)})
  end

  # Strictly finer: every field the run is keyed by is in the fact's key, and the
  # fact's key has at least one more. Equal keys are the ordinary, correct case —
  # one fact per run — and a key that merely *differs* is a modelling error of a
  # different kind, reported by `facts_not_keyed_by_their_run/1`.
  #
  # **Compared as sets, and that was a bug.** The list comparison called
  # `[:b, :a]` finer than `[:a, :b]`, because the two lists are not equal — but a
  # key is a set of fields, and writing its fields in another order identifies
  # exactly the same thing. The false positive landed on the one check whose whole
  # job is to be believed about the direction a report is wrong in, and the fix a
  # reader would reach for is to reorder a keyword list, which changes nothing.
  @spec finer?([atom()], [atom()]) :: boolean()
  defp finer?(identity, instance) do
    identity = MapSet.new(identity)
    instance = MapSet.new(instance)

    MapSet.subset?(instance, identity) and not MapSet.equal?(instance, identity)
  end

  @typedoc "An event whose identity does not contain the run identity of its process."
  @type unkeyed_by_run :: %{
          contract: module(),
          event: atom(),
          identity: [atom()],
          process: atom(),
          instance: [atom()],
          missing: [atom()]
        }

  @doc """
  Events whose `identity` does not contain the fields their process keys a run by.

  ## The two shapes this covers, and why they are one finding

  `identity: [:x]` under `instance: [:a]` is a fact keyed by something unrelated to
  its run. `identity: [:a, :x]` under `instance: [:a, :b]` is a fact keyed by half
  of it. Neither is equal to the run key and neither is finer than it, so
  `assertions_finer_than_their_run/1` says nothing about either — its subject is a
  key that contains the run and says more, and these say **less**.

  ## Why it is a check of its own rather than a branch of that one

  A different population, a different consequence, a different fix.

  The population is every declared event, not the anchor of an assertion: the damage
  does not need a `trace` to exist.

  The consequence is upstream of any report. `PNS.Job` builds the asynchronous
  idempotency key out of `identity` and nothing else, so when the identity does not
  contain the run, the same field values occurring in two different runs produce the
  same key. The client's idempotency table then reads the second fact as a repeat of
  the first and its handler never runs — a consequence skipped, in silence, with the
  log still showing both events. The other check reports a verdict that is too kind;
  this one reports work that quietly did not happen.

  The fix differs too. The finer case is usually fixed by rekeying the **process**,
  because the promise is about the item. This one is usually fixed on the **event**,
  by putting the run's fields into the fact's key where they were simply forgotten —
  the run fields are already in the payload, since a compile gate requires it.

  Reported rather than refused, for the same reason as its neighbour: an identity is
  a modelling claim, and there are contracts where the fact genuinely is global and
  the process is the thing keyed wrongly. A gate would decide that for the author.

  ## What it does not catch

  An event with no `identity` at all — the common case, and correct wherever the fact
  happens once per run. `PNS.Job` then keys on the event's own identifier, which
  collides with nothing.
  """
  @spec facts_not_keyed_by_their_run([module()] | nil) :: [unkeyed_by_run()]
  def facts_not_keyed_by_their_run(contracts \\ nil) do
    for contract <- contracts || PNS.Registry.contracts(),
        event <- contract.events(),
        identity = event.identity,
        identity != nil,
        process = event.process && contract.process(event.process),
        process != nil,
        missing = process.instance -- identity,
        missing != [] do
      %{
        contract: contract,
        event: event.name,
        identity: identity,
        process: process.name,
        instance: process.instance,
        missing: missing
      }
    end
    |> Enum.sort_by(&{inspect(&1.contract), to_string(&1.event)})
  end

  @typedoc "One name declared by more than one contract."
  @type collision :: %{name: atom(), contracts: [module()]}

  @doc """
  Event names declared by more than one contract.

  ## What is actually ambiguous, and what is not

  Not `PNS.Registry.declared_events/0`: it tags every event with the contract it came
  from, so both survive the list intact. Not `contract.process_of/1` either — that
  function is generated per contract and can only see its own events.

  The ambiguity is one level down, in **every lookup keyed by an event name alone**,
  and dispatch is one of them. `PNS.Registry.handlers_for/1`, `sync_handlers_for/1`
  and `async_handlers_for/1` filter handlers on `event` and never look at `contract`,
  and `PNS.Emitter` calls them with nothing but the event's name. So emitting an event
  from contract A **runs contract B's handlers** — a foreign process's consequences,
  executed inside A's transaction, against a payload declared by A.

  Two more readers merge silently rather than cross-firing. `PNS.Graph.overlay/1`
  indexes nodes by event name, so one of the two events supplies the process and
  contract for both. `PNS.Check.stage_index/0` does the same, so backward-edge
  detection reads one contract's stages against the other's handlers.

  ## Why an error rather than a warning

  This is not a modelling opinion the engine has no business overruling. Nothing here
  is expressible correctly: there is one namespace for event names because dispatch
  has one, and two contracts inside it means the wrong code runs. Every symptom of it
  points somewhere else — a handler that "sometimes fires twice", a graph whose
  process labels are wrong — so it is exactly the kind of thing worth failing a build
  over rather than leaving to be discovered.
  """
  @spec event_names_declared_twice([module()] | nil) :: [collision()]
  def event_names_declared_twice(contracts \\ nil) do
    collisions(contracts, fn contract -> Enum.map(contract.events(), & &1.name) end)
  end

  @doc """
  Process names declared by more than one contract.

  A run's identity is `"<process>|<values>"` (`PNS.Instance`) and carries no trace of
  the contract, so two processes with one name write into one namespace in the log's
  `instance_id` column. Where their `instance` fields also coincide — likely, since a
  shared name usually means a shared subject — runs of one **are** runs of the other,
  and no query can separate them afterwards. The log keeps what was written.

  What reads that column reads it by name too: `PNS.Graph.overlay/1` counts runs per
  process name, so the denominator every path report divides by is the sum of both.
  `PNS.Trace` is the exception — it filters by contract, so assertions stay honest
  while the coverage numbers beside them do not, which is a worse mixture than either
  being wrong alone.

  An error for the same reason as its neighbour: the collision is in a namespace the
  engine owns, and neither contract can be repaired without renaming.
  """
  @spec process_names_declared_twice([module()] | nil) :: [collision()]
  def process_names_declared_twice(contracts \\ nil) do
    collisions(contracts, fn contract -> Enum.map(contract.processes(), & &1.name) end)
  end

  @spec collisions([module()] | nil, (module() -> [atom()])) :: [collision()]
  defp collisions(contracts, names) do
    for contract <- contracts || PNS.Registry.contracts(), name <- names.(contract) do
      {name, contract}
    end
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.filter(fn {_name, declarers} -> length(declarers) > 1 end)
    |> Enum.map(fn {name, declarers} -> %{name: name, contracts: Enum.sort(declarers)} end)
    |> Enum.sort_by(&to_string(&1.name))
  end

  @typedoc "An assertion with no deadline, which therefore has no failing case."
  @type unfalsifiable :: %{contract: module(), trace: atom(), from: atom(), eventually: atom()}

  @doc """
  Assertions declared without `within`.

  `PNS.Trace` treats a missing deadline as no deadline: any occurrence at or after
  `from` satisfies the assertion, and where nothing occurs the verdict stays
  `:pending` for ever, because the window a violation needs to be past never closes.
  So the assertion has **no failing case at all** — it is satisfied or it is waiting,
  and it can be neither refuted nor confirmed by anything that fails to happen.

  That reads in the report as an assertion being met, which is why it is worth a line
  rather than a paragraph in a moduledoc. `within` is optional in the DSL and stays
  optional: "eventually, with no deadline" is a legitimate thing to say about a
  process nobody has agreed a number for yet, and the honest handling of a number
  nobody confirmed is `unverified`, not a compile error. An `info` says the sentence
  is unfalsifiable as written without deciding what it should have said.

  Recorded as a candidate in `PLAN.md` and in `PNS.Trace`'s own comment since the
  evaluator was written; this is that candidate.
  """
  @spec unfalsifiable_assertions([module()] | nil) :: [unfalsifiable()]
  def unfalsifiable_assertions(contracts \\ nil) do
    for contract <- contracts || PNS.Registry.contracts(),
        trace <- contract.traces(),
        is_nil(trace.within) do
      %{contract: contract, trace: trace.name, from: trace.from, eventually: trace.eventually}
    end
    |> Enum.sort_by(&{inspect(&1.contract), to_string(&1.trace)})
  end

  @doc """
  Whether there is nothing at all to check.

  **A report of `0 errors, 0 warnings, 0 notices` is what a healthy repository looks
  like, and it is also what an engine scanning the wrong application looks like.** The
  two are indistinguishable, and the second one happened here the first time the
  engine compiled as its own package: it defaulted to its own name, scanned itself,
  found no contracts and said everything was fine.

  Configuration fixed the default; it did not fix the silence. `PNS.Registry.load!/1`
  raises for an application that is not loaded — a typo — but an application that is
  loaded and simply holds no contracts is not a typo and cannot be distinguished from
  one that does, so the scan returns nothing and every check downstream iterates over
  an empty list and finds nothing wrong.

  A warning rather than an error, because it is the true state of a repository on the
  day before its first contract, and a check that fails a build for being new gets
  removed before it ever catches the real case.
  """
  @spec no_contracts?([module()] | nil) :: boolean()
  def no_contracts?(contracts \\ nil), do: (contracts || PNS.Registry.contracts()) == []

  @typedoc "One event with more than one synchronous handler."
  @type competing_handlers :: %{event: atom(), modules: [module()]}

  @doc """
  Events with more than one synchronous handler, in the order those handlers will run.

  Reported rather than forbidden, because two handlers writing disjoint derived state
  in one transaction are legitimate and order-independent. What is not legitimate is
  **depending** on their order: `PNS.Registry` sorts them so a build reproduces, and
  that order is alphabetical by module name, which is a fact about spelling rather
  than about the process. Rename a module and it changes silently.

  So this is a warning about a shape: if the order matters, the contract is expressing
  sequence through a coincidence, and the fix is in the contract — one handler
  publishing an event the other subscribes to, which makes the sequence a declared
  path the overlay can see.

  Not a compile error, because the two handlers are in different modules and neither
  knows about the other while compiling. It is a whole-program property, so it belongs
  where the whole-program checks are.
  """
  @spec competing_sync_handlers() :: [competing_handlers()]
  def competing_sync_handlers do
    PNS.Registry.handlers()
    |> Enum.reject(& &1.async)
    |> Enum.group_by(& &1.event)
    |> Enum.filter(fn {_event, handlers} -> length(handlers) > 1 end)
    |> Enum.map(fn {event, _} ->
      %{event: event, modules: Enum.map(PNS.Registry.sync_handlers_for(event), & &1.module)}
    end)
    |> Enum.sort_by(&to_string(&1.event))
  end

  # An event's stage is on the event, and the process holds only the order of
  # stages — so position is the index of the stage in that order.
  @spec stage_index() :: %{atom() => {atom(), non_neg_integer(), atom()}}
  defp stage_index do
    for event <- PNS.Registry.declared_events(),
        process = event.process && event.contract.process(event.process),
        index = Enum.find_index(process.stages, &(&1 == event.stage)),
        into: %{} do
      {event.name, {process.name, index, event.stage}}
    end
  end
end
