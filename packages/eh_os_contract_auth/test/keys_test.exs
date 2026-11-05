defmodule EhOsContract.Auth.KeysTest do
  @moduledoc """
  EA: the key store's branches, each of the tests EHOS's design asks for — a key
  removed from the JWKS is refused after the next refresh; a failed fetch keeps
  the last set; an unknown `kid` fetches at most once per interval; a first start
  without EHOS refuses with `:no_keys`; a restart without EHOS works on the keys in
  the table.
  """

  use EhOsContract.Auth.KeyCase, async: false

  alias EhOsContract.Auth
  alias EhOsContract.Auth.Keys

  import ExUnit.CaptureLog, only: [with_log: 1]

  defmodule HeldRepo do
    @moduledoc false
    # The test repo, whose transactions wait for the test's word while the test is
    # named in `config :eh_os_contract_auth, HeldRepo`.
    alias EhOsContract.Auth.TestRepo

    def transaction(fun, opts \\ []) do
      with test when is_pid(test) <- Application.get_env(:eh_os_contract_auth, __MODULE__) do
        send(test, {:writing, self()})

        receive do
          :go -> :ok
        end
      end

      TestRepo.transaction(fun, opts)
    end

    defdelegate query!(sql, params, opts), to: TestRepo
    defdelegate delete_all(queryable, opts), to: TestRepo
    defdelegate insert_all(source, rows, opts), to: TestRepo
  end

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

    # #89: an address is taken only as every parser reads it, so the loopback exception cannot
    # be reached by one a browser or Node's URL reads as another host. The rule is EHOS's own
    # (`Ehos.Credentials.check_issuer/1`), with a path, since this is the key set's.
    test "takes https, or plain http on loopback, only as every parser reads it" do
      for url <- [
            "https://ehos.example.com/.well-known/jwks.json",
            "https://ehos.example.com:8443/.well-known/jwks.json",
            "https://ehos.example.com:443/.well-known/jwks.json",
            "https://10.0.0.1/jwks.json",
            "https://[::1]:4443/jwks.json",
            "https://ehos.example.com",
            "http://localhost:4000/.well-known/jwks.json",
            "http://localhost:80/jwks.json",
            "http://127.0.0.1:4000/jwks.json",
            "http://[::1]:4000/jwks.json"
          ] do
        assert Keys.check!(url: url) == :ok, url
      end
    end

    test "refuses an address parsers read differently, or with a user, a query or a fragment" do
      for url <- [
            # A browser takes the host to be evil.example; URI.parse/1 takes it to be localhost.
            "http://evil.example\\@localhost/.well-known/jwks.json",
            "http://user:secret@localhost/jwks.json",
            "https://user@ehos.example.com/jwks.json",
            "http://LOCALHOST/jwks.json",
            "http://ehos.localhost/jwks.json",
            "https://EHOS.example.com/jwks.json",
            "https://ehos.example.com/jwks.json?x=1",
            "https://ehos.example.com/jwks.json#x",
            # Hosts a browser reads as another address: 127.0.0.1, and 8.0.0.1 in octal.
            "https://127.1/jwks.json",
            "https://0x7f000001/jwks.json",
            "https://2130706433/jwks.json",
            "https://010.0.0.1/jwks.json",
            # Read back otherwise than written: a scheme in capitals, a port with a leading
            # zero, or an empty one.
            "HTTPS://ehos.example.com/jwks.json",
            "https://ehos.example.com:0443/jwks.json",
            "https://ehos.example.com:/jwks.json",
            "http://localhost:0/jwks.json",
            "https://ehos.example.com:99999/jwks.json",
            "https://localhost:4000/jwks.json\n",
            "https://",
            "ehos.example.com/jwks.json"
          ] do
        assert_raise ArgumentError, ~r/not https/, fn -> Keys.check!(url: url) end
      end
    end

    for key <- [:refresh_every, :refetch_at_most_every],
        value <- [0, 4_999, 5_000.0] do
      test "refuses #{key}: #{inspect(value)}, shorter than a fetch may take or not milliseconds" do
        assert_raise ArgumentError, ~r/#{unquote(key)}: in milliseconds, at least 5000/, fn ->
          Keys.start_link([
            {:name, :"keys_#{unquote(key)}"},
            {:url, "https://ehos.test/.well-known/jwks.json"},
            {:repo, Repo},
            {unquote(key), unquote(value)}
          ])
        end
      end
    end

    test "control: takes intervals of five seconds and more" do
      assert Keys.check!(
               url: "https://ehos.test/.well-known/jwks.json",
               refresh_every: 5_000,
               refetch_at_most_every: :timer.minutes(1)
             ) == :ok
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

  test "a locked table holds neither the start nor an early fetch past the call" do
    pair = key_pair()
    ehos = ehos({:keys, [pair]})
    clock = clock()
    lock_table!()

    {elapsed, {keys, log}} =
      :timer.tc(fn -> with_log(fn -> start_keys(ehos, clock: clock) end) end, :millisecond)

    assert log =~ "could not read eh_os_contract_auth_keys"
    assert log =~ "could not write eh_os_contract_auth_keys"
    assert elapsed < 4_000, "took #{elapsed} ms"
    assert {:ok, _} = Auth.verify(credential(pair), keys: keys)

    # EHOS rotates while the table is still held: the first credential signed with
    # the new key gets in, on the early fetch it asked for.
    rotated = key_pair()
    answer(ehos, {:keys, [rotated]})
    advance(clock, :timer.seconds(30))

    {elapsed, {verified, _log}} =
      :timer.tc(
        fn -> with_log(fn -> Auth.verify(credential(rotated), keys: keys) end) end,
        :millisecond
      )

    assert {:ok, _} = verified
    assert elapsed < 4_000, "took #{elapsed} ms"
  end

  test "a key fetched is in force before the table is written" do
    ehos = ehos({:keys, [key_pair()]})
    keys = start_keys(ehos, repo: HeldRepo)
    rotated = key_pair()
    answer(ehos, {:keys, [rotated]})

    Application.put_env(:eh_os_contract_auth, HeldRepo, self())
    on_exit(fn -> Application.delete_env(:eh_os_contract_auth, HeldRepo) end)
    refresh = Task.async(fn -> Keys.refresh(keys) end)

    assert_receive {:writing, writer}, 5_000
    assert Keys.kids(keys) == [rotated.kid]

    send(writer, :go)
    assert Task.await(refresh) == :ok
  end

  # Returns once a pin waits in the mailbox of the key process, which a held write keeps
  # from taking it.
  defp await_pin_queued(keys) do
    {:messages, messages} = Process.info(Process.whereis(keys), :messages)

    unless Enum.any?(messages, &match?({:"$gen_call", _from, {:pin, _kid, _public}}, &1)) do
      Process.sleep(10)
      await_pin_queued(keys)
    end
  end

  # A connection of its own, outside the sandbox, holds the table as a migration or
  # `VACUUM FULL` does, until the test ends, and commits nothing. Called before the
  # key process starts: the sandbox's transaction holds what that process touched
  # until the test ends, so a lock asked for after it would never be granted.
  defp lock_table! do
    test = self()

    connection =
      Repo.config() |> Keyword.take([:hostname, :port, :username, :password, :database])

    holder =
      spawn(fn ->
        {:ok, conn} = Postgrex.start_link(connection)

        Postgrex.transaction(
          conn,
          fn conn ->
            Postgrex.query!(
              conn,
              "LOCK TABLE eh_os_contract_auth_keys IN ACCESS EXCLUSIVE MODE",
              []
            )

            send(test, :locked)

            receive do
              :release -> Postgrex.rollback(conn, :released)
            end
          end,
          timeout: :infinity
        )

        GenServer.stop(conn)
      end)

    # Registered before the lock is waited for, so a lock taken late is released too.
    # Run by another process than the test's, so it watches the holder itself.
    on_exit(fn ->
      ref = Process.monitor(holder)
      send(holder, :release)

      receive do
        {:DOWN, ^ref, :process, ^holder, _reason} -> :ok
      end
    end)

    assert_receive :locked, 5_000
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

  test "an unknown kid waits the interval from the end of the last fetch, not its start" do
    pair = key_pair()
    clock = clock()
    test = self()

    # A fetch that takes twenty seconds of the key process's clock.
    slow = fn conn ->
      send(test, :fetched)
      advance(clock, :timer.seconds(20))
      Req.Test.json(conn, %{"keys" => [Map.put(pair.public, "kid", pair.kid)]})
    end

    keys = start_keys(nil, clock: clock, plug: slow)
    assert_received :fetched

    # Thirty-five seconds after the start's fetch began, fifteen after it ended.
    advance(clock, :timer.seconds(15))
    assert Auth.verify(credential(key_pair()), keys: keys) == {:error, :unknown_key}
    refute_received :fetched

    # The control: thirty after it ended.
    advance(clock, :timer.seconds(15))
    assert Auth.verify(credential(key_pair()), keys: keys) == {:error, :unknown_key}
    assert_received :fetched
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

  # A pin queued behind a fetch, such as the start's, can wait longer than
  # `GenServer.call/2`'s five seconds.
  test "a pin waits for the key process as long as a refresh does" do
    keys = start_keys(ehos({:keys, [key_pair()]}), repo: HeldRepo)
    pinned = key_pair()

    Application.put_env(:eh_os_contract_auth, HeldRepo, self())
    on_exit(fn -> Application.delete_env(:eh_os_contract_auth, HeldRepo) end)
    refresh = Task.async(fn -> Keys.refresh(keys) end)
    assert_receive {:writing, writer}, 5_000

    pin = Task.async(fn -> Keys.pin(pinned.public, keys) end)
    # The hold counts from the moment the pin is in the process's mailbox, not from the
    # start of the task, so the old five seconds cannot cover it.
    await_pin_queued(keys)
    Process.sleep(5_500)
    send(writer, :go)

    assert Task.await(refresh) == :ok
    assert Task.await(pin) == pinned.kid
  end

  test "pinning works only where the configuration allows it" do
    pair = key_pair()
    keys = start_keys(ehos({:keys, [key_pair()]}))
    Application.put_env(:eh_os_contract_auth, :pin_keys, false)
    on_exit(fn -> Application.put_env(:eh_os_contract_auth, :pin_keys, true) end)

    assert_raise ArgumentError, ~r/pinning a key: for tests only/, fn ->
      Keys.pin(pair.public, keys)
    end

    assert Auth.verify(credential(pair), keys: keys) == {:error, :unknown_key}
  end

  # A module that is not async runs after the async ones, alone: Mix's environment can be
  # changed here, and is put back after each test.
  describe "test trust where Mix's environment is not :test" do
    setup do
      on_exit(fn ->
        Mix.env(:test)
        Application.put_env(:eh_os_contract_auth, :pin_keys, true)
      end)
    end

    test "is given with pin_keys: true and Mix's environment :test" do
      assert Keys.test_trust?()
      assert Keys.check_trust!([plug: {Req.Test, __MODULE__}], "the child", "EHOS") == :ok
    end

    test "pin_keys: true stops the boot in another environment" do
      for env <- [:dev, :prod] do
        Mix.env(env)
        refute Keys.test_trust?()

        assert_raise ArgumentError,
                     ~r/pin_keys: true is set where no test runs: Mix's environment is #{inspect(env)}/,
                     fn ->
                       Keys.check_trust!([], "the child", "EHOS")
                     end
      end
    end

    test "a key, the sign-in stand-in and the Testing stand-ins are refused in another environment" do
      pair = key_pair()
      keys = start_keys(ehos({:keys, [key_pair()]}))
      Mix.env(:dev)

      assert_raise ArgumentError, ~r/pinning a key: for tests only/, fn ->
        Keys.pin(pair.public, keys)
      end

      assert_raise ArgumentError,
                   ~r/a stand-in for EhOsContract.Auth.SignIn: for tests only/,
                   fn ->
                     EhOsContract.Auth.Testing.SignIn.ensure_started(:stand_in_refused)
                   end

      assert_raise ArgumentError, ~r/Testing.People, .Grants and .Mail: for tests only/, fn ->
        EhOsContract.Auth.Testing.People.list()
      end

      Mix.env(:test)
      assert Auth.verify(credential(pair), keys: keys) == {:error, :unknown_key}
    end

    test "with pin_keys: false, a plug is refused and the boot goes on without one" do
      Application.put_env(:eh_os_contract_auth, :pin_keys, false)

      for env <- [:test, :dev] do
        Mix.env(env)
        assert Keys.check_trust!([], "the child", "EHOS") == :ok

        assert_raise ArgumentError,
                     ~r/the child takes plug: only where Mix's environment is :test/,
                     fn ->
                       Keys.check_trust!([plug: {Req.Test, __MODULE__}], "the child", "EHOS")
                     end
      end
    end

    # In a node of its own: this one runs Mix, and its Mix cannot be stopped.
    test "where Mix's code is loaded but its application is not started, nothing is trusted" do
      # This project's code alone, run by the Elixir that runs this test.
      build = Mix.Project.build_path()

      paths =
        for path <- :code.get_path(),
            String.starts_with?(to_string(path), build),
            do: ["-pa", to_string(path)]

      elixir = Path.expand("../../bin/elixir", :code.lib_dir(:elixir))

      script = """
      Application.put_env(:eh_os_contract_auth, :pin_keys, true)
      IO.inspect(Code.ensure_loaded?(Mix))
      IO.inspect(EhOsContract.Auth.Keys.test_trust?())

      try do
        EhOsContract.Auth.Keys.check_trust!([], "the child", "EHOS")
      rescue
        e in ArgumentError -> IO.puts(e.message)
      end
      """

      {out, 0} = System.cmd(elixir, List.flatten(paths) ++ ["-e", script])

      assert out ==
               "true\nfalse\nconfig :eh_os_contract_auth, pin_keys: true is set where no test " <>
                 "runs: Mix's environment is not there, since the :mix application is not " <>
                 "started, not :test. The line lets code trust keys and answers EHOS did not " <>
                 "give. Put it in config/test.exs alone, and remove it from config/config.exs, " <>
                 "config/<environment>.exs and config/runtime.exs\n"
    end
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

  test "a refresh of a key process that is not running says so, and does not raise" do
    assert Keys.refresh(:not_started) == {:error, :not_running}
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
