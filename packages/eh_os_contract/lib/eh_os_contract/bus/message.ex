defmodule EhOsContract.Bus.Message do
  @moduledoc """
  One integration event on the way between two applications.

  - `id` — `<source event id>/<name>`, the same every time the relay publishes it;
  - `key` — what makes two messages one fact, so the subscriber's inbox takes only
    the first: the SHA-256, in hex, of the name and the values of the
    fields the `publish` declares `idempotent_on:`. A second event with the same
    values is the same fact under a new id, and its message has the same key. The id
    stands in for it when the publication declares no such fields, or one of them is
    `nil`, which identifies nothing;
  - `name` — the versioned name the `publish` declares, `"rehmed.visit.closed.v1"`;
  - `correlation_id` — the source event's, which the subscriber's fact carries on, so a
    run across two applications can be assembled;
  - `payload` — the declared `fields` of the source event and nothing else, as JSON
    (`EhOsContract.Bus`, "A message").
  """

  # An integration event (v2 §16); its key is what makes two messages one fact
  # (`eh-os` FM-08).

  @enforce_keys [:id, :key, :name, :correlation_id, :payload]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          key: String.t(),
          name: String.t(),
          correlation_id: String.t(),
          payload: %{optional(String.t()) => term()}
        }
end
