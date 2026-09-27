defmodule EhOsContract.ValueInvariantsTest do
  @moduledoc """
  The invariants of domain values at run time (plan EL2b): a command, a recorded event
  and a query's parameters are refused with the invariant a value breaks, an event a
  decision returns with one raises, and so does a domain service's call — the items
  of a list, the fields of a value with fields and the value an alias stands for
  included, and each before the value's own.
  """

  use EhOsContract.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias EhOsContract.{Actor, CommandRecord, Event}
  alias ValueRig.Till
  alias ValueRig.Till.Commands.{PayIn, ShortChange}
  alias ValueRig.Till.DomainServices.Splitting
  alias ValueRig.Till.Events.Counted
  alias ValueRig.Till.Queries.PaymentsAbove

  @cashier Actor.credential("u-1", [
             "value_rig.pay_in",
             "value_rig.short_change",
             "value_rig.payments_above"
           ])

  defp pay(fields),
    do: EhOsContract.dispatch(Till, struct!(PayIn, [till_id: "t-1"] ++ fields), actor: @cashier)

  defp log, do: Repo.all(from(e in Event, order_by: e.position))
  defp rows, do: Repo.all(CommandRecord)

  describe "a command" do
    test "whose values keep their invariants is accepted" do
      assert {:ok, _receipt} =
               pay(
                 amount: 250,
                 fees: [1, 1000],
                 window: %{from: ~D[2026-01-01], to: ~D[2026-01-01]},
                 payment: %{amount: 1, note: nil}
               )

      assert [%{type: "till.paid_in"}] = log()
    end

    test "carrying a value that breaks one is refused with it, before anything is decided" do
      assert pay(amount: 0) == {:error, {:invalid, [amount: {:invariant, :positive}]}}
      assert log() == []
      assert rows() == []
    end

    test "is held to the invariants of a list's items, of a value's fields, and of an alias" do
      assert pay(amount: 1, fees: [1000, 1001]) ==
               {:error, {:invalid, [fees: {:invariant, :capped}]}}

      # A fee is an amount: the amount's invariant is asked before the fee's own.
      assert pay(amount: 1, fees: [0]) == {:error, {:invalid, [fees: {:invariant, :positive}]}}

      assert pay(amount: 1, window: %{from: ~D[2026-02-01], to: ~D[2026-01-31]}) ==
               {:error, {:invalid, [window: {:invariant, :in_order}]}}

      assert pay(amount: 1, payment: %{amount: -5, note: "tip"}) ==
               {:error, {:invalid, [payment: {:invariant, :positive}]}}
    end

    test "that does not fit its types is refused on the type, and no invariant is asked" do
      Process.put(:value_rig_amount_answers, :never_asked)
      assert pay(amount: "a lot") == {:error, {:invalid, [amount: :type]}}
      assert Process.delete(:value_rig_amount_answers) == :never_asked
    end
  end

  test "an event a decision returns with a value that breaks an invariant raises, and nothing is appended" do
    error =
      assert_raise ArgumentError, fn ->
        EhOsContract.dispatch(Till, %ShortChange{till_id: "t-1"}, actor: @cashier)
      end

    assert error.message =~ "decided event :paid_in with fields that do not fit"
    assert error.message =~ "{:invariant, :positive}"
    assert log() == []
  end

  test "a recorded event carrying a value that breaks an invariant is refused" do
    assert EhOsContract.record(Till, %Counted{till_id: "t-1", amount: -1},
             actor: Actor.system(:counter)
           ) == {:error, {:invalid, [amount: {:invariant, :positive}]}}

    assert log() == []
  end

  test "a query's parameter that breaks an invariant is refused before the query runs" do
    assert EhOsContract.query(Till, %PaymentsAbove{above: 0}, actor: @cashier) ==
             {:error, {:invalid, [above: {:invariant, :positive}]}}

    assert EhOsContract.query(Till, %PaymentsAbove{above: 1}, actor: @cashier) == {:ok, []}
  end

  test "a domain service's result that breaks an invariant raises" do
    assert Splitting.half(5) == 2
    assert Splitting.half(1) == nil

    Process.put(:value_rig_half_of_nothing, true)

    error = assert_raise ArgumentError, fn -> Splitting.half(1) end

    assert error.message =~
             "returned a result that does not fit :amount (it breaks invariant :positive)"
  end

  test "a check that answers neither true nor false raises, without saying what it answered" do
    Process.put(:value_rig_amount_answers, "Jan Kowalski")

    error = assert_raise ArgumentError, fn -> pay(amount: 5) end
    assert error.message =~ "ValueRig.Amount.positive/1 answered neither true nor false"
    refute error.message =~ "Kowalski"
    assert log() == []
  end

  test "over HTTP, the invariant a value breaks is named where its field's problem goes" do
    opts = EhOsContract.Plug.init(contracts: [Till])

    conn =
      conn(:post, "/commands/value_rig.pay_in", Jason.encode!(%{till_id: "t-1", amount: 0}))
      |> put_req_header("content-type", "application/json")
      |> assign(:eh_os_contract_actor, @cashier)
      |> EhOsContract.Plug.call(opts)

    assert {conn.status, Jason.decode!(conn.resp_body)} ==
             {422, %{"invalid" => %{"amount" => "positive"}}}
  end

  test "a value's check is looked up once, not in the index for every value" do
    {:ok, _} = pay(amount: 1)

    apps = Enum.uniq(List.wrap(Application.get_env(:eh_os_contract, :applications)))
    key = {EhOsContract.Implementations, apps}
    index = EhOsContract.Implementations.index(nil)
    on_exit(fn -> :persistent_term.put(key, index) end)

    declarations = Map.delete(index.declarations, {ValueRig.Domain, :value, :amount})
    :persistent_term.put(key, %{index | declarations: declarations})

    assert pay(amount: 0) == {:error, {:invalid, [amount: {:invariant, :positive}]}}
  end

  test "reading the log back never asks: an event written before an invariant still reads" do
    {:ok, _} = pay(amount: 3)
    [row] = log()

    Process.put(:value_rig_amount_answers, false)
    model = EhOsContract.Model.fetch(Till)
    values = EhOsContract.Codec.values(model.domain)
    [event] = EhOsContract.Consumer.decode_all!(model, values, [row])
    assert event.amount == 3
    assert Process.delete(:value_rig_amount_answers) == false
  end
