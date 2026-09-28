defmodule Taxvision.AccountingMonthTest do
  @moduledoc """
  Opening a month across TaxVision's two contracts, dispatched in the host (v2 plan,
  E9c): the accountant's check, the registries asked by the effect, the comparison,
  the policy that opens the month — and a month later the timer that checks the next
  period on its own (P1). The registries are `Taxvision.Adapters.RegistryLookup.Fake`.
  """

  use Taxvision.DataCase, async: false

  alias EhOsContract.{Actor, Clock, Event, Testing, Trace}
  alias Taxvision.Contracts.{AccountingMonth, RegistryWatch}
  alias Taxvision.Contracts.AccountingMonth.Commands.OpenMonth
  alias Taxvision.Contracts.RegistryWatch.Commands.{CompleteCompanyProfile, RetriggerVerification}

  @at ~U[2026-09-01 06:00:00Z]

  defp accountant(company) do
    capabilities =
      ~w(taxvision.complete_company_profile taxvision.retrigger_verification taxvision.open_month)

    Actor.credential(
      "u-accountant",
      capabilities,
      Map.new(capabilities, &{&1, %{"company_id" => [company]}})
    )
  end

  defp types, do: Repo.all(from(e in Event, order_by: e.position, select: e.type))

  defp profile!(company) do
    {:ok, _} =
      EhOsContract.dispatch(
        RegistryWatch,
        %CompleteCompanyProfile{company_id: company, legal_form: "JDG", vat_status: "czynny"},
        actor: accountant(company)
      )
  end

  defp retrigger!(company, period) do
    {:ok, _} =
      Clock.at(@at, fn ->
        EhOsContract.dispatch(
          RegistryWatch,
          %RetriggerVerification{company_id: company, period_id: period},
          actor: accountant(company)
        )
      end)

    Clock.at(@at, fn -> Testing.drain() end)
  end

  # The registries answer for one company what the test says, the rest as the fake does.
  defp registries(answers) do
    previous = Application.get_env(:eh_os_contract_host, Taxvision.Adapters.RegistryLookup.Fake)

    Application.put_env(:eh_os_contract_host, Taxvision.Adapters.RegistryLookup.Fake,
      responses: answers
    )

    on_exit(fn ->
      if previous,
        do:
          Application.put_env(
            :eh_os_contract_host,
            Taxvision.Adapters.RegistryLookup.Fake,
            previous
          ),
        else: Application.delete_env(:eh_os_contract_host, Taxvision.Adapters.RegistryLookup.Fake)
    end)
  end

  setup do
    Testing.drain()
    :ok
  end

  test "the data agrees: the registries are asked, the check logged, and the policy opens the month" do
    profile!("c-1")
    retrigger!("c-1", "2026-08")

    assert types() == [
             "client.company_profile_completed",
             "client.data_completeness_confirmed",
             "client.registry_status_checked",
             "client.registry_check_logged",
             "client.registry_data_consistent",
             "accounting_month.accounting_month_opened"
           ]

    assert [%{verdict: :satisfied, via: :eventually}] =
             Trace.evaluate(AccountingMonth, :month_opens_or_is_blocked,
               now: DateTime.add(@at, 3600)
             )
  end

  test "the company is struck off the VAT register: blocked, and the accountant cannot open it by hand" do
    registries(%{
      "c-2" => {:ok, %{legal_form: "JDG", vat_status: "wykreślony", vies_status: "aktywny"}}
    })

    profile!("c-2")
    retrigger!("c-2", "2026-08")

    assert "client.registry_discrepancy_detected" in types()
    refute "accounting_month.accounting_month_opened" in types()

    assert {:error, %EhOsContract.Rejection{invariant: :opens_only_on_consistent_registry}} =
             EhOsContract.dispatch(
               AccountingMonth,
               %OpenMonth{company_id: "c-2", period_id: "2026-08"},
               actor: accountant("c-2")
             )

    # The promise keeps the other way: the month is blocked, not forgotten.
    assert [%{verdict: :satisfied, via: :or_else}] =
             Trace.evaluate(AccountingMonth, :month_opens_or_is_blocked,
               now: DateTime.add(@at, 3600)
             )
  end

  test "a month after August is checked, the timer checks September by itself" do
    profile!("c-1")
    retrigger!("c-1", "2026-08")

    # Not yet: a day short of a month.
    Clock.at(~U[2026-09-30 06:00:00Z], fn -> Testing.drain() end)

    refute Enum.any?(
             Repo.all(from(e in Event, select: e.payload)),
             &(&1["period_id"] == "2026-09")
           )

    Clock.at(~U[2026-10-01 07:00:00Z], fn -> Testing.drain() end)

    september =
      Repo.all(
        from(e in Event,
          where: fragment("? @> ?::text[]", e.tags, ^["period_id:2026-09"]),
          order_by: e.position,
          select: e.type
        )
      )

    assert september == [
             "client.data_completeness_confirmed",
             "client.registry_status_checked",
             "client.registry_check_logged",
             "client.registry_data_consistent",
             "accounting_month.accounting_month_opened"
           ]
  end

  test "a period named otherwise than YYYY-MM is refused before anything is decided" do
    profile!("c-1")

    assert {:error, {:invalid, [period_id: {:invariant, :named_by_month}]}} =
             EhOsContract.dispatch(
               RegistryWatch,
               %RetriggerVerification{company_id: "c-1", period_id: "2026-8"},
               actor: accountant("c-1")
             )
  end
end
