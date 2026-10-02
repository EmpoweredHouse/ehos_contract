defmodule EhOsContract.Auth.SignIn.Http do
  @moduledoc false

  # How sign-in reaches EHOS: its discovery document and keys, and every call `oidcc`
  # makes, through `oidcc`'s HTTP adapter in place of its default, `httpc`. The default
  # follows redirects (to plain http too), buffers a body of any size, and gives a call
  # a connect timeout on top of its timeout. What a sign-in trusts is fetched here, so
  # it is held to what `EhOsContract.Auth.Keys` holds the key set to:
  #
  #   * https only, and no redirect followed: a redirect is an answer, which `oidcc`
  #     refuses as a status it did not expect;
  #   * a body of at most 64 KiB;
  #   * one deadline for the whole call, the `timeout` `oidcc` passes.
  #
  # Nothing here raises: a defect of the transport is an `{:error, _}`, as a refused
  # connection is.

  @behaviour :oidcc_http_adapter

  @connect_timeout 5_000
  @max_body 64 * 1024
  @default_deadline 10_000

  @doc false
  @impl :oidcc_http_adapter
  @spec request(atom(), tuple(), keyword(), keyword(), map()) ::
          {:ok,
           {{charlist(), non_neg_integer(), charlist()}, [{charlist(), charlist()}], binary()}}
          | {:error, term()}
  def request(method, request, http_options, _request_options, config) do
    {url, headers, body} = split(request)
    deadline = Keyword.get(http_options, :timeout, @default_deadline)

    with :ok <- https(url) do
      task = Task.async(fn -> send_request(method, url, headers, body, deadline, config) end)

      case Task.yield(task, deadline) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        nil -> {:error, :timeout}
        {:exit, reason} -> {:error, {:exit, reason}}
      end
    end
  end

  @doc false
  # A GET of a JSON object, for the discovery document and the key set.
  @spec get_json(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def get_json(url, config) do
    case request(:get, {url, []}, [timeout: @default_deadline], [], config) do
      {:ok, {{_version, 200, _reason}, _headers, body}} ->
        case Jason.decode(body) do
          {:ok, json} when is_map(json) -> {:ok, json}
          _other -> {:error, :not_a_json_object}
        end

      {:ok, {{_version, status, _reason}, _headers, _body}} ->
        {:error, {:status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp split({url, headers}), do: {to_string(url), headers(headers), nil}

  defp split({url, headers, content_type, body}) do
    {to_string(url), [{"content-type", to_string(content_type)} | headers(headers)],
     IO.iodata_to_binary(body)}
  end

  defp headers(headers) do
    Enum.map(headers, fn {name, value} -> {to_string(name), IO.iodata_to_binary(value)} end)
  end

  defp https(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> :ok
      _other -> {:error, {:not_https, url}}
    end
  end

  # Runs in a task of its own, so a call that outlives the deadline is killed rather
  # than left to finish; an exception in it is an answer, not a crash of the caller
  # the task is linked to.
  defp send_request(method, url, headers, body, deadline, config) do
    options =
      [
        method: method,
        url: url,
        headers: headers,
        redirect: false,
        retry: false,
        decode_body: false,
        receive_timeout: deadline,
        connect_options: connect_options(config),
        into: &at_most/2
      ]
      |> then(&if body, do: Keyword.put(&1, :body, body), else: &1)
      |> Kernel.++(Keyword.take(Map.to_list(config), [:plug]))

    case Req.request(options) do
      {:ok, %Req.Response{body: :too_large}} ->
        {:error, :response_too_large}

      {:ok, %Req.Response{} = response} ->
        {:ok,
         {{~c"HTTP/1.1", response.status, ~c""}, charlist_headers(response), response.body || ""}}

      {:error, exception} ->
        {:error, exception}
    end
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp connect_options(config) do
    case Keyword.take(Map.to_list(config), [:cacertfile, :cacerts]) do
      [] -> [timeout: @connect_timeout]
      authority -> [timeout: @connect_timeout, transport_opts: authority]
    end
  end

  defp charlist_headers(response) do
    for {name, values} <- response.headers, value <- List.wrap(values) do
      {String.to_charlist(name), String.to_charlist(value)}
    end
  end

  # Collects the body up to `@max_body` and gives up past it.
  defp at_most({:data, data}, {request, response}) do
    body = (response.body || "") <> data

    if byte_size(body) > @max_body,
      do: {:halt, {request, %{response | body: :too_large}}},
      else: {:cont, {request, %{response | body: body}}}
  end
end
