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
    :crypto.exor(left, right) |> :binary.bin_to_list() |> Enum.reduce(0, &Bitwise.bor(&1, &2)) ==
      0
  end

  defp secure_compare(_, _), do: false

  @spec secret() :: binary()
  defp secret do
    Application.get_env(:pns, __MODULE__)[:secret] ||
      raise "no secret configured for #{inspect(__MODULE__)}"
  end
end

defmodule PNS.Auth.OidcVerifier do
  @moduledoc """
  The identity seam's real verifier (`docs/adr/identity-seam.md`): validates a
  bearer token's signature locally against the provider's JWKS, via
  `Oidcc.Token.validate_jwt/3` — the same freshness trade-off `PNS.Auth`
  already documents for entitlement, no network call once the JWKS is cached.

  **Not the active verifier.** `config/dev.exs` and `config/test.exs` still
  point `:auth_verifier` at `LocalToken`. This module reads its own
  configuration from `Application.get_env/2` at call time rather than compile
  time, deliberately, so nothing here needs a checked-in config entry — and
  therefore no vendor name — until swapping it in is an actual decision
  rather than a side effect of writing this module.

  Needs an `Oidcc.ProviderConfiguration.Worker` already running under the
  name given as `:provider`. This module starts none of its own: the seam
  commits to consuming discovery and JWKS, not to owning the process that
  fetches them. For manual testing against a running sidecar, see
  `priv/poc/identity_smoke_test.exs`.
  """

  @behaviour PNS.Auth.Verifier

  alias PNS.Auth.Actor

  @impl true
  def verify(token) when is_binary(token) do
    conf = config()

    with {:ok, client_context} <-
           Oidcc.ClientContext.from_configuration_worker(
             conf.provider,
             conf.client_id,
             conf.client_secret
           ),
         signing_algs = signing_algs(client_context),
         {:ok, claims} <-
           Oidcc.Token.validate_jwt(token, client_context, %{signing_algs: signing_algs}) do
      {:ok,
       %Actor{
         subject: claims["sub"],
         roles: extract_roles(claims, conf.roles_claim),
         claims: claims
       }}
    end
  end

  def verify(_), do: {:error, :missing_token}

  # An arbitrary bearer token is not an ID token, so — unlike
  # `validate_id_token/3` — `oidcc` cannot infer which algorithms the issuer
  # signs with from the token type alone. The provider configuration already
  # lists what it supports.
  defp signing_algs(client_context) do
    client_context.provider_configuration.id_token_signing_alg_values_supported
  end

  # Where a role claim lives is the provider's business, not ours (`PNS.Auth`'s
  # moduledoc: "one claim, no engine"). Zitadel nests project roles as a map
  # keyed by role name; everything else is expected to hand back a plain list.
  defp extract_roles(claims, roles_claim) do
    case claims[roles_claim] do
      roles when is_list(roles) -> roles
      roles when is_map(roles) -> Map.keys(roles)
      _ -> []
    end
  end

  defp config do
    conf =
      Application.get_env(:pns, __MODULE__) ||
        raise "no config for #{inspect(__MODULE__)} — see priv/poc/identity_smoke_test.exs"

    %{
      provider: Keyword.fetch!(conf, :provider),
      client_id: Keyword.fetch!(conf, :client_id),
      client_secret: Keyword.fetch!(conf, :client_secret),
      roles_claim: Keyword.get(conf, :roles_claim, "roles")
    }
  end
end

defmodule PNS.Auth.IdentityAdmin do
  @moduledoc """
  The thin proxy behaviour `docs/adr/identity-seam.md` decided on 9 August:
  the handful of user-management calls the accounts screen needs, so the
  provider's own request shapes never reach a caller outside this module —
  the same reason `Verifier` exists for authentication.

  "Thin" is the design, not a shortcut: listing users is the provider's own
  user list, granting access is a role grant. Only a company-specific
  condition on top of a grant would be code, and that lands in the
  contract's own `rule`, not here — see `docs/adr/identity-seam.md`'s
  "Three levels" table.
  """

  @typedoc "A user as the accounts screen shows it — never the provider's own shape."
  @type user :: %{id: String.t(), name: String.t(), email: String.t(), roles: [String.t()]}

  @callback list_users() :: [user()]
  @callback grant_role(user_id :: String.t(), role :: String.t()) :: :ok | {:error, term()}
  @callback revoke_role(user_id :: String.t(), role :: String.t()) :: :ok | {:error, term()}
  @callback invite_user(email :: String.t(), name :: String.t()) ::
              {:ok, user()} | {:error, term()}
