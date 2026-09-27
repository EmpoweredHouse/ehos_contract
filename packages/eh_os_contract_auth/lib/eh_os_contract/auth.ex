defmodule EhOsContract.Auth do
  @moduledoc """
  Verifies the credentials EHOS issues, against keys this application keeps in its
  own database (v2 §16, D14; `eh-os` D-33, D-34).

      # config/config.exs
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
      without `exp` is expired: nothing here trusts a credential forever.

  Anything that is not a well-formed credential in this form — not a JWT, no
  `kid`, a `sub` that is not a string, a `cap` that is not a list of strings — is
  `:bad_signature`: it is not something EHOS signed, whatever its bytes say.

  An accepted credential becomes an `EhOsContract.Actor` of kind `:credential`,
  with `subject`, `capabilities` and `scopes` exactly as it carries them in `sub`,
  `cap` and `scp` (`eh-os` D-40). The engine asks the configured
  `EhOsContract.Authorizer` what that actor may do.

  How the keys are kept, refreshed and refetched is `EhOsContract.Auth.Keys`.
  """

  use Boundary, deps: [EhOsContract], exports: [Keys, Migrations]

  alias EhOsContract.Actor
  alias EhOsContract.Auth.Keys

  @typedoc "Why a credential is refused."
  @type reason ::
          :expired | :unknown_key | :bad_signature | :wrong_audience | :wrong_issuer | :no_keys

  @typedoc "What `verify/2` takes, each overriding the configuration."
  @type option :: {:audience, String.t()} | {:issuer, String.t()} | {:keys, atom()}

  @doc """
  The child that keeps the keys, for the application's supervision tree, after its
  repo: `EhOsContract.Auth` in the list of children.

  It reads `:issuer` and `:jwks_url` from `config :eh_os_contract_auth` and raises
  at boot when neither is there; `:audience` is read by `verify/2`, and is checked
  here too, so a missing one fails the boot rather than every request.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    config = Application.get_all_env(:eh_os_contract_auth)

    unless config[:audience] do
      raise ArgumentError,
            "config :eh_os_contract_auth, audience: \"<application>/<environment>\" is missing; " <>
              "it is the only audience a credential for this application may carry"
    end

    url =
      config[:jwks_url] ||
        (config[:issuer] && String.trim_trailing(config[:issuer], "/") <> "/.well-known/jwks.json") ||
        raise ArgumentError,
              "config :eh_os_contract_auth needs issuer: (EHOS's public URL), or jwks_url:"

    %{
      id: __MODULE__,
      start: {Keys, :start_link, [Keyword.merge([url: url], opts)]},
      type: :worker
    }
  end

  @doc """
  The actor of `token`, or why the credential is refused. See the module's doc for
  what is checked and in which order.

  `:audience` and `:issuer` default to the configuration; `:keys` names the
  `EhOsContract.Auth.Keys` process, `EhOsContract.Auth.Keys` by default.
  """
  @spec verify(String.t(), [option()]) :: {:ok, Actor.t()} | {:error, reason()}
  def verify(token, opts \\ []) when is_binary(token) do
    config = Application.get_all_env(:eh_os_contract_auth)
    issuer = Keyword.get_lazy(opts, :issuer, fn -> Keyword.fetch!(config, :issuer) end)
    audience = Keyword.get_lazy(opts, :audience, fn -> Keyword.fetch!(config, :audience) end)

    with {:ok, kid} <- kid(token),
         {:ok, jwk} <- Keys.fetch(kid, Keyword.get(opts, :keys, Keys)),
         {:ok, claims} <- signed(token, jwk),
         :ok <- claim(claims["iss"] == issuer, :wrong_issuer),
         :ok <- claim(claims["aud"] == audience, :wrong_audience),
         :ok <- claim(unexpired?(claims["exp"]), :expired) do
      actor(claims)
    end
  end

  defp kid(token) do
    case Joken.peek_header(token) do
      {:ok, %{"alg" => "Ed25519", "kid" => kid}} when is_binary(kid) -> {:ok, kid}
      _ -> {:error, :bad_signature}
    end
  rescue
    _malformed -> {:error, :bad_signature}
  end

  defp signed(token, jwk) do
    case Joken.verify(token, Joken.Signer.create("Ed25519", jwk)) do
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

  defp actor(claims) do
    {:ok, Actor.credential(claims["sub"], claims["cap"], Map.get(claims, "scp", %{}))}
  rescue
    _malformed -> {:error, :bad_signature}
  end
end
