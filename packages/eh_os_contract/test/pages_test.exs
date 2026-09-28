defmodule EhOsContract.PagesTest do
  @moduledoc """
  Plan EL3: **a domain and its contracts as Markdown pages, one per element, linked**
  (ESDM's `documentation`), and `mix eh_os_contract.pages --output`, which writes
  them, deletes what it wrote before and no longer has, and with `--check` says
  whether a directory is current.
  """

  use ExUnit.Case, async: false

  alias EhOsContract.{Pages, Registry}

  defp pages(domain), do: Pages.render(domain, Registry.v2_contracts())

  # Every relative Markdown link on a page, resolved against the page's directory.
  defp links(path, text) do
    for [_, target] <- Regex.scan(~r/\]\(([^)#]+)\)/, text),
        not String.contains?(target, "://") do
      path |> Path.dirname() |> Path.join(target) |> Path.expand("/") |> Path.relative_to("/")
    end
  end

  test "every link on every page of every fixture domain leads to a page there" do
    for domain <- Registry.domains() do
      pages = pages(domain)

      for {path, text} <- pages, target <- links(path, text) do
        assert Map.has_key?(pages, target),
               "#{inspect(domain)}: #{path} links to #{target}, which is not a page"
      end

      name = domain.__eh_os_contract_model__().name
      for {path, text} <- pages, do: assert(String.starts_with?(text, Pages.marker(name)), path)
    end
  end

  describe "the pages of ValueRig" do
    setup do
      %{pages: pages(ValueRig.Domain)}
    end

    test "one per element: the domain, each value and context, the contract and each declaration",
         %{pages: pages} do
      assert Enum.sort(Map.keys(pages)) == [
               "index.md",
               "till/index.md",
               "till/till/aggregates/till.md",
               "till/till/commands/pay_in.md",
               "till/till/commands/short_change.md",
               "till/till/domain_services/splitting.md",
               "till/till/events/counted.md",
               "till/till/events/paid_in.md",
               "till/till/index.md",
               "till/till/queries/payments_above.md",
               "till/till/read_models/payments.md",
               "values/amount.md",
               "values/fee.md",
               "values/payment.md",
               "values/window.md"
             ]
    end

    test "a value shows its invariants with their examples, and who uses it", %{pages: pages} do
      amount = pages["values/amount.md"]

      assert amount =~ "# Value `amount`"
      assert amount =~ "### `positive`\n\nAn amount is more than nothing"
      assert amount =~ "Broken by: `0`, `-5`"
      assert amount =~ "Kept by: `1`, `250`"
      assert amount =~ "- value [`fee`](fee.md)"
      assert amount =~ "- command [`pay_in`](../till/till/commands/pay_in.md) of ValueRig.Till"

      assert pages["values/window.md"] =~ ~s|Broken by: `%{from: "2026-02-01", to: "2026-01-31"}`|
    end

    test "a command links its unit, its events and its fields' values", %{pages: pages} do
      pay_in = pages["till/till/commands/pay_in.md"]

      assert pay_in =~ "Aggregate [`till`](../aggregates/till.md)"
      assert pay_in =~ "Issued by: `cashier`."
      assert pay_in =~ "Emits: [`paid_in`](../events/paid_in.md)"
      assert pay_in =~ "| `fees` | list of [`fee`](../../../values/fee.md) |  | optional |"
    end

    test "an event says who emits it, who records it and who reads it", %{pages: pages} do
      assert pages["till/till/events/paid_in.md"] =~
               "Emitted by: [`pay_in`](../commands/pay_in.md), [`short_change`](../commands/short_change.md)"

      counted = pages["till/till/events/counted.md"]
      assert counted =~ "Recorded by: `counter`."
      assert counted =~ "- read model [`payments`](../read_models/payments.md)"
    end

    test "a unit draws itself, as the graph task does (plan EG1)", %{pages: pages} do
      till = pages["till/till/aggregates/till.md"]

      assert till =~
               "## Diagram\n\n```mermaid\n" <>
                 EhOsContract.Graph.unit_to_mermaid(ValueRig.Till, :till) <> "\n```\n"
    end

    test "a domain service shows each rule with its examples as calls", %{pages: pages} do
      splitting = pages["till/till/domain_services/splitting.md"]

      assert splitting =~ "## `half` — Half of an amount, rounded down"
      assert splitting =~ "Returns [`amount`](../../../values/amount.md), or nothing"
      assert splitting =~ "- **`rounded_down`** — An odd amount loses its last grosz"
      assert splitting =~ "  - `half(5)` returns `2`"
      assert splitting =~ "  - `half(1)` returns `nil`"
    end

    test "the domain lists its contexts and values and prints its tree", %{pages: pages} do
      index = pages["index.md"]

      assert index =~ "- [`till`](till/index.md) — Till · core subdomain `core`"
      assert index =~ "- [`amount`](values/amount.md)"
      assert index =~ "```\ndomain value_rig  1 context · 1 contract"
    end
  end

  test "a process manager's reactions say what they issue and which timers they set" do
    chase = pages(DispatchRig.Domain)["ledger/ledger/process_managers/first_deposit_chase.md"]

    assert chase =~
             "- [`account_opened`](../events/account_opened.md) → sets timer `first_deposit_due`"

    assert chase =~
             "- [`deposited`](../events/deposited.md) → sets timer `review`, cancels timer `first_deposit_due`"

    assert chase =~ "- `first_deposit_due` → [`flag_account`](../commands/flag_account.md)"
  end

  # The EL3 review: the page stated a promise without its `or_else`, and left out
  # what the process includes from other contracts.
  test "a process shows its deadline, what it includes and its promises as declared" do
    episode =
      pages(UniversalityGate.Domain)["treatment/treatment_episode/index.md"]

    assert episode =~ "Deadline: 30 days (unverified)."

    assert episode =~
             "- `referral_reaches_a_decision`: after [`referral_received`](events/referral_received.md), " <>
               "eventually [`payer_eligibility_confirmed`](events/payer_eligibility_confirmed.md) within " <>
               "3 days, or else [`payer_eligibility_denied`](events/payer_eligibility_denied.md)"

    branch = pages(DispatchRig.Domain)["ledger/branch/index.md"]
    assert branch =~ "## Included from other contracts"

    assert branch =~
             "[`account_opened` of DispatchRig.Ledger](../ledger/events/account_opened.md)"
  end

  # The EL3 review: a timer named in `on` printed as an event received from another
  # application, and a scenario that only sets a timer said "as declared".
  test "a process manager's timer in `on`, and a scenario's timers and end" do
    ledger = EhOsContract.Model.fetch(DispatchRig.Ledger)
    [chase] = ledger.process_managers
    on_timer = %{event: :review, issues: [:flag_account], sets: [], cancels: []}

    scenario = %{
      description: "an account opened sets the chase",
      target: %{kind: :process_manager, name: :first_deposit_chase},
      trigger: %{kind: :on, name: :account_opened, data: %{}},
      given: [],
      expect: [],
      issues: [],
      rejected: nil,
      sets: [:first_deposit_due],
      cancels: [],
      ended: true,
      actor: nil,
      scope: nil
    }

    ledger = %{
      ledger
      | process_managers: [%{chase | on: chase.on ++ [on_timer]}],
        scenarios: [scenario]
    }

    page =
      Pages.render(DispatchRig.Domain, [ledger])[
        "ledger/ledger/process_managers/first_deposit_chase.md"
      ]

    assert page =~ "- timer `review` → [`flag_account`](../commands/flag_account.md)"
    refute page =~ "(received)"

    assert page =~
             "- an account opened sets the chase\n\n  on `account_opened`; sets `first_deposit_due`, ends the run"
  end

  # The EL3 review: `inspect/1` prints a map's keys in the order their atoms were
  # made, so a map inside a tuple printed differently on two builds.
  test "an example prints the same on every build, maps inside tuples included" do
    till = EhOsContract.Model.fetch(ValueRig.Till)
    [splitting] = till.domain_services
    [half] = splitting.functions
    [rule | _] = half.rules
    rule = %{rule | examples: [{[5], {:ok, %{zz_pages_probe: 1, aa_pages_probe: 2}}}]}
    till = %{till | domain_services: [%{splitting | functions: [%{half | rules: [rule]}]}]}

    page = Pages.render(ValueRig.Domain, [till])["till/till/domain_services/splitting.md"]
    assert page =~ "`half(5)` returns `{:ok, %{aa_pages_probe: 2, zz_pages_probe: 1}}`"
  end

  # The EL3 review: "Published" printed the publication's name as its source, and
  # "Consumed" neither linked a sibling's events nor said what they are called here.
  test "what a contract publishes and consumes, linked, under the names it uses" do
    till = EhOsContract.Model.fetch(ValueRig.Till)

    publication = %{
      name: :paid,
      as: "till.paid.v1",
      from: :paid_in,
      fields: [],
      idempotent_on: []
    }

    till = %{till | publishes: [publication]}
    page = Pages.render(ValueRig.Domain, [till])["till/till/index.md"]
    assert page =~ "- `paid`, published as `till.paid.v1`, from [`paid_in`](events/paid_in.md)"

    branch = EhOsContract.Model.fetch(DispatchRig.Branch)
    [consumed] = branch.consumes
    branch = %{branch | consumes: [%{consumed | renames: %{account_opened: :opened}}]}

    pages =
      Pages.render(DispatchRig.Domain, [EhOsContract.Model.fetch(DispatchRig.Ledger), branch])

    assert pages["ledger/branch/index.md"] =~
             "- [`DispatchRig.Ledger`](../ledger/index.md): " <>
               "[`account_opened`](../ledger/events/account_opened.md) as `opened`"
  end

  # The EL3 review: "Used by" skipped entities and process managers, and nothing led
  # from an entity to the fields that name it.
  test "who uses a value and who refers to an entity, entities included" do
    field = fn name, type, extra ->
      Map.merge(
        %{
          name: name,
          type: type,
          optional: true,
          label: nil,
          personal: nil,
          subject: nil,
          default: nil
        },
        extra
      )
    end

    clinic = %{
      name: :clinic,
      label: "Clinic",
      context: :till,
      identified_by: :clinic_id,
      source: nil,
      fields: [field.(:clinic_id, :id, %{optional: false}), field.(:fee, :fee, %{})]
    }

    domain = EhOsContract.Model.fetch(ValueRig.Domain)
    domain = %{domain | entities: [clinic]}

    till = EhOsContract.Model.fetch(ValueRig.Till)
    [pay_in | commands] = till.commands
    clinics = field.(:clinics, {:list, :id}, %{refers_to: :clinic})
    till = %{till | commands: [%{pay_in | fields: pay_in.fields ++ [clinics]} | commands]}

    pages = Pages.render(domain, [till])

    assert pages["values/fee.md"] =~ "- entity [`clinic`](../entities/clinic.md)"
    assert pages["entities/clinic.md"] =~ "## Referred to by\n\n- command [`pay_in`]"

    assert pages["till/till/commands/pay_in.md"] =~
             "| `clinics` | list of `:id` of [`clinic`](../../../entities/clinic.md) |"
  end

  # The EL3 review: the client's text went into tables and code spans as it was.
  test "a label with a bar or a line break stays in its cell, and a backtick in its span" do
    till = EhOsContract.Model.fetch(ValueRig.Till)
    [pay_in | commands] = till.commands
    [till_id | fields] = pay_in.fields

    till = %{
      till
      | commands: [
          %{pay_in | fields: [%{till_id | label: "Kasa | punkt\nsprzedaży"} | fields]} | commands
        ]
    }

    page = Pages.render(ValueRig.Domain, [till])["till/till/commands/pay_in.md"]
    assert page =~ "| `till_id` | `:id` | Kasa \\| punkt sprzedaży |  |"

    domain = EhOsContract.Model.fetch(ValueRig.Domain)
    [amount | rest] = domain.values
    [positive] = amount.invariants
    amount = %{amount | invariants: [%{positive | violated_by: ["a`b"]}]}
    page = Pages.render(%{domain | values: [amount | rest]}, [])["values/amount.md"]
    assert page =~ ~s|Broken by: `` "a`b" ``|
  end

  test "two contracts of one context that would share a directory are refused" do
    till = EhOsContract.Model.fetch(ValueRig.Till)
    twin = %{till | module: Module.concat([Other, Till])}

    assert_raise ArgumentError,
                 ~r/ValueRig.Till and Other.Till would share the directory till\/till/,
                 fn ->
                   Pages.render(ValueRig.Domain, [till, twin])
                 end
  end

  # The EL3 review: a domain's names are not held to snake_case as a contract's are.
  test "a name that is no snake_case name, and two elements of one path, are refused" do
    domain = EhOsContract.Model.fetch(ValueRig.Domain)
    [amount | rest] = domain.values

    escaping = %{domain | values: [%{amount | name: :"../../escape"} | rest]}

    assert_raise ArgumentError,
                 ~r|the page "values/../../escape.md" would be named after ".."|,
                 fn ->
                   Pages.render(escaping, [])
                 end

    spaced = %{domain | values: [%{amount | name: :"Money Amount"} | rest]}
    assert_raise ArgumentError, ~r/named after "Money Amount"/, fn -> Pages.render(spaced, []) end

    [till] = domain.contexts

    clashing = %{
      domain
      | contexts: [%{till | name: :values}],
        values: [%{amount | name: :index} | rest]
    }

    assert_raise ArgumentError, ~r|two elements would have the page values/index.md|, fn ->
      Pages.render(clashing, [])
    end
  end

  describe "mix eh_os_contract.pages" do
    setup do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    end

    defp run(args), do: Mix.Tasks.EhOsContract.Pages.run(args ++ ["--domain", "value_rig"])

    @tag :tmp_dir
    test "writes the pages, and --check says the directory is current", %{tmp_dir: dir} do
      run(["--output", dir])
      assert_received {:mix_shell, :info, [written]}
      assert written == "#{dir}: 15 pages written"

      assert File.read!(Path.join(dir, "values/amount.md")) ==
               pages(ValueRig.Domain)["values/amount.md"]

      run(["--output", dir, "--check"])
      assert_received {:mix_shell, :info, [current]}
      assert current == "#{dir}: current"
    end

    @tag :tmp_dir
    test "--check names a page that differs, one missing and one left over", %{tmp_dir: dir} do
      run(["--output", dir])

      File.write!(
        Path.join(dir, "values/amount.md"),
        Pages.marker(:value_rig) <> "\n\nedited by hand\n"
      )

      File.rm!(Path.join(dir, "values/fee.md"))

      File.write!(
        Path.join(dir, "values/tip.md"),
        Pages.marker(:value_rig) <> "\n\nA value since removed.\n"
      )

      error = assert_raise Mix.Error, fn -> run(["--output", dir, "--check"]) end

      assert error.message =~
               "#{dir} is not current; run `mix eh_os_contract.pages --output #{dir}`"

      assert error.message =~ "values/amount.md differs"
      assert error.message =~ "values/fee.md is missing"
      assert error.message =~ "values/tip.md is left over"
    end

    @tag :tmp_dir
    test "deletes a page it wrote and no longer has, and nothing else", %{tmp_dir: dir} do
      File.mkdir_p!(Path.join(dir, "values"))

      File.write!(
        Path.join(dir, "values/tip.md"),
        Pages.marker(:value_rig) <> "\n\nA value since removed.\n"
      )

      File.write!(Path.join(dir, "README.md"), "# Written by a person\n")

      run(["--output", dir])
      assert_received {:mix_shell, :info, [written]}
      assert written == "#{dir}: 15 pages written, 1 left over deleted"

      refute File.exists?(Path.join(dir, "values/tip.md"))
      assert File.read!(Path.join(dir, "README.md")) == "# Written by a person\n"
    end

    test "asks where the pages go" do
      assert_raise Mix.Error, ~r/--output <directory>/, fn -> run([]) end
      assert_raise Mix.Error, ~r/--output <directory>/, fn -> run(["--output", ""]) end
    end

    # The EL3 review: a file the task did not write, and a link, are never written
    # over, nor through; and a link is not followed when looking for pages to delete.
    @tag :tmp_dir
    test "writes nothing when a file it did not write is where a page goes", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "index.md"), "# Written by a person\n")

      error = assert_raise Mix.Error, fn -> run(["--output", dir]) end
      assert error.message =~ "#{dir}: nothing written, since these are not pages this task wrote"
      assert error.message =~ "\n  index.md"
      assert File.read!(Path.join(dir, "index.md")) == "# Written by a person\n"
      refute File.exists?(Path.join(dir, "values"))

      check = assert_raise Mix.Error, fn -> run(["--output", dir, "--check"]) end
      assert check.message =~ "index.md is in the way"
    end

    @tag :tmp_dir
    test "never writes through a link, nor deletes behind one", %{tmp_dir: dir} do
      out = Path.join(dir, "out")
      elsewhere = Path.join(dir, "elsewhere")
      File.mkdir_p!(Path.join(out, "values"))
      File.mkdir_p!(elsewhere)

      # A page left over, written by this task, behind a linked directory.
      File.write!(
        Path.join(elsewhere, "tip.md"),
        Pages.marker(:value_rig) <> "\n\nA value since removed.\n"
      )

      File.ln_s!(elsewhere, Path.join(out, "shared"))

      # A page's own path, linked to a person's file outside.
      File.write!(Path.join(elsewhere, "notes.md"), "# Notes\n")
      File.ln_s!(Path.join(elsewhere, "notes.md"), Path.join(out, "values/amount.md"))

      error = assert_raise Mix.Error, fn -> run(["--output", out]) end
      assert error.message =~ "values/amount.md"
      assert File.read!(Path.join(elsewhere, "notes.md")) == "# Notes\n"

      File.rm!(Path.join(out, "values/amount.md"))
      run(["--output", out])
      assert_received {:mix_shell, :info, [written]}
      assert written == "#{out}: 15 pages written"
      assert File.exists?(Path.join(elsewhere, "tip.md"))
    end

    @tag :tmp_dir
    test "reads the output's name as a name, not a pattern", %{tmp_dir: dir} do
      out = Path.join(dir, "o[u]t")
      sibling = Path.join(dir, "out")
      File.mkdir_p!(Path.join(sibling, "values"))

      File.write!(
        Path.join(sibling, "values/tip.md"),
        Pages.marker(:value_rig) <> "\n\nNot this one's.\n"
      )

      File.mkdir_p!(Path.join(out, "values"))

      File.write!(
        Path.join(out, "values/tip.md"),
        Pages.marker(:value_rig) <> "\n\nA value since removed.\n"
      )

      run(["--output", out])
      assert_received {:mix_shell, :info, [written]}
      assert written == "#{out}: 15 pages written, 1 left over deleted"
      refute File.exists?(Path.join(out, "values/tip.md"))
      assert File.exists?(Path.join(sibling, "values/tip.md"))
    end

    # The EL3 review: a host with two domains may write both into one tree.
    @tag :tmp_dir
    test "leaves another domain's pages where they are", %{tmp_dir: dir} do
      File.mkdir_p!(Path.join(dir, "shredding"))
      page = Pages.marker(:shredding_rig) <> "\n\nAnother domain's.\n"
      File.write!(Path.join(dir, "shredding/index.md"), page)

      run(["--output", dir])
      assert_received {:mix_shell, :info, [written]}
      assert written == "#{dir}: 15 pages written"
      assert File.read!(Path.join(dir, "shredding/index.md")) == page

      run(["--output", dir, "--check"])
      assert_received {:mix_shell, :info, [current]}
      assert current == "#{dir}: current"
    end

    @tag :tmp_dir
    test "a directory a deleted page leaves empty goes with it", %{tmp_dir: dir} do
      File.mkdir_p!(Path.join(dir, "gone/deeper"))

      File.write!(
        Path.join(dir, "gone/deeper/page.md"),
        Pages.marker(:value_rig) <> "\n\nGone.\n"
      )

      run(["--output", dir])
      refute File.exists?(Path.join(dir, "gone"))
      assert File.exists?(Path.join(dir, "values"))
    end
  end
end
