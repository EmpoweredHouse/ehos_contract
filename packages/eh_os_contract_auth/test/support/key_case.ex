defmodule EhOsContract.Auth.KeyCase do
  @moduledoc """
  EHOS, as far as this package can see it: a key pair that signs credentials, and a
  JWKS endpoint a test can change, break and count.

  The endpoint is a function plug handed to Req (`req_options: [plug: …]`), so no
  port is opened and the fetcher's own code — the request, the status, the body —
  runs as it does against EHOS.

  The key process runs outside the test process and reads and writes the table, so
  these tests share the sandbox and are not async.
  """

  use ExUnit.CaseTemplate

  alias EhOsContract.Auth.{Keys, TestRepo}

  using do
    quote do
      import EhOsContract.Auth.KeyCase

      alias EhOsContract.Auth.TestRepo, as: Repo
    end
  end

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(TestRepo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  @doc "A fresh Ed25519 key pair: `%{private: jwk, public: jwk, kid: thumbprint}`."
  def key_pair do
    jwk = JOSE.JWK.generate_key({:okp, :Ed25519})
    {_, private} = JOSE.JWK.to_map(jwk)
    {_, public} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    %{private: private, public: public, kid: JOSE.JWK.thumbprint(jwk)}
  end

  @doc """
  A credential signed by `pair`, with EHOS's claims for the test configuration and
  `claims` over them. `header:` overrides the header EHOS writes.
  """
  def credential(pair, claims \\ %{}, opts \\ []) do
    header = Map.merge(%{"kid" => pair.kid}, Map.new(Keyword.get(opts, :header, %{})))
    alg = Map.get(header, "alg", "Ed25519")

    claims =
      Map.merge(
        %{
          "iss" => "https://ehos.test",
          "sub" => "u-anna",
          "aud" => "rehmed/test",
          "iat" => DateTime.to_unix(DateTime.utc_now()),
          "exp" => DateTime.to_unix(DateTime.utc_now()) + 600,
          "jti" => Ecto.UUID.generate(),
          "cap" => ["rehmed.record_payment"]
        },
        Map.new(claims)
      )

    signer = Joken.Signer.create(alg, pair.private, Map.delete(header, "alg"))
    {:ok, token, _claims} = Joken.encode_and_sign(claims, signer)
    token
  end

  @doc """
  EHOS's JWKS endpoint: an agent holding what it answers — `{:keys, [pair]}`,
  `{:status, code}`, `:down`, or one of the answers no EHOS gives: `:redirect` (to
  another host, which does serve a key), `:huge` (a body past the limit) and `:many`
  (more keys than a rotation holds) — and how many times it was asked.
  """
  def ehos(answer) do
    {:ok, agent} = Agent.start_link(fn -> %{answer: answer, requests: 0} end)
    agent
  end

  def answer(ehos, answer), do: Agent.update(ehos, &%{&1 | answer: answer})
  def requests(ehos), do: Agent.get(ehos, & &1.requests)

  @doc "A clock the test moves, in milliseconds, for the key process's intervals."
  def clock do
    {:ok, agent} = Agent.start_link(fn -> 0 end)
    agent
  end

  def advance(clock, ms), do: Agent.update(clock, &(&1 + ms))

  @doc """
  Starts a key process fetching from `ehos`, under a name of its own, and waits
  until its start — the table loaded, the first fetch done — has run.
  `req_options:` replaces the plug that plays `ehos`.
  """
  def start_keys(ehos, opts \\ []) do
    name = Keyword.get_lazy(opts, :name, fn -> :"keys_#{System.unique_integer([:positive])}" end)
    clock = Keyword.get_lazy(opts, :clock, &clock/0)

    spec =
      {Keys,
       name: name,
       url: "https://ehos.test/.well-known/jwks.json",
       repo: TestRepo,
       req_options: Keyword.get_lazy(opts, :req_options, fn -> [plug: &serve(ehos, &1)] end),
       clock: fn -> Agent.get(clock, & &1) end}

    start_supervised!(Supervisor.child_spec(spec, id: name))
    # A call is answered only after `handle_continue/2`, so this returns once the
    # start has run.
    :sys.get_state(name)
    name
  end

  defp serve(ehos, conn) do
    answer = Agent.get_and_update(ehos, &{&1.answer, %{&1 | requests: &1.requests + 1}})

    case answer do
      {:keys, pairs} ->
        Req.Test.json(conn, %{"keys" => Enum.map(pairs, &jwks_entry/1)})

      {:status, status} ->
        Plug.Conn.send_resp(conn, status, "")

      :down ->
        Req.Test.transport_error(conn, :econnrefused)

      :redirect ->
        redirect(conn)

      :huge ->
        # A key a fetch without the limit would store, past the limit.
        Req.Test.json(conn, %{
          "keys" => [jwks_entry(key_pair())],
          "padding" => String.duplicate("x", 70_000)
        })

      :many ->
        Req.Test.json(conn, %{"keys" => Enum.map(1..17, fn _ -> jwks_entry(key_pair()) end)})
    end
  end

  # Elsewhere does serve a key: a fetch that followed the redirect would store it.
  defp redirect(%{host: "elsewhere.test"} = conn),
    do: Req.Test.json(conn, %{"keys" => [jwks_entry(key_pair())]})

  defp redirect(conn) do
    conn
    |> Plug.Conn.put_resp_header("location", "https://elsewhere.test/keys")
    |> Plug.Conn.send_resp(302, "")
  end

  # What EHOS publishes for a key: its public half, with the `kid` and `alg` a JWKS
  # usually carries beside it.
  defp jwks_entry(pair), do: Map.merge(pair.public, %{"kid" => pair.kid, "alg" => "Ed25519"})
end
