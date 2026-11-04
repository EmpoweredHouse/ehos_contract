defmodule EhOsContract.Auth.Testing do
  # The check that every entry point refuses, which EHOS asks of an application.
  @moduledoc """
  Credentials for a host's tests, and the check that every entry point refuses one
  without the capability.

      use EhOsContract.Auth.Testing

      test "every entry point refuses a credential without the capability" do
        assert_every_entry_refuses([Clinic.Contracts.VisitSettlement], %{
          "clinic.record_payment" => fn token ->
            build_conn()
            |> put_req_header("authorization", "Bearer " <> token)
            |> put_req_header("content-type", "application/json")
            |> post("/api/commands/clinic.record_payment", ~s({"visit_id": "visit-anna"}))
          end,
          # … one entry per capability the contracts declare
        })
      end

      test "a receptionist records a payment" do
        token = credential("u-anna", ["clinic.record_payment"])
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
  needs `config :eh_os_contract_auth, pin_keys: true`, and raises without it. Put the
  line in `config/test.exs` alone: the package does not check the environment it is
  set in. No running EHOS is needed. The key process still makes its first fetch of the
  keys, and the first credential waits for it; a `plug:` on the `EhOsContract.Auth` child
  answers it without the network. The claims are EHOS's — the configured `iss` and `aud`,
  ten minutes of life from `EhOsContract.Clock.now/0`.

  **A browser signed in.** `sign_in/3` writes a session for a page behind
  `EhOsContract.Auth.Session`, as signing in through EHOS does, and returns the token
  for the test's session; `sign_out/1` ends it. Without an `EhOsContract.Auth.SignIn`
  child, a stand-in that never calls EHOS takes its name, so `config :eh_os_contract_auth,
  sign_in:` is not needed in `config/test.exs`.

  **People and grants without EHOS.** With

      # config/test.exs
      config :eh_os_contract_auth,
        people_directory: EhOsContract.Auth.Testing.People,
        granter: EhOsContract.Auth.Testing.Grants,
        mail_sender: EhOsContract.Auth.Testing.Mail

  `EhOsContract.Auth.People.directory/0` lists nobody,
  `EhOsContract.Auth.Grants.granter/0` answers every grant as made and
  `EhOsContract.Auth.Mail.sender/0` every message as taken, until a test says otherwise
  with `stub_people/1`, `stub_grants/1` or `stub_mail/1`. A message the application asks
  to send comes to the test as `{:ehos_mail, message}`, for `assert_received`.

  What a test says holds for it and for the processes it starts, a LiveView's and a
  task's, which name it among their `$callers`, and for no other test, so the tests stay
  `async: true`. A host that uses
  Mox or Hammox can instead `defmock` the three behaviours and `stub_with/2` them with
  `EhOsContract.Auth.People.Directory.Static`, `EhOsContract.Auth.Grants.Local` and
  `EhOsContract.Auth.Mail.Local`. Like the test key, the three `Testing` stand-ins answer
  only with `pin_keys: true`, and raise without it.

  A stub is made in the test itself, or in a `setup` block, which runs in the test's
  process; one made in `setup_all` runs in another process, which the test does not name
  among its `$callers`, and is not seen.

  `credential/3`, `sign_in/3`, `sign_out/1` and `assert_every_entry_refuses/3` run in the
  test process and read and write through the engine's repo, so they belong in a test that
  owns a sandbox connection, as any test of the host's that dispatches does.
  `stub_people/1`, `stub_grants/1` and `stub_mail/1` touch no repo.
  """

  import ExUnit.Assertions

  alias EhOsContract.Auth.{Keys, SignIn}
  alias EhOsContract.Auth.Testing.SignIn, as: StandIn
  alias EhOsContract.Auth.SignIn.Sessions

  @key {__MODULE__, :key}

  @doc """
  Imports `credential/3`, `sign_in/3`, `sign_out/1`, `assert_every_entry_refuses/3`,
  `stub_people/1`, `stub_grants/1` and `stub_mail/1`.
  """
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
    {token, _expires_at} = signed(subject, capabilities, scopes, opts)
    token
  end

  @doc """
  Signs a browser in as `subject`, holding `capabilities`, without EHOS: a session row
  whose credential for this application `credential/3` issued, as a sign-in through EHOS
  writes it. Returns the token the browser keeps; put it in the test's session under
  `EhOsContract.Auth.Session.session_key/0`, and `EhOsContract.Auth.Session` lets the
  request through, with the actor of that credential.

      token = sign_in("u-anna", ["clinic.record_payment"])

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{EhOsContract.Auth.Session.session_key() => token})
        |> get("/visits/7")

  When no `EhOsContract.Auth.SignIn` runs under the name, a stand-in is started there
  once per test run: it holds a client made for the test and never calls EHOS, and it
  keeps the name until the run ends. So a test that starts a sign-in child of its own
  gives it another `name:`, and passes that name here as `sign_in:` to sign in through
  it; a running child is used as it is.

  The credential is for this application alone, and lives ten minutes from
  `EhOsContract.Clock.now/0`. Through the stand-in, a credential that must be renewed,
  because the test moved the clock past those ten minutes, and
  `EhOsContract.Auth.Session.credential/3` for another application, answer
  `:ehos_unavailable`: renewing is EHOS's. Through a running child, renewing calls the
  EHOS it is configured with.

  `opts`: `scopes:`, as `credential/3` takes them; `sign_in:`, the child's name
  (`EhOsContract.Auth.SignIn` by default); `keys:`, the key process. Raises as
  `credential/3` does without the key process or `pin_keys: true`.
  """
  @spec sign_in(String.t(), [String.t()], keyword()) :: String.t()
  def sign_in(subject, capabilities, opts \\ []) do
    opts = Keyword.validate!(opts, scopes: %{}, sign_in: SignIn, keys: Keys)
    {token, expires_at} = signed(subject, capabilities, opts[:scopes], keys: opts[:keys])
    :ok = StandIn.ensure_started(opts[:sign_in])
    unique = fn -> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false) end

    {:ok, browser_token} =
      Sessions.create(opts[:sign_in], %{
        subject: subject,
        sid: "test-sid-" <> unique.(),
        auth_time: EhOsContract.Clock.now(),
        refresh_token: "test-refresh-" <> unique.(),
        id_token: "test-id-" <> unique.(),
        credential: %{
          resource: SignIn.config(opts[:sign_in]).address,
          token: token,
          expires_at: expires_at
        }
      })

    browser_token
  end

  @doc """
  Signs out the browser `sign_in/3` signed in: its session is deleted, and
  `EhOsContract.Auth.Session` then treats the browser as signed out — a redirect to sign
  in for a page, 401 for anything else. Signing out twice is not an error.

      token = sign_in("u-anna", ["clinic.record_payment"])
      :ok = sign_out(token)

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{EhOsContract.Auth.Session.session_key() => token})
        |> get("/visits/7")

      assert redirected_to(conn) =~ "/auth/ehos/sign-in"
  """
  @spec sign_out(String.t()) :: :ok
  def sign_out(browser_token), do: Sessions.delete(browser_token)

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

    repo = EhOsContract.Config.fetch!(:repo)

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

  defp signed(subject, capabilities, scopes, opts) do
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
    {token, DateTime.from_unix!(claims["exp"])}
  end

  defp engine_rows(repo) do
    for table <- ~w(eh_os_contract_events eh_os_contract_commands), into: %{} do
      [[count]] = repo.query!("SELECT count(*) FROM #{table}").rows
      {table, count}
    end
  end

  @doc """
  The people `EhOsContract.Auth.Testing.People` answers for this test: a list, as
  `EhOsContract.Auth.People.Directory.Static` takes it, or `{:error, reason}`, which
  every call then answers, as EHOS down (`:unavailable`) or not agreed (`:not_agreed`).

      stub_people([%{id: "6f1c0a1e-0000-4000-8000-000000000001", email: "ada@example.com", name: "Ada"}])
      stub_people({:error, :not_agreed})
  """
  @spec stub_people([map()] | {:error, EhOsContract.Auth.People.reason()}) :: :ok
  def stub_people(people)
      when is_list(people) or
             (is_tuple(people) and tuple_size(people) == 2 and elem(people, 0) == :error and
                is_atom(elem(people, 1))) do
    Process.put({__MODULE__, :people}, people)
    :ok
  end

  @doc """
  What `EhOsContract.Auth.Testing.Grants` answers for this test: `:made`, every grant and
  revocation made as `EhOsContract.Auth.Grants.Local` makes them, which is also what it
  answers when a test says nothing; or `{:error, reason}`, which every call then answers.

      stub_grants({:error, :beyond_rule})
  """
  @spec stub_grants(:made | {:error, EhOsContract.Auth.Grants.reason()}) :: :ok
  def stub_grants(answer)
      when answer == :made or
             (is_tuple(answer) and tuple_size(answer) == 2 and elem(answer, 0) == :error and
                is_atom(elem(answer, 1))) do
    Process.put({__MODULE__, :grants}, answer)
    :ok
  end

  @doc """
  What `EhOsContract.Auth.Testing.Mail` answers for this test: `:sent`, every message
  taken as `EhOsContract.Auth.Mail.Local` takes it, which is also what it answers when a
  test says nothing; or `{:error, reason}`, which every call then answers: an atom, or
  `{:beyond_agreement, reasons}` or `{:invalid, reasons}`. Stub a reason
  `EhOsContract.Auth.Mail` documents: one it never answers is taken here, and only a
  Hammox mock of `EhOsContract.Auth.Mail.Sender` refuses it. Each message still comes to the test as
  `{:ehos_mail, message}`.

      stub_mail({:error, :not_agreed})
      stub_mail({:error, {:beyond_agreement, ["to[0]: not a person of this company"]}})
  """
  @spec stub_mail(:sent | {:error, EhOsContract.Auth.Mail.reason()}) :: :ok
  def stub_mail(answer)
      when answer == :sent or
             (is_tuple(answer) and tuple_size(answer) == 2 and elem(answer, 0) == :error and
                (is_atom(elem(answer, 1)) or
                   (is_tuple(elem(answer, 1)) and tuple_size(elem(answer, 1)) == 2 and
                      elem(elem(answer, 1), 0) in [:beyond_agreement, :invalid] and
                      is_list(elem(elem(answer, 1), 1))))) do
    Process.put({__MODULE__, :mail}, answer)
    :ok
  end

  # The test's process: the first of the `$callers` chain, which started the rest; this one
  # when it names none and is not an OTP process, as a test's is not; or none, for a server
  # the test did not start, whose mailbox would keep the message or log it whole.
  @doc false
  @spec test_process() :: pid() | nil
  def test_process do
    case Process.get(:"$callers", []) do
      [] -> if Process.get(:"$initial_call"), do: nil, else: self()
      callers -> List.last(callers)
    end
  end

  # What a test stubbed under `name`: in this process, or in the first of its `$callers`
  # that stubbed it, a LiveView's or a task's test. Only where test keys may be pinned, as
  # the sign-in stand-in: anywhere else a stand-in would answer for EHOS.
  @doc false
  @spec stubbed!(:people | :grants | :mail, term()) :: term()
  def stubbed!(name, default) do
    :ok = Keys.test_only!("EhOsContract.Auth.Testing.People, .Grants and .Mail")

    key = {__MODULE__, name}

    Enum.find_value([self() | Process.get(:"$callers", [])], default, fn pid ->
      case Process.info(pid, :dictionary) do
        {:dictionary, dictionary} ->
          List.keyfind(dictionary, key, 0) |> then(&(&1 && elem(&1, 1)))

        nil ->
          nil
      end
    end)
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
