defmodule EhOsContract.Auth.DevelopmentTest do
  # The mode at work, in a child process where it starts: `mix test` runs in `:test`, which the
  # refusal refuses. Each child checks out the test repo in the sandbox, so what it writes is
  # rolled back when it ends.
  use ExUnit.Case, async: true

  alias EhOsContract.Auth.Child

  # Starts the repo, the keys and the mode, and binds `token`, the token the mode printed, and
  # `sup`, the supervisor of the two children.
  @started """
  alias EhOsContract.Auth.{Development, Session, SignIn}
  alias EhOsContract.Auth.Development.{Credential, Guard}

  {:ok, _} = EhOsContract.Auth.TestRepo.start_link()
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(EhOsContract.Auth.TestRepo)
  Ecto.Adapters.SQL.Sandbox.mode(EhOsContract.Auth.TestRepo, {:shared, self()})

  {:ok, io} = StringIO.open("")
  leader = Process.group_leader()
  Process.group_leader(self(), io)
  {:ok, sup} = Supervisor.start_link([EhOsContract.Auth, {Development, url: "http://localhost:4000"}], strategy: :one_for_one)
  Process.group_leader(self(), leader)
  {_, printed} = StringIO.contents(io)
  [_, token] = Regex.run(~r{http://localhost:4000/dev/sign-in\\?token=(\\S+)}, printed)

  page = fn browser ->
    Plug.Test.conn(:get, "/visits")
    |> Plug.Conn.put_req_header("accept", "text/html")
    |> Plug.Test.init_test_session(%{Session.session_key() => browser})
    |> Session.call(Session.init(assign_actor: true))
  end

  later = fn minutes, fun -> EhOsContract.Clock.at(DateTime.add(DateTime.utc_now(), minutes * 60), fun) end
  """

  defp run(body), do: Child.run(@started <> body, contracts: true)

  test "the token is printed at start, with the page's address and the terminal's command" do
    assert {printed, true} =
             run("""
             {printed, Development.token?(token)}
             """)

    assert printed =~ "Development sign-in, with a key made at this start"
    assert printed =~ "mix eh_os_contract.dev.credential --token "
  end

  test "the actors of the domain, with their capabilities and scopes" do
    assert run("Development.actors()") == [
             %{role: "clinic.manager", capabilities: ["clinic.close_visit"], scopes: []},
             %{
               role: "clinic.receptionist",
               capabilities: ["clinic.record_payment"],
               scopes: ["clinic_id"]
             }
           ]
  end

  test "a person signed in passes the session plug with the union of the actors' capabilities" do
    assert run("""
           {:ok, browser} = Development.sign_in("u-dev", ["clinic.receptionist", "clinic.manager"], %{"clinic_id" => "clinic-1"})
           conn = page.(browser)
           actor = conn.assigns.eh_os_contract_actor
           {conn.halted, actor.subject, actor.capabilities |> Enum.sort(), actor.scopes}
           """) ==
             {false, "u-dev", ["clinic.close_visit", "clinic.record_payment"],
              %{"clinic.record_payment" => %{"clinic_id" => ["clinic-1"]}}}
  end

  test "signing in refuses an actor the domain does not have, a scope without a value, no person" do
    assert run("""
           [
             Development.sign_in("u-dev", ["clinic.nobody", "clinic.manager"]),
             Development.sign_in("u-dev", ["clinic.receptionist"]),
             Development.sign_in("u-dev", ["clinic.receptionist"], %{"clinic_id" => ""}),
             Development.sign_in("", ["clinic.manager"]),
             Development.credential("u-dev", ["clinic.nobody"])
           ]
           """) == [
             {:error, {:unknown_actors, ["clinic.nobody"]}},
             {:error, {:missing_scopes, ["clinic_id"]}},
             {:error, {:missing_scopes, ["clinic_id"]}},
             {:error, :no_subject},
             {:error, {:unknown_actors, ["clinic.nobody"]}}
           ]
  end

  test "a development session is renewed after its credential expires, through the mode" do
    assert {{false, ["clinic.close_visit"]}, {false, ["clinic.close_visit"]}, renewed?} =
             run("""
             {:ok, browser} = Development.sign_in("u-dev", ["clinic.manager"])
             {:ok, session} = EhOsContract.Auth.SignIn.Sessions.fetch(SignIn, browser)
             [%{token: first}] = Map.values(session.credentials)

             at = fn minutes ->
               later.(minutes, fn ->
                 conn = page.(browser)
                 {conn.halted, conn.assigns.eh_os_contract_actor.capabilities |> Enum.to_list()}
               end)
             end

             after_first = at.(11)
             after_second = at.(22)
             {:ok, session} = EhOsContract.Auth.SignIn.Sessions.fetch(SignIn, browser)
             [%{token: last}] = Map.values(session.credentials)
             {after_first, after_second, last != first}
             """)

    assert renewed?
  end

  test "a session whose credential the mode's key did not sign is signed out at renewal" do
    assert run("""
           other = JOSE.JWK.generate_key({:okp, :Ed25519})
           now = DateTime.utc_now()
           claims = %{"iss" => "https://ehos.test", "aud" => "clinic/test", "sub" => "u-dev", "exp" => DateTime.to_unix(now) + 600, "cap" => ["clinic.close_visit"]}
           {_, foreign} = JOSE.JWT.sign(other, %{"alg" => "Ed25519", "kid" => JOSE.JWK.thumbprint(other)}, claims) |> JOSE.JWS.compact()

           {:ok, browser} =
             EhOsContract.Auth.SignIn.Sessions.create(SignIn, %{
               subject: "u-dev", sid: "sid", auth_time: now, refresh_token: "r", id_token: "i",
               credential: %{resource: SignIn.config(SignIn).address, token: foreign, expires_at: DateTime.add(now, 600)}
             })

           conn = later.(11, fn -> page.(browser) end)
           {conn.status, Plug.Conn.get_resp_header(conn, "location"), EhOsContract.Auth.SignIn.Sessions.fetch(SignIn, browser)}
           """) == {302, ["/dev/sign-in?return_to=%2Fvisits"], {:error, :signed_out}}
  end

  test "after a restart, which makes a new key, a development session is signed out and sent to /dev/sign-in" do
    assert {{false, nil}, {302, ["/dev/sign-in?return_to=%2Fvisits"]}, false,
            {:error, :not_renewable}} =
             run("""
             {:ok, browser} = Development.sign_in("u-dev", ["clinic.manager"])
             {:ok, bearer} = Development.credential("u-dev", ["clinic.manager"])
             before = page.(browser)

             :ok = Supervisor.terminate_child(sup, Development)
             {:ok, _} = Supervisor.restart_child(sup, Development)

             conn = page.(browser)

             {{before.halted, before.status}, {conn.status, Plug.Conn.get_resp_header(conn, "location")},
              Development.token?(token), Development.renew(SignIn, "u-dev", bearer)}
             """)
  end

  test "a credential signed with the development key is refused by a verifier that did not pin it" do
    assert run("""
           {:ok, bearer} = Development.credential("u-dev", ["clinic.manager"])
           {:ok, _} = EhOsContract.Auth.Keys.start_link(name: :elsewhere, url: "http://127.0.0.1:9/jwks")
           {:ok, actor} = EhOsContract.Auth.verify(bearer)
           {actor.subject, EhOsContract.Auth.verify(bearer, keys: :elsewhere)}
           """) == {"u-dev", {:error, :no_keys}}
  end

  test "the guard refuses each check alone, and answers no CORS header" do
    results =
      run("""
      request = fn opts ->
        conn = Plug.Test.conn(:get, "/dev/sign-in" <> Keyword.get(opts, :query, ""))
        conn = %{conn | remote_ip: Keyword.get(opts, :remote_ip, {127, 0, 0, 1}), host: Keyword.get(opts, :host, "localhost")}
        conn = Enum.reduce(Keyword.get(opts, :headers, []), conn, fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end)
        conn = if opts[:session], do: Plug.Test.init_test_session(conn, opts[:session]) |> Plug.Conn.fetch_session(), else: conn

        conn =
          conn
          |> Plug.Conn.put_resp_header("access-control-allow-origin", "*")
          |> Guard.call(Guard.init([]))

        conn = if conn.halted, do: conn, else: Plug.Conn.send_resp(conn, 200, "")
        cors = Enum.filter(conn.resp_headers, fn {name, _} -> String.starts_with?(name, "access-control-allow-") end)
        {conn.status, cors, opts[:session] && Plug.Conn.get_session(conn)}
      end

      first = request.(query: "?token=" <> token, session: %{})
      {200, [], remembered} = first

      %{
        passes: request.(query: "?token=" <> token),
        header: request.(headers: [{"x-dev-sign-in-token", token}]),
        ipv6: request.(query: "?token=" <> token, remote_ip: {0, 0, 0, 0, 0, 0, 0, 1}, host: "[::1]"),
        mapped: request.(query: "?token=" <> token, remote_ip: {0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 1}),
        session: request.(session: remembered),
        no_token: request.([]),
        wrong_token: request.(query: "?token=" <> token <> "x"),
        not_loopback: request.(query: "?token=" <> token, remote_ip: {192, 168, 1, 7}),
        wrong_host: request.(query: "?token=" <> token, host: "rebound.example"),
        wrong_session: request.(session: %{"eh_os_contract_auth_development_token" => "AAAA"})
      }
      """)

    for name <- [:passes, :header, :ipv6, :mapped, :session],
        do: assert({200, [], _} = results[name], "#{name}: #{inspect(results[name])}")

    for name <- [:no_token, :wrong_token, :not_loopback, :wrong_host, :wrong_session],
        do: assert({403, [], _} = results[name], "#{name}: #{inspect(results[name])}")
  end

  test "the terminal's endpoint answers a credential, behind the guard" do
    assert {{200, actor}, {422, %{"error" => "unknown_actors: clinic.nobody"}}, 403, 404} =
             run("""
             post = fn body, headers ->
               conn =
                 Plug.Test.conn(:post, "/", Jason.encode!(body))
                 |> Map.put(:host, "localhost")
                 |> Plug.Conn.put_req_header("content-type", "application/json")

               conn = Enum.reduce(headers, conn, fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end)
               Credential.call(conn, Credential.init([]))
             end

             answer = fn conn -> {conn.status, Jason.decode!(conn.resp_body)} end
             headers = [{"x-dev-sign-in-token", token}]

             {200, %{"credential" => bearer}} = answer.(post.(%{actors: ["clinic.receptionist"], scopes: %{clinic_id: "clinic-1"}}, headers))
             {:ok, actor} = EhOsContract.Auth.verify(bearer)

             {{200, {actor.subject, Enum.sort(actor.capabilities)}},
              answer.(post.(%{actors: ["clinic.nobody"]}, headers)),
              post.(%{actors: ["clinic.manager"]}, []).status,
              Credential.call(%{Plug.Test.conn(:get, "/") | host: "localhost"} |> Plug.Conn.put_req_header("x-dev-sign-in-token", token), []).status}
             """)

    assert actor == {"dev", ["clinic.record_payment"]}
  end
end