end

defmodule EhOsContract.ValueWithoutImplementationTest do
  @moduledoc """
  Plan EL2b: `value-without-implementation` — a value whose invariants no module
  checks, in a domain some contract of which has code — and dispatch raising on a
  value of it. The index dispatch and `check` read is swapped for one without
  `ValueRig.Amount`, as a host that forgot to write it would have it.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Actor, Implementations}
  alias EhOsContract.Check.{Completeness, Finding}

  setup do
    apps = Enum.uniq(List.wrap(Application.get_env(:eh_os_contract, :applications)))
    key = {Implementations, apps}
    index = Implementations.index(nil)
    on_exit(fn -> :persistent_term.put(key, index) end)

    declarations = Map.delete(index.declarations, {ValueRig.Domain, :value, :amount})
    :persistent_term.put(key, %{index | declarations: declarations})

    # What a check found before, and keeps (`EhOsContract.Value`), goes with it.
    kept = {EhOsContract.Value, ValueRig.Domain, :amount}
    :persistent_term.erase(kept)
    on_exit(fn -> :persistent_term.erase(kept) end)
    :ok
  end

  test "is said of a value nobody checks, at its declaration, and of no other" do
    findings =
      for %Finding{rule: "value-without-implementation"} = f <-
            Completeness.findings([ValueRig.Till]),
          do: {f.message, f.at[:file] |> to_string() |> Path.basename(), f.at[:location]}

    assert [{message, "domain.ex", 16}] = findings

    assert message =~
             "value :amount of ValueRig.Domain declares invariants and no module checks them"

    assert message =~ "`use ValueRig.Domain, value: :amount`"
  end

  test "dispatch raises on a value of it, and names the module to write" do
    error =
      assert_raise ArgumentError, fn ->
        EhOsContract.dispatch(
          ValueRig.Till,
          %ValueRig.Till.Commands.PayIn{till_id: "t-1", amount: 5},
          actor: Actor.credential("u-1", ["value_rig.pay_in"])
        )
      end

    assert error.message =~
             "no module implements value :amount of ValueRig.Domain; bind one with " <>
               "`use ValueRig.Domain, value: :amount`"
  end
end
