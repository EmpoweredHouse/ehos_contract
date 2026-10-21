defmodule EhOsContract.Auth.GrantsTest do
  @moduledoc """
  A signed-in person grants and revokes, through the application, a role their rule lets
  them give. EHOS is `EhOsContract.Auth.FakeEhos`, which exchanges a person's credential
  and serves the grant routes as EHOS's grants API describes them.

  Every test runs against committed data, in `EhOsContract.Auth.CommitRepo`'s database,
  as `EhOsContract.Auth.RenewalTest` does, since a stale credential is renewed under a
  lease taken in autocommit.

  Not async: the tests change `config :eh_os_contract_auth` and the engine's repo.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import EhOsContract.Auth.KeyCase, only: [key_pair: 0, start_keys: 2, ehos: 1, clock: 0]

  alias EhOsContract.Auth.{CommitRepo, FakeEhos, Grants, Session, SignIn}
  alias EhOsContract.Auth.Grants.Grant
  alias EhOsContract.Auth.SignIn.Sessions

  @moduletag :tmp_dir

  @address "https://clinic.test"
  @role "clinic.client"

  setup %{tmp_dir: dir} do
    previous = Application.get_all_env(:eh_os_contract_auth)
    repo = Application.fetch_env!(:eh_os_contract, :repo)
    Application.put_env(:eh_os_contract, :repo, CommitRepo)

    on_exit(fn ->
      Application.put_env(:eh_os_contract, :repo, repo)
      restore(previous)
      CommitRepo.query!("DELETE FROM eh_os_contract_auth_sessions")
    end)

    {key_file, key} = FakeEhos.client_key_file(dir)

    Application.put_env(:eh_os_contract_auth, :sign_in,
      client_id: "clinic/test",
      client_key_file: key_file,
      address: @address,
      secret_key_base: String.duplicate("s", 64),
      applications: %{}
    )

    pair = key_pair()
    ehos = FakeEhos.start(signer: pair.private)
    name = start!(ehos)
    {token, session} = signed_in!(ehos, name)

    %{
      ehos: ehos,
      name: name,
      token: token,
      session: session,
      client_key: key,
      keys: start_keys(ehos({:keys, [pair]}), repo: CommitRepo, clock: clock())
    }
  end

  describe "granting" do
    test "a new email is invited and bound, with the person's own credential exchanged",
         context do
      assert {:ok, %Grant{} = grant} =
               Grants.grant(conn(context), [email: "bea@example.com", role: @role, name: "Bea"],
                 sign_in: context.name
               )

      assert %Grant{
               email: "bea@example.com",
               state: :invited,
               role: @role,
               bound: :now,
               delivery: :mailed
             } = grant

      assert grant.person_id =~ ~r/\A[0-9a-f-]{36}\z/

      # The exchange: the session's credential for this application, as the sign-in's client.
      assert [exchange] = exchanges(context)
      assert exchange["subject_token"] == context.session.credentials[@address].token
      assert exchange["subject_token_type"] == "urn:ietf:params:oauth:token-type:access_token"
      assert exchange["audience"] == "ehos"
      refute Enum.any?(~w(scope resource actor_token), &Map.has_key?(exchange, &1))

      assertion = exchange["client_assertion"]
      public = JOSE.JWK.to_public(JOSE.JWK.from_map(context.client_key))
      assert {true, %JOSE.JWT{fields: claims}, _jws} = JOSE.JWT.verify(public, assertion)
      assert claims["iss"] == "clinic/test" and claims["sub"] == "clinic/test"
      assert claims["aud"] == "https://ehos.test/oauth/token"

      # The grant: with the credential EHOS exchanged, never the person's own.
      assert [call] = FakeEhos.grant_calls(context.ehos)
      assert call.method == "POST"
      assert call.path == "/api/v1/role-bindings/grants"
      assert Map.has_key?(FakeEhos.exchanged(context.ehos), call.bearer)
      refute call.bearer == context.session.credentials[@address].token
      assert call.body == %{"email" => "bea@example.com", "role" => @role, "name" => "Bea"}
    end

    test "a LiveView's session map grants as a connection does, and a name left out is not sent",
         context do
      assert {:ok, %Grant{bound: :now}} =
               Grants.grant(browser(context), [email: "bea@example.com", role: @role],
                 sign_in: context.name
               )

      assert [%{body: body}] = FakeEhos.grant_calls(context.ehos)
      assert body == %{"email" => "bea@example.com", "role" => @role}
    end

    test "granting again answers the role bound before, so a page may ask again", context do
      args = [email: "bea@example.com", role: @role]

      assert {:ok, %Grant{bound: :now} = first} = grant(context, args)
      assert {:ok, %Grant{bound: :before} = again} = grant(context, args)
      assert again.person_id == first.person_id
      assert again.role_binding_id == first.role_binding_id
    end

    test "a person who has joined is bound and mailed nothing", context do
      id = FakeEhos.person(context.ehos, "cyd@example.com", "joined")

      assert {:ok, %Grant{person_id: ^id, state: :joined, delivery: :none}} =
               grant(context, email: "cyd@example.com", role: @role)
    end

    test "a link held past the hour's three is said so", context do
      held = %{
        "person" => %{
          "id" => Ecto.UUID.generate(),
          "email" => "bea@example.com",
          "state" => "invited"
        },
        "role_binding" => %{"id" => Ecto.UUID.generate(), "role" => @role, "bound" => "now"},
        "delivery" => "held"
      }

      FakeEhos.grants_answer(context.ehos, {:status, 201, held})

      assert {:ok, %Grant{delivery: :held}} =
               grant(context, email: "bea@example.com", role: @role)
    end

    test "each refusal of the grant route is answered by its code", context do
      for {status, code} <- [
            {403, "beyond_rule"},
            {422, "unknown_role"},
            {409, "mail_required"},
            {409, "person_disabled"},
            {422, "invalid_email"},
            {422, "invalid_name"},
            {409, "already_bound"},
            {429, "too_many_invitations"},
            {502, "not_mailed"},
            {404, "not_found"}
          ] do
        FakeEhos.grants_answer(
          context.ehos,
          {:status, status, %{"error" => code, "message" => "No."}}
        )

        assert grant(context, email: "bea@example.com", role: @role) ==
                 {:error, String.to_existing_atom(code)}
      end
    end

    test "a person disabled since the exchange is not permitted, whichever check finds it",
         context do
      for {status, code} <- [{401, "disabled"}, {403, "forbidden"}] do
        FakeEhos.grants_answer(context.ehos, {:status, status, %{"error" => code}})

        assert grant(context, email: "bea@example.com", role: @role) == {:error, :not_permitted}
      end
    end

    test "the API's limit is a rate limit", context do
      FakeEhos.grants_answer(context.ehos, {:status, 429, %{"error" => "too_many_calls"}})

      assert grant(context, email: "bea@example.com", role: @role) == {:error, :rate_limited}
    end

    test "raises for an argument it does not take, and calls nobody", context do
      for args <- [
            [role: @role],
            [email: "bea@example.com"],
            [email: "", role: @role],
            [email: "bea@example.com", role: @role, name: 7],
            [email: "bea@example.com", role: @role, scope: "x"],
            %{email: "bea@example.com", role: @role},
            [email: "bea@example.com" <> <<0xFF>>, role: @role],
            [email: "bea@example.com", role: @role, name: "Bea" <> <<0xC3>>]
          ] do
        assert_raise ArgumentError, fn -> grant(context, args) end
      end

      assert_raise ArgumentError, fn ->
        Grants.grant(conn(context), [email: "bea@example.com", role: @role],
          sign_in: context.name,
          typo: 1
        )
      end

      assert exchanges(context) == []
    end
  end

  describe "revoking" do
    test "unbinds the role from the person a grant named", context do
      {:ok, granted} = grant(context, email: "bea@example.com", role: @role)

      assert Grants.revoke(conn(context), granted.person_id, @role, sign_in: context.name) ==
               {:ok, %{role_binding_id: granted.role_binding_id, role: @role}}

      assert [_grant, call] = FakeEhos.grant_calls(context.ehos)
      assert call.method == "DELETE"
      assert call.path == "/api/v1/role-bindings/grants/#{granted.person_id}/#{@role}"
      assert call.body == nil
      assert Map.has_key?(FakeEhos.exchanged(context.ehos), call.bearer)

      # The binding is gone: revoking again finds none.
      assert Grants.revoke(conn(context), granted.person_id, @role, sign_in: context.name) ==
               {:error, :not_found}
    end

    test "an id that is no one's is not sent", context do
      for id <- ["", "bea@example.com", "../people", "6f1c0a1e-0000-4000-8000-00000000000"] do
        assert Grants.revoke(conn(context), id, @role, sign_in: context.name) ==
                 {:error, :not_found}
      end

      assert exchanges(context) == []
    end

    test "a role that is not <application>.<name> is no role, and is not sent", context do
      id = Ecto.UUID.generate()

      for role <- [
            "..",
            ".",
            "clinic",
            "clinic./x",
            "clinic/../x.client",
            "clinic.Client",
            "clinic.a b",
            "clin" <> <<0xFF>> <> ".client"
          ] do
        assert Grants.revoke(conn(context), id, role, sign_in: context.name) ==
                 {:error, :unknown_role},
               inspect(role)
      end

      assert exchanges(context) == []
    end

    test "an application's name with characters a path does not take is sent encoded", context do
      id = Ecto.UUID.generate()
      Grants.revoke(conn(context), id, "clin%ic.client", sign_in: context.name)

      assert [%{path: path}] = FakeEhos.grant_calls(context.ehos)
      assert path == "/api/v1/role-bindings/grants/#{id}/clin%25ic.client"
    end
  end

  describe "the exchange" do
    test "a refused exchange is not permitted, and nothing is granted", context do
      FakeEhos.exchange_answer(context.ehos, :invalid_grant)

      assert grant(context, email: "bea@example.com", role: @role) == {:error, :not_permitted}
      assert FakeEhos.grant_calls(context.ehos) == []
    end

    test "the token endpoint's limit is a rate limit", context do
      FakeEhos.exchange_answer(context.ehos, {:status, 429, %{"error" => "slow_down"}})

      assert grant(context, email: "bea@example.com", role: @role) == {:error, :rate_limited}
    end

    test "a client EHOS refuses to exchange for is EHOS unavailable, and logged", context do
      FakeEhos.exchange_answer(context.ehos, {:status, 401, %{"error" => "invalid_client"}})

      log =
        capture_log(fn ->
          assert grant(context, email: "bea@example.com", role: @role) == {:error, :unavailable}
        end)

      assert log =~ "invalid_client"
      assert FakeEhos.grant_calls(context.ehos) == []
    end

    test "an exchange answered without a credential is EHOS unavailable", context do
      FakeEhos.exchange_answer(context.ehos, :no_token)

      capture_log(fn ->
        assert grant(context, email: "bea@example.com", role: @role) == {:error, :unavailable}
      end)
    end

    test "a credential with seconds left while another request renews is not sent", context do
      {:ok, session} = Sessions.fetch(context.name, context.token)
      assert {:taken, nil} = Sessions.take_lease(session, "another-request", 30_000)
      almost = DateTime.add(session.credentials[@address].expires_at, -3)

      assert EhOsContract.Clock.at(almost, fn ->
               grant(context, email: "bea@example.com", role: @role)
             end) == {:error, :renewal_busy}

      assert exchanges(context) == []
    end

    test "a stale credential is renewed first, and the renewed one exchanged", context do
      later = DateTime.add(DateTime.utc_now(), 11 * 60)
      FakeEhos.advance(context.ehos, 11 * 60)

      assert {:ok, %Grant{}} =
               EhOsContract.Clock.at(later, fn ->
                 Grants.grant(conn(context), [email: "bea@example.com", role: @role],
                   sign_in: context.name,
                   keys: context.keys
                 )
               end)

      assert [refresh, exchange] = FakeEhos.token_requests(context.ehos) |> Enum.drop(1)
      assert refresh["grant_type"] == "refresh_token"
      refute exchange["subject_token"] == context.session.credentials[@address].token

      {:ok, session} = Sessions.fetch(context.name, context.token)
      assert exchange["subject_token"] == session.credentials[@address].token
    end
  end

  describe "what a call keeps and repeats" do
    test "neither credential is kept: each grant exchanges anew, and the session holds no other",
         context do
      assert {:ok, _grant} = grant(context, email: "bea@example.com", role: @role)
      assert {:ok, _grant} = grant(context, email: "cyd@example.com", role: @role)

      assert [first, second] = FakeEhos.grant_calls(context.ehos)
      refute first.bearer == second.bearer
      assert length(exchanges(context)) == 2

      {:ok, session} = Sessions.fetch(context.name, context.token)
      assert Map.keys(session.credentials) == [@address]

      for exchanged <- Map.keys(FakeEhos.exchanged(context.ehos)) do
        refute inspect(session) =~ exchanged
      end
    end

    test "nothing is retried: a failed call is asked once", context do
      for answer <- [:reset, :not_json, {:status, 503, %{"error" => "unavailable"}}] do
        FakeEhos.grants_answer(context.ehos, answer)
        before = length(FakeEhos.grant_calls(context.ehos))

        capture_log(fn ->
          assert grant(context, email: "bea@example.com", role: @role) == {:error, :unavailable}
        end)

        assert length(FakeEhos.grant_calls(context.ehos)) == before + 1, inspect(answer)
      end

      FakeEhos.grants_answer(context.ehos, nil)
      FakeEhos.exchange_answer(context.ehos, :reset)

      capture_log(fn ->
        assert grant(context, email: "bea@example.com", role: @role) == {:error, :unavailable}
      end)

      assert length(exchanges(context)) == 4
    end

    test "EHOS down is EHOS unavailable, and the log holds no credential", context do
      FakeEhos.down(context.ehos, true)

      log =
        capture_log(fn ->
          assert grant(context, email: "bea@example.com", role: @role) == {:error, :unavailable}
        end)

      refute log =~ "eyJ"
    end

    test "an exception inside the request is logged without the request", context do
      FakeEhos.grants_answer(context.ehos, :raise)

      log =
        capture_log(fn ->
          assert grant(context, email: "bea@example.com", role: @role) == {:error, :unavailable}
        end)

      assert [%{bearer: bearer}] = FakeEhos.grant_calls(context.ehos)
      assert log =~ "could not be reached"
      refute log =~ bearer
      refute log =~ "authorization"
    end

    test "an answer EHOS never gives is EHOS unavailable", context do
      FakeEhos.grants_answer(context.ehos, {:status, 201, %{"person" => %{"id" => 7}}})

      capture_log(fn ->
        assert grant(context, email: "bea@example.com", role: @role) == {:error, :unavailable}
      end)
    end
  end

  describe "the session" do
    test "a browser signed in to nobody is signed out, and EHOS is not asked", context do
      assert Grants.grant(%{}, [email: "bea@example.com", role: @role], sign_in: context.name) ==
               {:error, :signed_out}

      assert Grants.grant(
               %{Session.session_key() => "nobody"},
               [email: "bea@example.com", role: @role],
               sign_in: context.name
             ) == {:error, :signed_out}

      assert exchanges(context) == []
    end
  end

  defp grant(context, args),
    do: Grants.grant(conn(context), args, sign_in: context.name)

  defp conn(context),
    do: Plug.Test.init_test_session(Plug.Test.conn(:post, "/"), browser(context))

  defp browser(context), do: %{Session.session_key() => context.token}

  defp exchanges(context),
    do:
      context.ehos
      |> FakeEhos.token_requests()
      |> Enum.filter(&(&1["grant_type"] == "urn:ietf:params:oauth:grant-type:token-exchange"))

  # A code exchange through EHOS's fake, written as the callback writes it.
  defp signed_in!(ehos, name) do
    config = SignIn.config(name)
    FakeEhos.grant(ehos, "code-1", "clinic/test", %{"nonce" => "n-1"})
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
