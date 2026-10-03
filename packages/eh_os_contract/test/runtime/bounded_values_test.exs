defmodule EhOsContract.BoundedValuesTest do
  @moduledoc """
  Values a request controls are bounded where what holds them is: a decimal finite and
  of a size its log form can be written in, an identifier no longer than an index entry
  can key, an integer within a 64-bit column, a date within the years Postgres keeps.
  Past a bound a value does not fit its type, `{field, :type}`, rather than failing a
  write or a host's read model later. Reading the log back asks none of it: what was
  written before the bounds still reads.
  """

  use EhOsContract.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias EhOsContract.{Actor, Codec}

  @opts EhOsContract.Plug.init(contracts: [DispatchRig.Ledger, DispatchRig.Transfer])
  @clerk Actor.credential("u-1", ["dispatch_rig.open_account", "dispatch_rig.deposit"])

  defp field(type), do: [%{name: :value, type: type, optional: false}]
  defp decoded(type, value), do: Codec.decode(field(type), %{"value" => value}, %{})

  defp http(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", "req-#{System.unique_integer([:positive])}")
    |> assign(:eh_os_contract_actor, @clerk)
    |> EhOsContract.Plug.call(@opts)
  end

  describe "a decimal" do
    test "is finite, with an exponent and a coefficient of at most a thousand digits" do
      for value <- [
            "NaN",
            "Infinity",
            "-Infinity",
            "1E1001",
            "1E-1001",
            String.duplicate("9", 1001)
          ] do
        assert decoded(:decimal, value) == {:error, [value: :type]}, value
      end

      # Decimal itself parses text within decimal128: at most 34 digits, an exponent to 6144.
      for value <- ["1E1000", "1E-1000", String.duplicate("9", 34), "12.50", 7] do
        assert {:ok, %{value: %Decimal{}}} = decoded(:decimal, value), inspect(value)
      end
    end

    # A struct a host's code built would otherwise fail at the append, where `:normal`
    # refuses to write past its digits.
    test "a struct past the bounds is a problem, not an exception at the write" do
      assert Codec.problems(field(:decimal), %{value: Decimal.new(1, 1, 50_000)}, %{}) ==
               [value: :type]

      assert Codec.problems(
               field(:decimal),
               %{value: Decimal.new(1, Integer.pow(10, 1000), 0)},
               %{}
             ) ==
               [value: :type]

      assert Codec.problems(field(:decimal), %{value: Decimal.new("NaN")}, %{}) == [value: :type]
      assert Codec.problems(field(:decimal), %{value: Decimal.new("12.50")}, %{}) == []
    end
  end

  describe "an identifier" do
    test "is at most 255 bytes, over HTTP and from code" do
      long = String.duplicate("a", 256)

      conn = http("/commands/dispatch_rig.open_account", %{account_id: long, branch_id: "b-7"})

      assert {conn.status, Jason.decode!(conn.resp_body)} ==
               {422, %{"invalid" => %{"account_id" => "type"}}}

      assert Codec.problems(field(:id), %{value: long}, %{}) == [value: :type]

      assert decoded(:id, long) == {:error, [value: :type]}

      # And a query's parameter.
      auditor = Actor.credential("u-2", ["dispatch_rig.balance_of"])

      query =
        conn(:get, "/queries/dispatch_rig.balance_of?account_id=#{long}")
        |> assign(:eh_os_contract_actor, auditor)
        |> EhOsContract.Plug.call(@opts)

      assert {query.status, Jason.decode!(query.resp_body)} ==
               {422, %{"invalid" => %{"account_id" => "type"}}}

      ok =
        http("/commands/dispatch_rig.open_account", %{
          account_id: String.duplicate("a", 255),
          branch_id: "b-7"
        })

      assert ok.status == 200
    end
  end

  describe "an integer" do
    test "is within a signed 64-bit integer" do
      {:ok, _} =
        EhOsContract.call(
          {:command, "dispatch_rig.open_account"},
          %{"account_id" => "a-1", "branch_id" => "b-7"},
          actor: @clerk
        )

      conn = http("/commands/dispatch_rig.deposit", %{account_id: "a-1", amount: 2 ** 63})

      assert {conn.status, Jason.decode!(conn.resp_body)} ==
               {422, %{"invalid" => %{"amount" => "type"}}}

      assert decoded(:integer, -(2 ** 63) - 1) == {:error, [value: :type]}
      assert {:ok, %{value: 9_223_372_036_854_775_807}} = decoded(:integer, 2 ** 63 - 1)
      assert Codec.problems(field(:integer), %{value: 2 ** 70}, %{}) == [value: :type]
    end
  end

  describe "a date and a timestamp" do
    test "are within the years 1 to 9999" do
      for {type, value} <- [
            {:date, "0000-12-31"},
            {:date, "-0001-01-01"},
            {:timestamp, "0000-01-01T00:00:00Z"}
          ] do
        assert decoded(type, value) == {:error, [value: :type]}, value
      end

      assert {:ok, _} = decoded(:date, "0001-01-01")
      assert {:ok, _} = decoded(:date, "9999-12-31")
      assert {:ok, _} = decoded(:timestamp, "9999-12-31T23:59:59Z")
      assert Codec.problems(field(:date), %{value: ~D[0000-01-01]}, %{}) == [value: :type]
    end
  end

  test "reading the log back asks none of it" do
    open = fn _path, _subject, value -> {:ok, value} end

    fields = [
      %{name: :value, type: :integer, optional: false},
      %{name: :id, type: :id, optional: false}
    ]

    stored = %{"value" => 2 ** 70, "id" => String.duplicate("a", 300)}

    assert {:ok, %{value: value}} = Codec.decode(fields, stored, %{}, open: open)
    assert value == 2 ** 70

    for {type, raw} <- [
          {:decimal, "NaN"},
          {:date, "0000-01-01"},
          {:timestamp, "0000-01-01T00:00:00Z"}
        ] do
      assert {:ok, _} = Codec.decode(field(type), %{"value" => raw}, %{}, open: open), raw
      assert decoded(type, raw) == {:error, [value: :type]}, raw
    end
  end

  test "over HTTP, a query string that is not UTF-8 is a 400, after the caller may ask" do
    auditor = Actor.credential("u-2", ["dispatch_rig.balance_of"])

    conn =
      conn(:get, "/queries/dispatch_rig.balance_of?account_id=%FF")
      |> assign(:eh_os_contract_actor, auditor)
      |> EhOsContract.Plug.call(@opts)

    assert {conn.status, Jason.decode!(conn.resp_body)} ==
             {400, %{"error" => "invalid_query_string"}}

    stranger =
      conn(:get, "/queries/dispatch_rig.balance_of?account_id=%FF")
      |> assign(:eh_os_contract_actor, Actor.credential("u-3", []))
      |> EhOsContract.Plug.call(@opts)

    assert stranger.status == 403

    # Past Plug's length a query string is 414, as Plug says, not a 400.
    long =
      conn(
        :get,
        "/queries/dispatch_rig.balance_of?account_id=" <> String.duplicate("a", 1_000_001)
      )
      |> assign(:eh_os_contract_actor, auditor)
      |> EhOsContract.Plug.call(@opts)

    assert {long.status, Jason.decode!(long.resp_body)} ==
             {414, %{"error" => "invalid_query_string"}}
  end
end