end

defmodule PNS.Auth.LocalIdentityAdmin do
  @moduledoc """
  A dev-only identity admin: one `Agent`, no persistence, seeded empty.

  What is deliberately not here: a password, a session, anything
  authentication touches — this module only ever manages the *roles* half of
  identity, the same boundary `Verifier`/`LocalToken` draws for the other
  half. Disappears when a real provider (Zitadel, per
  `docs/identity-admin-guide.md`) takes over; nothing calls this by name
  outside the accounts screen's own tests and whatever process starts it.
  """

  @behaviour PNS.Auth.IdentityAdmin

  use Agent

  @doc "Starts empty. A host wires this into its own supervision tree."
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts \\ []), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  @impl true
  def list_users do
    Agent.get(__MODULE__, & &1) |> Map.values() |> Enum.sort_by(& &1.email)
  end

  @impl true
  def grant_role(user_id, role) do
    update_user(user_id, &%{&1 | roles: Enum.uniq([role | &1.roles])})
  end

  @impl true
  def revoke_role(user_id, role) do
    update_user(user_id, &%{&1 | roles: List.delete(&1.roles, role)})
  end

  @impl true
  def invite_user(email, name) do
    user = %{id: Ecto.UUID.generate(), name: name, email: email, roles: []}
    Agent.update(__MODULE__, &Map.put(&1, user.id, user))
    {:ok, user}
  end

  @spec update_user(String.t(), (PNS.Auth.IdentityAdmin.user() -> PNS.Auth.IdentityAdmin.user())) ::
          :ok | {:error, :not_found}
  defp update_user(user_id, fun) do
    Agent.get_and_update(__MODULE__, fn users ->
      case Map.fetch(users, user_id) do
        {:ok, user} -> {:ok, Map.put(users, user_id, fun.(user))}
        :error -> {{:error, :not_found}, users}
      end
    end)
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

  @verifier Application.compile_env!(:pns, :auth_verifier)
  @identity_admin Application.compile_env!(:pns, :identity_admin)

  @doc "Level 1: who is this."
  @spec verify(String.t()) :: {:ok, PNS.Auth.Actor.t()} | {:error, term()}
  def verify(token), do: verifier().verify(token)

  @doc """
  Level 2, the admin side: the accounts screen's own read — every user the
  provider knows about, roles included. See `PNS.Auth.IdentityAdmin`.
  """
  @spec list_users() :: [PNS.Auth.IdentityAdmin.user()]
  def list_users, do: identity_admin().list_users()

  @doc "Level 2, the admin side: granting access is a role grant, nothing more."
  @spec grant_role(String.t(), String.t()) :: :ok | {:error, term()}
  def grant_role(user_id, role), do: identity_admin().grant_role(user_id, role)

  @doc "Level 2, the admin side: removing access is the same call with the opposite direction."
  @spec revoke_role(String.t(), String.t()) :: :ok | {:error, term()}
  def revoke_role(user_id, role), do: identity_admin().revoke_role(user_id, role)

  @doc "Level 2, the admin side: inviting someone is a provider endpoint."
  @spec invite_user(String.t(), String.t()) ::
          {:ok, PNS.Auth.IdentityAdmin.user()} | {:error, term()}
  def invite_user(email, name), do: identity_admin().invite_user(email, name)

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

  @doc """
  The explicit stand-in for "no human actor" — a scheduled job, a backfill, an
  import — used wherever `PNS.emit`/`emit_all` is called without a `ctx.actor`.

  A nil actor conflates two different facts: "we asked and there genuinely is no
  person" and "nobody supplied one." The second is a caller that forgot, and the
  first should read as a positive statement, not an absence — `PNS.Event.actor`
  never stores `nil` for exactly this reason.
  """
  @spec system_actor() :: String.t()
  def system_actor, do: "system"

  defp verifier, do: @verifier
  defp identity_admin, do: @identity_admin
end
