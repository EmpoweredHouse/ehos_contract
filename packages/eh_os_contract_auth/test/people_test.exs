defmodule EhOsContract.Auth.PeopleTest do
  @moduledoc """
  #252: the application reads EHOS's people as itself. The fake EHOS here answers as
  EHOS's `Ehos.SignIn.Token` and `EhosWeb.PeopleController` do on its
  `main` of 8 October 2026: a ten-minute credential for `client_credentials` with a
  `private_key_jwt` assertion signed by the client key, `unauthorized_client` for a
  deployment that does not ask, and the people API, 403 while no people manager agrees,
  whose next page's `Link` repeats the request's query with the cursor.

  Not async: the tests change `config :eh_os_contract_auth`.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias EhOsContract.Auth.{FakeEhos, People}
  alias EhOsContract.Auth.People.Person

  @moduletag :tmp_dir

  @issuer "https://ehos.test"
  @ada %{
    "id" => "6f1c0a1e-0000-4000-8000-000000000001",
    "email" => "ada@example.com",
    "name" => "Ada Lovelace",
    "state" => "joined"
  }
  @alan %{
    "id" => "6f1c0a1e-0000-4000-8000-000000000002",
    "email" => "alan@example.com",
    "name" => nil,
    "state" => "invited"
  }

  setup %{tmp_dir: dir} do
    previous = Application.get_all_env(:eh_os_contract_auth)
    on_exit(fn -> restore(previous) end)

    {key_file, key} = FakeEhos.client_key_file(dir)

    Application.put_env(:eh_os_contract_auth, :people,
      client_id: "equipment/test",
      client_key_file: key_file
    )

    {:ok, ehos} =
      Agent.start_link(fn ->
        %{
          agreed: true,
          asks: true,
          down: false,
          tokens: [],
          requests: [],
          queries: [],
          expires_in: 600,
          answer: nil,
          token_delay: 0
        }
      end)

    %{ehos: ehos, key: key, dir: dir}
  end

  defp start!(ehos) do
    name = :"people_#{System.unique_integer([:positive])}"
    start_supervised!({People, name: name, plug: &serve(ehos, &1)})
    name
  end

  defp set(ehos, changes), do: Agent.update(ehos, &Map.merge(&1, changes))
  defp ehos(ehos, key), do: Agent.get(ehos, &Map.fetch!(&1, key))

  ## EHOS, as far as the people client reaches it

  defp serve(ehos, conn) do
    state = Agent.get(ehos, & &1)
    Agent.update(ehos, &%{&1 | requests: &1.requests ++ [{conn.method, conn.request_path}]})

    cond do
      state.down -> Req.Test.transport_error(conn, :econnrefused)
      conn.request_path == "/oauth/token" -> token(ehos, state, conn)
      true -> api(ehos, state, conn)
    end
  end

  defp token(ehos, state, conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    form = URI.decode_query(body)

    cond do
      state.answer == :invalid_client ->
        answer(conn, 401, %{"error" => "invalid_client"})

      state.answer == :token_rate_limited ->
        answer(conn, 429, %{"error" => "slow_down"})

      not state.asks ->
        answer(conn, 400, %{"error" => "unauthorized_client"})

      true ->
        assert form["grant_type"] == "client_credentials"

        assert form["client_assertion_type"] ==
                 "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

        refute Map.has_key?(form, "scope")
        refute Map.has_key?(form, "resource")
        check_assertion!(form["client_assertion"])

        Process.sleep(state.token_delay)

        token =
          Agent.get_and_update(ehos, fn state ->
            token = "credential-#{length(state.tokens) + 1}"
            {token, %{state | tokens: state.tokens ++ [token]}}
          end)

        Req.Test.json(conn, %{
          "access_token" => token,
          "token_type" => "Bearer",
          "expires_in" => state.expires_in
        })
    end
  end

  # As `Ehos.SignIn.Token` checks it: the client's key, iss and sub the client, aud the token
  # endpoint, a jti, a lifetime of at most five minutes.
  defp check_assertion!(assertion) do
    key_file = Application.get_env(:eh_os_contract_auth, :people)[:client_key_file]

    jwk =
      key_file |> File.read!() |> Jason.decode!() |> JOSE.JWK.from_map() |> JOSE.JWK.to_public()

    assert {true, %JOSE.JWT{fields: claims}, %JOSE.JWS{fields: %{"kid" => kid}}} =
             JOSE.JWT.verify_strict(jwk, ["Ed25519"], assertion)

    assert kid == JOSE.JWK.thumbprint(jwk)

    assert {claims["iss"], claims["sub"], claims["aud"]} ==
             {"equipment/test", "equipment/test", @issuer <> "/oauth/token"}

    assert is_binary(claims["jti"])
    assert claims["exp"] - claims["iat"] <= 300
  end

  defp api(ehos, state, conn) do
    token = conn |> Plug.Conn.get_req_header("authorization") |> List.first()

    cond do
      state.answer == :api_rate_limited ->
        answer(conn, 429, %{"errors" => %{"detail" => "too many calls"}})

      state.answer == :garbage ->
        Req.Test.json(conn, %{"people" => [%{"id" => 1}]})

      state.answer in [422, 500] ->
        answer(conn, state.answer, %{"errors" => %{}})

      state.answer == :always_401 or token != "Bearer " <> List.last(state.tokens) ->
        answer(conn, 401, %{"errors" => %{"detail" => "expired"}})

      not state.agreed ->
        answer(conn, 403, %{"errors" => %{"detail" => "this needs ehos.people.read"}})

      conn.request_path == "/api/people" ->
        list(ehos, conn)

      conn.request_path == "/api/people/" <> @ada["id"] ->
        Req.Test.json(conn, %{"person" => @ada})

      true ->
        answer(conn, 404, %{"errors" => %{"detail" => "not found"}})
    end
  end

  defp list(ehos, conn) do
    conn = Plug.Conn.fetch_query_params(conn)
    Agent.update(ehos, &%{&1 | queries: &1.queries ++ [conn.query_params]})

    if conn.query_params["after"] do
      Req.Test.json(conn, %{"people" => [@alan]})
    else
      # As EHOS writes it: the same query, with the cursor.
      next = conn.query_params |> Map.put("after", "Y3Vyc29y") |> URI.encode_query()

      conn
      |> Plug.Conn.put_resp_header("link", ~s(<#{@issuer}/api/people?#{next}>; rel="next"))
      |> Req.Test.json(%{"people" => [@ada]})
    end
  end

  defp cursor(query), do: Base.url_encode64(query, padding: false)

  # The renewal's minute has come: as if the credential were about to expire.
  defp due(server), do: :sys.replace_state(server, &%{&1 | renew_at: &1.renew_at - 10_000})

  defp eventually(check, tries \\ 50) do
    cond do
      check.() -> :ok
      tries == 0 -> flunk("never came true")
      true -> Process.sleep(20) && eventually(check, tries - 1)
    end
  end

  defp answer(conn, status, body),
    do: conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)

  ## The tests

  describe "reading" do
    test "lists the people page by page and reads one by id, with one credential",
         %{ehos: ehos} do
      server = start!(ehos)

      assert {:ok, %{people: [%Person{} = ada], next: next}} =
               People.list(server: server, q: "a", limit: 1)

      assert ada == %Person{
               id: @ada["id"],
               email: "ada@example.com",
               name: "Ada Lovelace",
               state: :joined
             }

      # The cursor carries the page's query: the next page is asked for with it alone.
      assert {:ok, %{people: [%Person{name: nil, state: :invited}], next: nil}} =
               People.list(server: server, after: next)

      assert ehos(ehos, :queries) == [
               %{"q" => "a", "limit" => "1"},
               %{"q" => "a", "limit" => "1", "after" => "Y3Vyc29y"}
             ]

      assert {:ok, ^ada} = People.get(@ada["id"], server: server)
      assert {:ok, ^ada} = People.get(String.upcase(@ada["id"]), server: server)

      assert People.get("6f1c0a1e-0000-4000-8000-00000000ffff", server: server) ==
               {:error, :not_found}

      assert ehos(ehos, :tokens) == ["credential-1"]
    end

    test "sends the query EHOS reads", %{ehos: ehos} do
      server = start!(ehos)

      assert {:ok, _page} =
               People.list(server: server, q: "ad", state: [:invited, :joined], limit: 10)

      assert ehos(ehos, :queries) == [
               %{"q" => "ad", "state" => "invited,joined", "limit" => "10"}
             ]
    end

    test "refuses, before asking EHOS, what EHOS never answers an application",
         %{ehos: ehos} do
      server = start!(ehos)

      for opts <- [
            [limit: 501],
            [state: :disabled],
            [state: [:joined, :disabled]],
            [state: []],
            [q: String.duplicate("a", 2049)],
            [sort: :name],
            [after: "not a cursor"],
            [after: ""],
            [after: cursor("id=1&after=x")],
            [after: cursor("q=a")],
            [after: cursor("state=disabled&after=x")],
            [after: cursor("limit=100000&after=x")],
            [after: cursor("q=#{String.duplicate("a", 2049)}&after=x")],
            [after: cursor("after=x"), q: "a"]
          ] do
        assert_raise ArgumentError, fn -> People.list([server: server] ++ opts) end
      end

      for id <- ["", "..", "../people", "ada@example.com"] do
        assert People.get(id, server: server) == {:error, :not_found}
      end

      assert ehos(ehos, :requests) == []
    end
  end

  describe "the credential" do
    test "is renewed beside, a minute before it expires, while callers go on with it",
         %{ehos: ehos} do
      server = start!(ehos)
      assert {:ok, _} = People.list(server: server)

      # The minute before it expires: the call is answered at once, and a renewal starts.
      due(server)
      set(ehos, %{token_delay: 300})
      {elapsed, {:ok, _}} = :timer.tc(fn -> People.list(server: server) end)
      assert elapsed < 250_000

      eventually(fn -> ehos(ehos, :tokens) == ["credential-1", "credential-2"] end)
    end

    test "is taken again once when EHOS answers 401, and a second 401 is :unavailable",
         %{ehos: ehos} do
      server = start!(ehos)
      assert {:ok, _} = People.list(server: server)

      # EHOS no longer accepts the credential it holds, as after its keys rotate.
      Agent.update(ehos, &%{&1 | tokens: &1.tokens ++ ["credential-new"]})

      assert {:ok, _} = People.list(server: server)
      assert List.last(ehos(ehos, :tokens)) == "credential-3"

      set(ehos, %{answer: :always_401})
      capture_log(fn -> assert People.list(server: server) == {:error, :unavailable} end)
    end

    test "is asked for once by callers that need it at the same time, and the process still answers",
         %{ehos: ehos} do
      set(ehos, %{token_delay: 300})
      server = start!(ehos)

      tasks = Enum.map(1..5, fn _ -> Task.async(fn -> People.list(server: server) end) end)
      Process.sleep(50)

      # The request is not made in the process: it answers while the request is out.
      {elapsed, _state} = :timer.tc(fn -> :sys.get_state(server) end)
      assert elapsed < 100_000

      assert tasks |> Task.await_many() |> Enum.all?(&match?({:ok, _}, &1))
      assert ehos(ehos, :tokens) == ["credential-1"]
    end

    test "a refusal is answered for five seconds without asking EHOS again", %{ehos: ehos} do
      set(ehos, %{asks: false})
      server = start!(ehos)

      capture_log(fn ->
        for _ <- 1..5, do: assert(People.list(server: server) == {:error, :not_asked})
      end)

      assert ehos(ehos, :requests) == [{"POST", "/oauth/token"}]
    end

    test "a failed renewal keeps the credential while it is valid, for every caller",
         %{ehos: ehos} do
      server = start!(ehos)
      assert {:ok, _} = People.list(server: server)

      due(server)
      set(ehos, %{answer: :token_rate_limited})

      for _ <- 1..3, do: assert({:ok, _} = People.list(server: server))
      eventually(fn -> :sys.get_state(server).failed != nil end)
      assert {:ok, _} = People.list(server: server)
      assert ehos(ehos, :tokens) == ["credential-1"]
    end

    test "is not taken at start, so the host starts while EHOS is down", %{ehos: ehos} do
      set(ehos, %{down: true})
      server = start!(ehos)
      assert ehos(ehos, :requests) == []

      log = capture_log(fn -> assert People.list(server: server) == {:error, :unavailable} end)
      assert log =~ "could not be reached"

      # The outage is answered for five seconds; after that EHOS is asked again.
      set(ehos, %{down: false})
      :sys.replace_state(server, &%{&1 | failed: nil})
      assert {:ok, _} = People.list(server: server)
    end
  end

  describe "refusals, each an error a page can say" do
    test "no agreement is :not_agreed", %{ehos: ehos} do
      set(ehos, %{agreed: false})
      server = start!(ehos)

      assert People.list(server: server) == {:error, :not_agreed}
      assert People.get(@ada["id"], server: server) == {:error, :not_agreed}
    end

    test "a deployment that does not ask is :not_asked", %{ehos: ehos} do
      set(ehos, %{asks: false})
      server = start!(ehos)

      capture_log(fn -> assert People.list(server: server) == {:error, :not_asked} end)
    end

    test "EHOS's limits are :rate_limited", %{ehos: ehos} do
      server = start!(ehos)

      set(ehos, %{answer: :api_rate_limited})
      assert People.list(server: server) == {:error, :rate_limited}

      set(ehos, %{answer: :token_rate_limited})
      assert People.list(server: start!(ehos)) == {:error, :rate_limited}
    end

    test "an answer EHOS never gives, or a failure, is :unavailable, and logged",
         %{ehos: ehos} do
      server = start!(ehos)

      for answer <- [:garbage, 422, 500] do
        set(ehos, %{answer: answer})

        log =
          capture_log(fn -> assert People.list(server: server) == {:error, :unavailable} end)

        assert log =~ "EHOS's people API answered"
      end
    end

    test "a key EHOS does not accept is :unavailable", %{ehos: ehos} do
      set(ehos, %{answer: :invalid_client})
      server = start!(ehos)

      log = capture_log(fn -> assert People.list(server: server) == {:error, :unavailable} end)
      assert log =~ "invalid_client"
    end

    test "a process that is not running is :unavailable, not an exit" do
      log =
        capture_log(fn ->
          assert People.list(server: :"no_such_#{System.unique_integer([:positive])}") ==
                   {:error, :unavailable}
        end)

      assert log =~ "not running"
    end
  end

  describe "at boot" do
    test "refuses a configuration it cannot use, naming no secret", %{dir: dir} do
      for people <- [
            nil,
            [],
            [client_id: "", client_key_file: "x"],
            [client_id: "a/b"],
            [client_id: "a/b", client_key_file: "x", extra: 1]
          ] do
        Application.put_env(:eh_os_contract_auth, :people, people)
        assert_raise ArgumentError, fn -> People.child_spec([]) end
      end

      {key_file, key} = FakeEhos.client_key_file(dir, %{"kid" => "wrong"})

      Application.put_env(:eh_os_contract_auth, :people,
        client_id: "a/b",
        client_key_file: key_file
      )

      error = assert_raise ArgumentError, fn -> People.child_spec([]) end
      refute error.message =~ key["d"]

      {key_file, _key} = FakeEhos.client_key_file(dir)

      Application.put_env(:eh_os_contract_auth, :people,
        client_id: "a/b",
        client_key_file: key_file
      )

      Application.put_env(:eh_os_contract_auth, :issuer, "http://ehos.test")
      assert_raise ArgumentError, ~r/issuer/, fn -> People.child_spec([]) end
    end

    test "never shows the client key or the credential", %{ehos: ehos, key: key} do
      server = start!(ehos)
      assert {:ok, _} = People.list(server: server)

      refute inspect(:sys.get_state(server)) =~ key["d"]
      refute inspect(:sys.get_status(server)) =~ "credential-1"
    end
  end

  defp restore(previous) do
    for {key, _value} <- Application.get_all_env(:eh_os_contract_auth),
        not Keyword.has_key?(previous, key),
        do: Application.delete_env(:eh_os_contract_auth, key)

    for {key, value} <- previous, do: Application.put_env(:eh_os_contract_auth, key, value)
  end
end
