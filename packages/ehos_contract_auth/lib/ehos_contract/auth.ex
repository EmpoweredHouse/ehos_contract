defmodule EhosContract.Auth do
  # The design: v2 §16 and D14 in docs/adr/. The rest is EHOS's: the credential's form (a
  # ten-minute Ed25519 JWT, the key's thumbprint as `kid`), the keys kept in the application's own
  # table with a row for every decision, a refusal recorded as carefully as an acceptance, and the
  # claims `cap` and `scp`.
  @moduledoc """
  Verifies the credentials EHOS issues, against keys this application keeps in its
  own database.

      # config/config.exs
      config :ehos_contract, authorizer: EhosContract.Auth

      config :ehos_contract_auth,
        issuer: "https://ehos.example.com",
        audience: "clinic/production"
        # jwks_url: defaults to the issuer's "/.well-known/jwks.json"

      # the application's supervision tree, after the repo
      children = [MyApp.Repo, EhosContract, EhosContract.Auth]

      # a migration
      def up, do: EhosContract.Auth.Migrations.up()
      def down, do: EhosContract.Auth.Migrations.down()

  The repo is the engine's, `config :ehos_contract, :repo`.

  **Nothing is delivered to the application but EHOS's address.** EHOS holds the
  Ed25519 key pair, in a Kubernetes Secret its chart creates, and publishes the
  public halves at `/.well-known/jwks.json`; this package fetches them from there
  (`EhosContract.Auth.Keys`). What proves the key set is EHOS's is the TLS
  certificate of that URL, checked against the system's certificate authorities. An
  EHOS behind an internal authority needs it named, as an option of the child:

      {EhosContract.Auth, cacertfile: "/etc/ehos/ca.pem"}

  That, or `cacerts:`, is all the package takes about the fetch
  (`EhosContract.Auth.Keys.start_link/1`).

  **A credential** is a JWT signed with Ed25519. `verify/2` accepts
  one when all of these hold, and answers the first that does not:

    * the header says `alg: "Ed25519"` and nothing else — not `EdDSA`, not an
      algorithm the token chooses — and its signature checks against the key whose
      RFC 7638 thumbprint is the header's `kid`. Otherwise `:bad_signature`, or
      `:unknown_key` when no key in force has that thumbprint, or `:no_keys` when
      this application has never seen a key set;
    * `iss` is the configured issuer, or `:wrong_issuer`;
    * `aud` is exactly the configured audience, one string, or `:wrong_audience`;
    * `exp` is later than `EhosContract.Clock.now/0`, or `:expired`. A credential
      without `exp` is expired: nothing here trusts a credential forever;
    * `exp` is at most fifteen minutes away — EHOS's ten, and five for clocks that
      disagree — or `:bad_signature`: a credential claiming to live longer is not
      one EHOS issues, whoever signed it.

  Anything that is not a well-formed credential in this form — not a JWT, no
  `kid`, a `crit` header, a `sub` that is not a string or is blank, a `cap` that is not
  a list of strings — is
  `:bad_signature`: it is not something EHOS signed, whatever its bytes say.

  An accepted credential becomes an `EhosContract.Actor` of kind `:credential`,
  with `subject`, `capabilities` and `scopes` exactly as it carries them in `sub`,
  `cap` and `scp`. Over HTTP, `EhosContract.Auth.Plug` does this for
  a bearer token in front of `EhosContract.Plug`.

  **This module is also the `EhosContract.Authorizer`** the engine asks what that
  actor may do. `authorize/2` decides with `EhosContract.Authorizer.check/2` alone —
  no rule of its own, so it narrows nothing — and writes one row to
  `ehos_contract_auth_decisions` for every decision, a refusal as carefully as an
  acceptance: who, which capability, which contract and
  version, the scope value asked for, the outcome and the reason.

  A scope value a text column cannot hold (invalid UTF-8, a NUL), one past 256 bytes,
  or one that starts `sha256:` is recorded as `sha256:` and its hex digest; the decision
  is `check/2`'s, as for any other value.

  The row records the authorization, not the command. A command allowed here may
  still be rejected on an invariant or fail in code, and what became of it is the
  engine's row in `ehos_contract_commands`: two records, two rows. The engine asks
  before its own transaction, so the row goes through whatever connection the call
  is on. A caller that wraps `EhosContract.dispatch/3` in a transaction of its own
  and rolls it back rolls the row back with it; `EhosContract.Plug` never does.
  A row that cannot be written fails the call: a decision nobody recorded is not
  made.

  How the keys are kept, refreshed and refetched is `EhosContract.Auth.Keys`; tests
  get credentials from `EhosContract.Auth.Testing`.
  """

  use Boundary,
    deps: [EhosContract],
    exports: [
      Development,
      Development.Router,
      Egress,
      EhosYaml,
      Keys,
      Manifest,
      Migrations,
      Plug,
      Session,
      SignIn,
      SignIn.Router,
      Testing
    ]

  @behaviour EhosContract.Authorizer

  alias EhosContract.{Actor, Authorizer}
  alias EhosContract.Auth.{Address, Keys, Manifest}

  @decisions "ehos_contract_auth_decisions"
  @max_scope_value 256
  @max_lifetime 15 * 60

  @typedoc "Why a credential is refused."
  @type reason ::
          :expired | :unknown_key | :bad_signature | :wrong_audience | :wrong_issuer | :no_keys

  @typedoc "What `verify/2` takes, each overriding the configuration."
  @type option :: {:audience, String.t()} | {:issuer, String.t()} | {:keys, atom()}

  @doc """
  The child that keeps the keys, for the application's supervision tree, after its
  repo: `EhosContract.Auth` in the list of children.

  It reads `:issuer` and `:jwks_url` from `config :ehos_contract_auth`, and raises
  at boot without an issuer, on an issuer EHOS would not start with (`https://<host>[:port]`
  alone, or `http://` on loopback, as every parser reads it), or when the key set would be
  fetched over anything but https (plain http is allowed for `localhost`, `127.0.0.1` and
  `::1` only), or from an address not every parser reads as written. `opts` go to
  `EhosContract.Auth.Keys.start_link/1`, which raises on one it does not take; the
  address is the configuration's, and `url:` among them is refused. `:audience` and
  `:issuer` are read by `verify/2` on every credential, and are checked here too, so
  a missing one fails the boot rather than every request.

  It also raises when `audience` is not `"<application>/<environment>"` with both
  parts non-empty (`"clinic"`, `"clinic/"`, `"/prod"`), or its application is not a
  name EHOS gives one; when that application does not equal, exactly, the `name:` of
  one of the domains that have contracts in the applications of
  `config :ehos_contract, applications:`; and when another of those domains declares
  a `publish` in any of its contracts. Every name the application publishes begins
  with its domain's name, and EHOS lets an application publish only under the name it
  registered; a domain that publishes nothing sends no name to anyone, so a release
  may hold several. A domain named `:my_shop` does not match `"my-shop/prod"`: EHOS
  never names an application with `_`, so the message advises renaming the domain to
  `:"my-shop"`, as the manifest generator does. It raises as well when a contract's
  domain is not loaded, so its name cannot be compared. Each message names what it
  found and how to fix it.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    config = Application.get_all_env(:ehos_contract_auth)

    unless config[:audience] do
      raise ArgumentError,
            "config :ehos_contract_auth, audience: \"<application>/<environment>\" is missing; " <>
              "it is the only audience a credential for this application may carry"
    end

    check_application!(config[:audience], EhosContract.Registry.load!().contracts)

    unless config[:issuer] do
      raise ArgumentError,
            "config :ehos_contract_auth, issuer: \"<EHOS's public URL>\" is missing; it is " <>
              "the only iss a credential may carry, and the default place of its keys"
    end

    # Compared with each credential's `iss` as a string, so one EHOS would never start with is
    # refused here, rather than every credential at `verify/2` (#89, EHOS's own rule for its
    # issuer).
    if Address.check(config[:issuer], plain_on_loopback: true, path: false) == :error do
      raise ArgumentError,
            "config :ehos_contract_auth, issuer: is #{Address.shown(config[:issuer])}, which " <>
              "EHOS would not start with: https://<host>[:port] alone, or http:// on " <>
              "localhost, 127.0.0.1 or ::1, as every parser reads it, so no credential's iss " <>
              "could equal it"
    end

    url = config[:jwks_url] || config[:issuer] <> "/.well-known/jwks.json"

    # The address is the configuration's, which the check holds to https: a `url:`
    # here replaced it after the check.
    if Keyword.has_key?(opts, :url) do
      raise ArgumentError,
            "ehos_contract_auth takes EHOS's address from config :ehos_contract_auth, " <>
              "issuer: or jwks_url:, not from url: in its child options"
    end

    opts = Keyword.put(opts, :url, url)
    Keys.check!(opts)

    %{
      id: __MODULE__,
      start: {Keys, :start_link, [opts]},
      type: :worker
    }
  end

  @doc false
  # #180: the namespace an application publishes under is its domain's `name:` (D11), and EHOS
  # binds the application to the name it registered it under. Checked whenever the
  # child starts, which needs an audience, so a mismatch shows before the bus refuses the first
  # publish. Only domains with contracts count, as in the manifest: the `name:` of one of them must
  # equal the application's exactly, since a domain whose name EHOS would not take (`:my_shop`)
  # cannot have its manifest generated either. Only a `publish` sends a name to other
  # applications, so every other domain must publish nothing. An application without contracts
  # publishes nothing, and passes.
  @spec check_application!(String.t(), [module() | map()]) :: :ok
  def check_application!(audience, contracts) when is_binary(audience) do
    application = audience_application!(audience)

    by_domain =
      contracts
      |> Enum.map(&EhosContract.Model.fetch/1)
      |> Enum.group_by(& &1.domain)
      |> Enum.map(fn {domain, models} -> {domain!(domain, models), models} end)
      |> Enum.sort_by(fn {domain, _models} -> to_string(domain.name) end)

    {own, others} =
      Enum.split_with(by_domain, fn {domain, _} ->
        to_string(domain.name) == application
      end)

    publishing =
      Enum.filter(others, fn {_, models} -> Enum.any?(models, &(&1.publishes != [])) end)

    case {own, publishing} do
      # No contracts, so no name to publish under, and nothing to hold the audience to.
      {[], _} when by_domain == [] ->
        :ok

      {[], _} ->
        raise ArgumentError,
              unmatched_message(audience, application, by_domain)

      {_own, []} ->
        :ok

      {[{domain, _} | _], publishing} ->
        raise ArgumentError, publishing_message(audience, application, domain, publishing)
    end
  end

  # An audience EHOS never issues: no domain should be renamed after it.
  defp audience_application!(audience) do
    case String.split(audience, "/", parts: 2) do
      [application, environment] when application != "" and environment != "" ->
        unless Manifest.application?(application) do
          raise ArgumentError,
                "config :ehos_contract_auth, audience: #{inspect(audience)} is malformed: its " <>
                  "application, the part before the /, is #{inspect(application)}, and EHOS " <>
                  "names an application with lowercase letters, digits and dashes, starting " <>
                  "with a letter, not ending with a dash, at most 63 characters, and not ehos. " <>
                  "Copy the audience EHOS issues for this application, " <>
                  "<application>/<environment>"
        end

        application

      _otherwise ->
        raise ArgumentError,
              "config :ehos_contract_auth, audience: #{inspect(audience)} is malformed: EHOS " <>
                "issues <application>/<environment>, both parts non-empty. Copy the audience " <>
                "EHOS issues for this application"
    end
  end

  # The engine runs a contract whose domain is not loaded, with its days in UTC (v2 §8); the name
  # compared here has no such default, and skipping the domain would leave its contracts to
  # publish under a name nobody checked.
  defp domain!(domain, models) do
    if is_atom(domain) and Code.ensure_loaded?(domain) and
         function_exported?(domain, :__ehos_contract_model__, 0) do
      domain.__ehos_contract_model__()
    else
      raise ArgumentError,
            "#{Enum.map_join(models, ", ", &inspect(&1.module))} names the domain " <>
              "#{inspect(domain)}, which is not loaded on this node, so its name: cannot be " <>
              "compared with the application's in EHOS: include the domain's application in " <>
              "the release, or in config :ehos_contract, applications:"
    end
  end

  defp unmatched_message(audience, application, by_domain) do
    domains = Enum.map(by_domain, &elem(&1, 0))
    named = Enum.map_join(domains, ", ", &domain_name/1)
    found = if length(domains) == 1, do: "the domain", else: "the domains"

    "config :ehos_contract_auth, audience: #{inspect(audience)} names the application " <>
      "#{application} in EHOS, and none of the domains with contracts in this application " <>
      "has that name: it has #{found} #{named}. Every name the application publishes, and " <>
      "every contract id it stores, begins with its domain's name:, and EHOS lets an " <>
      "application publish only under its own name, so one domain's name: must equal the " <>
      "application's exactly: " <> advice(application, by_domain)
  end

  @renames "(it renames every event and every stored contract id, so the event log starts again)"

  # A domain spelled with `_` where EHOS has `-` is the one meant, and only renaming it helps:
  # EHOS never names an application with `_`. Otherwise the domain to rename, or to register the
  # application under when EHOS takes its name: the one, else the one that publishes, since only
  # its name reaches other applications.
  defp advice(application, by_domain) do
    domains = Enum.map(by_domain, &elem(&1, 0))

    publishing =
      for {domain, models} <- by_domain, Enum.any?(models, &(&1.publishes != [])), do: domain

    case {Enum.filter(domains, &(dashed(&1.name) == application)), domains, publishing} do
      {[domain | _], _domains, _publishing} ->
        "the domain #{domain_name(domain)} differs from it only in _ where EHOS has -, and " <>
          "EHOS never names an application with _. Rename the domain, such as name: " <>
          "#{atom_literal(application)} #{@renames}."

      {[], [domain], _publishing} ->
        "rename the domain #{domain_name(domain)} to name: #{atom_literal(application)} " <>
          "#{@renames}" <> register(domain) <> "."

      {[], _several, [domain]} ->
        "rename the domain that publishes, #{domain_name(domain)}, to name: " <>
          "#{atom_literal(application)} #{@renames}" <> register(domain) <> "."

      {[], _several, _publishing} ->
        "rename one of them to name: #{atom_literal(application)} #{@renames}, or register " <>
          "the application in EHOS under the name of one of them that EHOS takes."
    end
  end

  # EHOS registers an application only under a name it takes: `:my_shop` offers no such way out.
  defp register(domain) do
    name = to_string(domain.name)

    if Manifest.application?(name),
      do: ", or register the application in EHOS as #{name}",
      else: ""
  end

  defp publishing_message(audience, application, own, publishing) do
    listed =
      Enum.map_join(publishing, "; ", fn {domain, models} ->
        publications =
          for model <- models, publication <- model.publishes do
            "#{inspect(model.module)} publishes #{publication.as}"
          end

        "the domain #{domain_name(domain)}: " <> Enum.join(publications, ", ")
      end)

    "config :ehos_contract_auth, audience: #{inspect(audience)} names the application " <>
      "#{application} in EHOS, whose domain is #{domain_name(own)}, and another domain with " <>
      "contracts in this application declares a publish: #{listed}. A publication's name " <>
      "begins with its domain's name:, and EHOS lets an application publish only under its " <>
      "own name, so this one would publish under a name that is not the application's. " <>
      "Move that domain's contracts to an application of its own, registered in EHOS under " <>
      "the domain's name, or remove its publish."
  end

  defp domain_name(domain), do: "#{domain.name} (#{inspect(domain.module)})"

  defp dashed(name), do: String.replace(to_string(name), "_", "-")

  # How the name is written as an atom in a domain's `use`: `:clinic`, `:"billing-app"`.
  defp atom_literal(name) do
    if Regex.match?(~r/\A[a-z][a-z0-9_]*\z/, name), do: ":#{name}", else: ":#{inspect(name)}"
  end

  # For the host's health check, which EHOS asks of an application.
  @doc """
  Whether this application holds at least one key to verify with, for the host's
  health check.

  `false` is the one state in which EHOS being down means nobody gets in: the key
  process has never seen a key set, neither in its table nor from EHOS, and every
  credential is refused with `:no_keys`. It is also `false` when the key process is
  not running. It never fetches and never raises.

  `:keys` names the `EhosContract.Auth.Keys` process, as in `verify/2`.
  """
  @spec ready?([{:keys, atom()}]) :: boolean()
  def ready?(opts \\ []) do
    Keys.held(Keyword.get(opts, :keys, Keys)) > 0
  end

  @doc """
  The actor of `token`, or why the credential is refused. See the module's doc for
  what is checked and in which order.

  `:audience` and `:issuer` default to the configuration; `:keys` names the
  `EhosContract.Auth.Keys` process, `EhosContract.Auth.Keys` by default.
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
  The engine's question about a credential's actor: `EhosContract.Authorizer.check/2`'s
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
      contract: request.contract_id,
      contract_version: request.version,
      scope_dimension: dimension,
      scope_value: recorded(value),
      outcome: if(decision == :ok, do: "allowed", else: "refused"),
      reason: with({:error, reason} <- decision, do: Atom.to_string(reason), else: (_ -> nil))
    }

    {1, _} = EhosContract.Config.fetch!(:repo).insert_all(@decisions, [row])
    decision
  end

  # #66: the scope value as it was asked for, unless a text column cannot hold it (invalid UTF-8,
  # a NUL) or it is past 256 bytes. Then its SHA-256: the insert would fail, or store a request's
  # body, and a refusal would become a 500. A value that reads as a digest is digested too, so a
  # recorded `sha256:` is always this function's. Only what is recorded changes; the decision is
  # `check/2`'s.
  defp recorded(value) when is_binary(value) do
    if byte_size(value) <= @max_scope_value and String.valid?(value) and
         not String.contains?(value, <<0>>) and not String.starts_with?(value, "sha256:"),
       do: value,
       else: "sha256:" <> Base.encode16(:crypto.hash(:sha256, value), case: :lower)
  end

  defp recorded(nil), do: nil

  defp config!(key), do: Application.fetch_env!(:ehos_contract_auth, key)

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
    do: DateTime.to_unix(EhosContract.Clock.now()) < exp

  defp unexpired?(_exp), do: false

  # EHOS issues credentials for ten minutes; this allows five more for
  # clocks that disagree. One that claims to live longer is not in EHOS's form,
  # whoever signed it: a key that leaked must not mint credentials for a year.
  defp within_lifetime?(exp),
    do: exp - DateTime.to_unix(EhosContract.Clock.now()) <= @max_lifetime

  # The claims' shapes are checked here, and the members' by `Actor.credential/3`,
  # whose ArgumentError is the one thing rescued: any other exception is a defect in
  # this code, not a credential to refuse.
  # A subject with a NUL is not EHOS's either: no text column holds it, and it names the actor
  # in every row (#66).
  defp actor(%{"sub" => sub, "cap" => cap} = claims) when is_binary(sub) and is_list(cap) do
    if String.contains?(sub, <<0>>), do: raise(ArgumentError, "a NUL in sub")
    {:ok, Actor.credential(sub, cap, Map.get(claims, "scp", %{}))}
  rescue
    ArgumentError -> {:error, :bad_signature}
  end

  defp actor(_claims), do: {:error, :bad_signature}
end
