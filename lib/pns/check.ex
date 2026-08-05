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
