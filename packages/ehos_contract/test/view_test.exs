defmodule EhosContract.ViewTest do
  @moduledoc """
  Plan EL2: **a domain as a tree for a terminal** (ESDM's `view`): contexts, the
  contracts in each, their units, consumers, read models and queries, with what
  connects them, and with `details:` what each declares.
  """

  use EhosContract.DslCase, async: false

  alias EhosContract.View

  @domain EhosContract.ViewTest.Clinic
  @visits EhosContract.ViewTest.Visits

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhosContract.Domain, name: :clinic, language: :en

        context :settlement, "Settlement", subdomain: :core
        context :archive, "Archive", subdomain: :generic
        actor :reception, :human, "Front desk"
        external :sms, "SMS gateway", direction: :outbound

        subdomain :core, "Core", type: :core
        subdomain :generic, "Generic", type: :generic
      end

      defmodule #{inspect(@visits)} do
        use EhosContract.Contract, domain: #{inspect(@domain)}, context: :settlement, id: "clinic.#{contract_name(@visits)}"

        aggregate :visit, "Visit" do
          identity :visit_id
          invariant :paid_once, "A visit is paid once"

          command :pay, "Pay", by: :reception, emits: :paid, rejects: [:paid_once, :positive] do
            field :amount, :integer
            constraint :positive, "The amount is positive"
          end

          event :paid, "Paid" do
            field :amount, :integer
          end

          event :noted, "Noted", recorded_by: :reception do
            field :sms_id, :id, issued_by: :sms
          end
        end

        policy :thank, "Thank", handles: :paid, issues: :pay
        effect :text, "SMS", handles: :paid, calls: :sms, idempotency: [key: :visit_id, owner: :self]

        read_model :payments, "Payments", projects: :paid do
          field :amount, :integer
        end

        query :payments_of, "Payments", reads: :payments, by: :reception do
          param :visit_id, :id
        end

        scenario "a second payment is rejected" do
          given :paid, %{amount: 1}
          command :pay, %{amount: 1}
          rejected :paid_once
        end

        scenario "a payment of 0 is rejected" do
          command :pay, %{amount: 0}
          rejected :positive
        end
      end
      """,
      "clinic.ex"
    )

    :ok
  end

  test "the domain, its contexts, a contract and what it holds, each with what connects it" do
    assert View.render(@domain, [@visits]) ==
             """
             domain clinic  2 contexts · 1 contract
             ├─ context settlement  Settlement · subdomain core (core) · 1 contract
             │  └─ contract #{inspect(@visits)}
             │     ├─ aggregate visit  1 cmd · 2 evts
             │     │  ├─ command pay  → paid
             │     │  ├─ event paid  ← pay
             │     │  └─ event noted  ← recorded by reception
             │     ├─ policy thank  ← paid → pay
             │     ├─ effect text  ← paid → sms
             │     ├─ read model payments  ← paid
             │     └─ query payments_of  → payments
             └─ context archive  Archive · subdomain generic (generic) · no contract\
             """
  end

  test "one branch, with the declarations under each row" do
    assert View.render(@domain, [@visits], path: [:settlement, :visit], details: true) ==
             """
             domain clinic  2 contexts · 1 contract
             └─ context settlement  Settlement · subdomain core (core) · 1 contract
                └─ contract #{inspect(@visits)}
                   └─ aggregate visit  1 cmd · 2 evts
                      │  identity: visit_id
                      │  invariant paid_once — A visit is paid once
                      ├─ command pay  → paid
                      │     visit_id: :id
                      │     amount: :integer
                      │     constraint positive — The amount is positive
                      ├─ event paid  ← pay
                      │     visit_id: :id
                      │     amount: :integer
                      └─ event noted  ← recorded by reception
                            visit_id: :id
                            sms_id: :id, issued by sms\
             """
  end

  # Plan DD, P2e (#220): a process module under the domain, after its contexts.
  test "a process module, its stages in order with the events each includes" do
    modules = [UniversalityGate.TreatmentEpisode, UniversalityGate.TreatmentEpisodeRun]
    tree = View.render(UniversalityGate.Domain, modules, details: true)

    assert tree =~ "domain universality_gate  1 context · 1 contract · 1 process\n"

    assert tree =~
             """
             └─ process universality_gate.treatment_episode_run  Treatment episode: from referral to closing · one per episode_id · 4 stages
                │  ends on payer_eligibility_denied, episode_closed, episode_abandoned
                │  deadline 30 days (unverified)
                │  promise referral_reaches_a_decision  referral_received → payer_eligibility_confirmed within 3 days, or else payer_eligibility_denied
                │  promise episode_reaches_an_end  treatment_plan_approved → episode_closed within 90 days, or else episode_abandoned
                ├─ stage qualification  ← UniversalityGate.TreatmentEpisode: referral_received, patient_identity_confirmed, payer_eligibility_checked, payer_eligibility_confirmed, payer_eligibility_denied
                ├─ stage plan  ← UniversalityGate.TreatmentEpisode: treatment_plan_approved
             """

    # One branch keeps a context, so no process under it; the root line still counts the
    # whole domain, as it counts its contexts and contracts (plan DD, P2e (#220),
    # review: it counted the processes shown).
    [context] = UniversalityGate.Domain.__ehos_contract_model__().contexts
    branch = View.render(UniversalityGate.Domain, modules, path: [context.name])
    assert branch =~ "domain universality_gate  1 context · 1 contract · 1 process\n"
    refute branch =~ "─ process"
  end

  # Plan DD, P2e (#220), review: a stage listed a contract twice when its
  # events were not adjacent, and a stage with nothing resolved ended in "← ".
  test "a stage's events by contract in first-appearance order, and a stage with none" do
    run = EhosContract.Model.fetch(DispatchRig.LedgerRun)

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

    tree =
      View.render(DispatchRig.Domain, [
        DispatchRig.Ledger,
        DispatchRig.Transfer,
        %{run | stages: stages, ends_on: []}
      ])

    assert tree =~
             "stage moving  ← DispatchRig.Ledger: deposited, withdrawn; " <>
               "DispatchRig.Transfer: account_moved\n"

    assert tree =~ "stage elsewhere  ← no included event resolves to a contract of the domain"
  end

  # Plan DD, P2e (#220), review: the tree said "one per a, b" where the report, the page
  # and the dashboard say "one per a and b".
  test "a process module's runs are told apart in the report's words" do
    run = EhosContract.Model.fetch(UniversalityGate.TreatmentEpisodeRun)
    modules = [UniversalityGate.TreatmentEpisode]

    assert View.render(
             UniversalityGate.Domain,
             modules ++ [%{run | correlate: [:episode_id, :payer_id]}]
           ) =~
             "closing · one per episode_id and payer_id · 4 stages"

    refute View.render(UniversalityGate.Domain, modules ++ [%{run | correlate: []}]) =~ "one per"
  end

  test "control: a contract of another domain is not in the tree" do
    refute View.render(@domain, [ProcessShapes.Bare]) =~ "ProcessShapes"
  end

  test "a path naming nothing is refused, not printed as an empty branch" do
    assert_raise ArgumentError,
                 ~r/context :settlement has no unit or other declaration :paid/,
                 fn ->
                   View.render(@domain, [@visits], path: [:settlement, :paid])
                 end

    assert_raise ArgumentError, ~r/has no context :billing/, fn ->
      View.render(@domain, [@visits], path: [:billing])
    end
  end
end
