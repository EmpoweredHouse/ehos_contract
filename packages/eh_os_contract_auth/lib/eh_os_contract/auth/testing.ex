defmodule EhOsContract.Auth.Testing do
  @moduledoc """
  Credentials for a host's tests, and the check that every entry point refuses one
  without the capability (`eh-os` D-34).

      use EhOsContract.Auth.Testing

      test "every entry point refuses a credential without the capability" do
        assert_every_entry_refuses([Rehmed.Contracts.VisitSettlement], %{
          "rehmed.record_payment" => fn token ->
            build_conn()
            |> put_req_header("authorization", "Bearer " <> token)
            |> post("/api/commands/rehmed.record_payment", %{visit_id: "visit-anna"})
          end,
          # … one entry per capability the contracts declare
        })
      end

      test "a receptionist records a payment" do
        token = credential("u-anna", ["rehmed.record_payment"])
        # … call the entry point with it, and assert what it did
      end

  **Why a map from every capability to an entry point.** The engine cannot drive a
  host's door, which it does not know: an HTTP route, a LiveView event, a job that
  arrives with a credential. The host names, for each capability its contracts
  declare, a function that calls its own door with a token. The check then calls
  each one with a credential that grants every other capability and not this one,
  and asserts the door refused it where it should: a `refused` row with
  `missing_capability` in `eh_os_contract_auth_decisions`, and nothing new in the
  engine's log or in `eh_os_contract_commands`. A capability the contracts declare
  and the map does not name fails the check, and so does a key the contracts do not
  declare, so a new command cannot be added unchecked. `<name>.subscribe`, which a
  contract derives for each event it consumes from another application, is not a
  person's and has no door: it needs no entry, and takes none. It proves that each door
  refuses, not that every path into the domain passes through one.

  **The test key.** `credential/3` signs with an Ed25519 key made once per test run
  and pinned in the running `EhOsContract.Auth.Keys` (`EhOsContract.Auth.Keys.pin/2`):
  trusted like EHOS's, kept through refreshes, never written to the table. Pinning
  needs `config :eh_os_contract_auth, pin_keys: true` in `config/test.exs`, and
  raises anywhere it is not set. No EHOS
  and no network are needed. The claims are EHOS's — the configured `iss` and `aud`,
  ten minutes of life from `EhOsContract.Clock.now/0`.

  Both run in the test process and read and write through the engine's repo, so
  they belong in a test that owns a sandbox connection, as any test of the host's
  that dispatches does.
  """

  import ExUnit.Assertions

  alias EhOsContract.Auth.Keys

  @key {__MODULE__, :key}

  @doc "Imports `credential/3` and `assert_every_entry_refuses/3`."
  defmacro __using__(_opts) do
    quote do
      import EhOsContract.Auth.Testing
    end
  end

  @doc """
  A credential for `subject`, granting `capabilities` and, for scoped ones, the
  values in `scopes` — `%{capability => %{dimension => [value]}}`, as `scp` carries
  them. `opts` may name the key process (`keys:`).
  """
  @spec credential(String.t(), [String.t()], EhOsContract.Actor.scopes(), keyword()) ::
          String.t()
  def credential(subject, capabilities, scopes \\ %{}, opts \\ []) do
    {private, public} = key()
    name = Keyword.get(opts, :keys, Keys)

    unless Process.whereis(name) do
      raise ArgumentError,
            "#{inspect(name)} is not running, so the test key has nowhere to be trusted: start " <>
              "EhOsContract.Auth in the application's supervision tree, after its repo"
    end

    kid = Keys.pin(public, name)
    config = Application.get_all_env(:eh_os_contract_auth)
    now = DateTime.to_unix(EhOsContract.Clock.now())

    claims =
      %{
        "iss" => Keyword.fetch!(config, :issuer),
        "aud" => Keyword.fetch!(config, :audience),
        "sub" => subject,
        "iat" => now,
        "exp" => now + 600,
        "jti" => Ecto.UUID.generate(),
        "cap" => Enum.sort(capabilities)
      }
      |> then(&if scopes == %{}, do: &1, else: Map.put(&1, "scp", scopes))

    signer = Joken.Signer.create("Ed25519", private, %{"kid" => kid})
    {:ok, token, _claims} = Joken.encode_and_sign(claims, signer)
    token
  end

  @doc """
  Calls each entry point in `entries` — `%{capability => fn token -> … end}` — with a
  credential that grants every capability `contracts` declare but that one, and
  asserts the refusal and its row, and that the engine wrote nothing. See the
  module's doc. `opts` may name the key process (`keys:`).
  """
  @spec assert_every_entry_refuses(
          [module()] | module(),
          %{String.t() => (String.t() -> any())},
          keyword()
        ) :: :ok
  def assert_every_entry_refuses(contracts, entries, opts \\ []) when is_map(entries) do
    # `<name>.subscribe` is the application's, granted to it and never in a person's
    # credential, and no door of the host takes it.
    declared =
      contracts
      |> List.wrap()
      |> Enum.map(&EhOsContract.Model.capabilities/1)
      |> Enum.reduce(%{}, &Map.merge(&2, &1))
      |> Enum.reject(fn {_capability, access} -> access.kind == :subscribe end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    missing = declared -- Map.keys(entries)
    unknown = Enum.sort(Map.keys(entries) -- declared)

    if missing != [] or unknown != [] do
      flunk(
        "every capability the contracts declare needs an entry point, and nothing else does\n" <>
          if(missing == [], do: "", else: "  no entry for: #{Enum.join(missing, ", ")}\n") <>
          if(unknown == [], do: "", else: "  not declared: #{Enum.join(unknown, ", ")}\n")
      )
    end

    repo = Application.fetch_env!(:eh_os_contract, :repo)

    for capability <- declared do
      subject = "eh-os-contract-auth-test-#{System.unique_integer([:positive])}"
      token = credential(subject, declared -- [capability], %{}, opts)
      before = engine_rows(repo)

      Map.fetch!(entries, capability).(token)

      decisions =
        repo.query!(
          "SELECT outcome, reason FROM eh_os_contract_auth_decisions " <>
            "WHERE subject = $1 AND capability = $2",
          [subject, capability]
        ).rows

      assert decisions == [["refused", "missing_capability"]],
             "the entry point for #{capability} did not ask EhOsContract.Auth, or it did not " <>
               "refuse: expected one refused row for a credential without the capability, and " <>
               "found #{inspect(decisions)}. Is `config :eh_os_contract, authorizer: " <>
               "EhOsContract.Auth` set, and does the entry go through EhOsContract.dispatch/3 " <>
               "or EhOsContract.query/3?"

      assert engine_rows(repo) == before,
             "the entry point for #{capability} wrote to the engine's log or to " <>
               "eh_os_contract_commands with a credential that does not grant it"
    end

    :ok
  end

  defp engine_rows(repo) do
    for table <- ~w(eh_os_contract_events eh_os_contract_commands), into: %{} do
      [[count]] = repo.query!("SELECT count(*) FROM #{table}").rows
      {table, count}
    end
  end

  # One key per test run: made on first use, kept in `:persistent_term`.
  defp key do
    case :persistent_term.get(@key, nil) do
      nil ->
        jwk = JOSE.JWK.generate_key({:okp, :Ed25519})
        {_, private} = JOSE.JWK.to_map(jwk)
        {_, public} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
        :persistent_term.put(@key, {private, public})
        {private, public}

      pair ->
        pair
    end
  end
end
