defmodule EhOsContract.Auth.PoolsTest do
  @moduledoc """
  The Finch pools that the package's calls to EHOS go through (#595): one for each set
  of pool options, started once. Given `connect_options:`, Req asked for a pool on each
  call, and with `SSLKEYLOGFILE` set Finch opened the file each time and never closed
  it.

  `async: false`: the tests set `SSLKEYLOGFILE` and `config :req, default_options`,
  which are global.
  """

  use ExUnit.Case, async: false

  alias EhOsContract.Auth.Pools

  @supervisor EhOsContract.Auth.Pools.Supervisor

  setup do
    key_log = System.get_env("SSLKEYLOGFILE")
    defaults = Application.get_env(:req, :default_options)

    on_exit(fn ->
      if key_log,
        do: System.put_env("SSLKEYLOGFILE", key_log),
        else: System.delete_env("SSLKEYLOGFILE")

      if defaults,
        do: Application.put_env(:req, :default_options, defaults),
        else: Application.delete_env(:req, :default_options)
    end)
  end

  @tag :tmp_dir
  test "calls at once start one pool for their options, and open SSLKEYLOGFILE once", %{
    tmp_dir: dir
  } do
    System.put_env("SSLKEYLOGFILE", Path.join(dir, "keys.log"))

    # One port, as a child calls one EHOS: Finch opens the file again for each host.
    port = closed_port()

    # The control: a pool opens the file when it starts, as Finch does for each pool.
    before = open_files()
    refused(connect_options(), port)
    opened = open_files() - before
    assert opened > 0

    options = connect_options()
    {files, pools} = {open_files(), pools()}

    1..20
    |> Enum.map(fn _ -> Task.async(fn -> refused(options, port) end) end)
    |> Task.await_many()

    for _ <- 1..20, do: refused(options, port)

    assert pools() - pools == 1
    assert open_files() - files == opened
  end

  test "other connection options, or another origin, get a pool of their own" do
    {port, other_port} = {closed_port(), closed_port()}
    {options, other_options} = {connect_options(), connect_options()}
    pools = pools()

    refused(options, port)
    refused(other_options, port)
    refused(options, other_port)
    refused(options, port)

    assert pools() - pools == 3
  end

  @tag :tmp_dir
  test "a pool that does not start fails the call, and the next calls, not the package", %{
    tmp_dir: dir
  } do
    System.put_env("SSLKEYLOGFILE", Path.join([dir, "no such directory", "keys.log"]))
    pools = Process.whereis(Pools)

    for _ <- 1..5 do
      assert_raise RuntimeError, ~r/the Finch pool of the calls to EHOS did not start: /, fn ->
        refused(connect_options())
      end
    end

    assert Process.whereis(Pools) == pools
  end

  test "a pool that stops is started again by the next call" do
    options = connect_options()
    refused(options)

    # No other test runs beside this one, which is not async: every pool can stop.
    for {_, pid, _, _} <- DynamicSupervisor.which_children(@supervisor),
        do: Process.exit(pid, :kill)

    wait_until(fn -> pools() == 0 and named_pools() == [] end)

    refused(options)
    assert pools() == 1
  end

  test "a call goes through its pool, and a global connect_options: does not get to it" do
    Application.put_env(:req, :default_options, connect_options: [timeout: 1])

    assert {:ok, %Req.Response{status: 200, body: "ok"}} =
             Pools.request(
               url: "http://127.0.0.1:#{answering_server({127, 0, 0, 1})}/",
               connect_options: connect_options(),
               retry: false
             )
  end

  test "a call to an IPv6 address gets a pool that speaks IPv6" do
    assert {:ok, %Req.Response{status: 200, body: "ok"}} =
             Pools.request(
               url: "http://[::1]:#{answering_server({0, 0, 0, 0, 0, 0, 0, 1})}/",
               connect_options: connect_options(),
               retry: false
             )
  end

  # A call refused at a closed port: it starts the pool of its options, and sends nothing.
  defp refused(options, port \\ closed_port()) do
    assert {:error, %Req.TransportError{reason: :econnrefused}} = call(options, port)
  end

  # The names of the pools still registered: a pool's processes stop after it.
  defp named_pools do
    for name <- Process.registered(),
        String.starts_with?(Atom.to_string(name), "Elixir.EhOsContract.Auth.Pools.Pool_"),
        do: name
  end

  defp wait_until(done?, tries \\ 100) do
    cond do
      done?.() -> :ok
      tries == 0 -> flunk("the pools did not stop")
      true -> Process.sleep(10) && wait_until(done?, tries - 1)
    end
  end

  defp call(options, port),
    do: Pools.request(url: "http://127.0.0.1:#{port}/", connect_options: options, retry: false)

  defp closed_port do
    {:ok, listen} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(listen)
    :ok = :gen_tcp.close(listen)
    port
  end

  # Options of their own, so that the pool is new to the test.
  defp connect_options, do: [timeout: 1_000 + System.unique_integer([:positive])]

  defp pools, do: DynamicSupervisor.count_children(@supervisor).active

  # A server at `ip` that answers one request with 200 and "ok".
  defp answering_server(ip) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, ip: ip])
    {:ok, port} = :inet.port(listen)

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      {:ok, _request} = :gen_tcp.recv(socket, 0)
      :ok = :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\nok")
      Process.sleep(:infinity)
    end)

    port
  end

  # The file servers open in this node: each file that Finch opens is one.
  defp open_files do
    Enum.count(Process.list(), fn pid ->
      match?({:current_function, {:file_io_server, _, _}}, Process.info(pid, :current_function))
    end)
  end
end
