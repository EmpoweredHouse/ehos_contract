defmodule EhOsContract.Auth.TestingTest do
  @moduledoc """
  `EhOsContract.Auth.Testing.assert_every_entry_refuses/3` asks a door for every
  capability a person may hold, and none for `<name>.subscribe` (plan E12c), which is
  the application's.
  """

  use ExUnit.Case, async: true

  defmodule Domain do
    @moduledoc false
    use EhOsContract.Domain, name: :testing_rig, language: :en

    subdomain(:core, "Core", type: :core)
    context(:stock, "Stock", subdomain: :core)

    actor(:scheduler, :system, "Scheduler")
  end

  defmodule Stock do
    @moduledoc false
    use EhOsContract.Contract, domain: Domain, context: :stock, id: "testing_rig.stock"

    subscribe "other_shop.order.placed.v1", as: :order_placed do
      field(:order_id, :id)
    end

    aggregate :reservation, "Reservation" do
      identity(:order_id)
      command(:reserve, "Reserve", by: :scheduler, emits: :reserved)
      event(:reserved, "Reserved")
    end

    policy(:reserve_for_order, "Reserve for an order", handles: :order_placed, issues: :reserve)
  end

  test "a contract that consumes another application's event needs no door for it" do
    assert Map.keys(EhOsContract.Model.capabilities(Stock)) == [
             "other_shop.order.placed.subscribe"
           ]

    assert EhOsContract.Auth.Testing.assert_every_entry_refuses(Stock, %{}) == :ok
  end

  test "and a door named for it is one the contracts do not declare" do
    error =
      assert_raise ExUnit.AssertionError, fn ->
        EhOsContract.Auth.Testing.assert_every_entry_refuses(Stock, %{
          "other_shop.order.placed.subscribe" => fn _token -> :ok end
        })
      end

    assert error.message =~ "not declared: other_shop.order.placed.subscribe"
  end
end

defmodule EhOsContract.Auth.TestingSignInTest do
  @moduledoc """
  `EhOsContract.Auth.Testing.sign_in/3` and `sign_out/1` (#443): a browser signed in
  without EHOS, which `EhOsContract.Auth.Session` lets through as it does one signed in
  through EHOS, and signed out again.

  Not async: the key process reads and writes the table outside the test process.
  """

  use EhOsContract.Auth.KeyCase, async: false

  import Plug.Test

  alias EhOsContract.Actor
  alias EhOsContract.Auth.{Session, SignIn, Testing}

  setup do
    keys = start_keys(ehos({:keys, [key_pair()]}))
    %{keys: keys, sign_in: :"sign_in_#{System.unique_integer([:positive])}"}
  end

  test "a browser signed in passes the session plug, with the actor of its credential",
       context do
    token = Testing.sign_in("u-anna", ["clinic.record_payment"], opts(context))

    conn = page(context, token)

    refute conn.halted
    assert %{subject: "u-anna"} = conn.assigns.eh_os_contract_session

    assert %Actor{kind: :credential, subject: "u-anna", capabilities: capabilities} =
             conn.assigns.eh_os_contract_actor

    assert MapSet.member?(capabilities, "clinic.record_payment")

    assert {:ok, %Actor{subject: "u-anna"}} =
             Session.actor(%{Session.session_key() => token}, opts(context))
  end

  test "signed out, the page sends a navigation to sign in and refuses anything else",
       context do
    token = Testing.sign_in("u-anna", [], opts(context))

    assert Testing.sign_out(token) == :ok
    assert Testing.sign_out(token) == :ok

    assert page(context, token).status == 401

    navigation = page(context, token, [{"accept", "text/html"}])
    assert navigation.status == 302

    assert {:error, :signed_out} =
             Session.actor(%{Session.session_key() => token}, opts(context))
  end

  test "the stand-in is started once, and a second browser shares it", context do
    first = Testing.sign_in("u-anna", [], opts(context))
    config = SignIn.config(context.sign_in)
    second = Testing.sign_in("u-bob", [], opts(context))

    assert SignIn.config(context.sign_in) == config
    assert first != second
    assert page(context, second).assigns.eh_os_contract_session.subject == "u-bob"
  end

  test "browsers signed in at once, while the stand-in starts, all find it", context do
    tokens =
      1..20
      |> Enum.map(fn i ->
        Task.async(fn -> Testing.sign_in("u-#{i}", [], opts(context)) end)
      end)
      |> Task.await_many()

    assert length(Enum.uniq(tokens)) == 20
  end

  test "asked to refresh, the stand-in answers that EHOS is unavailable, and keeps its sessions",
       context do
    token = Testing.sign_in("u-anna", [], opts(context))

    assert SignIn.refresh(context.sign_in) == {:error, :ehos_unavailable}
    assert page(context, token).assigns.eh_os_contract_session.subject == "u-anna"
  end

  test "past the credential's ten minutes, the stand-in cannot renew it", context do
    token = Testing.sign_in("u-anna", [], opts(context))
    later = DateTime.add(EhOsContract.Clock.now(), 11 * 60)

    assert {:error, :ehos_unavailable} =
             EhOsContract.Clock.at(later, fn ->
               Session.actor(%{Session.session_key() => token}, opts(context))
             end)
  end

  defp opts(context), do: [sign_in: context.sign_in, keys: context.keys]

  defp page(context, token, headers \\ []) do
    conn =
      Enum.reduce(headers, conn(:get, "/visits/7"), fn {key, value}, conn ->
        Plug.Conn.put_req_header(conn, key, value)
      end)

    conn
    |> init_test_session(%{Session.session_key() => token})
    |> Session.call(
      Session.init(sign_in: context.sign_in, keys: context.keys, assign_actor: true)
    )
  end
end
