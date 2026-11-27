defmodule EhosContract.QueryStringTest do
  @moduledoc """
  #618: a query's params reach its implementation the same whether a client sends the
  query string the OpenAPI document describes, through `EhosContract.Plug`, or code sends
  the equivalent JSON map to `EhosContract.call/3`. `QueryRig.Desk`'s query takes a param
  of every shape the compiler accepts; a shape it does not carry is refused at compile
  time (P7, `EhosContract.ContractLinksDomainTest`).
  """

  use EhosContract.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias EhosContract.{Actor, OpenAPI}

  @capability "query_rig.find_visits"
  @path "/queries/#{@capability}"
  @clerk Actor.credential("u-1", [@capability])
  @opts EhosContract.Plug.init(contracts: [QueryRig.Desk])

  @full %{
    "text" => "a b&c=d ąę/?#[]",
    "count" => 42,
    "price" => "12.50",
    "urgent" => true,
    "day" => "2026-11-27",
    "at" => "2026-11-27T10:15:00Z",
    "id" => "v-1",
    "desk" => "desk-1",
    "kind" => "booked",
    "minutes" => 30,
    "room" => "r-1",
    "ids" => ["a-1", "a-2"],
    "counts" => [1, 2, 3],
    "kinds" => ["walk_in", "booked"],
    "rooms" => ["r-1", "r-2"],
    "tags" => ["x", "y z"],
    "window" => %{"from" => "2026-11-01", "to" => "2026-11-30"},
    "need" => %{"service_id" => "s-1", "minutes" => 45, "urgent" => false, "note" => "n"},
    "need_ref" => %{"service_id" => "s-2", "minutes" => 15, "urgent" => true},
    "missing_need" => %{"service_id" => "s-3", "minutes" => 5, "urgent" => true}
  }

  # Lists of one, and the optional params and the optional field left out.
  @short @full
         |> Map.merge(%{
           "ids" => ["a-1"],
           "counts" => [7],
           "kinds" => ["walk_in"],
           "rooms" => ["r-9"],
           "tags" => ["only"]
         })
         |> Map.update!("need", &Map.delete(&1, "note"))
         |> Map.delete("missing_need")

  for {name, params} <- [
        {"every param", @full},
        {"lists of one, optional params left out", @short}
      ] do
    test "#{name}: the request the document describes decodes as the JSON map does" do
      params = unquote(Macro.escape(params))
      parameters = parameters()

      # Every param the query declares is described, so none escapes the comparison.
      [query] = EhosContract.Model.fetch(QueryRig.Desk).queries
      declared = Enum.map(query.params, &to_string(&1.name))
      assert Enum.sort(Enum.map(parameters, & &1["name"])) == Enum.sort(declared)

      query_string =
        parameters
        |> Enum.filter(&Map.has_key?(params, &1["name"]))
        |> Enum.flat_map(&encode(&1, Map.fetch!(params, &1["name"])))
        |> URI.encode_query()

      conn =
        conn(:get, "#{@path}?#{query_string}")
        |> assign(:ehos_contract_actor, @clerk)
        |> EhosContract.Plug.call(@opts)

      assert {conn.status, Jason.decode!(conn.resp_body)} == {200, %{"rows" => []}}
      assert_received {:query_rig_params, over_http}

      assert {:ok, []} = EhosContract.call({:query, @capability}, params, actor: @clerk)
      assert_received {:query_rig_params, from_json}

      assert over_http == from_json

      # Both read every param given, not a nil each.
      for {name, _value} <- params,
          do: refute(Map.fetch!(from_json, String.to_existing_atom(name)) == nil, name)
    end
  end

  defp parameters do
    OpenAPI.document(QueryRig.Desk)["paths"][@path]["get"]["parameters"]
  end

  # The pairs OpenAPI 3.1's `style` and `explode` give a value (its "Style Values"
  # table), and nothing the document does not say: a form it does not define fails.
  defp encode(%{"name" => name, "style" => "form", "explode" => true}, values)
       when is_list(values),
       do: Enum.map(values, &{name, text(name, &1)})

  defp encode(%{"name" => name, "style" => "form", "explode" => true}, value),
    do: [{name, text(name, value)}]

  defp encode(%{"name" => name, "style" => "deepObject", "explode" => true}, %{} = object),
    do: for({key, value} <- object, do: {"#{name}[#{key}]", text("#{name}.#{key}", value)})

  defp encode(parameter, value),
    do: flunk("OpenAPI gives no form to #{inspect(value)} as #{inspect(parameter)}")

  defp text(_name, value) when is_binary(value), do: value
  defp text(_name, value) when is_integer(value) or is_boolean(value), do: to_string(value)

  defp text(name, value),
    do: flunk("OpenAPI gives no form to #{inspect(value)} in #{name} of a query string")
end
