defmodule EhOsContract.Web.Api.Model do
  @moduledoc """
  The named v2 model document for one contract, or an index of all of them.

  `GET <mount>/model` lists v2 contracts with their contract version and exported
  document digest. `GET <mount>/model/My.Contract` serves
  `EhOsContract.Model.to_data/1`, with its digest in the body and as the `ETag`.

  Authenticated through the same resolver as conformance and AsyncAPI: the model
  contains the client's domain language and authorization surface.
  """

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
        nil -> json(conn, 200, index())
        name -> one(conn, name)
      end
    end
  end

  @spec index() :: map()
  defp index do
    contracts =
      for contract <- EhOsContract.Registry.contracts(),
          document = EhOsContract.Model.to_data(contract) do
        %{
          "contract" => inspect(contract),
          "version" => EhOsContract.Model.fetch(contract).version,
          "digest" => document["digest"]
        }
      end
      |> Enum.sort_by(& &1["contract"])

    %{"schema" => "eh_os_contract.model-index.v1", "contracts" => contracts}
  end

  @spec one(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  defp one(conn, name) do
    case Enum.find(EhOsContract.Registry.contracts(), &(inspect(&1) == name)) do
      nil ->
        json(conn, 404, %{"error" => "not_found", "detail" => "unknown contract #{name}"})

      contract ->
        document = EhOsContract.Model.to_data(contract)

        conn
        |> put_resp_header("etag", ~s("#{document["digest"]}"))
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
