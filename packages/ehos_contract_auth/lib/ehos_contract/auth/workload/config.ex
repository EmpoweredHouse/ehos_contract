defmodule EhosContract.Auth.Workload.Config do
  @moduledoc false

  # What `EhosContract.Auth.Workload` holds of its configuration. The client key is the secret
  # every assertion is signed with, so it is left out of every inspection, a crash report's
  # included.

  @derive {Inspect, except: [:client_key]}
  @enforce_keys [:issuer, :token_endpoint, :client_id, :client_key, :request_opts]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          issuer: String.t(),
          token_endpoint: String.t(),
          client_id: String.t(),
          client_key: JOSE.JWK.t(),
          request_opts: map()
        }
end
