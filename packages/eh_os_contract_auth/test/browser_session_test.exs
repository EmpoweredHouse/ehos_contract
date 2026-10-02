defmodule EhOsContract.Auth.BrowserSessionTest do
  @moduledoc """
  EB2b (#78): a browser signed in through EHOS and out again, through
  `EhOsContract.Auth.SignIn.Router` and `EhOsContract.Auth.Session`, against an EHOS
  played by `EhOsContract.Auth.FakeEhos` (S2, S6, S7, S8 in
  docs/adr/browser-session.md, and `eh-os` D-68).

  The host is played here too: an encrypted cookie session, a body parser, the router
  forwarded at `/auth/ehos`, and a page behind the session plug. EHOS's authorization
  endpoint is a redirect the browser follows, so the test reads the URL the router
  sends it to and grants the code EHOS would.

  Not async: the tests change `config :eh_os_contract_auth`.
  """

  use EhOsContract.Auth.KeyCase, async: false

  import Plug.Conn
  import Plug.Test

  alias EhOsContract.Actor
  alias EhOsContract.Auth.{FakeEhos, Session, SignIn}
  alias EhOsContract.Auth.SignIn.Router

  @moduletag :tmp_dir

  @address "https://rehmed.test"
  @secret_key_base String.duplicate("k", 64)

  setup %{tmp_dir: dir} do
    previous = Application.get_all_env(:eh_os_contract_auth)
    on_exit(fn -> restore(previous) end)

    {key_file, _key} = FakeEhos.client_key_file(dir)

    Application.put_env(:eh_os_contract_auth, :sign_in,
      client_id: "rehmed/test",
      client_key_file: key_file,
      address: @address,
      secret_key_base: String.duplicate("s", 64),
      applications: %{}
    )

    # EHOS signs credentials with one key, and the verifier holds it.
    pair = key_pair()
    ehos = FakeEhos.start(signer: pair.private)
    keys = start_keys(ehos({:keys, [pair]}))

    %{ehos: ehos, name: start!(ehos), keys: keys}
  end

  describe "signing in" do
    test "a browser signs in and comes back signed in, with the actor of its credential",
         context do
      browser = sign_in(context, "/visits/7?tab=payments")

      assert redirected_to(browser) == "/visits/7?tab=payments"

      page = get(context, "/visits/7", browser)
      assert page.status == 200
      assert %{subject: "u-anna"} = page.assigns.eh_os_contract_session

      # What `EhOsContract.Plug` serves, as `EhOsContract.Auth.Plug` assigns it for a bearer token.
      assert %Actor{kind: :credential, subject: "u-anna"} = page.assigns.eh_os_contract_actor
      refute inspect(page.assigns) =~ "eyJ"

      assert {:ok, %Actor{subject: "u-anna"}} =
               Session.actor(page, sign_in: context.name, keys: context.keys)
    end

    test "the redirect asks EHOS for a code with PKCE, a nonce and the derived callback",
         context do
      query = context |> start_sign_in("/") |> authorization_query()

      assert query["client_id"] == "rehmed/test"
      assert query["redirect_uri"] == @address <> "/auth/ehos/callback"
      assert query["response_type"] == "code"
      assert query["code_challenge_method"] == "S256"
      assert byte_size(query["code_challenge"]) == 43
      assert is_binary(query["nonce"]) and is_binary(query["state"])
    end

    test "a callback whose iss is not EHOS's is refused, and nobody is signed in", context do
      browser = sign_in(context, "/", iss: "https://elsewhere.test")

      assert browser.status == 401
      assert rows() == 0
      assert FakeEhos.token_requests(context.ehos) == []
      assert redirected_to(get(context, "/visits/7", browser)) =~ "/auth/ehos/sign-in?"
    end

    # S6: behind an ingress with several pods, the callback may come from another peer.
    test "a callback from another address than the redirect's signs in all the same", context do
      started = start_sign_in(context, "/")
      query = authorization_query(started)
      FakeEhos.grant(context.ehos, "code-1", "rehmed/test", %{"nonce" => query["nonce"]})

      callback =
        conn(
          :get,
          "/auth/ehos/callback?" <>
            URI.encode_query(%{
              "code" => "code-1",
              "state" => query["state"],
              "iss" => "https://ehos.test"
            })
        )
        |> Map.put(:remote_ip, {10, 0, 0, 2})

      assert redirected_to(request(context, callback, started)) == "/"
      assert rows() == 1
    end

    test "a callback no sign-in began here is refused", context do
      conn =
        request(context, conn(:get, "/auth/ehos/callback?code=c&state=s&iss=https://ehos.test"))

      assert conn.status == 401
      assert rows() == 0
    end

    test "a code exchanged without the request's PKCE verifier is refused", context do
      started = start_sign_in(context, "/")
      query = authorization_query(started)
      # EHOS holds another challenge than the one the router sent.
      FakeEhos.grant(context.ehos, "code-1", "rehmed/test", %{
        "nonce" => query["nonce"],
        "code_challenge" => Base.url_encode64(:crypto.hash(:sha256, "other"), padding: false)
      })

      browser = callback(context, started, query["state"], "https://ehos.test")
      assert browser.status == 401
      assert rows() == 0
    end

    test "return_to is followed only as a path of this application", context do
      for return_to <- [
            "https://elsewhere.test/",
            "//elsewhere.test/",
            "/\\elsewhere.test",
            "javascript:alert(1)",
            "visits",
            "/visits\n/x"
          ] do
        assert redirected_to(sign_in(context, return_to)) == "/", inspect(return_to)
      end
    end

    # S2: nothing put in the session before sign-in, by the person or by someone who could set
    # its cookie, names anything after it.
    test "each sign-in starts an empty session with a new token", context do
      planted = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      browser = sign_in(context, "/", planted: planted)
      session = session(context, browser)

      refute session[Session.session_key()] == planted
      refute Map.has_key?(session, "planted")
      refute session["_csrf_token"] == "planted-csrf"
      assert rows() == 1
    end

    test "signing in again in a signed-in browser ends the session it had", context do
      first = sign_in(context, "/")
      old = session_token(context, first)

      second = sign_in(context, "/", browser: first)

      assert rows() == 1
      refute session_token(context, second) == old
      assert EhOsContract.Auth.SignIn.Sessions.fetch(context.name, old) == {:error, :signed_out}
    end

    # A credential every page would refuse would send the browser round and round EHOS.
    test "a credential verify/2 refuses, or of another person, refuses the sign-in", context do
      for grant <- [%{"audience" => "ledger/test"}, %{"credential_sub" => "u-bartek"}] do
        browser = sign_in(context, "/", grant: grant)

        assert browser.status == 401, inspect(grant)
        assert rows() == 0
      end
    end

    test "the credential's own exp bounds when it is renewed first", context do
      browser = sign_in(context, "/", grant: %{"credential_lifetime" => 100})

      {:ok, session} =
        EhOsContract.Auth.SignIn.Sessions.fetch(context.name, session_token(context, browser))

      expires_at = session.credentials["https://rehmed.test"].expires_at
      assert DateTime.diff(expires_at, DateTime.utc_now()) in 90..101
    end

    test "a token response missing what a session needs refuses the sign-in", context do
      for grant <- [
            %{"sid" => ""},
            %{"sub" => ""},
            %{"auth_time" => 999_999_999_999_999},
            # Within the renewal margin: every request would renew it.
            %{"credential_lifetime" => 20}
          ] do
        browser = sign_in(context, "/", grant: grant)

        assert browser.status == 401, inspect(grant)
        assert rows() == 0
      end
    end

    test "is unavailable, with 503 and no redirect, while EHOS cannot be signed in with",
         context do
      FakeEhos.discovery(
        context.ehos,
        &Map.delete(&1, "authorization_response_iss_parameter_supported")
      )

      :ok = SignIn.refresh(context.name)

      conn = start_sign_in(context, "/")
      assert conn.status == 503
      assert get_resp_header(conn, "location") == []
    end
  end

  describe "the session plug" do
    test "sends a page request without a session to sign in, and back", context do
      conn = get(context, "/visits/7?tab=payments", nil)

      assert conn.halted
      assert redirected_to(conn) == "/auth/ehos/sign-in?return_to=%2Fvisits%2F7%3Ftab%3Dpayments"
    end

    test "answers 401 to any other request without a session, a page's fetch() too", context do
      for conn <- [
            conn(:post, "/visits/7", %{}),
            conn(:get, "/visits/7") |> put_req_header("accept", "application/json")
          ] do
        conn = request(context, conn)

        assert conn.status == 401
        assert conn.halted
        assert get_resp_header(conn, "location") == []
      end
    end

    test "redirects a navigation a browser marks as one, whatever it accepts", context do
      conn = conn(:get, "/visits/7") |> put_req_header("sec-fetch-mode", "navigate")

      assert redirected_to(request(context, conn)) =~ "/auth/ehos/sign-in?"
    end

    # Signing in again would get the same credential, and the browser would go round EHOS for ever.
    test "answers 401, not a redirect, to a credential refused for another reason", context do
      browser = sign_in(context, "/")
      conn = get(context, "/strict", browser)

      assert conn.status == 401
      assert get_resp_header(conn, "location") == []
    end

    test "actor/2 on a connection the plug gave an actor reads no session again", context do
      browser = sign_in(context, "/")
      page = get(context, "/visits/7", browser)
      :ok = EhOsContract.Auth.SignIn.Sessions.delete(session_token(context, browser))

      assert {:ok, %Actor{subject: "u-anna"}} = Session.actor(page, sign_in: context.name)
    end

    # S4: renewing is the only thing actor/2 and the plug do beyond reading.
    test "renews an expired credential through EHOS, and gives the person's actor", context do
      browser = sign_in(context, "/")
      FakeEhos.advance(context.ehos, 660)
      later = DateTime.add(DateTime.utc_now(), 660)

      assert {:ok, %Actor{subject: "u-anna"}} =
               EhOsContract.Clock.at(later, fn ->
                 Session.actor(session(context, browser),
                   sign_in: context.name,
                   keys: context.keys
                 )
               end)

      page = EhOsContract.Clock.at(later, fn -> get(context, "/visits/7", browser) end)
      assert page.status == 200
      assert %Actor{subject: "u-anna"} = page.assigns.eh_os_contract_actor
    end

    test "answers 503, not a redirect, while EHOS cannot renew an expired credential", context do
      browser = sign_in(context, "/")
      FakeEhos.refresh_answer(context.ehos, {:status, 503})
      later = DateTime.add(DateTime.utc_now(), 660)

      page = EhOsContract.Clock.at(later, fn -> get(context, "/visits/7", browser) end)

      assert page.status == 503
      assert get_resp_header(page, "location") == []
      assert rows() == 1
    end

    test "sends a browser whose sign-in ended at renewal to sign in again", context do
      browser = sign_in(context, "/")
      FakeEhos.refresh_answer(context.ehos, :no_id_token)
      later = DateTime.add(DateTime.utc_now(), 660)

      page = EhOsContract.Clock.at(later, fn -> get(context, "/visits/7", browser) end)

      assert redirected_to(page) =~ "/auth/ehos/sign-in?"
      assert rows() == 0
    end

    test "actor/2 reads a LiveView's session map as it reads a connection", context do
      browser = sign_in(context, "/")
      session = session(context, browser)

      assert {:ok, %Actor{subject: "u-anna"}} =
               Session.actor(session, sign_in: context.name, keys: context.keys)

      assert Session.actor(%{}, sign_in: context.name) == {:error, :signed_out}
    end
  end

  describe "signing out" do
    test "sends the browser to EHOS's end session with the ID token, back to exactly the root",
         context do
      browser = sign_in(context, "/")
      {csrf, browser} = csrf_token(context, browser)

      out =
        request(context, conn(:post, "/auth/ehos/sign-out", %{"_csrf_token" => csrf}), browser)

      location = URI.parse(redirected_to(out))
      query = URI.decode_query(location.query)

      assert "#{location.scheme}://#{location.host}#{location.path}" ==
               "https://ehos.test/oauth/end_session"

      # eh-os D-68: exactly `https://<host>/`, which EHOS compares as a string.
      assert query["post_logout_redirect_uri"] == @address <> "/"

      assert %{"sub" => "u-anna"} =
               query["id_token_hint"] |> JOSE.JWT.peek_payload() |> Map.get(:fields)

      assert rows() == 0
      assert redirected_to(get(context, "/visits/7", out)) =~ "/auth/ehos/sign-in?"
    end

    test "is refused without the CSRF token", context do
      browser = sign_in(context, "/")

      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        request(context, conn(:post, "/auth/ehos/sign-out", %{}), browser)
      end

      assert rows() == 1
    end
  end

  # The browser's steps. Each request carries the cookies of the response before it.

  defp sign_in(context, return_to, opts \\ []) do
    started = start_sign_in(context, return_to, opts)
    query = authorization_query(started)

    FakeEhos.grant(
      context.ehos,
      "code-1",
      "rehmed/test",
      Map.merge(
        %{
          "nonce" => query["nonce"],
          "code_challenge" => query["code_challenge"],
          "redirect_uri" => query["redirect_uri"]
        },
        Keyword.get(opts, :grant, %{})
      )
    )

    callback(context, started, query["state"], Keyword.get(opts, :iss, "https://ehos.test"))
  end

  defp start_sign_in(context, return_to, opts \\ []) do
    conn = conn(:get, "/auth/ehos/sign-in?" <> URI.encode_query(%{"return_to" => return_to}))

    previous =
      case Keyword.get(opts, :planted) do
        nil -> Keyword.get(opts, :browser)
        planted -> plant(context, planted)
      end

    request(context, conn, previous)
  end

  defp callback(context, started, state, iss) do
    query = URI.encode_query(%{"code" => "code-1", "state" => state, "iss" => iss})
    request(context, conn(:get, "/auth/ehos/callback?" <> query), started)
  end

  # A browser's navigation, as a browser sends it.
  defp get(context, path, previous) do
    conn = conn(:get, path) |> put_req_header("accept", "text/html,application/xhtml+xml")
    request(context, conn, previous)
  end

  defp authorization_query(conn) do
    [location] = get_resp_header(conn, "location")
    assert String.starts_with?(location, "https://ehos.test/oauth/authorize?")
    location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end

  defp redirected_to(conn) do
    assert conn.status == 302
    conn |> get_resp_header("location") |> hd()
  end

  # The host, as a Phoenix endpoint and router would be.
  defp request(context, conn, previous \\ nil) do
    conn = if previous, do: recycle_cookies(conn, previous), else: conn

    conn
    |> put_req_header("user-agent", "test browser")
    |> Map.put(:secret_key_base, @secret_key_base)
    |> Plug.Session.call(
      Plug.Session.init(
        store: :cookie,
        key: "_host",
        signing_salt: "signing",
        encryption_salt: "encryption"
      )
    )
    |> fetch_session()
    |> Plug.Parsers.call(Plug.Parsers.init(parsers: [:urlencoded], pass: ["*/*"]))
    |> route(context)
  end

  defp route(%Plug.Conn{path_info: ["auth", "ehos" | rest]} = conn, context),
    do: Plug.forward(conn, rest, Router, Router.init(sign_in: context.name, keys: context.keys))

  defp route(%Plug.Conn{path_info: ["csrf"]} = conn, _context) do
    conn = Plug.CSRFProtection.call(conn, Plug.CSRFProtection.init([]))
    send_resp(conn, 200, Plug.CSRFProtection.get_csrf_token())
  end

  defp route(%Plug.Conn{path_info: ["plant", token]} = conn, _context) do
    conn
    |> put_session(Session.session_key(), token)
    |> put_session("_csrf_token", "planted-csrf")
    |> put_session("planted", "by someone else")
    |> send_resp(200, "")
  end

  defp route(%Plug.Conn{path_info: ["session"]} = conn, _context),
    do: send_resp(conn, 200, :erlang.term_to_binary(get_session(conn)))

  defp route(%Plug.Conn{path_info: ["strict"]} = conn, context) do
    opts =
      Session.init(sign_in: context.name, assign_actor: true, keys: context.keys, audience: "x/y")

    case Session.call(conn, opts) do
      %Plug.Conn{halted: true} = conn -> conn
      conn -> send_resp(conn, 200, "a page")
    end
  end

  defp route(conn, context) do
    opts = Session.init(sign_in: context.name, assign_actor: true, keys: context.keys)

    case Session.call(conn, opts) do
      %Plug.Conn{halted: true} = conn -> conn
      conn -> send_resp(conn, 200, "a page")
    end
  end

  defp plant(context, token), do: request(context, conn(:get, "/plant/" <> token))

  defp csrf_token(context, browser) do
    conn = request(context, conn(:get, "/csrf"), browser)
    {conn.resp_body, conn}
  end

  # The Plug session as a LiveView's `mount/3` is given it.
  defp session(context, browser) do
    context
    |> request(conn(:get, "/session"), browser)
    |> Map.fetch!(:resp_body)
    |> :erlang.binary_to_term()
  end

  defp session_token(context, browser), do: session(context, browser)[Session.session_key()]

  defp rows,
    do: Repo.query!("SELECT count(*) FROM eh_os_contract_auth_sessions").rows |> hd() |> hd()

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
