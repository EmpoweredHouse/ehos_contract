defmodule EhOsContract.Web.Api.OpenAPI do
  # The generated OpenAPI document for one v2 contract, or the index of all of them.
  #
  # `GET <mount>/openapi` lists each contract with its version and document digest.
  # `GET <mount>/openapi/<contract id>` serves that contract's command-and-query API,
  # with the digest both in `info["x-eh-os-contract-digest"]` and as the `ETag`.
  #
  # The same host resolver that protects conformance, model and AsyncAPI documents
  # protects these routes. They expose the contract's authorization surface and
  # business language, even though they contain no business data.
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    conn = EhOsContract.Web.Api.Authorize.call(conn, opts)

    if conn.halted do
      conn
    else
      case conn.path_params["contract"] do
        nil -> json(conn, 200, %{"contracts" => EhOsContract.OpenAPI.index()})
        name -> one(conn, name)
      end
    end
  end

  @spec one(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  defp one(conn, name) do
    case EhOsContract.Registry.contract(name) do
      nil ->
        json(conn, 404, %{"error" => "not_found", "detail" => "unknown contract #{name}"})

      contract ->
        document = EhOsContract.OpenAPI.document(contract)

        conn
        |> put_resp_header("etag", ~s("#{document["info"]["x-eh-os-contract-digest"]}"))
        |> json(200, document)
    end
  end

  @spec json(Plug.Conn.t(), pos_integer(), map()) :: Plug.Conn.t()
  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode_to_iodata!(body))
  end
end
