defmodule EhosContract.Auth.ApplicationNameTest do
  @moduledoc """
  The application `audience` names in EHOS equals the `name:` of one domain with
  contracts exactly, and every other domain with contracts publishes nothing, or the
  boot is refused (#180).

  The domains and contracts below are invented for this test, a clinic and a shop,
  each in an OTP application loaded here so that the engine's scan finds it as it
  finds a host's.
  """

  use ExUnit.Case, async: false

  defmodule ClinicDomain do
    @moduledoc false
    use EhosContract.Domain, name: :clinic, language: :en

    subdomain(:core, "Core", type: :core)
    context(:visits, "Visits", subdomain: :core)
    actor(:desk, :system, "Desk")
  end

  defmodule ClinicVisits do
    @moduledoc false
    use EhosContract.Contract, domain: ClinicDomain, context: :visits, id: "clinic.visits"

    aggregate :visit, "Visit" do
      identity(:visit_id)
      command(:close_visit, "Close a visit", by: :desk, emits: :visit_closed)
      event(:visit_closed, "Visit closed")
    end
  end

  defmodule ShopDomain do
    @moduledoc false
    use EhosContract.Domain, name: :my_shop, language: :en

    subdomain(:core, "Core", type: :core)
    context(:orders, "Orders", subdomain: :core)
    actor(:till, :system, "Till")
  end

  defmodule ShopOrders do
    @moduledoc false
    use EhosContract.Contract, domain: ShopDomain, context: :orders, id: "my_shop.orders"

    aggregate :order, "Order" do
      identity(:order_id)
      command(:place_order, "Place an order", by: :till, emits: :order_placed)
      event(:order_placed, "Order placed")
    end
  end

  defmodule DashedShopDomain do
    @moduledoc false
    use EhosContract.Domain, name: :"my-shop", language: :en

    subdomain(:core, "Core", type: :core)
    context(:orders, "Orders", subdomain: :core)
    actor(:till, :system, "Till")
  end

  defmodule DashedShopOrders do
    @moduledoc false
    use EhosContract.Contract, domain: DashedShopDomain, context: :orders, id: "my-shop.orders"

    aggregate :order, "Order" do
      identity(:order_id)
      command(:place_order, "Place an order", by: :till, emits: :order_placed)
      event(:order_placed, "Order placed")
    end

    publish(:order_placed,
      from: :order_placed,
      fields: [:order_id]
    )
  end

  defmodule ShopPayments do
    @moduledoc false
    use EhosContract.Contract, domain: ShopDomain, context: :orders, id: "my_shop.payments"

    aggregate :payment, "Payment" do
      identity(:payment_id)
      command(:take_payment, "Take a payment", by: :till, emits: :payment_taken)
      event(:payment_taken, "Payment taken")
    end

    publish(:payment_taken,
      from: :payment_taken,
      fields: [:payment_id]
    )
  end

  setup do
    engine = Application.get_env(:ehos_contract, :applications)
    audience = Application.get_env(:ehos_contract_auth, :audience)

    on_exit(fn ->
      Application.put_env(:ehos_contract, :applications, engine)
      Application.put_env(:ehos_contract_auth, :audience, audience)
      for app <- [:auth_rig_clinic, :auth_rig_shop, :auth_rig_both], do: :application.unload(app)
      EhosContract.Registry.load!()
    end)
  end

  test "an application deployed under no domain's name refuses to start" do
    error =
      assert_raise ArgumentError, fn ->
        boot(:auth_rig_clinic, [ClinicDomain, ClinicVisits], "billing-app/prod")
      end

    assert error.message =~ ~s(audience: "billing-app/prod" names the application billing-app)
    assert error.message =~ "the domain clinic (#{inspect(ClinicDomain)})"

    assert error.message =~
             ~s{rename the domain clinic (#{inspect(ClinicDomain)}) to name: :"billing-app"}

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

  test "a domain named with _ refuses EHOS's spelling of it, with -, advising the rename" do
    error =
      assert_raise ArgumentError, fn ->
        boot(:auth_rig_shop, [ShopDomain, ShopOrders], "my-shop/prod")
      end

    assert error.message =~
             "the domain my_shop (#{inspect(ShopDomain)}) differs from it only in _ where EHOS has -"

    assert error.message =~ ~s{Rename the domain, such as name: :"my-shop"}
    refute error.message =~ "register"
  end

  test "of two domains spelled with _ and with -, only the one with - is the application's" do
    # The one with `-` matches, so the other is held to publishing nothing, which it does.
    assert %{start: _} =
             boot(
               :auth_rig_both,
               [ShopDomain, ShopOrders, DashedShopDomain, DashedShopOrders],
               "my-shop/prod"
             )

    # Were `_` the same as `-`, the one with `_` would match too and pass with its publish.
    error =
      assert_raise ArgumentError, fn ->
        boot(
          :auth_rig_both,
          [ShopDomain, ShopOrders, ShopPayments, DashedShopDomain, DashedShopOrders],
          "my-shop/prod"
        )
      end

    assert error.message =~ "whose domain is my-shop (#{inspect(DashedShopDomain)})"
    assert error.message =~ "the domain my_shop (#{inspect(ShopDomain)}): "
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
               "#{inspect(ShopPayments)} publishes my-shop.payment_taken.v1"

    refute error.message =~ inspect(ShopOrders)
  end

  test "the publishing domain may be the application's" do
    assert %{start: _} =
             boot(
               :auth_rig_both,
               [ClinicDomain, ClinicVisits, DashedShopDomain, DashedShopOrders],
               "my-shop/prod"
             )
  end

  test "a domain without contracts is not compared" do
    assert %{start: _} =
             boot(:auth_rig_clinic, [ClinicDomain, ClinicVisits, ShopDomain], "clinic/prod")
  end

  test "an audience without both an application and an environment is refused as malformed" do
    for audience <- ["clinic", "clinic/", "/prod", "/", ""] do
      error =
        assert_raise ArgumentError, fn ->
          boot(:auth_rig_clinic, [ClinicDomain, ClinicVisits], audience)
        end

      assert error.message =~ ~s(audience: #{inspect(audience)} is malformed)
      assert error.message =~ "<application>/<environment>, both parts non-empty"
      refute error.message =~ "rename"
    end
  end

  test "an audience in the domain's spelling, with _, is refused as malformed: EHOS never issues it" do
    error =
      assert_raise ArgumentError, fn ->
        boot(:auth_rig_shop, [ShopDomain, ShopOrders], "my_shop/prod")
      end

    assert error.message =~ ~s(its application, the part before the /, is "my_shop")
  end

  test "with several domains, none publishing, the advice is to rename one of them" do
    error =
      assert_raise ArgumentError, fn ->
        boot(:auth_rig_both, [ClinicDomain, ClinicVisits, ShopDomain, ShopOrders], "billing/prod")
      end

    assert error.message =~ "rename one of them to name: :billing"
  end

  test "with several domains, the one that publishes is the one named to rename" do
    error =
      assert_raise ArgumentError, fn ->
        boot(
          :auth_rig_both,
          [ClinicDomain, ClinicVisits, ShopDomain, ShopOrders, ShopPayments],
          "billing/prod"
        )
      end

    assert error.message =~
             "rename the domain that publishes, my_shop (#{inspect(ShopDomain)}), to name: :billing"

    # EHOS takes no name with `_`, so registering the application under it is no way out.
    refute error.message =~ "register the application in EHOS as"
  end

  test "a contract whose domain is not loaded is refused, naming both" do
    model = %{ClinicVisits.__ehos_contract_model__() | domain: NoSuchDomain}

    error =
      assert_raise ArgumentError, fn ->
        EhosContract.Auth.check_application!("clinic/prod", [model])
      end

    assert error.message =~ "#{inspect(ClinicVisits)} names the domain NoSuchDomain"
    assert error.message =~ "not loaded"
  end

  defp boot(app, modules, audience) do
    :application.unload(app)

    :ok =
      :application.load(
        {:application, app,
         [description: ~c"rig", vsn: ~c"0", modules: modules, registered: [], applications: []]}
      )

    Application.put_env(:ehos_contract, :applications, [app])
    Application.put_env(:ehos_contract_auth, :audience, audience)
    EhosContract.Auth.child_spec([])
  end
end
