defmodule EhOsContract.Auth do
  @moduledoc """
  Verifies the credentials EHOS issues, against keys this application keeps in its
  own database (v2 §16, D14; `eh-os` D-33, D-34).

      # config/config.exs
      config :eh_os_contract, authorizer: EhOsContract.Auth

      config :eh_os_contract_auth,
        issuer: "https://ehos.example.com",
        audience: "rehmed/production"
        # jwks_url: defaults to the issuer's "/.well-known/jwks.json"

      # the application's supervision tree, after the repo
      children = [MyApp.Repo, EhOsContract, EhOsContract.Auth]

      # a migration
      def up, do: EhOsContract.Auth.Migrations.up()
      def down, do: EhOsContract.Auth.Migrations.down()

  The repo is the engine's, `config :eh_os_contract, :repo`.

  **Nothing is delivered to the application but EHOS's address.** EHOS holds the
  Ed25519 key pair, in a Kubernetes Secret its chart creates, and publishes the
  public halves at `/.well-known/jwks.json`; this package fetches them from there
  (`EhOsContract.Auth.Keys`). What proves the key set is EHOS's is the TLS
  certificate of that URL, checked against the system's certificate authorities. An
  EHOS behind an internal authority needs it named, through the options every fetch
  takes:

      {EhOsContract.Auth,
       req_options: [connect_options: [transport_opts: [cacertfile: "/etc/ehos/ca.pem"]]]}

  These `:connect_options` are merged over the fetch's own, so its two-second
  connect timeout stays (`EhOsContract.Auth.Keys.start_link/1`).

  **A credential** is a JWT signed with Ed25519 (`eh-os` D-33). `verify/2` accepts
  one when all of these hold, and answers the first that does not:

    * the header says `alg: "Ed25519"` and nothing else — not `EdDSA`, not an
      algorithm the token chooses — and its signature checks against the key whose
      RFC 7638 thumbprint is the header's `kid`. Otherwise `:bad_signature`, or
      `:unknown_key` when no key in force has that thumbprint, or `:no_keys` when
      this application has never seen a key set;
    * `iss` is the configured issuer, or `:wrong_issuer`;
    * `aud` is exactly the configured audience, one string, or `:wrong_audience`;
    * `exp` is later than `EhOsContract.Clock.now/0`, or `:expired`. A credential
      without `exp` is expired: nothing here trusts a credential forever;
    * `exp` is at most fifteen minutes away — EHOS's ten, and five for clocks that
      disagree — or `:bad_signature`: a credential claiming to live longer is not
      one EHOS issues, whoever signed it.

  Anything that is not a well-formed credential in this form — not a JWT, no
  `kid`, a `crit` header, a `sub` that is not a string, a `cap` that is not a list of
  strings — is
  `:bad_signature`: it is not something EHOS signed, whatever its bytes say.

  An accepted credential becomes an `EhOsContract.Actor` of kind `:credential`,
  with `subject`, `capabilities` and `scopes` exactly as it carries them in `sub`,
  `cap` and `scp` (`eh-os` D-40). Over HTTP, `EhOsContract.Auth.Plug` does this for
  a bearer token in front of `EhOsContract.Plug`.

  **This module is also the `EhOsContract.Authorizer`** the engine asks what that
  actor may do. `authorize/2` decides with `EhOsContract.Authorizer.check/2` alone —
  no rule of its own, so it narrows nothing — and writes one row to
  `eh_os_contract_auth_decisions` for every decision, a refusal as carefully as an
  acceptance (`eh-os` D-34, FM-21): who, which capability, which contract and
  version, the scope value asked for, the outcome and the reason.

  The row records the authorization, not the command. A command allowed here may
  still be rejected on an invariant or fail in code, and what became of it is the
  engine's row in `eh_os_contract_commands`: two facts, two rows. The engine asks
  before its own transaction, so the row goes through whatever connection the call
  is on. A caller that wraps `EhOsContract.dispatch/3` in a transaction of its own
  and rolls it back rolls the row back with it; `EhOsContract.Plug` never does.
  A row that cannot be written fails the call: a decision nobody recorded is not
  made.

  How the keys are kept, refreshed and refetched is `EhOsContract.Auth.Keys`; tests
  get credentials from `EhOsContract.Auth.Testing`.
  """

  use Boundary, deps: [EhOsContract], exports: [Keys, Migrations, Plug, Testing]

  @behaviour EhOsContract.Authorizer

  alias EhOsContract.{Actor, Authorizer}
  alias EhOsContract.Auth.Keys

  @decisions "eh_os_contract_auth_decisions"
  @max_lifetime 15 * 60

  @typedoc "Why a credential is refused."
  @type reason ::
          :expired | :unknown_key | :bad_signature | :wrong_audience | :wrong_issuer | :no_keys

  @typedoc "What `verify/2` takes, each overriding the configuration."
  @type option :: {:audience, String.t()} | {:issuer, String.t()} | {:keys, atom()}

  @doc """
  The child that keeps the keys, for the application's supervision tree, after its
  repo: `EhOsContract.Auth` in the list of children.

  It reads `:issuer` and `:jwks_url` from `config :eh_os_contract_auth`, and raises
  at boot without an issuer or an audience, or with one that is not a string; when
  the key set's address is not https (plain http is allowed for `localhost` only) or
  has an `@`, a query, a fragment or a character a URL is not sent with; on `url:` in
  `opts`; and on `req_options` other than the few
  `EhOsContract.Auth.Keys.start_link/1` names. `:audience` and `:issuer` are read by
  `verify/2` on every credential, and are checked here too, so a missing one fails
  the boot rather than every request.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    config = Application.get_all_env(:eh_os_contract_auth)

    # Empty, as `System.get_env("AUDIENCE", "")` gives it, is missing too: the boot
    # would pass, and every credential be refused.
    if config[:audience] in [nil, ""] do
      raise ArgumentError,
            "config :eh_os_contract_auth, audience: \"<application>/<environment>\" is missing; " <>
              "it is the only audience a credential for this application may carry"
    end

    unless is_binary(config[:audience]) do
      raise ArgumentError, "config :eh_os_contract_auth, audience: takes a string"
    end

    if config[:issuer] in [nil, ""] do
      raise ArgumentError,
            "config :eh_os_contract_auth, issuer: \"<EHOS's public URL>\" is missing; it is " <>
              "the only iss a credential may carry, and the default place of its keys"
    end

    # Checked before it is read, so a charlist from `:os.getenv/1` is not shown.
    unless is_binary(config[:issuer]) do
      raise ArgumentError, "config :eh_os_contract_auth, issuer: takes a string"
    end

    url =
      case config[:jwks_url] do
        unset when unset in [nil, ""] ->
          String.trim_trailing(config[:issuer], "/") <> "/.well-known/jwks.json"

        jwks_url ->
          jwks_url
      end

    # The address is the configuration's, which the check below holds to https.
    if Keyword.has_key?(opts, :url) do
      raise ArgumentError,
            "eh_os_contract_auth takes EHOS's address from config :eh_os_contract_auth, " <>
              "issuer: or jwks_url:, not from url: in its child options"
    end

    opts = Keyword.put(opts, :url, url)
    Keys.check_options!(opts)

    %{
      id: __MODULE__,
      start: {Keys, :start_link, [opts]},
      type: :worker
    }
  end

  @doc """
  Whether this application holds at least one key to verify with, for the host's
  health check (`eh-os` D-34).

  `false` is the one state in which EHOS being down means nobody gets in: the key
  process has never seen a key set, neither in its table nor from EHOS, and every
  credential is refused with `:no_keys`. It is also `false` when the key process is
  not running. It never fetches and never raises.

  `:keys` names the `EhOsContract.Auth.Keys` process, as in `verify/2`.
  """
  @spec ready?([{:keys, atom()}]) :: boolean()
  def ready?(opts \\ []) do
    Keys.held(Keyword.get(opts, :keys, Keys)) > 0
  end

  @doc """
  The actor of `token`, or why the credential is refused. See the module's doc for
  what is checked and in which order.

  `:audience` and `:issuer` default to the configuration; `:keys` names the
  `EhOsContract.Auth.Keys` process, `EhOsContract.Auth.Keys` by default.
  """
  @spec verify(String.t(), [option()]) :: {:ok, Actor.t()} | {:error, reason()}
  def verify(token, opts \\ []) when is_binary(token) do
    issuer = Keyword.get_lazy(opts, :issuer, fn -> config!(:issuer) end)
    audience = Keyword.get_lazy(opts, :audience, fn -> config!(:audience) end)

    with {:ok, kid} <- kid(token),
         {:ok, signer} <- Keys.fetch(kid, Keyword.get(opts, :keys, Keys)),
         {:ok, claims} <- signed(token, signer),
         :ok <- claim(claims["iss"] == issuer, :wrong_issuer),
         :ok <- claim(claims["aud"] == audience, :wrong_audience),
         :ok <- claim(unexpired?(claims["exp"]), :expired),
         :ok <- claim(within_lifetime?(claims["exp"]), :bad_signature) do
      actor(claims)
    end
  end

  @doc """
  The engine's question about a credential's actor: `EhOsContract.Authorizer.check/2`'s
  answer, recorded. See the module's doc for the row.
  """
  @impl Authorizer
  @spec authorize(Actor.t(), Authorizer.Request.t()) :: :ok | {:error, Authorizer.reason()}
  def authorize(%Actor{kind: :credential} = actor, %Authorizer.Request{} = request) do
    decision = Authorizer.check(actor, request)
    {dimension, value} = request.scope || {nil, nil}

    row = %{
      subject: actor.subject,
      kind: Atom.to_string(request.kind),
      capability: request.capability,
      contract: inspect(request.contract),
      contract_version: request.version,
      scope_dimension: dimension,
      scope_value: value,
      outcome: if(decision == :ok, do: "allowed", else: "refused"),
      reason: with({:error, reason} <- decision, do: Atom.to_string(reason), else: (_ -> nil))
    }

    {1, _} = Application.fetch_env!(:eh_os_contract, :repo).insert_all(@decisions, [row])
    decision
  end

  defp config!(key), do: Application.fetch_env!(:eh_os_contract_auth, key)

  defp kid(token) do
    case Joken.peek_header(token) do
      # `crit` names header parameters a verifier must understand or refuse (RFC 7515
      # §4.1.11); this one understands none, and EHOS sets none.
      {:ok, %{"crit" => _}} -> {:error, :bad_signature}
      {:ok, %{"alg" => "Ed25519", "kid" => kid}} when is_binary(kid) -> {:ok, kid}
      _ -> {:error, :bad_signature}
    end
  rescue
    _malformed -> {:error, :bad_signature}
  end

  defp signed(token, signer) do
    case Joken.verify(token, signer) do
      {:ok, claims} -> {:ok, claims}
      {:error, _reason} -> {:error, :bad_signature}
    end
  rescue
    _malformed -> {:error, :bad_signature}
  end

  defp claim(true, _reason), do: :ok
  defp claim(false, reason), do: {:error, reason}

  defp unexpired?(exp) when is_integer(exp),
    do: DateTime.to_unix(EhOsContract.Clock.now()) < exp

  defp unexpired?(_exp), do: false

  # EHOS issues credentials for ten minutes (`eh-os` D-33); this allows five more for
  # clocks that disagree. One that claims to live longer is not in EHOS's form,
  # whoever signed it: a key that leaked must not mint credentials for a year.
  defp within_lifetime?(exp),
    do: exp - DateTime.to_unix(EhOsContract.Clock.now()) <= @max_lifetime

  # The claims' shapes are checked here, and the members' by `Actor.credential/3`,
  # whose ArgumentError is the one thing rescued: any other exception is a defect in
  # this code, not a credential to refuse.
  defp actor(%{"sub" => sub, "cap" => cap} = claims) when is_binary(sub) and is_list(cap) do
    {:ok, Actor.credential(sub, cap, Map.get(claims, "scp", %{}))}
  rescue
    ArgumentError -> {:error, :bad_signature}
  end

  defp actor(_claims), do: {:error, :bad_signature}
end
