defmodule EhOsContract.Auth.PoolsTest do
  @moduledoc """
  The Finch pools that the package's calls to EHOS go through (#595): one for each set
  of connection options, started once. Given `connect_options:`, Req asked for a pool on
  each call, and with `SSLKEYLOGFILE` set Finch opened the file each time and never
  closed it.

  `async: false`: the test sets `SSLKEYLOGFILE`, which is global.
  """

  use ExUnit.Case, async: false

  alias EhOsContract.Auth.Pools

  @tag :tmp_dir
  test "calls at once start one pool for their options, and open SSLKEYLOGFILE once", %{
    tmp_dir: dir
  } do
    previous = System.get_env("SSLKEYLOGFILE")

    on_exit(fn ->
      if previous,
        do: System.put_env("SSLKEYLOGFILE", previous),
        else: System.delete_env("SSLKEYLOGFILE")
    end)

    System.put_env("SSLKEYLOGFILE", Path.join(dir, "keys.log"))

    # The control: a pool opens the file when it starts, as Finch does for each pool.
    before = open_files()
    Pools.finch(options())
    opened = open_files() - before
    assert opened > 0

    options = options()
    before = open_files()

    names =
      1..20
      |> Enum.map(fn _ -> Task.async(fn -> Pools.finch(options) end) end)
      |> Task.await_many()
      |> Enum.uniq()

    assert [[name: name]] = names
    assert is_pid(Process.whereis(name))
    for _ <- 1..20, do: assert(Pools.finch(options) == [name: name])

    assert open_files() - before == opened
  end

  test "other connection options get a pool of their own" do
    assert Pools.finch(timeout: 2_000) != Pools.finch(timeout: 2_001)
    assert Pools.finch(timeout: 2_000) == Pools.finch(timeout: 2_000)
  end

  test "a call goes through its pool, and a global connect_options: does not get to it" do
    previous = Application.get_env(:req, :default_options)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:req, :default_options, previous),
        else: Application.delete_env(:req, :default_options)
    end)

    Application.put_env(:req, :default_options, connect_options: [timeout: 1])
    url = "http://127.0.0.1:#{answering_server()}/"

    assert {:ok, %Req.Response{status: 200, body: "ok"}} =
             Pools.request(url: url, finch: Pools.finch(options()), retry: false)
  end

  # Options of their own, so that the pool is new to the test.
  defp options, do: [timeout: 1_000 + System.unique_integer([:positive])]

  # A server on loopback that answers one request with 200 and "ok".
  defp answering_server do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
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
