defmodule EhOsContract.PagesTest do
  @moduledoc """
  Plan EL3: **a domain and its contracts as Markdown pages, one per element, linked**
  (ESDM's `documentation`), and `mix eh_os_contract.pages --output`, which writes
  them, deletes what it wrote before and no longer has, and with `--check` says
  whether a directory is current.
  """

  use ExUnit.Case, async: false

  alias EhOsContract.{Pages, Registry}

  defp pages(domain), do: Pages.render(domain, Registry.contracts() ++ Registry.processes())

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

      for {path, text} <- pages,
          String.ends_with?(path, ".md"),
          do: assert(String.starts_with?(text, Pages.marker(name)), path)

      # Beside them, each contract's and process module's graph document, which nothing
      # else writes.
      for {path, text} <- pages, String.ends_with?(path, ".json") do
        assert Pages.graph?(path, text, domain), path
        refute Pages.graph?(path, text, Enum)
      end
    end
  end

  describe "the pages of ValueRig" do
    setup do
      %{pages: pages(ValueRig.Domain)}
    end

    test "one per element: the domain, each value and context, the contract and each declaration",
         %{pages: pages} do
      assert Enum.sort(Map.keys(pages)) == [
               "graph/value_rig.till.json",
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

    test "no page draws a diagram: the contract's page links its graph document instead (plan E13b)",
         %{pages: pages} do
      refute pages["index.md"] =~ "## Context map"
      refute pages["till/till/aggregates/till.md"] =~ "## Diagram"
      assert pages["till/till/index.md"] =~ "[graph](../../graph/value_rig.till.json)"
    end

    test "a domain service shows each rule with its examples as calls", %{pages: pages} do
      splitting = pages["till/till/domain_services/splitting.md"]

      assert splitting =~ "## `half` — Half of an amount, rounded down"
      assert splitting =~ "Returns [`amount`](../../../values/amount.md), or nothing"
      assert splitting =~ "- **`rounded_down`** — An odd amount loses its last cent"
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

    assert chase =~
             "- `first_deposit_due` — First deposit due (1 day after it is set) → " <>
               "[`flag_account`](../commands/flag_account.md)"

    assert chase =~ "- `review` — Review (at `review_at`) → "
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
      identity: :clinic_id,
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

  # Plan DD, L3 (#286): a field may identify a unit, which its page then lists.
  test "a field that identifies a unit links to its page, which lists the field" do
    till = EhOsContract.Model.fetch(ValueRig.Till)
    [pay_in | commands] = till.commands

    previous = %{
      name: :previous_till_id,
      type: :id,
      refers_to: :till,
      optional: true,
      label: nil,
      personal: nil,
      subject: nil,
      default: nil
    }

    till = %{till | commands: [%{pay_in | fields: pay_in.fields ++ [previous]} | commands]}
    pages = Pages.render(ValueRig.Domain, [till])

    assert pages["till/till/commands/pay_in.md"] =~
             "| `previous_till_id` | `:id` of [`till`](../aggregates/till.md) |"

    assert pages["till/till/aggregates/till.md"] =~
             "## Referred to by\n\n- command [`pay_in`](../commands/pay_in.md) of " <>
               inspect(ValueRig.Till)
  end

  # Plan DD, L3 (#286): the domain knows only entities, so an entity's field naming a
  # name a unit shares still links to the entity, as the graph says.
  test "a domain field naming a name an entity and a unit share links to the entity" do
    field = fn name, type, extra ->
      Map.merge(
        %{name: name, type: type, label: nil, personal: nil, subject: nil, default: nil},
        extra
      )
    end

    till = %{
      name: :till,
      label: "Till",
      context: :till,
      identity: :till_id,
      source: nil,
      fields: [field.(:till_id, :id, %{optional: false})]
    }

    branch = %{
      name: :branch,
      label: "Branch",
      context: :till,
      identity: :branch_id,
      source: nil,
      fields: [
        field.(:branch_id, :id, %{optional: false}),
        field.(:main_till_id, :id, %{optional: false, refers_to: :till})
      ]
    }

    domain = EhOsContract.Model.fetch(ValueRig.Domain)
    pages = Pages.render(%{domain | entities: [till, branch]}, [ValueRig.Till])

    assert pages["entities/branch.md"] =~
             "| `main_till_id` | `:id` of [`till`](till.md) |"

    assert pages["entities/till.md"] =~ "## Referred to by\n\n- entity [`branch`](branch.md)"
  end

  # The EL3 review: the client's text went into tables and code spans as it was.
  test "a label with a bar or a line break stays in its cell, and a backtick in its span" do
    till = EhOsContract.Model.fetch(ValueRig.Till)
    [pay_in | commands] = till.commands
    [till_id | fields] = pay_in.fields

    till = %{
      till
      | commands: [
          %{pay_in | fields: [%{till_id | label: "Till | point\nof sale"} | fields]} | commands
        ]
    }

    page = Pages.render(ValueRig.Domain, [till])["till/till/commands/pay_in.md"]
    assert page =~ "| `till_id` | `:id` | Till \\| point of sale |  |"

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

    broken = %{domain | values: [%{amount | name: :"amount\n"} | rest]}
    assert_raise ArgumentError, ~r/named after "amount\\n"/, fn -> Pages.render(broken, []) end

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

  # Plan DD, P2e (#220): a process module's page and its document.
  describe "the pages of a process module" do
    setup do
      %{pages: pages(UniversalityGate.Domain)}
    end

    test "its page and its graph document, by its id", %{pages: pages} do
      assert Map.has_key?(pages, "processes/treatment_episode_run.md")

      document =
        Jason.decode!(pages["graph/process/universality_gate.treatment_episode_run.json"])

      assert document["kind"] == "process"
      assert document["process"] == "universality_gate.treatment_episode_run"
    end

    test "says what tells a run, who answers for it, its stages, ends, promises and deadline",
         %{pages: pages} do
      page = pages["processes/treatment_episode_run.md"]
      event = &"[`#{&1}`](../treatment/treatment_episode/events/#{&1}.md)"

      assert page =~
               "# Process `universality_gate.treatment_episode_run` — Treatment episode: from referral to closing"

      assert page =~
               "[graph](../graph/process/universality_gate.treatment_episode_run.json)"

      assert page =~ "Runs: one per `episode_id`."
      assert page =~ "Accountable: `attending_physician` — Attending physician."

      # Said plainly where it is declared: the report leaves an unconfirmed one out.
      assert page =~
               "Deadline: 30 days from the start of a run. Not confirmed by the process owner " <>
                 "(`unverified`), so the conformance report leaves it out."

      assert page =~
               "2. `plan` — [`UniversalityGate.TreatmentEpisode`](../treatment/treatment_episode/index.md): " <>
                 event.("treatment_plan_approved")

      assert page =~ "#{event.("payer_eligibility_denied")} (ends a run)"
      assert page =~ "## Ends a run\n\n- #{event.("payer_eligibility_denied")}\n"

      assert page =~
               "- `referral_reaches_a_decision`: after #{event.("referral_received")}, eventually " <>
                 "#{event.("payer_eligibility_confirmed")} within 3 days, or else " <>
                 event.("payer_eligibility_denied") <> "\n"

      assert page =~
               "- `payer_registry` — Payer registry: confirmation of eligibility for treatment · " <>
                 "what rests on it: #{event.("payer_eligibility_checked")}"
    end

    test "a promise that waits on a system says so, and the owner reads it without its code name" do
      run = EhOsContract.Model.fetch(UniversalityGate.TreatmentEpisodeRun)
      [first | rest] = run.promises
      run = %{run | promises: [Map.put(first, :waits_on, [:payer_registry]) | rest]}

      render =
        &Pages.render(UniversalityGate.Domain, [UniversalityGate.TreatmentEpisode, run], &1)

      page = render.([])["processes/treatment_episode_run.md"]
      assert page =~ ", waiting on "
      assert page =~ "the promises that wait on it: `referral_reaches_a_decision`"

      owner = render.(audience: :owner)["processes/treatment_episode_run.md"]
      assert owner =~ " · a promise above waits on it"
      refute owner =~ "referral_reaches_a_decision"
    end

    test "an unconfirmed promise says the report leaves it out" do
      run = EhOsContract.Model.fetch(UniversalityGate.TreatmentEpisodeRun)
      [first | rest] = run.promises
      run = %{run | promises: [%{first | unverified: true} | rest]}

      page =
        Pages.render(UniversalityGate.Domain, [UniversalityGate.TreatmentEpisode, run])[
          "processes/treatment_episode_run.md"
        ]

      assert page =~
               "or else [`payer_eligibility_denied`](../treatment/treatment_episode/events/payer_eligibility_denied.md). " <>
                 "Not confirmed by the process owner (`unverified`), so the conformance report leaves it out.\n"
    end

    test "the domain's page and each including contract's page link it", %{pages: pages} do
      assert pages["index.md"] =~
               "## Processes\n\n- [`universality_gate.treatment_episode_run`](processes/treatment_episode_run.md) " <>
                 "— Treatment episode: from referral to closing"

      assert pages["index.md"] =~ "└─ process universality_gate.treatment_episode_run"

      assert pages["treatment/treatment_episode/index.md"] =~
               "## Processes that include its events\n\n" <>
                 "- [`universality_gate.treatment_episode_run`](../../processes/treatment_episode_run.md) " <>
                 "— Treatment episode: from referral to closing · includes " <>
                 "[`referral_received`](events/referral_received.md), "
    end

    # Plan DD, P2e (#220), review: a stage listed a contract twice when its
    # events were not adjacent, and a stage with nothing resolved ended in "— ".
    test "a stage's events by contract in first-appearance order, and a stage with none" do
      page =
        Pages.render(DispatchRig.Domain, [DispatchRig.Ledger, DispatchRig.Transfer, mixed_run()])[
          "processes/ledger_run.md"
        ]

      assert page =~
               "1. `moving` — [`DispatchRig.Ledger`](../ledger/ledger/index.md): " <>
                 "[`deposited`](../ledger/ledger/events/deposited.md), " <>
                 "[`withdrawn`](../ledger/ledger/events/withdrawn.md); " <>
                 "[`DispatchRig.Transfer`](../ledger/transfer/index.md): " <>
                 "[`account_moved`](../ledger/transfer/events/account_moved.md)\n"

      assert page =~ "2. `elsewhere` — _no included event resolves to a contract of the domain_\n"
    end

    # Plan DD, P2e (#220), review: a model built without `correlate` raised.
    test "a process module without correlate says nothing of what tells its runs apart" do
      page =
        Pages.render(UniversalityGate.Domain, [
          UniversalityGate.TreatmentEpisode,
          %{EhOsContract.Model.fetch(UniversalityGate.TreatmentEpisodeRun) | correlate: []}
        ])["processes/treatment_episode_run.md"]

      refute page =~ "Runs:"
    end

    test "control: a contract none of whose events a process includes lists none" do
      refute pages(ValueRig.Domain)["till/till/index.md"] =~ "Processes"
    end

    test "a process document is the pages' only at its own path, apart from a contract's",
         %{pages: pages} do
      path = "graph/process/universality_gate.treatment_episode_run.json"
      text = pages[path]

      assert Pages.graph?(path, text, UniversalityGate.Domain)
      # A process module may share its id with a contract: the contract's path is not its.
      refute Pages.graph?(
               "graph/universality_gate.treatment_episode_run.json",
               text,
               UniversalityGate.Domain
             )

      refute Pages.graph?(path, text, ValueRig.Domain)
    end

    test "a process module whose id: is no dotted name gets no page outside the directory" do
      run = EhOsContract.Model.fetch(UniversalityGate.TreatmentEpisodeRun)

      assert_raise ArgumentError, ~r|a process module's document is named after its id:|, fn ->
        Pages.render(UniversalityGate.Domain, [%{run | id: "../../escape"}])
      end
    end
  end

  # A run whose first stage includes two contracts' events interleaved, and whose second
  # includes only an event of another domain, which does not resolve.
  defp mixed_run do
    run = EhOsContract.Model.fetch(DispatchRig.LedgerRun)

    stages = [
      %{
        name: :moving,
        label: nil,
        includes: [
          %{contract: DispatchRig.Ledger, event: :deposited},
          %{contract: DispatchRig.Transfer, event: :account_moved},
          %{contract: DispatchRig.Ledger, event: :withdrawn}
        ]
      },
      %{name: :elsewhere, label: nil, includes: [%{contract: ValueRig.Till, event: :paid_in}]}
    ]

    %{run | stages: stages, ends_on: []}
  end

  # The E13a pre-PR review: a contract's graph document is named after its id:, which a
  # model built by hand is not held to.
  test "a contract whose id: is no dotted name gets no graph document outside the pages" do
    till = EhOsContract.Model.fetch(ValueRig.Till)

    assert_raise ArgumentError, ~r|would be named after "../../escape"|, fn ->
      Pages.render(ValueRig.Domain, [%{till | id: "../../escape"}])
    end

    domain = inspect(ValueRig.Domain)

    claimed =
      Jason.encode!(%{
        "schema" => "eh_os_contract.graph.v1",
        "kind" => "contract",
        "domain" => domain,
        "contract" => "sub/escape"
      })

    refute Pages.graph?("graph/sub/escape.json", claimed, ValueRig.Domain)
  end

  # Plan DD, L4 (#326): the owner reads the model in the business's words, without the
  # engineering around it.
  describe "the owner's pages" do
    defp owner(domain),
      do: Pages.render(domain, Registry.contracts() ++ Registry.processes(), audience: :owner)

    test "are the engineer's tree without the graph documents, every link leading to a page" do
      for domain <- Registry.domains() do
        engineer = pages(domain)
        pages = owner(domain)

        assert Enum.sort(Map.keys(pages)) ==
                 engineer
                 |> Map.keys()
                 |> Enum.reject(&String.ends_with?(&1, ".json"))
                 |> Enum.sort()

        name = domain.__eh_os_contract_model__().name

        for {path, text} <- pages do
          assert String.starts_with?(text, Pages.marker(name, :owner)), path
          refute String.starts_with?(text, Pages.marker(name)), path

          for target <- links(path, text),
              do: assert(Map.has_key?(pages, target), "#{path} links to #{target}")
        end
      end
    end

    test "say nothing of the engineering: modules, versions, types, delivery, correlation" do
      for domain <- Registry.domains(), {path, text} <- owner(domain) do
        for word <- [
              "Delivered ",
              "second delivery",
              "Stored as ",
              "Runs: ",
              "Runs are told by",
              "Identity: ",
              " · version ",
              "](../../graph/",
              "| Type |"
            ] do
          refute text =~ word, "#{inspect(domain)} #{path} says #{inspect(word)}"
        end

        for contract <- Registry.contracts() do
          refute text =~ inspect(contract), "#{path} names #{inspect(contract)}"
        end
      end
    end

    test "show the code only where the model has no word: a stage, a value or a member" do
      for domain <- Registry.domains() do
        model = domain.__eh_os_contract_model__()

        unlabelled =
          for(%{label: nil, name: name} <- model.values, do: "`#{name}`") ++
            for(
              %{type: {:enum, members}} <- model.values,
              member <- members,
              is_atom(member),
              do: "`#{member}`"
            ) ++
            for process <- Registry.processes(),
                EhOsContract.Model.fetch(process).domain == domain,
                %{label: nil, name: name} <- EhOsContract.Model.process(process).stages,
                do: "`#{name}`"

        for {path, text} <- owner(domain), [span] <- Regex.scan(~r/`[^`]+`/, text) do
          assert span in unlabelled, "#{inspect(domain)} #{path} shows #{span}"
        end
      end
    end

    test "name each declaration by its label, a field by its label alone" do
      pages = owner(ValueRig.Domain)
      event = pages["till/till/events/paid_in.md"]

      assert event =~ "# Event — Paid in\n"
      assert event =~ "In [Till](../index.md)"
      refute event =~ "`paid_in`"
      # Fields without a label are the code's, so there is no section of them.
      refute event =~ "## Fields"
    end

    test "a policy by what it handles and issues, and a process without its keys" do
      pages = owner(ProcessShapes.Domain)
      policy = pages["handling/promised/policies/log_arrival.md"]

      assert policy =~ "# Policy — Log a request on its arrival\n"
      assert policy =~ "Handles: ["
      refute policy =~ "at_least_once"

      process = pages["processes/handling.md"]
      # A stage with no label is named as the code names it (`owner-view-without-label`).
      assert process =~ "1. `intake` — "
      # A promise has no label, so it is read by its rule.
      assert process =~ "## Promises\n\n- After ["
      refute process =~ "completed_or_refusal_notified"
    end
  end

  describe "mix eh_os_contract.pages" do
    setup do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    end

    defp run(args), do: Mix.Tasks.EhOsContract.Pages.run(args ++ ["--domain", "value_rig"])

    @tag :tmp_dir
    test "--audience owner writes the owner's pages, and checks them", %{tmp_dir: dir} do
      run(["--output", dir, "--audience", "owner"])
      assert_received {:mix_shell, :info, [written]}
      assert written == "#{dir}: 15 pages written"

      assert File.read!(Path.join(dir, "values/amount.md")) ==
               Pages.render(ValueRig.Domain, Registry.contracts(), audience: :owner)[
                 "values/amount.md"
               ]

      run(["--output", dir, "--audience", "owner", "--check"])
      assert_received {:mix_shell, :info, [current]}
      assert current == "#{dir}: current"

      # The engineer's pages do not go over the owner's: each would be in the way.
      error = assert_raise Mix.Error, fn -> run(["--output", dir]) end
      assert error.message =~ "nothing written, since these are not pages this task wrote"

      assert_raise Mix.Error, ~r/--audience is engineering or owner, not "boss"/, fn ->
        run(["--output", dir, "--audience", "boss"])
      end
    end

    @tag :tmp_dir
    test "writes the pages, and --check says the directory is current", %{tmp_dir: dir} do
      run(["--output", dir])
      assert_received {:mix_shell, :info, [written]}
      assert written == "#{dir}: 16 pages written"

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
      assert written == "#{dir}: 16 pages written, 1 left over deleted"

      refute File.exists?(Path.join(dir, "values/tip.md"))
      assert File.read!(Path.join(dir, "README.md")) == "# Written by a person\n"
    end

    @tag :tmp_dir
    test "a contract's graph document is the task's at its own path only", %{tmp_dir: dir} do
      run(["--output", dir])
      assert_received {:mix_shell, :info, [_written]}
      ours = File.read!(Path.join(dir, "graph/value_rig.till.json"))
      assert Jason.decode!(ours)["contract"] == "value_rig.till"

      # The document of a contract the domain no longer has is deleted; a copy a person
      # saved under another name, and a person's JSON, stay.
      gone =
        String.replace(ours, ~s("contract": "value_rig.till"), ~s("contract": "value_rig.gone"))

      File.write!(Path.join(dir, "graph/value_rig.gone.json"), gone)
      File.write!(Path.join(dir, "graph/value_rig.till-before.json"), ours)
      File.write!(Path.join(dir, "graph/notes.json"), ~s({"mine": true}))

      # Nor does the task fail on a file it cannot read, or one whose contract is no name.
      odd = String.replace(ours, ~s("contract": "value_rig.till"), ~s("contract": {"a": 1}))
      File.write!(Path.join(dir, "graph/odd.json"), odd)
      locked = Path.join(dir, "graph/locked.json")
      File.write!(locked, ours)
      File.chmod!(locked, 0o000)
      on_exit(fn -> File.chmod(locked, 0o600) end)

      run(["--output", dir])
      assert_received {:mix_shell, :info, [written]}
      assert written == "#{dir}: 16 pages written, 1 left over deleted"
      refute File.exists?(Path.join(dir, "graph/value_rig.gone.json"))
      assert File.read!(Path.join(dir, "graph/value_rig.till-before.json")) == ours
      assert File.exists?(Path.join(dir, "graph/notes.json"))
      assert File.exists?(Path.join(dir, "graph/odd.json"))
      assert File.exists?(locked)
      File.chmod!(locked, 0o600)

      # A person's file at the path the task would write is in the way.
      File.write!(Path.join(dir, "graph/value_rig.till.json"), ~s({"mine": true}))
      error = assert_raise Mix.Error, fn -> run(["--output", dir]) end
      assert error.message =~ "graph/value_rig.till.json"
    end

    # Plan DD, P2e (#220): a process module's document is the task's to replace and to
    # delete, at its own path.
    @tag :tmp_dir
    test "writes a process module's page and document, and deletes one it no longer has",
         %{tmp_dir: dir} do
      run = fn args ->
        Mix.Tasks.EhOsContract.Pages.run(args ++ ["--domain", "universality_gate"])
      end

      run.(["--output", dir])
      assert_received {:mix_shell, :info, [_written]}
      path = Path.join(dir, "graph/process/universality_gate.treatment_episode_run.json")
      ours = File.read!(path)
      assert File.exists?(Path.join(dir, "processes/treatment_episode_run.md"))

      gone =
        String.replace(
          ours,
          ~s("process": "universality_gate.treatment_episode_run"),
          ~s("process": "universality_gate.gone")
        )

      File.write!(Path.join(dir, "graph/process/universality_gate.gone.json"), gone)
      # A process document at a contract's path is a person's.
      File.write!(Path.join(dir, "graph/universality_gate.gone.json"), gone)

      run.(["--output", dir])
      assert_received {:mix_shell, :info, [written]}
      assert written =~ ", 1 left over deleted"
      refute File.exists?(Path.join(dir, "graph/process/universality_gate.gone.json"))
      assert File.exists?(Path.join(dir, "graph/universality_gate.gone.json"))

      run.(["--output", dir, "--check"])
      assert_received {:mix_shell, :info, [current]}
      assert current == "#{dir}: current"
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
      assert written == "#{out}: 16 pages written"
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
      assert written == "#{out}: 16 pages written, 1 left over deleted"
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
      assert written == "#{dir}: 16 pages written"
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
