defmodule EhOsContract.Auth.KeysTest do
  @moduledoc """
  EA: the key store's branches, each of the tests `eh-os` D-34 lists — a key
  removed from the JWKS is refused after the next refresh; a failed fetch keeps
  the last set; an unknown `kid` fetches at most once per interval; a first start
  without EHOS refuses with `:no_keys`; a restart without EHOS works on the keys in
  the table.
  """

  use EhOsContract.Auth.KeyCase, async: false

  alias EhOsContract.Auth
  alias EhOsContract.Auth.Keys

  import ExUnit.CaptureLog, only: [with_log: 1]

  test "a key removed from the JWKS is refused after the next refresh" do
    kept = key_pair()
    removed = key_pair()
    ehos = ehos({:keys, [kept, removed]})
    keys = start_keys(ehos)
    assert {:ok, _} = Auth.verify(credential(removed), keys: keys)

    answer(ehos, {:keys, [kept]})
    assert {:ok, _} = Auth.verify(credential(removed), keys: keys), "not until the refresh"

    :ok = Keys.refresh(keys)
    assert Auth.verify(credential(removed), keys: keys) == {:error, :unknown_key}
    assert {:ok, _} = Auth.verify(credential(kept), keys: keys)
    assert Repo.query!("SELECT kid FROM eh_os_contract_auth_keys").rows == [[kept.kid]]
  end

  test "the scheduled refresh fetches every five minutes by default" do
    ehos = ehos({:keys, [key_pair()]})
    keys = start_keys(ehos)

    assert :sys.get_state(keys).refresh_every == :timer.minutes(5)
    assert requests(ehos) == 1

    send(keys, :refresh)
    :sys.get_state(keys)
    assert requests(ehos) == 2
  end

  describe "a failed fetch changes nothing" do
    for {failure, answer} <- [
          {"EHOS down", :down},
          {"an error status", {:status, 503}},
          {"a key set with no Ed25519 key", {:keys, []}},
          {"a redirect to another host", :redirect},
          {"a body past the limit", :huge},
          {"more keys than a rotation holds", :many}
        ] do
      test failure do
        pair = key_pair()
        ehos = ehos({:keys, [pair]})
        keys = start_keys(ehos)

        answer(ehos, unquote(Macro.escape(answer)))
        assert {:error, _reason} = Keys.refresh(keys)

        assert {:ok, _} = Auth.verify(credential(pair), keys: keys)
        assert Keys.kids(keys) == [pair.kid]
        assert Repo.query!("SELECT kid FROM eh_os_contract_auth_keys").rows == [[pair.kid]]
      end
    end
  end

  describe "the fetch's transport options" do
    # What Req would hand Mint: the host's authority, beside the two seconds to
    # connect, which Mint would otherwise make thirty.
    defp transport(keys) do
      options = Map.new(:sys.get_state(keys).request_options)
      Req.Finch.pool_options(options)[:conn_opts][:transport_opts]
    end

    test "name the host's certificate authority, and keep the connect timeout" do
      keys = start_keys(ehos({:keys, [key_pair()]}), cacertfile: "/etc/ehos/ca.pem")
      assert transport(keys) == [timeout: 2_000, cacertfile: "/etc/ehos/ca.pem"]

      keys = start_keys(ehos({:keys, [key_pair()]}), cacerts: [<<1, 2, 3>>])
      assert transport(keys) == [timeout: 2_000, cacerts: [<<1, 2, 3>>]]
    end

    test "are the connect timeout alone, when no authority is named" do
      assert transport(start_keys(ehos({:keys, [key_pair()]}))) == [timeout: 2_000]
    end
  end

  describe "a key process started directly" do
    # `start_link/1` checks what `EhOsContract.Auth.child_spec/1` checks, so a host
    # that lists `Keys` itself gets no way around it. A name of its own for each, so
    # a check that stopped raising fails its assertion rather than a later start.
    test "refuses an address that is not https" do
      assert_raise ArgumentError, ~r/not https/, fn ->
        Keys.start_link(name: :keys_http, url: "http://ehos.example.com/jwks.json", repo: Repo)
      end
    end

    test "refuses an option it does not take, as req_options: from before" do
      assert_raise ArgumentError, ~r/unknown keys \[:req_options\]/, fn ->
        Keys.start_link(
          name: :keys_req_options,
          url: "https://ehos.test/.well-known/jwks.json",
          repo: Repo,
          req_options: [redirect: true]
        )
      end
    end
  end

  # A real socket, not a plug: the step this guards against is Finch's, whose
  # receive timeout starts again with every read. A byte a second never trips the
  # three-second one, so only the deadline can end this fetch.
  test "an EHOS that trickles its answer holds a fetch for five seconds, not longer" do
    pair = key_pair()

    Repo.insert_all("eh_os_contract_auth_keys", [
      %{kid: pair.kid, jwk: pair.public, fetched_at: DateTime.utc_now()}
    ])

    url = "http://127.0.0.1:#{trickling_ehos()}/jwks.json"

    {elapsed, {keys, log}} =
      :timer.tc(
        fn -> with_log(fn -> start_keys(nil, url: url, plug: nil) end) end,
        :millisecond
      )

    assert log =~ "(:timeout)"
    assert_received {:trickled, _byte}
    assert elapsed >= 5_000 and elapsed < 8_000, "took #{elapsed} ms"

    # A failed fetch like any other: the key from the table stays in force.
    assert {:ok, _} = Auth.verify(credential(pair), keys: keys)
  end

  # A Finch pool that times out exits rather than raises, and a host's plug or
  # adapter may throw; the plugs here do the same inside the request.
  for {kind, plug} <- [
        exit: quote(do: fn _conn -> exit(:pool_timeout) end),
        throw: quote(do: fn _conn -> throw(:pool_timeout) end)
      ] do
    test "#{kind} inside the request is a failed fetch, not a crash of the key process" do
      pair = key_pair()
      ehos = ehos({:keys, [pair]})
      stop_supervised!(start_keys(ehos))

      keys = start_keys(ehos, plug: unquote(plug))

      assert Keys.refresh(keys) == {:error, {unquote(kind), :pool_timeout}}
      assert {:ok, _} = Auth.verify(credential(pair), keys: keys)
    end
  end

  # Accepts one fetch, answers with headers promising a body, and sends it a byte a
  # second until the fetch hangs up; tells the test of every byte it sent.
  defp trickling_ehos do
    test = self()
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listen)

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      {:ok, _request} = :gen_tcp.recv(socket, 0)

      :ok =
        :gen_tcp.send(
          socket,
          "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: 1000\r\n\r\n"
        )

      trickle(socket, test)
    end)

    port
  end

  defp trickle(socket, test) do
    Process.sleep(1_000)

    with :ok <- :gen_tcp.send(socket, " ") do
      send(test, {:trickled, " "})
      trickle(socket, test)
    end
  end

  test "an unknown kid fetches at most once per thirty seconds" do
    known = key_pair()
    ehos = ehos({:keys, [known]})
    clock = clock()
    keys = start_keys(ehos, clock: clock)
    assert requests(ehos) == 1

    # Just past the interval from the start's fetch: one early fetch, then none.
    advance(clock, :timer.seconds(30))
    stranger = credential(key_pair())
    assert Auth.verify(stranger, keys: keys) == {:error, :unknown_key}
    assert Auth.verify(stranger, keys: keys) == {:error, :unknown_key}
    assert requests(ehos) == 2

    advance(clock, :timer.seconds(29))
    assert Auth.verify(stranger, keys: keys) == {:error, :unknown_key}
    assert requests(ehos) == 2

    # The control: once the interval has passed, a key EHOS added meanwhile is found.
    added = key_pair()
    answer(ehos, {:keys, [known, added]})
    advance(clock, :timer.seconds(1))
    assert {:ok, _} = Auth.verify(credential(added), keys: keys)
    assert requests(ehos) == 3
  end

  test "a known kid fetches nothing" do
    pair = key_pair()
    ehos = ehos({:keys, [pair]})
    clock = clock()
    keys = start_keys(ehos, clock: clock)
    advance(clock, :timer.minutes(1))

    assert {:ok, _} = Auth.verify(credential(pair), keys: keys)
    assert requests(ehos) == 1
  end

  test "a first start without EHOS refuses every credential with :no_keys" do
    ehos = ehos(:down)
    clock = clock()
    keys = start_keys(ehos, clock: clock)

    assert Auth.verify(credential(key_pair()), keys: keys) == {:error, :no_keys}

    # The control: EHOS back, and the next early fetch lets the credential in.
    pair = key_pair()
    answer(ehos, {:keys, [pair]})
    advance(clock, :timer.seconds(30))
    assert {:ok, _} = Auth.verify(credential(pair), keys: keys)
  end

  test "ready? says whether any key is held, for the host's health check" do
    refute Auth.ready?(keys: :not_started)

    ehos = ehos(:down)
    clock = clock()
    keys = start_keys(ehos, clock: clock)
    refute Auth.ready?(keys: keys)

    answer(ehos, {:keys, [key_pair()]})
    :ok = Keys.refresh(keys)
    assert Auth.ready?(keys: keys)

    # A failed fetch after that keeps the keys, so it stays ready.
    answer(ehos, :down)
    assert {:error, _} = Keys.refresh(keys)
    assert Auth.ready?(keys: keys)
  end

  test "a restart without EHOS verifies with the keys in the table" do
    pair = key_pair()
    ehos = ehos({:keys, [pair]})
    keys = start_keys(ehos)
    stop_supervised!(keys)

    answer(ehos, :down)
    keys = start_keys(ehos, name: keys)
    assert {:ok, _} = Auth.verify(credential(pair), keys: keys)
  end

  test "a key is known by its thumbprint, and only its public members are kept" do
    pair = key_pair()
    ehos = ehos({:keys, [pair]})

    # A JWKS entry naming another key's kid, and carrying its private part.
    impostor = key_pair()
    lying = %{pair | public: Map.put(pair.public, "d", pair.private["d"])}
    answer(ehos, {:keys, [lying, %{impostor | kid: pair.kid}]})
    keys = start_keys(ehos)

    assert Keys.kids(keys) == Enum.sort([pair.kid, impostor.kid])

    [jwk] =
      Repo.query!("SELECT jwk FROM eh_os_contract_auth_keys WHERE kid = $1", [pair.kid]).rows

    assert jwk == [%{"kty" => "OKP", "crv" => "Ed25519", "x" => pair.public["x"]}]
  end

  test "a pinned key is trusted through refreshes, and never written to the table" do
    ehos = ehos({:keys, [key_pair()]})
    keys = start_keys(ehos)
    pinned = key_pair()

    assert Keys.pin(pinned.public, keys) == pinned.kid
    assert {:ok, _} = Auth.verify(credential(pinned), keys: keys)

    answer(ehos, {:keys, [key_pair()]})
    :ok = Keys.refresh(keys)
    assert {:ok, _} = Auth.verify(credential(pinned), keys: keys)

    assert Repo.query!("SELECT count(*) FROM eh_os_contract_auth_keys WHERE kid = $1", [
             pinned.kid
           ]).rows == [[0]]
  end

  test "pinning works only where the configuration allows it" do
    pair = key_pair()
    keys = start_keys(ehos({:keys, [key_pair()]}))
    Application.put_env(:eh_os_contract_auth, :pin_keys, false)
    on_exit(fn -> Application.put_env(:eh_os_contract_auth, :pin_keys, true) end)

    assert_raise ArgumentError, ~r/pinning a key is for tests/, fn ->
      Keys.pin(pair.public, keys)
    end

    assert Auth.verify(credential(pair), keys: keys) == {:error, :unknown_key}
  end

  test "pinning something that is not an Ed25519 key raises in the caller, not the process" do
    pair = key_pair()
    keys = start_keys(ehos({:keys, [pair]}))
    pid = Process.whereis(keys)

    assert_raise ArgumentError, ~r/only an Ed25519 public key/, fn ->
      Keys.pin(%{"kty" => "EC", "crv" => "P-256"}, keys)
    end

    assert Process.whereis(keys) == pid
    assert {:ok, _} = Auth.verify(credential(pair), keys: keys)
  end

  test "a key process that is not running refuses with :no_keys, and does not raise" do
    assert Auth.verify(credential(key_pair()), keys: :not_started) == {:error, :no_keys}
    refute Auth.ready?(keys: :not_started)
  end

  test "a malformed entry costs itself, not the keys beside it, nor the process" do
    good = key_pair()

    malformed = %{
      kid: "bad",
      public: %{"kty" => "OKP", "crv" => "Ed25519", "x" => "not-32-bytes"}
    }

    ehos = ehos({:keys, [malformed, good]})
    keys = start_keys(ehos)

    assert Keys.kids(keys) == [good.kid]
    assert {:ok, _} = Auth.verify(credential(good), keys: keys)

    # Only malformed entries: a failed fetch, and the process is still there.
    answer(ehos, {:keys, [malformed]})
    assert {:error, :no_ed25519_key} = Keys.refresh(keys)
    assert Keys.kids(keys) == [good.kid]
  end

  test "an unknown kid inside the window does not call the key process" do
    ehos = ehos({:keys, [key_pair()]})
    keys = start_keys(ehos)
    :sys.suspend(keys)

    # A suspended process answers no call, so a verify that made one would wait.
    task = Task.async(fn -> Auth.verify(credential(key_pair()), keys: keys) end)
    assert Task.await(task, 1_000) == {:error, :unknown_key}
    :sys.resume(keys)
  end
end
