defmodule EhOsContract.Auth.ApplicationNameTest do
  @moduledoc """
  The application `audience` names in EHOS is the `name:` of one domain with contracts,
  and every other domain with contracts publishes nothing, or the boot is refused (#180).

  The domains and contracts below are invented for this test, a clinic and a shop,
  each in an OTP application loaded here so that the engine's scan finds it as it
  finds a host's.
  """

  use ExUnit.Case, async: false

  defmodule ClinicDomain do
    @moduledoc false
    use EhOsContract.Domain, name: :clinic, language: :en

    subdomain(:core, "Core", type: :core)
    context(:visits, "Visits", subdomain: :core)
    actor(:desk, :system, "Desk")
  end

  defmodule ClinicVisits do
    @moduledoc false
    use EhOsContract.Contract, domain: ClinicDomain, context: :visits, id: "clinic.visits"

    aggregate :visit, "Visit" do
      identity(:visit_id)
      command(:close_visit, "Close a visit", by: :desk, emits: :visit_closed)
      event(:visit_closed, "Visit closed")
    end
  end

  defmodule ShopDomain do
    @moduledoc false
    use EhOsContract.Domain, name: :my_shop, language: :en

    subdomain(:core, "Core", type: :core)
    context(:orders, "Orders", subdomain: :core)
    actor(:till, :system, "Till")
  end

  defmodule ShopOrders do
    @moduledoc false
    use EhOsContract.Contract, domain: ShopDomain, context: :orders, id: "my_shop.orders"

    aggregate :order, "Order" do
      identity(:order_id)
      command(:place_order, "Place an order", by: :till, emits: :order_placed)
      event(:order_placed, "Order placed")
    end
  end

  defmodule ShopPayments do
    @moduledoc false
    use EhOsContract.Contract, domain: ShopDomain, context: :orders, id: "my_shop.payments"

    aggregate :payment, "Payment" do
      identity(:payment_id)
      command(:take_payment, "Take a payment", by: :till, emits: :payment_taken)
      event(:payment_taken, "Payment taken")
    end

    publish(:payment_taken,
      as: "my-shop.payment.taken.v1",
      from: :payment_taken,
      fields: [:payment_id]
    )
  end

  setup do
    engine = Application.get_env(:eh_os_contract, :applications)
    audience = Application.get_env(:eh_os_contract_auth, :audience)

    on_exit(fn ->
      Application.put_env(:eh_os_contract, :applications, engine)
      Application.put_env(:eh_os_contract_auth, :audience, audience)
      for app <- [:auth_rig_clinic, :auth_rig_shop, :auth_rig_both], do: :application.unload(app)
      EhOsContract.Registry.load!()
    end)
  end

  test "an application deployed under no domain's name refuses to start" do
    error =
      assert_raise ArgumentError, fn ->
        boot(:auth_rig_clinic, [ClinicDomain, ClinicVisits], "billing-app/prod")
      end

    assert error.message =~ ~s(audience: "billing-app/prod" names the application billing-app)
    assert error.message =~ "the domain clinic (#{inspect(ClinicDomain)})"
    assert error.message =~ ~s(rename the domain to name: :"billing-app")
    assert error.message =~ "register the application in EHOS as clinic"
  end

  test "with several domains, none of them the application's, the boot is refused naming each" do
    error =
      assert_raise ArgumentError, fn ->
        boot(:auth_rig_both, [ClinicDomain, ClinicVisits, ShopDomain, ShopOrders], "billing/prod")
      end

    assert error.message =~
             "the domains clinic (#{inspect(ClinicDomain)}), my_shop (#{inspect(ShopDomain)})"
  end

  test "an application deployed under its domain's name starts" do
    assert %{start: _} = boot(:auth_rig_clinic, [ClinicDomain, ClinicVisits], "clinic/prod")
  end

  test "a domain named with _ starts under EHOS's spelling of it, with -" do
    assert %{start: _} = boot(:auth_rig_shop, [ShopDomain, ShopOrders], "my-shop/prod")
    assert %{start: _} = boot(:auth_rig_shop, [ShopDomain, ShopOrders], "my_shop/prod")
  end

  test "another domain with contracts that publishes nothing does not stop the boot" do
    assert %{start: _} =
             boot(
               :auth_rig_both,
               [ClinicDomain, ClinicVisits, ShopDomain, ShopOrders],
               "clinic/prod"
             )
  end

  test "another domain with contracts that publishes refuses the boot, naming its publication" do
    error =
      assert_raise ArgumentError, fn ->
        boot(
          :auth_rig_both,
          [ClinicDomain, ClinicVisits, ShopDomain, ShopOrders, ShopPayments],
          "clinic/prod"
        )
      end

    assert error.message =~ "whose domain is clinic (#{inspect(ClinicDomain)})"

    assert error.message =~
             "the domain my_shop (#{inspect(ShopDomain)}): " <>
               "#{inspect(ShopPayments)} publishes my-shop.payment.taken.v1"

    refute error.message =~ inspect(ShopOrders)
  end

  test "the publishing domain may be the application's" do
    assert %{start: _} =
             boot(
               :auth_rig_both,
               [ClinicDomain, ClinicVisits, ShopDomain, ShopOrders, ShopPayments],
               "my-shop/prod"
             )
  end

  test "a domain without contracts is not compared" do
    assert %{start: _} =
             boot(:auth_rig_clinic, [ClinicDomain, ClinicVisits, ShopDomain], "clinic/prod")
  end

  # The child itself refuses to start without an audience (`PackageTest`); a host without it
  # checks nothing, and neither does the check without an audience to compare.
  test "with no audience, nothing is checked" do
    assert EhOsContract.Auth.check_application!(nil, [ClinicVisits, ShopOrders]) == :ok
  end

  defp boot(app, modules, audience) do
    :application.unload(app)

    :ok =
      :application.load(
        {:application, app,
         [description: ~c"rig", vsn: ~c"0", modules: modules, registered: [], applications: []]}
      )

    Application.put_env(:eh_os_contract, :applications, [app])
    Application.put_env(:eh_os_contract_auth, :audience, audience)
    EhOsContract.Auth.child_spec([])
  end
end
