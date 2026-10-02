defmodule EhOsContract.Auth.RenewalTest do
  @moduledoc """
  EB3a (#78, #80): a signed-in person's credential renewed through EHOS (S4, S5 and S10
  in docs/adr/browser-session.md); EB3b (#78): another application's, by `resource`
  (S5, S7, S8). Every test runs against committed data, in
  `EhOsContract.Auth.CommitRepo`'s database, because the lease is taken and released
  by statements in autocommit, two renewals meet only across connections, and a
  renewal must hold no transaction while it calls EHOS.

  EHOS is `EhOsContract.Auth.FakeEhos`: strict rotation, a refresh token presented
  twice revokes its family, and a renewal returns an ID token in the shape #80 lists.

  Not async: the tests change `config :eh_os_contract_auth` and the engine's repo.
  """

  use ExUnit.Case, async: false

  import EhOsContract.Auth.KeyCase,
    only: [key_pair: 0, start_keys: 2, ehos: 1, clock: 0, advance: 2]

  alias EhOsContract.Auth.{CommitRepo, FakeEhos, Session, SignIn}
  alias EhOsContract.Auth.SignIn.{Renewal, Sessions}

  @moduletag :tmp_dir

  @address "https://rehmed.test"
  # Two applications in the sign-in's granted set, and one the person holds no role in.
  @ledger "https://ledger.test"
  @archive "https://archive.test"
  @billing "https://billing.test"

  setup %{tmp_dir: dir} do
    previous = Application.get_all_env(:eh_os_contract_auth)
    repo = Application.fetch_env!(:eh_os_contract, :repo)
    Application.put_env(:eh_os_contract, :repo, CommitRepo)

    on_exit(fn ->
      Application.put_env(:eh_os_contract, :repo, repo)
      restore(previous)
      CommitRepo.query!("DELETE FROM eh_os_contract_auth_sessions")
    end)

    {key_file, _key} = FakeEhos.client_key_file(dir)

    Application.put_env(:eh_os_contract_auth, :sign_in,
      client_id: "rehmed/test",
      client_key_file: key_file,
      address: @address,
      secret_key_base: String.duplicate("s", 64),
      applications: %{"ledger" => @ledger, "archive" => @archive, "billing" => @billing}
    )

    pair = key_pair()
    ehos = FakeEhos.start(signer: pair.private)
    name = start!(ehos)
    {token, session} = signed_in!(ehos, name)
    key_endpoint = ehos({:keys, [pair]})
    key_clock = clock()

    %{
      ehos: ehos,
      name: name,
      token: token,
      session: session,
      pair: pair,
      key_endpoint: key_endpoint,
      key_clock: key_clock,
      keys: start_keys(key_endpoint, repo: CommitRepo, clock: key_clock)
    }
  end

  test "a credential good for more than 30 seconds is used, and EHOS is not asked", context do
    assert Renewal.credential(context.name, context.token, @address, keys: context.keys) ==
             {:ok, context.session.credentials[@address].token}

    assert refreshes(context) == 0
  end

  # The confirmation's "past ten minutes, under EhOsContract.Clock.at/2", and #80: renewal goes
  # through Oidcc.Token.refresh/3, unmocked, on a response whose ID token has exactly #80's claims.
  test "past ten minutes, the credential is renewed and the refresh token rotated", context do
    later = minutes_later(context, 11)

    assert {:ok, renewed} =
             EhOsContract.Clock.at(later, fn ->
               Renewal.credential(context.name, context.token, @address, keys: context.keys)
             end)

    refute renewed == context.session.credentials[@address].token

    assert {:ok, %{subject: "u-anna"}} =
             EhOsContract.Clock.at(later, fn ->
               EhOsContract.Auth.verify(renewed, keys: context.keys)
             end)

    assert [form] = refresh_requests(context)
    assert form["refresh_token"] == context.session.refresh_token
    assert form["client_assertion_type"] =~ "jwt-bearer"
    refute Map.has_key?(form, "resource")

    {:ok, session} = Sessions.fetch(context.name, context.token)
    refute session.refresh_token == context.session.refresh_token
    refute session.id_token == context.session.id_token

    assert session.id_token
           |> JOSE.JWT.peek_payload()
           |> Map.get(:fields)
           |> Map.keys()
           |> Enum.sort() ==
             ~w(aud auth_time exp iat iss sid sub)

    assert lease(context) == [nil, nil]
  end

  test "two processes of one session, whose credential is stale, make one renewal", context do
    later = minutes_later(context, 11)
    FakeEhos.on_refresh(context.ehos, fn -> Process.sleep(500) end)

    results =
      1..2
      |> Enum.map(fn _ ->
        Task.async(fn ->
          EhOsContract.Clock.at(later, fn ->
            Renewal.credential(context.name, context.token, @address, keys: context.keys)
          end)
        end)
      end)
      |> Task.await_many(10_000)

    assert [{:ok, token}, {:ok, token}] = results
    assert refreshes(context) == 1
    assert {:ok, _session} = Sessions.fetch(context.name, context.token)
  end

  # D-64: no transaction across the call. Seen from the database, while EHOS is answering.
  test "no connection is idle in a transaction while EHOS is called", context do
    test = self()

    FakeEhos.on_refresh(context.ehos, fn ->
      %{rows: [[count]]} =
        CommitRepo.query!(
          "SELECT count(*) FROM pg_stat_activity " <>
            "WHERE datname = current_database() AND state LIKE 'idle in transaction%'"
        )

      send(test, {:idle_in_transaction, count})
    end)

    {:ok, _token} =
      EhOsContract.Clock.at(minutes_later(context, 11), fn ->
        Renewal.credential(context.name, context.token, @address, keys: context.keys)
      end)

    assert_received {:idle_in_transaction, 0}
  end

  test "EHOS's fake revokes the sign-in when a refresh token is presented twice", context do
    {:ok, client} = SignIn.client_context(context.name)
    opts = %{expected_subject: "u-anna", request_opts: SignIn.config(context.name).request_opts}

    assert {:ok, %Oidcc.Token{refresh: %{token: next}}} =
             Oidcc.Token.refresh(context.session.refresh_token, client, opts)

    assert {:error, {:http_error, 400, %{"error" => "invalid_grant"}}} =
             Oidcc.Token.refresh(context.session.refresh_token, client, opts)

    assert {:error, {:http_error, 400, %{"error" => "invalid_grant"}}} =
             Oidcc.Token.refresh(next, client, opts)
  end

  describe "what each outcome of a renewal leaves (S5)" do
    test "invalid_grant ends the session", context do
      {:ok, client} = SignIn.client_context(context.name)
      opts = %{expected_subject: "u-anna", request_opts: SignIn.config(context.name).request_opts}
      # Presented once here, so the renewal presents it a second time.
      {:ok, _token} = Oidcc.Token.refresh(context.session.refresh_token, client, opts)

      assert renew(context) == {:error, :signed_out}
      assert rows() == 0
    end

    for {answer, label} <- [{:reset, "no response"}, {{:status, 503}, "a 503"}] do
      test "#{label} keeps the refresh token, and the held credential while it is unexpired",
           context do
        FakeEhos.refresh_answer(context.ehos, unquote(Macro.escape(answer)))
        held = context.session.credentials[@address].token

        # Stale (inside the 30-second margin) but unexpired: the held credential.
        assert EhOsContract.Clock.at(seconds_later(context, 590), fn ->
                 Renewal.credential(context.name, context.token, @address, keys: context.keys)
               end) == {:ok, held}

        assert refreshes(context) == 1

        # Expired: none.
        assert renew(context) == {:error, :ehos_unavailable}

        {:ok, session} = Sessions.fetch(context.name, context.token)
        assert session.refresh_token == context.session.refresh_token
        # Held a moment as a pause, so the session's other requests do not call EHOS at once.
        assert [paused, %NaiveDateTime{}] = lease(context)
        assert paused =~ "paused"
        assert refreshes(context) == 1
      end
    end

    for {answer, label} <- [
          {:no_id_token, "without an ID token"},
          {:foreign_sub, "for another sub"}
        ] do
      test "a 200 oidcc refuses, #{label}, ends the session: its rotated token is lost",
           context do
        FakeEhos.refresh_answer(context.ehos, unquote(answer))

        assert renew(context) == {:error, :signed_out}
        assert rows() == 0
      end
    end

    test "a lease lost before the write ends the session", context do
      FakeEhos.on_refresh(context.ehos, fn ->
        CommitRepo.query!("UPDATE eh_os_contract_auth_sessions SET lease_holder = 'another'")
      end)

      assert renew(context) == {:error, :signed_out}
      assert rows() == 0
    end

    test "a waiter gives up when the lease is not released in time", context do
      CommitRepo.query!(
        "UPDATE eh_os_contract_auth_sessions " <>
          "SET lease_holder = 'another', lease_until = clock_timestamp() + interval '1 hour'"
      )

      assert EhOsContract.Clock.at(minutes_later(context, 11), fn ->
               Renewal.credential(context.name, context.token, @address,
                 wait_ms: 500,
                 poll_ms: 50
               )
             end) == {:error, :renewal_busy}

      assert refreshes(context) == 0
      assert rows() == 1
    end

    # S5: a holder that overran its lease or died mid-call may have presented the refresh token,
    # and presenting it again would revoke the sign-in everywhere.
    test "a lease another holder never released ends the session, and EHOS is not asked",
         context do
      CommitRepo.query!(
        "UPDATE eh_os_contract_auth_sessions " <>
          "SET lease_holder = 'another', lease_until = clock_timestamp() - interval '1 second'"
      )

      assert renew(context) == {:error, :signed_out}
      assert refreshes(context) == 0
      assert rows() == 0
    end

    test "a pause past its time is a lease like a free one", context do
      CommitRepo.query!(
        "UPDATE eh_os_contract_auth_sessions SET lease_holder = $1, " <>
          "lease_until = clock_timestamp() - interval '1 second'",
        [paused()]
      )

      assert {:ok, _token} = renew(context)
      assert refreshes(context) == 1
    end

    test "while another request renews, a credential still unexpired is used at once", context do
      CommitRepo.query!(
        "UPDATE eh_os_contract_auth_sessions " <>
          "SET lease_holder = 'another', lease_until = clock_timestamp() + interval '1 hour'"
      )

      # Waiting would end in :renewal_busy, after 15 seconds.
      assert EhOsContract.Clock.at(seconds_later(context, 590), fn ->
               Renewal.credential(context.name, context.token, @address, keys: context.keys)
             end) == {:ok, context.session.credentials[@address].token}

      assert refreshes(context) == 0
    end

    # The holder ended the session (invalid_grant) after this request had read it.
    test "a session ended while another held the lease is not served from an old read", context do
      stale = context.session
      CommitRepo.query!("DELETE FROM eh_os_contract_auth_sessions")

      assert EhOsContract.Clock.at(seconds_later(context, 590), fn ->
               Renewal.credential(context.name, context.token, @address,
                 keys: context.keys,
                 session: stale
               )
             end) == {:error, :signed_out}
    end

    for answer <- [:no_refresh_token, :expires_in_30, :exp_in_20, :foreign_sid, :jwt, :huge] do
      test "a 200 that cannot be used (#{answer}) ends the session", context do
        FakeEhos.refresh_answer(context.ehos, unquote(answer))

        assert renew(context) == {:error, :signed_out}
        assert rows() == 0
      end
    end

    # As the callback checks a sign-in: a credential every request would refuse is no renewal.
    test "a renewed credential verify/2 refuses for what it says ends the session", context do
      FakeEhos.refresh_answer(context.ehos, :foreign_audience)

      assert renew(context) == {:error, :signed_out}
      assert rows() == 0
    end

    # The application's verifier does not hold EHOS's new key yet: nothing is wrong with the
    # credential, and the rotated refresh token is kept.
    test "a renewed credential under a key this application does not hold yet is kept",
         context do
      FakeEhos.rotate_signer(context.ehos, JOSE.JWK.generate_key({:okp, :Ed25519}))

      assert {:ok, renewed} = renew(context)
      {:ok, session} = Sessions.fetch(context.name, context.token)
      assert session.credentials[@address].token == renewed
      refute session.refresh_token == context.session.refresh_token
    end

    # oidcc asks the child for keys once when an ID token names a kid it does not hold, and the
    # application's verifier refetches its own for the credential.
    test "after a key rotation at EHOS, the renewal fetches the new keys and goes on", context do
      new = key_pair()
      FakeEhos.rotate_signer(context.ehos, new.private)
      EhOsContract.Auth.KeyCase.answer(context.key_endpoint, {:keys, [context.pair, new]})

      assert {:ok, renewed} = renew(context)
      assert rows() == 1

      # The verifier refetches for an unknown kid at most every 30 seconds, and fetched at start.
      advance(context.key_clock, 31_000)

      assert {:ok, %{subject: "u-anna"}} =
               EhOsContract.Clock.at(minutes_later(context, 11), fn ->
                 EhOsContract.Auth.verify(renewed, keys: context.keys)
               end)
    end

    test "the credential's own exp bounds when it is renewed next", context do
      FakeEhos.refresh_answer(context.ehos, :short_exp)
      later = minutes_later(context, 11)

      {:ok, _token} =
        EhOsContract.Clock.at(later, fn ->
          Renewal.credential(context.name, context.token, @address, keys: context.keys)
        end)

      {:ok, session} = Sessions.fetch(context.name, context.token)
      expires_at = session.credentials[@address].expires_at
      assert DateTime.diff(expires_at, later) in 90..110
    end

    # oidcc fails before any request when the document offers no refresh grant; the status of an
    # earlier request of this process (the code exchange in setup) must not be read as its answer.
    test "a refusal before any request keeps the session, whatever this process asked before",
         context do
      FakeEhos.discovery(
        context.ehos,
        &Map.put(&1, "grant_types_supported", ["authorization_code"])
      )

      :ok = SignIn.refresh(context.name)

      assert renew(context) == {:error, :ehos_unavailable}
      assert rows() == 1
      assert refreshes(context) == 0
    end
  end

  describe "another application's credential (EB3b)" do
    test "two resources give two credentials, each with one aud, and the own one stays",
         context do
      conn = Plug.Test.init_test_session(Plug.Test.conn(:get, "/"), browser(context))

      assert {:ok, ledger} = Session.credential(conn, "ledger", sign_in: context.name)

      assert {:ok, archive} =
               Session.credential(browser(context), "archive", sign_in: context.name)

      assert claims(ledger)["aud"] == "ledger/test"
      assert claims(archive)["aud"] == "archive/test"
      assert claims(ledger)["sub"] == "u-anna"

      # Each renewal presented the refresh token the one before it returned, once.
      assert [first, second] = refresh_requests(context)
      assert first["resource"] == @ledger
      assert second["resource"] == @archive
      assert first["refresh_token"] == context.session.refresh_token
      refute second["refresh_token"] == first["refresh_token"]

      {:ok, session} = Sessions.fetch(context.name, context.token)
      assert session.credentials[@ledger].token == ledger
      assert session.credentials[@archive].token == archive

      assert session.credentials[@address].token ==
               context.session.credentials[@address].token

      # Held, so asked again it is the same one, and EHOS is not called.
      assert Session.credential(conn, "ledger", sign_in: context.name) == {:ok, ledger}
      assert refreshes(context) == 2
    end

    test "after invalid_target, the same refresh token renews the own application", context do
      assert Session.credential(browser(context), "billing", sign_in: context.name) ==
               {:error, :refused}

      assert [refused] = refresh_requests(context)
      assert refused["resource"] == @billing

      {:ok, session} = Sessions.fetch(context.name, context.token)
      assert session.refresh_token == context.session.refresh_token
      assert lease(context) == [nil, nil]

      assert {:ok, _token} = renew(context)
      assert [_refused, own] = refresh_requests(context)
      assert own["refresh_token"] == context.session.refresh_token
      refute Map.has_key?(own, "resource")
      assert rows() == 1
    end

    test "a refusal is remembered for ten minutes, and EHOS is not asked again", context do
      assert credential(context, "billing", 0) == {:error, :refused}
      assert credential(context, "billing", 9 * 60) == {:error, :refused}
      assert refreshes(context) == 1

      # The session lives on for every other application.
      assert {:ok, _ledger} = credential(context, "ledger", 9 * 60)
    end

    test "past ten minutes, EHOS is asked again, and a role granted meanwhile is seen",
         context do
      assert credential(context, "billing", 0) == {:error, :refused}
      FakeEhos.applications(context.ehos, &Map.put(&1, @billing, "billing/test"))

      assert {:ok, billing} = credential(context, "billing", 10 * 60 + 1)
      assert claims(billing)["aud"] == "billing/test"
      assert refreshes(context) == 2
    end

    # Signed out in another tab while EHOS was refusing: nothing is written for a session gone.
    test "a refusal for a session ended during the call is no refusal, but signed out",
         context do
      FakeEhos.on_refresh(context.ehos, fn ->
        CommitRepo.query!("DELETE FROM eh_os_contract_auth_sessions")
      end)

      assert credential(context, "billing", 0) == {:error, :signed_out}
    end

    test "a refusal drops the credential held for that application", context do
      assert {:ok, _ledger} = credential(context, "ledger", 0)
      FakeEhos.applications(context.ehos, &Map.delete(&1, @ledger))

      # Stale, inside the 30-second margin: renewed, and refused.
      assert credential(context, "ledger", 590) == {:error, :refused}

      assert CommitRepo.query!(
               "SELECT token, expires_at FROM eh_os_contract_auth_session_credentials " <>
                 "WHERE resource = $1",
               [@ledger]
             ).rows == [[nil, nil]]
    end

    # One lease per session: the second waits, and presents the refresh token the first returned.
    test "the own renewal and another application's at once present each token once", context do
      later = minutes_later(context, 11)
      FakeEhos.on_refresh(context.ehos, fn -> Process.sleep(300) end)

      results =
        [
          fn -> Renewal.credential(context.name, context.token, @address, keys: context.keys) end,
          fn -> Session.credential(browser(context), "ledger", sign_in: context.name) end
        ]
        |> Enum.map(fn call -> Task.async(fn -> EhOsContract.Clock.at(later, call) end) end)
        |> Task.await_many(10_000)

      assert [{:ok, _own}, {:ok, _ledger}] = results
      assert [first, second] = refresh_requests(context)
      refute first["refresh_token"] == second["refresh_token"]
      assert rows() == 1
    end

    test "credential/3 raises for a name applications does not have", context do
      assert_raise ArgumentError,
                   ~r/no application named "ledgr".*\["archive", "billing", "ledger"\]/,
                   fn ->
                     Session.credential(browser(context), "ledgr", sign_in: context.name)
                   end

      assert refreshes(context) == 0
    end
  end

  defp browser(context), do: %{Session.session_key() => context.token}

  defp credential(context, application, seconds) do
    EhOsContract.Clock.at(seconds_later(context, seconds), fn ->
      Session.credential(browser(context), application, sign_in: context.name)
    end)
  end

  defp claims(token), do: JOSE.JWT.peek_payload(token).fields

  defp paused do
    # What Renewal holds the lease as after a failed renewal.
    CommitRepo.query!("SELECT 'paused after a failed renewal'").rows |> hd() |> hd()
  end

  defp renew(context) do
    EhOsContract.Clock.at(minutes_later(context, 11), fn ->
      Renewal.credential(context.name, context.token, @address, keys: context.keys)
    end)
  end

  # EHOS's clock moves with the engine's, so what it issues then is good then.
  defp minutes_later(context, minutes), do: seconds_later(context, minutes * 60)

  defp seconds_later(context, seconds) do
    FakeEhos.advance(context.ehos, seconds - Agent.get(context.ehos, & &1.offset))
    DateTime.add(DateTime.utc_now(), seconds)
  end

  defp refresh_requests(context),
    do:
      context.ehos
      |> FakeEhos.token_requests()
      |> Enum.filter(&(&1["grant_type"] == "refresh_token"))

  defp refreshes(context), do: length(refresh_requests(context))

  defp rows,
    do:
      CommitRepo.query!("SELECT count(*) FROM eh_os_contract_auth_sessions").rows |> hd() |> hd()

  defp lease(_context) do
    CommitRepo.query!("SELECT lease_holder, lease_until FROM eh_os_contract_auth_sessions").rows
    |> hd()
  end

  # A code exchange through EHOS's fake, written as the callback writes it.
  defp signed_in!(ehos, name) do
    config = SignIn.config(name)

    FakeEhos.grant(ehos, "code-1", "rehmed/test", %{
      "nonce" => "n-1",
      "applications" => %{@ledger => "ledger/test", @archive => "archive/test"}
    })

    {:ok, context} = SignIn.client_context(name)

    {:ok, token} =
      Oidcc.Token.retrieve("code-1", context, %{
        redirect_uri: config.redirect_uri,
        nonce: "n-1",
        preferred_auth_methods: [:private_key_jwt],
        request_opts: config.request_opts
      })

    {:ok, browser_token} =
      Sessions.create(name, %{
        subject: token.id.claims["sub"],
        sid: token.id.claims["sid"],
        auth_time: DateTime.from_unix!(token.id.claims["auth_time"]),
        refresh_token: token.refresh.token,
        id_token: token.id.token,
        credential: %{
          resource: @address,
          token: token.access.token,
          expires_at: DateTime.add(DateTime.utc_now(), token.access.expires)
        }
      })

    {:ok, session} = Sessions.fetch(name, browser_token)
    {browser_token, session}
  end

  defp start!(ehos) do
    name = :"sign_in_#{System.unique_integer([:positive])}"
    start_supervised!({SignIn, [name: name, plug: FakeEhos.plug(ehos)]})
    :sys.get_state(name)
    name
  end

  defp restore(previous) do
    for {key, _value} <- Application.get_all_env(:eh_os_contract_auth),
        not Keyword.has_key?(previous, key),
        do: Application.delete_env(:eh_os_contract_auth, key)

    for {key, value} <- previous, do: Application.put_env(:eh_os_contract_auth, key, value)
  end
end
