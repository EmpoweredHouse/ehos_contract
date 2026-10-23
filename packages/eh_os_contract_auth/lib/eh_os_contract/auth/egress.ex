defmodule EhOsContract.Auth.Egress do
  # EHOS D-135, and its plan's step 5 (#415).
  @moduledoc """
  Calls to a host outside the installation, through the proxy EHOS gives the application.

  An application reaches a host outside the installation only by naming it in `ehos.yaml`
  (`ehos.yaml/v5`, `needs.egress`), and only through a proxy of its own, whose address EHOS gives
  it as `EHOS_EGRESS_PROXY`, `host:port`, with `HTTPS_PROXY` and `NO_PROXY` beside it. Every other
  way out is refused. Req reads none of these variables, so the client that calls such a host is
  given the proxy by attaching this plugin:

      Req.new(base_url: "https://registry.example.org")
      |> EhOsContract.Auth.Egress.attach()
      |> Req.get!(url: "/companies/123")

  With `EHOS_EGRESS_PROXY` set, an `https` request's connection is a `CONNECT` tunnel through the
  proxy, and TLS inside it is verified against the host the request names, which is also the name
  the handshake asks for, as without a proxy. It goes directly instead:

    * to a host `NO_PROXY` names, such as EHOS or another application of the installation;
    * for a plain `http` URL, which the proxy refuses, so that its headers and body are never sent
      to it in the clear;
    * where the variable is not set: in development, in tests, or where the application names no
      host.

  Each redirect is decided again, for the host it leads to. A proxy the caller set in
  `connect_options` is the caller's, and kept.

  The plugin is attached to the clients that call outside, never made a default for every Req
  call: this package calls EHOS with Req, and Req's defaults cannot carry a step that leaves a
  host in `NO_PROXY` direct.

  A request given its own Finch pool (`:finch`) cannot be given a proxy, since Req takes either
  that or `connect_options`: `attach/1` raises for one, and so does a request that gains one after
  it. So does a request when `EHOS_EGRESS_PROXY` is not `host:port`, which EHOS never writes.
  """

  @step :ehos_egress

  @doc """
  Attaches the proxy step to `request`, after Req's own steps, so that its URL is settled.

  Raises `ArgumentError` for a request given its own Finch pool.
  """
  @spec attach(Req.Request.t()) :: Req.Request.t()
  def attach(%Req.Request{} = request) do
    finch!(request)
    Req.Request.append_request_steps(request, [{@step, &put_proxy/1}])
  end

  @doc false
  @spec put_proxy(Req.Request.t()) :: Req.Request.t()
  def put_proxy(%Req.Request{} = request) do
    finch!(request)
    request = undo(request)
    env = Map.new(~w(EHOS_EGRESS_PROXY NO_PROXY no_proxy), &{&1, System.get_env(&1)})

    case request.url.scheme == "https" && proxy(request.url.host, env) do
      proxy when is_tuple(proxy) ->
        connect = Req.Request.get_option(request, :connect_options, [])

        if Keyword.has_key?(connect, :proxy) do
          request
        else
          request
          |> Req.Request.put_option(:connect_options, Keyword.put(connect, :proxy, proxy))
          |> Req.Request.put_private(@step, true)
        end

      _direct ->
        request
    end
  end

  # A redirect runs the steps again on the request that was sent: the proxy this step gave the
  # last hop is taken back before the next is decided.
  defp undo(request) do
    if Req.Request.get_private(request, @step) do
      connect = Req.Request.get_option(request, :connect_options, [])

      request
      |> Req.Request.put_option(:connect_options, Keyword.delete(connect, :proxy))
      |> Req.Request.put_private(@step, false)
    else
      request
    end
  end

  defp finch!(request) do
    if Req.Request.get_option(request, :finch) do
      raise ArgumentError,
            "EhOsContract.Auth.Egress cannot give a proxy to a request with its own :finch " <>
              "pool; give that pool the proxy instead"
    end
  end

  @doc """
  The Mint proxy for an `https` request to `host`, from the variables in `env`, or nil when it
  goes directly: `EHOS_EGRESS_PROXY` unset or empty, or `host` named by `NO_PROXY` (or
  `no_proxy`).

  `NO_PROXY` is read as curl reads what EHOS writes in it: `*` names every host; an entry names
  that host and every name under it, with or without a leading dot; a bracketed IPv6 address is
  read without its brackets; an entry's port is not compared. A range (`10.0.0.0/8`) names nothing.

      iex> EhOsContract.Auth.Egress.proxy("registry.example.org", %{"EHOS_EGRESS_PROXY" => "egress:3128"})
      {:http, "egress", 3128, []}

      iex> EhOsContract.Auth.Egress.proxy("ehos.office.example", %{
      ...>   "EHOS_EGRESS_PROXY" => "egress:3128",
      ...>   "NO_PROXY" => ".svc,office.example"
      ...> })
      nil

      iex> EhOsContract.Auth.Egress.proxy("registry.example.org", %{})
      nil

  Raises `ArgumentError` when `EHOS_EGRESS_PROXY` is not `host:port`.
  """
  @spec proxy(String.t() | nil, %{optional(String.t()) => String.t() | nil}) ::
          {:http, String.t(), 1..65_535, []} | nil
  def proxy(host, env) when is_map(env) do
    case env["EHOS_EGRESS_PROXY"] do
      address when address in [nil, ""] ->
        nil

      address ->
        if direct?(host, env["NO_PROXY"] || env["no_proxy"] || ""),
          do: nil,
          else: address!(address)
    end
  end

  defp address!(address) do
    with [host, port] <- String.split(address, ":"),
         true <- host != "",
         {port, ""} when port in 1..65_535 <- Integer.parse(port) do
      {:http, host, port, []}
    else
      _not_an_address ->
        raise ArgumentError, "EHOS_EGRESS_PROXY must be host:port, not #{inspect(address)}"
    end
  end

  # A request with no host is never sent through the proxy.
  defp direct?(nil, _no_proxy), do: true

  defp direct?(host, no_proxy) do
    host = host |> String.downcase() |> String.trim_trailing(".")

    no_proxy
    |> String.split(",", trim: true)
    |> Enum.map(&entry/1)
    |> Enum.any?(fn
      "" -> false
      "*" -> true
      entry -> host == entry or String.ends_with?(host, "." <> entry)
    end)
  end

  defp entry(entry) do
    entry = entry |> String.trim() |> String.downcase()

    case entry do
      # `[::1]` and `[::1]:443`: the address inside the brackets.
      "[" <> rest ->
        rest |> String.split("]", parts: 2) |> hd()

      _name ->
        entry = String.trim_leading(entry, ".")

        # An IPv6 address has colons of its own; only `name:port` and `a.b.c.d:port` lose a port.
        case String.split(entry, ":") do
          [name, _port] -> name
          _other -> entry
        end
    end
  end
end
