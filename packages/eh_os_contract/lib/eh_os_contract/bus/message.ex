defmodule EhOsContract.Bus.Message do
  @moduledoc """
  One integration event on the way between two applications (v2 §16).

  - `id` — `<source event id>/<publish name>`, the same every time the relay publishes
    it, so the subscriber's inbox recognises a second delivery;
  - `name` — the versioned name the `publish` declares, `"rehmed.visit.closed.v1"`;
  - `correlation_id` — the source event's, which the subscriber's fact carries on, so a
    run across two applications can be assembled;
  - `payload` — the declared `fields` of the source event and nothing else, as JSON
    (`EhOsContract.Bus`, "A message").
  """

  @enforce_keys [:id, :name, :correlation_id, :payload]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          correlation_id: String.t(),
          payload: %{optional(String.t()) => term()}
        }
end
