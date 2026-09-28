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

  test "a failed fetch logs the address without its query, which may carry a token" do
    keys = start_keys(ehos({:status, 503}))
    :sys.replace_state(keys, &%{&1 | url: "https://ehos.test/jwks.json?access_token=secret"})

    log = ExUnit.CaptureLog.capture_log(fn -> Keys.refresh(keys) end)
    assert log =~ "https://ehos.test/jwks.json"
    refute log =~ "secret"
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

  describe "a host's connect options" do
    # An adapter in place of the network: it sends the test the transport options
    # Req would hand Mint for this fetch, and answers as an EHOS that is down would.
    setup do
      test = self()

      adapter = fn request ->
        pool = Req.Finch.pool_options(request.options)
        send(test, {:transport, pool[:conn_opts][:transport_opts]})
        {request, Req.Response.new(status: 503)}
      end

      %{adapter: adapter}
    end

    test "keep the two-second connect timeout when naming a certificate authority", %{
      adapter: adapter
    } do
      transport = [cacertfile: "/etc/ehos/ca.pem"]

      start_keys(nil,
        req_options: [adapter: adapter, connect_options: [transport_opts: transport]]
      )

      assert_received {:transport, options}
      assert options[:timeout] == 2_000
      assert options[:cacertfile] == "/etc/ehos/ca.pem"
    end

    test "that are nil keep the defaults, and the key set is fetched", %{adapter: adapter} do
      start_keys(nil, req_options: [adapter: adapter, connect_options: nil])

      assert_received {:transport, [timeout: 2_000]}
    end

    test "with nil transport options keep the timeout, and nothing breaks", %{adapter: adapter} do
      start_keys(nil, req_options: [adapter: adapter, connect_options: [transport_opts: nil]])

      assert_received {:transport, [timeout: 2_000]}
    end

    test "replace the connect timeout when they set one", %{adapter: adapter} do
      start_keys(nil, req_options: [adapter: adapter, connect_options: [timeout: 500]])

      assert_received {:transport, [timeout: 500]}
    end
  end

  describe "a key process started directly" do
    # `start_link/1` checks what `EhOsContract.Auth.child_spec/1` checks, so a host
    # that lists `Keys` itself gets no way around it.
    # A name of its own, so a check that stopped raising fails its assertion rather
    # than a later test's start.
    test "refuses an address that is not https" do
      assert_raise ArgumentError, ~r/not https/, fn ->
        Keys.start_link(name: :keys_http, url: "http://ehos.example.com/jwks.json", repo: Repo)
      end
    end

    test "refuses a request option outside the few it takes" do
      assert_raise ArgumentError, ~r/does not take follow_redirects: in req_options/, fn ->
        Keys.start_link(
          name: :keys_redirect,
          url: "https://ehos.test/.well-known/jwks.json",
          repo: Repo,
          req_options: [follow_redirects: true]
        )
      end
    end
  end

  describe "Req's own defaults" do
    setup do
      saved = Application.fetch_env(:req, :default_options)

      on_exit(fn ->
        case saved do
          {:ok, defaults} -> Application.put_env(:req, :default_options, defaults)
          :error -> Application.delete_env(:req, :default_options)
        end
      end)
    end

    # Set for the host's other requests: none of it reaches this one — not an option,
    # a header, a body, nor a plugin's step — whether it was there at the boot or
    # set after it, to something else.
    test "do not reach the fetch, set before the boot or after it" do
      test = self()

      defaults = fn tag ->
        [
          follow_redirects: true,
          auth: {:bearer, "#{tag}"},
          headers: [authorization: "#{tag}"],
          body: "#{tag}",
          plugins: [fn request -> send(test, {:plugin, tag}) && request end]
        ]
      end

      adapter = fn request ->
        send(test, {:sent, request})
        {request, Req.Response.new(status: 503)}
      end

      Application.put_env(:req, :default_options, defaults.(:before))
      keys = start_keys(nil, req_options: [adapter: adapter])
      Req.default_options(defaults.(:after))
      assert {:error, {:status, 503}} = Keys.refresh(keys)

      for _fetch <- [:at_the_boot, :after_it] do
        assert_received {:sent, request}
        refute Map.has_key?(request.options, :follow_redirects)
        refute Map.has_key?(request.options, :auth)
        refute Map.has_key?(request.headers, "authorization")
        assert request.body == nil
      end

      refute_received {:plugin, _}
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
