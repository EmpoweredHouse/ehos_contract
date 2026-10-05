defmodule EhOsContract.SuppliedTest do
  @moduledoc """
  Plan T1: a field declared `supplied_by: :host` is refused from a request through
  `EhOsContract.call/3` and asked of the `EhOsContract.Supplier` instead, once the
  caller is authorized; the application's own `dispatch/3` is trusted and not asked.
  On `SupplyRig.Desk`, with `SupplyRig.Supplier` configured for the suite.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Actor, CommandRecord, Event, Receipt, Supplier}

  @clerk Actor.credential("u-1", ["supply_rig.close_visit", "supply_rig.arrival_noted"])
  @stranger Actor.credential("u-9", [])

  defp close(input, actor \\ @clerk),
    do: EhOsContract.call({:command, "supply_rig.close_visit"}, input, actor: actor)

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
  defp events, do: repo().all(Event)
  defp rows, do: repo().all(CommandRecord)

  describe "through call/3" do
    test "the value is the host's, and the host sees the actor and what the request gave" do
      assert {:ok, %Receipt{}} = close(%{"visit_id" => "v-1", "code" => "A1"})

      assert [%{payload: %{"code" => "A1", "reported" => true}}] = events()

      assert {@clerk,
              %Supplier.Request{
                kind: :command,
                capability: "supply_rig.close_visit",
                contract: SupplyRig.Desk,
                name: :close_visit,
                fields: [:reported],
                given: %{visit_id: "v-1", code: "A1"}
              }} = Process.get(:supply_rig_asked)
    end

    test "a caller that sends the field is refused by name, also when it sends null" do
      for sent <- [false, nil] do
        assert close(%{"visit_id" => "v-1", "code" => "A1", "reported" => sent}) ==
                 {:error, {:invalid, [reported: :supplied]}}
      end

      assert close(%{"visit_id" => "v-1", "reported" => true}) ==
               {:error, {:invalid, [code: :required, reported: :supplied]}},
             "named beside what else is wrong"

      assert events() == []
      assert Process.get(:supply_rig_asked) == nil
    end

    test "a caller that may not issue the command is refused first, and the host is not asked" do
      assert close(%{"visit_id" => "v-1", "code" => "A1"}, @stranger) ==
               {:error, :missing_capability}

      assert close(%{"visit_id" => "v-1", "reported" => true}, @stranger) ==
               {:error, :missing_capability},
             "what it sent is not described to a caller without the capability"

      assert Process.get(:supply_rig_asked) == nil
    end

    test "the host's refusal is not_supplied, and nothing is written" do
      Process.put(:supply_rig_answer, {:error, :register_down})

      assert close(%{"visit_id" => "v-1", "code" => "A1"}) ==
               {:error, {:not_supplied, :register_down}}

      assert events() == []
      assert rows() == []
    end

    test "a recorded event's field is supplied the same way" do
      assert {:ok, %Receipt{}} =
               EhOsContract.call({:record, "supply_rig.arrival_noted"}, %{"visit_id" => "v-1"},
                 actor: @clerk
               )

      assert [%{payload: %{"arrived_at" => arrived_at}}] = events()
      assert arrived_at == DateTime.to_iso8601(SupplyRig.Supplier.arrived_at())

      assert {_actor, %Supplier.Request{kind: :record, fields: [:arrived_at]}} =
               Process.get(:supply_rig_asked)
    end
  end

  describe "the host's answer is held to what it was asked" do
    test "other fields than asked for raise, naming them" do
      Process.put(:supply_rig_answer, {:ok, %{reported: true, code: "B2"}})

      error = assert_raise ArgumentError, fn -> close(%{"visit_id" => "v-1", "code" => "A1"}) end

      assert error.message =~
               "was asked for [:reported] of command :close_visit and answered [:code, :reported]"
    end

    test "a value that does not fit raises, naming the field and not the value" do
      Process.put(:supply_rig_answer, {:ok, %{reported: "yes, sent on Monday"}})

      error = assert_raise ArgumentError, fn -> close(%{"visit_id" => "v-1", "code" => "A1"}) end
      assert error.message =~ "with fields that do not fit: [reported: :type]"
      refute error.message =~ "Monday"
    end

    test "an answer of another shape raises, describing its shape only" do
      Process.put(:supply_rig_answer, %{reported: true})

      error = assert_raise ArgumentError, fn -> close(%{"visit_id" => "v-1", "code" => "A1"}) end
      assert error.message =~ "returned a bare map for command :close_visit"
    end
  end

  test "dispatch/3 from the application's own code is trusted, and the host is not asked" do
    command = %SupplyRig.Desk.Commands.CloseVisit{visit_id: "v-1", code: "A1", reported: false}

    assert {:ok, %Receipt{}} = EhOsContract.dispatch(SupplyRig.Desk, command, actor: @clerk)
    assert [%{payload: %{"reported" => false}}] = events()
    assert Process.get(:supply_rig_asked) == nil
  end

  describe "over HTTP" do
    import Plug.Conn
    import Plug.Test

    @opts EhOsContract.Plug.init(contracts: [SupplyRig.Desk])

    defp post(body) do
      conn(:post, "/commands/supply_rig.close_visit", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> assign(:eh_os_contract_actor, @clerk)
      |> EhOsContract.Plug.call(@opts)
    end

    test "the field sent is 422 supplied; the host's refusal is 503, its reason kept out" do
      conn = post(%{visit_id: "v-1", code: "A1", reported: true})
      assert conn.status == 422
      assert Jason.decode!(conn.resp_body) == %{"invalid" => %{"reported" => "supplied"}}

      Process.put(:supply_rig_answer, {:error, :register_down})
      conn = post(%{visit_id: "v-1", code: "A1"})
      assert conn.status == 503
      assert Jason.decode!(conn.resp_body) == %{"error" => "not_supplied"}
    end

    test "the OpenAPI document does not offer the field to send" do
      schema =
        EhOsContract.OpenAPI.document(SupplyRig.Desk)["paths"]["/commands/supply_rig.close_visit"][
          "post"
        ]["requestBody"]["content"]["application/json"]["schema"]

      assert Map.has_key?(schema["properties"], "code")
      refute Map.has_key?(schema["properties"], "reported")
    end
  end

  test "a node with a supplied field and no supplier does not start, naming both" do
    supplier = Application.fetch_env!(:eh_os_contract, :supplier)
    Application.delete_env(:eh_os_contract, :supplier)
    on_exit(fn -> Application.put_env(:eh_os_contract, :supplier, supplier) end)

    error = assert_raise ArgumentError, fn -> EhOsContract.Registry.load!(:eh_os_contract) end

    assert error.message =~
             "SupplyRig.Desk declares [:reported] of command :close_visit supplied_by: :host, " <>
               "and no supplier is configured"
  end
end
