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

  Found in Rehmed's monthly payer settlement, where a run is one payer in one month
  and the invariant is about each delivered visit in it. That case never reached a
  `trace`, because writing it by hand exposed the problem; the case that did reach
  one is `ProcessShapes.Rig`, and `test/trace_granularity_test.exs` pins the wrong
  answer it produces.

  ## What it does not catch

  An event with **no** `identity` at all, which is the common case: the contract
  then says nothing about repetition and this check has nothing to compare. Both
  Rehmed assertions anchor on `visit_completed`, which has no `identity` because a
  visit ends once — correct, and invisible to this check either way.

  Reported rather than refused. The honest fix is usually to key the process by the
  thing the promise is about, and that is a modelling decision; sometimes the
  anchoring fact already belongs to another process and there is currently nothing
  to write instead.
  """
  @spec assertions_finer_than_their_run() :: [finer_than_its_run()]
  def assertions_finer_than_their_run do
    for contract <- PNS.Registry.contracts(),
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
  # different kind, not this one.
  @spec finer?([atom()], [atom()]) :: boolean()
  defp finer?(identity, instance) do
    identity != instance and Enum.all?(instance, &(&1 in identity))
  end

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
