defmodule EhOsContract.Auth.PeopleTest do
  @moduledoc """
  #252 (`eh-os` D-81): the application reads EHOS's people as itself. The fake EHOS here
  answers as `eh-os`'s `Ehos.SignIn.Token` and `EhosWeb.PeopleController` do on its
  `main` of 8 October 2026: a ten-minute credential for `client_credentials` with a
  `private_key_jwt` assertion signed by the client key, `unauthorized_client` for a
  deployment that does not ask, and the people API, 403 while no people manager agrees.

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
          expires_in: 600,
          answer: nil
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

  # EHOS, as far as the people client reaches it.
  defp serve(ehos, conn) do
    state = Agent.get(ehos, & &1)
    Agent.update(ehos, &%{&1 | requests: &1.requests ++ [{conn.method, conn.request_path}]})

    cond do
      state.down ->
        Req.Test.transport_error(conn, :econnrefused)

      conn.request_path == "/oauth/token" ->
        token(ehos, state, conn)

      true ->
        api(state, conn)
    end
  end

  defp token(ehos, state, conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    form = URI.decode_query(body)

    cond do
      state.answer == :token_rate_limited ->
        conn |> Plug.Conn.put_status(429) |> Req.Test.json(%{"error" => "slow_down"})

      not state.asks ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "unauthorized_client"})

      true ->
        assert form["grant_type"] == "client_credentials"

        assert form["client_assertion_type"] ==
                 "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

        refute Map.has_key?(form, "scope")
        refute Map.has_key?(form, "resource")
        check_assertion!(form["client_assertion"])

        token = "credential-#{length(state.tokens) + 1}"
        Agent.update(ehos, &%{&1 | tokens: &1.tokens ++ [token]})

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

  defp api(state, conn) do
    token = conn |> Plug.Conn.get_req_header("authorization") |> List.first()

    cond do
      state.answer == :api_rate_limited ->
        conn
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{"errors" => %{"detail" => "too many calls"}})

      state.answer == :garbage ->
        Req.Test.json(conn, %{"people" => [%{"id" => 1}]})

      token != "Bearer " <> List.last(state.tokens || [""]) ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{"errors" => %{"detail" => "expired"}})

      not state.agreed ->
        conn
        |> Plug.Conn.put_status(403)
        |> Req.Test.json(%{"errors" => %{"detail" => "this needs ehos.people.read"}})

      conn.request_path == "/api/people" ->
        conn = Plug.Conn.fetch_query_params(conn)

        if conn.query_params["after"] do
          Req.Test.json(conn, %{"people" => [@alan]})
        else
          conn
          |> Plug.Conn.put_resp_header(
            "link",
            ~s(<#{@issuer}/api/people?limit=1&after=Y3Vyc29y>; rel="next")
          )
          |> Req.Test.json(%{"people" => [@ada]})
        end

      conn.request_path == "/api/people/" <> @ada["id"] ->
        Req.Test.json(conn, %{"person" => @ada})

      true ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"errors" => %{"detail" => "not found"}})
    end
  end

  describe "reading" do
    test "lists the people page by page and reads one by id, with one credential", %{ehos: ehos} do
      server = start!(ehos)

      assert {:ok, %{people: [%Person{} = ada], next: "Y3Vyc29y"}} =
               People.list(server: server, limit: 1)

      assert ada == %Person{
               id: @ada["id"],
               email: "ada@example.com",
               name: "Ada Lovelace",
               state: :joined
             }

      assert {:ok, %{people: [%Person{name: nil, state: :invited}], next: nil}} =
               People.list(server: server, after: "Y3Vyc29y")

      assert {:ok, ^ada} = People.get(@ada["id"], server: server)

      assert People.get("6f1c0a1e-0000-4000-8000-00000000ffff", server: server) ==
               {:error, :not_found}

      assert ehos(ehos, :tokens) == ["credential-1"]
    end

    test "sends the query EHOS reads, and refuses an option it does not take", %{ehos: ehos} do
      server = start!(ehos)

      assert {:ok, _page} =
               People.list(server: server, q: "ad", state: [:invited, :joined], limit: 10)

      assert_raise ArgumentError, fn -> People.list(server: server, limit: 501) end
      assert_raise ArgumentError, fn -> People.list(server: server, state: :retired) end
      assert_raise ArgumentError, fn -> People.list(server: server, sort: :name) end
    end
  end

  describe "the credential" do
    test "is taken again shortly before it expires", %{ehos: ehos} do
      set(ehos, %{expires_in: 30})
      server = start!(ehos)

      assert {:ok, _} = People.list(server: server)
      assert {:ok, _} = People.list(server: server)
      assert ehos(ehos, :tokens) == ["credential-1", "credential-2"]
    end

    test "is taken again once when EHOS answers 401", %{ehos: ehos} do
      server = start!(ehos)
      assert {:ok, _} = People.list(server: server)

      # EHOS no longer accepts the credential it holds, as after its keys rotate.
      Agent.update(ehos, &%{&1 | tokens: &1.tokens ++ ["credential-new"]})

      assert {:ok, _} = People.list(server: server)
      assert List.last(ehos(ehos, :tokens)) == "credential-3"
    end

    test "is not taken at start, so the host starts while EHOS is down", %{ehos: ehos} do
      set(ehos, %{down: true})
      server = start!(ehos)
      assert ehos(ehos, :requests) == []

      log = capture_log(fn -> assert People.list(server: server) == {:error, :unavailable} end)
      assert log =~ "could not be reached"

      set(ehos, %{down: false})
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

      set(ehos, %{answer: :token_rate_limited, tokens: []})
      server = start!(ehos)
      assert People.list(server: server) == {:error, :rate_limited}
    end

    test "an answer EHOS never gives is :unavailable", %{ehos: ehos} do
      set(ehos, %{answer: :garbage})
      server = start!(ehos)

      assert People.list(server: server) == {:error, :unavailable}
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

    test "never shows the client key", %{ehos: ehos, key: key} do
      server = start!(ehos)
      refute inspect(:sys.get_state(server)) =~ key["d"]
    end
  end

  defp restore(previous) do
    for {key, _value} <- Application.get_all_env(:eh_os_contract_auth),
        not Keyword.has_key?(previous, key),
        do: Application.delete_env(:eh_os_contract_auth, key)

    for {key, value} <- previous, do: Application.put_env(:eh_os_contract_auth, key, value)
  end
end
