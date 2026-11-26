defmodule EhosContract.CheckSeedActorTest do
  @moduledoc """
  The domain's seed actor in `mix ehos_contract.check` (#683): named in no `by:` and no
  `recorded_by:`, one per domain, and a `not_seeded` that names only commands and
  recorded events of the domain. Each rule has a control beside it that it leaves alone.

  The fixture is invented and compiled here, handed to the rules directly, so none of it
  joins the registry and fails this package's own `mix ehos_contract.check`.
  """

  use EhosContract.DslCase, async: false

  alias EhosContract.Check.{Completeness, Finding}

  @domain EhosContract.CheckSeedActorTest.Shop
  @orders EhosContract.CheckSeedActorTest.Orders
  @clean_domain EhosContract.CheckSeedActorTest.CleanShop
  @clean EhosContract.CheckSeedActorTest.CleanOrders

  setup_all do
    # Line numbers below are the file's: `defmodule` is line 1.
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhosContract.Domain, name: :shop, language: :en

        subdomain :core, "Core", type: :core
        context :orders, "Orders", subdomain: :core

        actor :clerk, :human, "Clerk"
        actor :sample_data, :seed, "Sample data",
          not_seeded: [refund: "Moves money", note: "A person's word", refnud: "A typo"]
        actor :demo_data, :seed, "Demo data"
      end

      defmodule #{inspect(@orders)} do
        use EhosContract.Contract, domain: #{inspect(@domain)}, context: :orders, id: "shop.orders"

        aggregate :order, "Order" do
          identity :order_id

          command :place, "Place", by: [:clerk, :sample_data], emits: :placed
          command :refund, "Refund", by: :clerk, emits: :refunded

          event :placed, "Placed"
          event :refunded, "Refunded"
          event :note, "Note", recorded_by: [:clerk, :sample_data]
        end

        read_model :orders, "Orders", projects: [:placed, :refunded, :note] do
          field :order_id, :id
        end

        query :all_orders, "All orders", reads: :orders, by: [:clerk, :sample_data]
      end
      """,
      "shop.ex"
    )

    compile(
      """
      defmodule #{inspect(@clean_domain)} do
        use EhosContract.Domain, name: :clean_shop, language: :en

        subdomain :core, "Core", type: :core
        context :orders, "Orders", subdomain: :core

        actor :clerk, :human, "Clerk"
        actor :sample_data, :seed, "Sample data", not_seeded: [refund: "Moves money"]
      end

      defmodule #{inspect(@clean)} do
        use EhosContract.Contract, domain: #{inspect(@clean_domain)}, context: :orders, id: "clean_shop.orders"

        aggregate :order, "Order" do
          identity :order_id

          command :place, "Place", by: :clerk, emits: :placed
          command :refund, "Refund", by: :clerk, emits: :refunded

          event :placed, "Placed"
          event :refunded, "Refunded"
        end
      end
      """,
      "clean_shop.ex"
    )

    :ok
  end

  defp findings(contracts, rule) do
    for %Finding{rule: ^rule} = f <- Completeness.findings(contracts),
        do: {f.message, Finding.place(f)}
  end

  test "the seed in a command's or a query's by: or an event's recorded_by:, at each" do
    assert [
             {command, {"shop.ex", 19}},
             {event, {"shop.ex", 24}},
             {query, {"shop.ex", 31}}
           ] = Enum.sort_by(findings([@orders], "seed-actor-in-by"), &elem(&1, 1))

    assert command =~
             "command :place of #{inspect(@orders)} names :sample_data, the domain's seed " <>
               "actor, in its `by:`"

    assert event =~ "event :note of #{inspect(@orders)} names :sample_data"
    assert event =~ "in its `recorded_by:`"
    assert query =~ "query :all_orders of #{inspect(@orders)} names :sample_data"

    # Control: the clean domain names its seed nowhere.
    assert findings([@clean], "seed-actor-in-by") == []
  end

  test "a second seed actor, at the second; control: one seed" do
    assert [{message, {"shop.ex", 10}}] = findings([@orders], "second-seed-actor")

    assert message =~
             "actor :demo_data of #{inspect(@domain)} is a second seed actor, beside :sample_data"

    assert findings([@clean], "second-seed-actor") == []
  end

  test "a not_seeded name that is no command or recorded event; control: one of each" do
    assert [{message, {"shop.ex", 8}}] = findings([@orders], "not-seeded-unknown")

    assert message =~
             "actor :sample_data of #{inspect(@domain)} lists :refnud in not_seeded, and no " <>
               "contract of the domain declares a command or a recorded event by that name"

    assert findings([@clean], "not-seeded-unknown") == []
  end

  test "the seed is never an orphan, though nothing names it" do
    assert findings([@clean], "orphan-actor") == []
  end

  test "each is an error" do
    for rule <- ["seed-actor-in-by", "second-seed-actor", "not-seeded-unknown"],
        do: assert(EhosContract.Check.Catalog.fetch!(rule).level == :error)
  end
end
