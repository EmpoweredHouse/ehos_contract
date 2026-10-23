defmodule EhOsContract.Auth.EgressTest do
  # The plugin reads the process environment, which these tests set.
  use ExUnit.Case, async: false

  alias EhOsContract.Auth.Egress

  doctest Egress

  @variables ~w(EHOS_EGRESS_PROXY NO_PROXY no_proxy)

  setup do
    kept = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(kept, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)
  end

  describe "proxy/2" do
    @proxy %{"EHOS_EGRESS_PROXY" => "egress:3128"}

    test "names the proxy for a host outside, and nothing without the variable" do
      assert Egress.proxy("registry.example.org", @proxy) == {:http, "egress", 3128, []}
      assert Egress.proxy("registry.example.org", %{"EHOS_EGRESS_PROXY" => ""}) == nil
      assert Egress.proxy("registry.example.org", %{}) == nil
    end

    # What EHOS gives a workload: `localhost,127.0.0.1,::1,.svc,.cluster.local,<domain>,.<domain>`.
    test "leaves what NO_PROXY names direct, as EHOS writes it" do
      env =
        Map.put(@proxy, "NO_PROXY", "localhost,127.0.0.1,::1,.svc,.cluster.local,office.example")

      for host <- ~w(localhost 127.0.0.1 ::1 ledger.office-staging.svc
                     ehos.ehos-system.svc.cluster.local office.example ehos.office.example
                     EHOS.Office.Example. ) do
        assert Egress.proxy(host, env) == nil, host
      end

      for host <- ~w(registry.example.org notoffice.example office.example.org svc.example) do
        assert Egress.proxy(host, env) == {:http, "egress", 3128, []}, host
      end
    end

    test "reads no_proxy too, a port in an entry, brackets and the wildcard" do
      assert Egress.proxy("a.example", Map.put(@proxy, "no_proxy", "example")) == nil
      assert Egress.proxy("a.example", Map.put(@proxy, "NO_PROXY", " a.example:443 ")) == nil
      assert Egress.proxy("::1", Map.put(@proxy, "NO_PROXY", "[::1]")) == nil
      assert Egress.proxy("::1", Map.put(@proxy, "NO_PROXY", "[::1]:443")) == nil
      assert Egress.proxy("10.0.0.1", Map.put(@proxy, "NO_PROXY", "10.0.0.0/8")) != nil
      assert Egress.proxy("a.example", Map.put(@proxy, "NO_PROXY", "*")) == nil
      assert Egress.proxy("a.example", Map.put(@proxy, "NO_PROXY", ",,")) != nil
    end

    test "sends a request with no host directly" do
      assert Egress.proxy(nil, @proxy) == nil
    end

    test "refuses an address that is not host:port" do
      for address <- [
            "egress",
            "egress:",
            ":3128",
            "egress:0",
            "egress:3128x",
            "http://egress:3128"
          ] do
        assert_raise ArgumentError, ~r/must be host:port/, fn ->
          Egress.proxy("registry.example.org", %{"EHOS_EGRESS_PROXY" => address})
        end
      end
    end
  end

  describe "attach/1" do
    setup do
      %{cacerts: cacerts, server: server} = tls_server(~w(registry.test localhost))
      proxy = connect_proxy(server)
      %{cacerts: cacerts, server: server, proxy: proxy}
    end

    test "reaches a host outside through the proxy, verified against its own name", c do
      System.put_env("EHOS_EGRESS_PROXY", "127.0.0.1:#{c.proxy}")

      assert %Req.Response{status: 200, body: "reached"} =
               get!("https://registry.test:#{c.server}/", c.cacerts)

      assert_received {:connect, "registry.test:" <> _port}

      # Its host settled from `base_url`, as the step runs after Req's own.
      assert %Req.Response{body: "reached"} =
               [
                 base_url: "https://registry.test:#{c.server}",
                 retry: false,
                 connect_options: [transport_opts: [cacerts: c.cacerts]]
               ]
               |> Req.new()
               |> Egress.attach()
               |> Req.get!(url: "/companies/1")

      assert_received {:connect, "registry.test:" <> _port}
    end

    test "refuses a far end whose certificate names another host", c do
      System.put_env("EHOS_EGRESS_PROXY", "127.0.0.1:#{c.proxy}")

      # The client's own check of the name, whichever alert this OTP sends for it.
      assert {:error, %Req.TransportError{reason: {:tls_alert, {_alert, why}}}} =
               get("https://elsewhere.test:#{c.server}/", c.cacerts)

      assert to_string(why) =~ "hostname_check_failed"

      assert_received {:connect, "elsewhere.test:" <> _port}
    end

    test "goes directly where NO_PROXY names the host", c do
      System.put_env("EHOS_EGRESS_PROXY", "127.0.0.1:#{c.proxy}")
      System.put_env("NO_PROXY", "localhost")

      assert %Req.Response{body: "reached"} = get!("https://localhost:#{c.server}/", c.cacerts)
      refute_received {:connect, _target}
    end

    test "does nothing without EHOS_EGRESS_PROXY", c do
      assert %Req.Response{body: "reached"} = get!("https://localhost:#{c.server}/", c.cacerts)
      refute_received {:connect, _target}
    end

    test "sends a plain http URL directly, never to the proxy in the clear", c do
      System.put_env("EHOS_EGRESS_PROXY", "127.0.0.1:#{c.proxy}")

      request =
        [url: "http://registry.test/", headers: [authorization: "Bearer secret"]]
        |> Req.new()
        |> Egress.attach()

      refute Keyword.has_key?(Egress.put_proxy(request).options[:connect_options] || [], :proxy)
    end

    test "decides again on a redirect, so a host NO_PROXY names is reached directly", c do
      System.put_env("EHOS_EGRESS_PROXY", "127.0.0.1:#{c.proxy}")
      System.put_env("NO_PROXY", "localhost")

      assert %Req.Response{body: "reached"} =
               get!("https://registry.test:#{c.server}/moved", c.cacerts)

      # The registry through the proxy, the redirect to localhost directly.
      assert_received {:connect, "registry.test:" <> _port}
      refute_received {:connect, _target}
    end

    test "takes back the proxy it set when a hop goes to http, and gives one when it leaves NO_PROXY",
         c do
      System.put_env("EHOS_EGRESS_PROXY", "127.0.0.1:#{c.proxy}")
      System.put_env("NO_PROXY", "localhost")
      proxied = Egress.put_proxy(Req.new(url: "https://registry.test/"))
      assert proxied.options.connect_options[:proxy] == {:http, "127.0.0.1", c.proxy, []}

      # A redirect runs the steps again on the request that was sent, with another URL.
      to_http = Egress.put_proxy(%{proxied | url: URI.parse("http://registry.test/")})
      refute Map.has_key?(to_http.options, :connect_options)

      direct = Egress.put_proxy(Req.new(url: "https://localhost/"))
      refute Map.has_key?(direct.options, :connect_options)

      out = Egress.put_proxy(%{direct | url: URI.parse("https://registry.test/")})
      assert out.options.connect_options[:proxy] == {:http, "127.0.0.1", c.proxy, []}
    end

    test "refuses an https request that speaks HTTP/2 alone, with or without a proxy", c do
      for options <- [[protocols: [:http2]], [protocol: :http2]] do
        request = Req.new(url: "https://registry.test/", connect_options: options)
        assert_raise ArgumentError, ~r/HTTP\/2 alone/, fn -> Egress.put_proxy(request) end
      end

      System.put_env("EHOS_EGRESS_PROXY", "127.0.0.1:#{c.proxy}")

      request =
        Req.new(url: "https://registry.test/", connect_options: [protocols: [:http2]])

      assert_raise ArgumentError, ~r/HTTP\/2 alone/, fn -> Egress.put_proxy(request) end

      # Req's default where the key is there but empty.
      unset = Req.new(url: "https://registry.test/", connect_options: [protocols: nil])
      assert Egress.put_proxy(unset).options.connect_options[:proxy]

      both =
        Req.new(url: "https://registry.test/", connect_options: [protocols: [:http1, :http2]])

      assert Egress.put_proxy(both).options.connect_options[:proxy]
    end

    test "refuses a request with its own Finch pool, which Req cannot give a proxy" do
      assert_raise ArgumentError, ~r/its own :finch pool/, fn ->
        [url: "https://registry.test/", finch: SomeFinch] |> Req.new() |> Egress.attach()
      end

      request = [url: "https://registry.test/"] |> Req.new() |> Egress.attach()

      assert_raise ArgumentError, ~r/its own :finch pool/, fn ->
        request |> Req.merge(finch: SomeFinch) |> Egress.put_proxy()
      end
    end

    test "keeps a proxy the caller set itself", c do
      System.put_env("EHOS_EGRESS_PROXY", "127.0.0.1:1")

      response =
        [url: "https://registry.test:#{c.server}/", retry: false]
        |> Req.new()
        |> Req.merge(
          connect_options: [
            proxy: {:http, "127.0.0.1", c.proxy, []},
            transport_opts: [cacerts: c.cacerts]
          ]
        )
        |> Egress.attach()
        |> Req.get!()

      assert response.body == "reached"
      assert_received {:connect, "registry.test:" <> _port}
    end
  end

  defp get!(url, cacerts) do
    {:ok, response} = get(url, cacerts)
    response
  end

  defp get(url, cacerts) do
    [url: url, retry: false, connect_options: [transport_opts: [cacerts: cacerts]]]
    |> Req.new()
    |> Egress.attach()
    |> Req.get()
  end

  # TLS 1.3 takes no certificate signed with SHA-1, which pkix_test_data uses by default.
  @signed [key: {:namedCurve, :secp256r1}, digest: :sha256]

  # A TLS server on 127.0.0.1 whose certificate names `names`, answering every request "reached".
  defp tls_server(names) do
    san =
      {:Extension, {2, 5, 29, 17}, false, Enum.map(names, &{:dNSName, String.to_charlist(&1)})}

    %{server_config: server, client_config: client} =
      :public_key.pkix_test_data(%{
        server_chain: %{
          root: @signed,
          intermediates: [],
          peer: [extensions: [san]] ++ @signed
        },
        client_chain: %{root: @signed, intermediates: [], peer: @signed}
      })

    {:ok, listen} =
      :ssl.listen(0, server ++ [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true])

    {:ok, {_ip, port}} = :ssl.sockname(listen)
    start_supervised!({Task, fn -> serve(listen) end}, id: :tls_server)
    %{cacerts: client[:cacerts], server: port}
  end

  # Until the test that opened it ends, and its listening socket with it.
  defp serve(listen) do
    case :ssl.transport_accept(listen) do
      {:ok, socket} ->
        with {:ok, socket} <- :ssl.handshake(socket, 5_000),
             {:ok, request} <- :ssl.recv(socket, 0, 5_000) do
          :ssl.send(socket, answer(request, listen))
          :ssl.close(socket)
        end

        serve(listen)

      {:error, _closed} ->
        :ok
    end
  end

  # `/moved` sends the client to the same server by the name `localhost`.
  defp answer("GET /moved" <> _rest, listen) do
    {:ok, {_ip, port}} = :ssl.sockname(listen)

    "HTTP/1.1 302 Found\r\nlocation: https://localhost:#{port}/\r\ncontent-length: 0\r\n" <>
      "connection: close\r\n\r\n"
  end

  defp answer(_request, _listen),
    do: "HTTP/1.1 200 OK\r\ncontent-length: 7\r\nconnection: close\r\n\r\nreached"

  # A CONNECT proxy that tells the test each tunnel it was asked for, and opens every one to the
  # TLS server, whatever host it names, as a resolver would.
  defp connect_proxy(server) do
    test = self()

    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen)
    start_supervised!({Task, fn -> tunnel(listen, server, test) end}, id: :connect_proxy)
    port
  end

  defp tunnel(listen, server, test) do
    case :gen_tcp.accept(listen) do
      {:ok, client} -> open(client, listen, server, test)
      {:error, _closed} -> :ok
    end
  end

  defp open(client, listen, server, test) do
    {:ok, request} = read_head(client, "")
    ["CONNECT " <> target | _] = String.split(request, " HTTP/")
    send(test, {:connect, target})

    {:ok, far} = :gen_tcp.connect({127, 0, 0, 1}, server, [:binary, active: false])
    :ok = :gen_tcp.send(client, "HTTP/1.1 200 Connection established\r\n\r\n")
    spawn(fn -> pipe(far, client) end)
    spawn(fn -> pipe(client, far) end)
    tunnel(listen, server, test)
  end

  defp read_head(socket, read) do
    if String.contains?(read, "\r\n\r\n") do
      {:ok, read}
    else
      with {:ok, more} <- :gen_tcp.recv(socket, 0, 5_000), do: read_head(socket, read <> more)
    end
  end

  defp pipe(from, to) do
    case :gen_tcp.recv(from, 0) do
      {:ok, data} ->
        :gen_tcp.send(to, data)
        pipe(from, to)

      {:error, _closed} ->
        :gen_tcp.close(to)
    end
  end
end
