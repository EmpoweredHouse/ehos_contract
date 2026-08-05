defmodule PNS.Auth.Actor do
  @moduledoc """
  Who is performing an operation. Reconstructed from the token, never from the
  engine's database.

  **`claims` is a bag, and that is deliberate.** The first version had
  `company_id` here as a struct field — meaning the engine knew that actors belong
  to **companies**. A clinic has sites, a hospital has wards, a haulier has
  terminals. A client's entity written into the package is exactly what a library
  has no business knowing, and it went unnoticed because the universality gate is
  a contract plus fakes — and the identity seam is not part of the contract.

  The engine reads exactly two things from a token: **who** (`subject`) and **what
  they are allowed** (`roles`, level 2). Everything else passes through raw in
  `claims` and is interpreted by domain code, because only it knows what a tenant
  is.
  """
  defstruct [:subject, roles: [], claims: %{}]

  @type t :: %__MODULE__{subject: String.t() | nil, roles: [String.t()], claims: map()}
end

defmodule PNS.Auth.Verifier do
  @moduledoc """
  The identity seam. **The only rule:** the engine receives a token, checks the
  signature, and holds neither credentials nor the ability to issue tokens.

  This behaviour is the whole architectural commitment, and it is deliberately
  silent about what stands on the other side. Today a local HMAC, because standing
  up a provider for a prototype is cost without signal. Tomorrow `oidcc` against a
  bought provider — and then one line of configuration changes, not domain code.
  """

  @callback verify(token :: String.t()) :: {:ok, PNS.Auth.Actor.t()} | {:error, term()}
end

defmodule PNS.Auth.LocalToken do
  @moduledoc """
  A dev-only verifier: an HMAC over a JSON payload.

  What is deliberately **not** here and will not be: a password table,
  registration, password reset, sessions. If they appeared, the seam would be
  broken and the engine would hold a second source of truth about who works at a
  company.

  `sign/1` exists only so that dev and tests have somewhere to get a token from. A
  real provider does not hand out its signing secret, so this function is the
  first thing to disappear when it is swapped — which is why no domain module may
  call it.
  """

  @behaviour PNS.Auth.Verifier

  alias PNS.Auth.Actor

  @impl true
  def verify(token) when is_binary(token) do
    with [body64, mac64] <- String.split(token, ".", parts: 2),
         {:ok, body} <- Base.url_decode64(body64, padding: false),
         {:ok, mac} <- Base.url_decode64(mac64, padding: false),
         true <- secure_compare(mac, mac(body)),
         {:ok, claims} <- Jason.decode(body) do
      {:ok,
       %Actor{
         subject: claims["sub"],
         # Roles stay strings. `String.to_atom` on data from a token would be a
         # vector for exhausting the atom table — atoms are never reclaimed.
         roles: claims["roles"] || [],
         claims: claims
       }}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def verify(_), do: {:error, :missing_token}

  @doc "Dev and tests. Disappears when a real provider takes over."
  @spec sign(map()) :: String.t()
  def sign(claims) do
    body = Jason.encode!(claims)
    Base.url_encode64(body, padding: false) <> "." <> Base.url_encode64(mac(body), padding: false)
  end

  @spec mac(binary()) :: binary()
  defp mac(body), do: :crypto.mac(:hmac, :sha256, secret(), body)

  # A constant-time comparison. `==` on binaries stops at the first differing
  # byte, which leaks how many characters matched.
  @spec secure_compare(binary(), binary()) :: boolean()
  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    :crypto.exor(left, right) |> :binary.bin_to_list() |> Enum.reduce(0, &Bitwise.bor(&1, &2)) == 0
  end

  defp secure_compare(_, _), do: false

  @spec secret() :: binary()
  defp secret do
    Application.get_env(:pns_prototype, __MODULE__)[:secret] ||
      raise "no secret configured for #{inspect(__MODULE__)}"
  end
end

defmodule PNS.Auth do
  @moduledoc """
  Three levels, three different owners (the identity document, 4 August).

  | Level | Question | Owner |
  |---|---|---|
  | Authentication | who is this | bought — here: `Verifier` |
  | Entitlement | can this person reach this API at all | bought — a role grant as a claim |
  | Domain rule | may they perform **this** operation on **this** data | ours — a rule in the contract |

  The second level comes free with any provider: grant a role, read one claim. You
  do not build an engine for that. The third level is where the value is, which is
  why it sits in the contract as a `rule` with examples — rather than in a
  provider's configuration, which knows nothing about our domain.
  """

  @verifier Application.compile_env!(:pns_prototype, :auth_verifier)

  @doc "Level 1: who is this."
  @spec verify(String.t()) :: {:ok, PNS.Auth.Actor.t()} | {:error, term()}
  def verify(token), do: verifier().verify(token)

  @doc """
  Level 2: entitlement. One claim from the token, no network, freshness bounded by
  the token's lifetime.

  Two other propagation routes, deliberately unused: a local replica updated by an
  event when a grant changes (the right shape for rules, and consistent with the
  event-driven direction), and asking a shared authorisation service on every
  request — the third is rejected because it turns several APIs into a distributed
  monolith where one outage takes down all of them.
  """
  @spec entitled?(PNS.Auth.Actor.t(), atom() | String.t()) :: boolean()
  def entitled?(%PNS.Auth.Actor{roles: roles}, role), do: to_string(role) in roles

  defp verifier, do: @verifier
end
