defmodule EhOsContract.Auth.Pools do
  @moduledoc false

  # The Finch pools that the package's calls to EHOS go through: one for each set of
  # connection options, started once and named, so that a call gives Req `finch:`, not
  # `connect_options:`. Given `connect_options:`, Req asks its supervisor for a pool on
  # each call, and Finch opens the file that `SSLKEYLOGFILE` names before it finds the
  # name taken: each call left the file open (#595). A pool is started through this
  # process, one at a time, so that two first calls do not both open it.

  use GenServer

  @supervisor EhOsContract.Auth.Pools.Supervisor

  @doc false
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_arg), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  # The `finch:` option of a call with `connect_options`, its pool started if it is not.
  # Called by keys.ex, sign_in/http.ex.
  @doc false
  @spec finch(keyword()) :: [name: atom()]
  def finch(connect_options) do
    pool = Req.Finch.pool_options(%{connect_options: connect_options})
    name = name(pool)

    unless Process.whereis(name), do: :ok = GenServer.call(__MODULE__, {:start, name, pool})
    [name: name]
  end

  # Runs a call with `options`, which name a pool through `finch/1`. A global
  # `config :req, default_options: [connect_options: ...]` is dropped: Req refuses it
  # beside `finch:`, and the package sets the connection itself.
  # Called by keys.ex, sign_in/http.ex.
  @doc false
  @spec request(keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def request(options) do
    options
    |> Req.new()
    |> Req.Request.delete_option(:connect_options)
    |> Req.request()
  end

  @impl GenServer
  def init(nil), do: {:ok, nil}

  @impl GenServer
  def handle_call({:start, name, pool}, _from, state) do
    if Process.whereis(name) == nil do
      {:ok, _pid} =
        DynamicSupervisor.start_child(@supervisor, {Finch, name: name, pools: %{default: pool}})
    end

    {:reply, :ok, state}
  end

  # One atom for each set of options, as Req names its own pools; a host gives few.
  defp name(pool) do
    hash = pool |> :erlang.term_to_binary() |> :erlang.md5() |> Base.encode32(padding: false)
    Module.concat(__MODULE__, "Pool_" <> hash)
  end
end
