defmodule EhOsContract.Auth.Pools do
  @moduledoc false

  # The Finch pools that the package's calls to EHOS go through: one for each set of
  # pool options and origin, started once and named. Given `connect_options:`, Req asks its
  # supervisor for a pool on each call, and Finch opens the file that `SSLKEYLOGFILE`
  # names before it finds the name taken: each call left the file open (#595). A pool
  # is started through this process, one at a time, so that two first calls do not
  # both open it. The origin's pool is configured, so that Finch starts it with the
  # instance: started on the first calls, it would be started by each of them that
  # finds it missing, and each would open the file.
  #
  # A pool is temporary: one that stops is started again by the next call, not
  # restarted in a loop, which would open the file again each time and count against
  # the package's supervisor.

  use GenServer

  @supervisor EhOsContract.Auth.Pools.Supervisor

  @doc false
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_arg), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  # Runs a call with Req's `options`, through the pool of its connection options. The
  # pool is built as Req builds its own: from the options with the global
  # `config :req, default_options` merged in, and `inet6` for a host that is an IPv6
  # address. Then `connect_options:` leaves the request, since Req refuses it beside
  # `finch:`. Raises when the pool does not start.
  # Called by keys.ex, sign_in/http.ex.
  @doc false
  @spec request(keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def request(options) do
    request = Req.new(options)

    request
    |> Req.Request.delete_option(:connect_options)
    |> Req.Request.put_option(:finch, name: pool!(request))
    |> Req.request()
  end

  defp pool!(request) do
    options =
      if String.contains?(request.url.host || "", ":"),
        do: Map.put(request.options, :inet6, true),
        else: request.options

    pool = Req.Finch.pool_options(options)
    url = request.url
    origin = URI.to_string(%URI{scheme: url.scheme, host: url.host, port: url.port})
    name = name({pool, origin})
    pools = %{:default => pool, origin => pool}

    with nil <- Process.whereis(name),
         {:error, reason} <- GenServer.call(__MODULE__, {:start, name, pools}) do
      raise "the Finch pool of the calls to EHOS did not start: #{describe(reason)}"
    end

    name
  end

  @impl GenServer
  def init(nil), do: {:ok, nil}

  @impl GenServer
  def handle_call({:start, name, pools}, _from, state) do
    # A call that waited behind the one that started it: a second start would open the
    # file before it finds the name taken.
    {:reply, if(Process.whereis(name), do: :ok, else: start(name, pools)), state}
  end

  defp start(name, pools) do
    child =
      Supervisor.child_spec({Finch, name: name, pools: pools},
        id: name,
        restart: :temporary
      )

    case DynamicSupervisor.start_child(@supervisor, child) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Only the exception's message: the pool's options can hold an authority's file.
  defp describe({exception, _stacktrace}) when is_exception(exception),
    do: Exception.message(exception)

  defp describe(_reason), do: "Finch refused its options"

  # One atom for each set of options and origin, as Req names its own pools; a host
  # gives few.
  defp name(key) do
    hash = key |> :erlang.term_to_binary() |> :erlang.md5() |> Base.encode32(padding: false)
    Module.concat(__MODULE__, "Pool_" <> hash)
  end
end
