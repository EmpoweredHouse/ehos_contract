defmodule PNS do
  @moduledoc """
  The package's public surface.

  What would be the `pns_core` hex package — kept in `lib/pns/` beside the client
  application in `lib/taxvision/`, with the boundary enforced by `boundary` from
  the first commit. The structure is the one notes §15 foresee for the first
  client, so moving it out beside the client's repository is a `git mv`.
  """

  use Boundary,
    deps: [],
    exports: [
      Auth,
      Auth.Actor,
      Auth.Verifier,
      Auth.LocalToken,
      Check,
      Conformance,
      Contract,
      Deployment,
      Emission,
      Emitter,
      Event,
      EventHandling,
      Graph,
      Handler,
      Instance,
      Job,
      Payload,
      Registry,
      Trace
    ]

  @doc "An intention to emit an event, returned by a pure decision function."
  @spec event(atom(), map()) :: PNS.Emission.t()
  def event(name, payload \\ %{}), do: %PNS.Emission{name: name, payload: payload}

  defdelegate emit(contract, type, payload, ctx \\ %{}), to: PNS.Emitter
  defdelegate emit!(contract, type, payload, ctx \\ %{}), to: PNS.Emitter
  defdelegate emit_all(contract, emissions, ctx \\ %{}), to: PNS.Emitter
end
