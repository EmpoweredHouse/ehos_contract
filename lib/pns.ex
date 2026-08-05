defmodule PNS do
  @moduledoc """
  Powierzchnia publiczna pakietu.

  To, co byłoby pakietem hex `pns_core` — trzymane w `lib/pns/` obok aplikacji
  klienta w `lib/taxvision/`, granica pilnowana przez `boundary` od pierwszego
  commita. Struktura jest ta, którą notatki §15 przewidują dla pierwszego
  klienta, więc przeniesienie obok repozytorium klienta jest `git mv`.
  """

  use Boundary,
    deps: [],
    exports: [
      Auth,
      Auth.Actor,
      Auth.Verifier,
      Auth.LocalToken,
      Contract,
      Emission,
      Emitter,
      Event,
      EventHandling,
      Graph,
      Handler,
      Instance,
      Job,
      Payload,
      Registry
    ]

  @doc "Zamiar wyemitowania zdarzenia, zwracany przez czystą funkcję decyzyjną."
  def event(name, payload \\ %{}), do: %PNS.Emission{name: name, payload: payload}

  defdelegate emit(contract, type, payload, ctx \\ %{}), to: PNS.Emitter
  defdelegate emit!(contract, type, payload, ctx \\ %{}), to: PNS.Emitter
  defdelegate emit_all(contract, emissions, ctx \\ %{}), to: PNS.Emitter
end
