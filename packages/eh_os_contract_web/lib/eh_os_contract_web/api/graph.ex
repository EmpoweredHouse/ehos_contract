defmodule EhOsContract.Web.Api.Graph do
  @moduledoc """
  The `graph.v1` documents and their overlays (plan E13a): what a renderer draws, in
  the dashboard or in EHOS Console, as the engine gives it.

      GET <mount>/graph                                   contracts and domains, with versions and digests
      GET <mount>/graph/My.Contract                       a contract's document, its digest as the ETag
      GET <mount>/graph/My.Contract/overlay?since=…&until=…   what the log says over it
      GET <mount>/graph/domain/My.Domain                  a domain's document
      GET <mount>/graph/domain/My.Domain/overlay?since=…&until=…

  A contract or a domain the registry does not hold is 404, never an empty graph. A
  document is the same bytes for the same declarations — every object's keys in
  order (`EhOsContract.Graph.Document.encode/2`) — so its digest is a sound `ETag`,
  and a request that already holds it (`If-None-Match`) gets 304. An overlay has no
  ETag: the log moves under it.

  Authenticated through the same resolver as the model and AsyncAPI: the documents
  carry the client's domain language and authorization surface, the overlays volume
  data about its business.
  """

  @behaviour Plug

  import Plug.Conn

  alias EhOsContract.Graph.{Document, Overlay}
  alias EhOsContract.Registry

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    conn = EhOsContract.Web.Api.Authorize.call(conn, opts)

    if conn.halted do
      conn
    else
      conn = fetch_query_params(conn)
      overlay? = Keyword.get(opts, :overlay, false)

      case {conn.path_params, Keyword.get(opts, :of, :contract)} do
        {%{"domain" => name}, :domain} -> domain(conn, name, overlay?)
        {%{"contract" => name}, :contract} -> contract(conn, name, overlay?)
        _index -> json(conn, 200, Document.encode(index()))
      end
    end
  end

  defp index do
    contracts = Registry.contracts()

    %{
      "schema" => "eh_os_contract.graph-index.v1",
      "contracts" =>
        contracts
        |> Enum.map(fn c ->
          d = Document.contract(c)
          %{"contract" => d["contract"], "version" => d["version"], "digest" => d["digest"]}
        end)
        |> Enum.sort_by(& &1["contract"]),
      "domains" =>
        Registry.domains()
        |> Enum.map(fn m ->
          d = Document.domain(m, contracts)

          %{
            "domain" => d["domain"],
            "name" => d["name"],
            "version" => d["version"],
            "digest" => d["digest"]
          }
        end)
        |> Enum.sort_by(& &1["domain"])
    }
  end

  defp contract(conn, name, overlay?) do
    case Enum.find(Registry.contracts(), &(inspect(&1) == name)) do
      nil -> not_found(conn, "unknown contract #{name}")
      c when overlay? -> overlay(conn, &Overlay.contract(c, &1))
      c -> document(conn, Document.contract(c))
    end
  end

  defp domain(conn, name, overlay?) do
    contracts = Registry.contracts()

    case Enum.find(Registry.domains(), &(inspect(&1) == name)) do
      nil -> not_found(conn, "unknown domain #{name}")
      d when overlay? -> overlay(conn, &Overlay.domain(d, contracts, &1))
      d -> document(conn, Document.domain(d, contracts))
    end
  end

  defp document(conn, document) do
    etag = ~s("#{document["digest"]}")
    conn = put_resp_header(conn, "etag", etag)

    if held?(conn, etag),
      do: send_resp(conn, 304, ""),
      else: json(conn, 200, Document.encode(document))
  end

  # Whether the request already holds this version: any tag of its `If-None-Match`,
  # compared weakly as RFC 9110 says for that header, or `*`.
  defp held?(conn, etag) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&(&1 |> String.trim() |> String.replace_prefix("W/", "")))
    |> Enum.any?(&(&1 in [etag, "*"]))
  end

  defp overlay(conn, build) do
    with {:ok, since} <- at(conn.params["since"], "since"),
         {:ok, until} <- at(conn.params["until"], "until") do
      json(conn, 200, Document.encode(build.(since: since, until: until)))
    else
      {:error, detail} ->
        json(conn, 400, Jason.encode!(%{"error" => "bad_request", "detail" => detail}))
    end
  end

  defp at(nil, _which), do: {:ok, nil}

  defp at(value, which) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at}
      {:error, _} -> {:error, "#{which} is not an ISO 8601 timestamp"}
    end
  end

  # `?since[]=…` or `?since[a]=…` decodes to a list or a map: bad input, not a defect.
  defp at(_value, which), do: {:error, "#{which} is not an ISO 8601 timestamp"}

  defp not_found(conn, detail),
    do: json(conn, 404, Jason.encode!(%{"error" => "not_found", "detail" => detail}))

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end
end
