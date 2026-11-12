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
  alias EhOsContract.Auth.Development.{Credential, Guard, Router}

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
    assert printed =~ "export EH_OS_CONTRACT_DEV_TOKEN="
    refute printed =~ "--token"
  end

  test "the process's status, which a crash report prints, never holds the private key" do
    assert {false, true} =
             run("""
             status = inspect(:sys.get_status(Process.whereis(SignIn)), limit: :infinity)
             {status =~ ~s("d" =>), status =~ ~s("x" =>)}
             """)
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
             Development.credential("u-dev", ["clinic.nobody"]),
             Development.credential("u-dev", [%{}]),
             Development.credential("u-dev", ["clinic.manager"], "clinic-1"),
             Development.credential("u-dev", ["clinic.receptionist"], %{"clinic_id" => 1})
           ]
           """) == [
             {:error, {:unknown_actors, ["clinic.nobody"]}},
             {:error, {:missing_scopes, ["clinic_id"]}},
             {:error, {:missing_scopes, ["clinic_id"]}},
             {:error, :no_subject},
             {:error, {:unknown_actors, ["clinic.nobody"]}},
             {:error, :malformed},
             {:error, :malformed},
             {:error, :malformed}
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
            {:error, :not_renewable}, {:error, :unknown_key}, 1,
            1} =
             run("""
             {:ok, browser} = Development.sign_in("u-dev", ["clinic.manager"])
             {:ok, bearer} = Development.credential("u-dev", ["clinic.manager"])
             before = page.(browser)

             :ok = Supervisor.terminate_child(sup, Development)
             {:ok, _} = Supervisor.restart_child(sup, Development)

             conn = page.(browser)

             {{before.halted, before.status}, {conn.status, Plug.Conn.get_resp_header(conn, "location")},
              Development.token?(token), Development.renew(SignIn, "u-dev", bearer),
              EhOsContract.Auth.verify(bearer), length(EhOsContract.Auth.Keys.kids()),
              # Kept through every refresh: the old key must not come back at the next one.
              map_size(:sys.get_state(EhOsContract.Auth.Keys).pinned)}
             """)
  end

  test "when the key process restarts, the mode pins its key there again, and its sessions go on" do
    assert run("""
           {:ok, browser} = Development.sign_in("u-dev", ["clinic.manager"])
           {:ok, bearer} = Development.credential("u-dev", ["clinic.manager"])
           mode = Process.whereis(SignIn)
           :ok = Supervisor.terminate_child(sup, EhOsContract.Auth)
           {:ok, _} = Supervisor.restart_child(sup, EhOsContract.Auth)
           :ok = Enum.find_value(1..50, fn _ -> if EhOsContract.Auth.Keys.kids() != [], do: :ok, else: Process.sleep(100) end)
           # A message the mode does not expect is ignored; the call after it is answered in order.
           send(mode, :anything)
           _ = :sys.get_status(mode)
           {Process.whereis(SignIn) == mode, elem(EhOsContract.Auth.verify(bearer), 0), page.(browser).halted}
           """) == {true, :ok, false}
  end

  test "a credential signed with the development key is refused by a verifier that did not pin it" do
    assert run("""
           {:ok, bearer} = Development.credential("u-dev", ["clinic.manager"])
           # A verifier that holds a key, just not the mode's.
           {_, other} = JOSE.JWK.generate_key({:okp, :Ed25519}) |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
           EhOsContract.Auth.TestRepo.insert_all("eh_os_contract_auth_keys", [%{kid: JOSE.JWK.thumbprint(JOSE.JWK.from_map(other)), jwk: other, fetched_at: DateTime.utc_now()}])
           {:ok, _} = EhOsContract.Auth.Keys.start_link(name: :elsewhere, url: "http://127.0.0.1:9/jwks")
           {:ok, actor} = EhOsContract.Auth.verify(bearer)
           {actor.subject, EhOsContract.Auth.verify(bearer, keys: :elsewhere)}
           """) == {"u-dev", {:error, :unknown_key}}
  end

  test "the guard refuses each check alone, and answers no CORS header" do
    results =
      run("""
      request = fn opts ->
        conn = Plug.Test.conn(:get, "/dev/sign-in" <> Keyword.get(opts, :query, ""))
        conn = %{conn | remote_ip: Keyword.get(opts, :remote_ip, {127, 0, 0, 1}), host: Keyword.get(opts, :host, "localhost")}
        conn = Plug.Test.put_peer_data(conn, %{address: Keyword.get(opts, :peer, {127, 0, 0, 1}), port: 50_000, ssl_cert: nil})
        # As the adapter sets them, `host` included, which `put_req_header/3` refuses.
        conn = %{conn | req_headers: Keyword.get(opts, :headers, []) ++ conn.req_headers}
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
        host_header: request.(query: "?token=" <> token, headers: [{"host", "localhost:4000"}]),
        not_loopback: request.(query: "?token=" <> token, remote_ip: {192, 168, 1, 7}, peer: {192, 168, 1, 7}),
        forwarded_for: request.(query: "?token=" <> token, peer: {192, 168, 1, 7}),
        wrong_host: request.(query: "?token=" <> token, host: "rebound.example"),
        forwarded_host: request.(query: "?token=" <> token, headers: [{"host", "rebound.example:4000"}]),
        wrong_session: request.(session: %{"eh_os_contract_auth_development_token" => "AAAA"})
      }
      """)

    for name <- [:passes, :header, :ipv6, :mapped, :session, :host_header],
        do: assert({200, [], _} = results[name], "#{name}: #{inspect(results[name])}")

    for name <-
          [
            :no_token,
            :wrong_token,
            :not_loopback,
            :forwarded_for,
            :wrong_host,
            :forwarded_host,
            :wrong_session
          ],
        do: assert({403, [], _} = results[name], "#{name}: #{inspect(results[name])}")
  end

  test "the terminal's endpoint answers a credential, behind the guard" do
    assert {{200, actor}, {422, %{"error" => "the domain has no actor clinic.nobody"}},
            {422, %{"error" => "the actors or the scopes are malformed"}}, 403,
            404} =
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
              answer.(post.(%{actors: [%{}], scopes: "clinic-1"}, headers)),
              post.(%{actors: ["clinic.manager"]}, []).status,
              Credential.call(%{Plug.Test.conn(:get, "/") | host: "localhost"} |> Plug.Conn.put_req_header("x-dev-sign-in-token", token), []).status}
             """)

    assert actor == {"dev", ["clinic.record_payment"]}
  end

  test "the router's page signs a browser in, and sends it back to a path of this application" do
    assert %{
             page: {200, page},
             signed_in: {303, "/visits", {false, "u-dev", ["clinic.record_payment"]}},
             missing_scope: {422, missing},
             elsewhere: {303, "//evil.example", "/"},
             tab: {303, "/\t/evil.example", "/"},
             no_csrf: :refused,
             no_token: 403,
             unknown: 404,
             credential: 200
           } =
             run("""
             request = fn method, path, opts ->
               conn = Plug.Test.conn(method, path, Keyword.get(opts, :body))
               conn = %{conn | host: "localhost"}
               conn = if opts[:body], do: Plug.Conn.put_req_header(conn, "content-type", "application/x-www-form-urlencoded"), else: conn
               conn = Enum.reduce(Keyword.get(opts, :headers, []), conn, fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end)
               conn = Plug.Test.init_test_session(conn, Keyword.get(opts, :session, %{}))
               Router.call(conn, Router.init([]))
             end

             first = request.(:get, "/sign-in?token=" <> token <> "&return_to=/visits", [])
             session = Plug.Conn.get_session(first)
             [_, csrf] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, first.resp_body)

             form = fn fields -> fields |> Enum.map_join("&", fn {k, v} -> URI.encode_www_form(k) <> "=" <> URI.encode_www_form(v) end) end
             post = fn fields, session -> request.(:post, "/sign-in", body: form.(fields), session: session) end

             signed = post.([{"_csrf_token", csrf}, {"subject", "u-dev"}, {"actors[]", "clinic.receptionist"}, {"scopes[clinic_id]", "clinic-1"}, {"return_to", "/visits"}], session)
             visit = page.(Plug.Conn.get_session(signed, Session.session_key()))
             actor = visit.assigns.eh_os_contract_actor

             missing = post.([{"_csrf_token", csrf}, {"actors[]", "clinic.receptionist"}], session)

             redirect = fn return_to ->
               conn = post.([{"_csrf_token", csrf}, {"actors[]", "clinic.manager"}, {"return_to", return_to}], session)
               {conn.status, return_to, conn |> Plug.Conn.get_resp_header("location") |> hd()}
             end

             no_csrf =
               try do
                 post.([{"actors[]", "clinic.manager"}], session)
                 :passed
               rescue
                 Plug.CSRFProtection.InvalidCSRFTokenError -> :refused
               end

             %{
               page: {first.status, first.resp_body},
               signed_in: {signed.status, signed |> Plug.Conn.get_resp_header("location") |> hd(), {visit.halted, actor.subject, Enum.sort(actor.capabilities)}},
               missing_scope: {missing.status, missing.resp_body},
               elsewhere: redirect.("//evil.example"),
               tab: redirect.("/\t/evil.example"),
               no_csrf: no_csrf,
               no_token: request.(:get, "/sign-in", []).status,
               unknown: request.(:get, "/elsewhere?token=" <> token, []).status,
               credential: request.(:post, "/credential", headers: [{"x-dev-sign-in-token", token}, {"content-type", "application/json"}], body: nil).status
             }
             """)

    assert page =~ ~s(value="clinic.receptionist")
    assert page =~ ~s(name="scopes[clinic_id]")
    assert page =~ ~s(name="return_to" value="/visits")
    assert missing =~ "the chosen actors need a value for clinic_id"
  end
end
