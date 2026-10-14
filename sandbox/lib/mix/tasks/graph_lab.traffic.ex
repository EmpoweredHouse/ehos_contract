defmodule Mix.Tasks.GraphLab.Traffic do
  @shortdoc "Fills the development database with runs of the graph's test set, drift included"

  @moduledoc """
  Fills the development database with runs of the test set for drawing the graph
  (`GraphLab`), so that the numbers the graph lays over its contracts and processes count
  something, drift included:

  - **paths taken**, and some never: nobody adds a service in the room or hands a visit
    over, and no patient confirms in the app, since no bus brings the app's message;
  - **a move the lifecycle does not allow**: a patient leaving the room whom reception
    never saw arrive;
  - **broken promises**: a report to P1 sent three days after the visit, a visit nobody
    closed or settled, a till left open overnight;
  - **stages out of order**: a visit closed clinically before the patient's leaving was
    recorded;
  - **a step that fails**: an SMS sent while the gateway was down, which Oban gave up on;
  - **refusals**: an invoice with a visit neither marked nor excluded, a count of a closed
    till;
  - **what waits**: the chases' timers of a visit that ended an hour ago.

  The runs go back about a week from now, each event stamped when it happened
  (`EhOsContract.Clock`), and what reacts to them runs then too. Run it once, against the
  development database only:

      $ cd sandbox && mix graph_lab.traffic

  It prints the command that starts the dashboard with the test set alone: the other
  client trees left out (`config :eh_os_contract, exclude:`), and the credential
  verifier's audience naming the set's domain, both on the command line. A second run
  is refused: to fill the database again, empty it first with `mix ecto.reset`, which
  empties all of it.

  **What it changes for its own run only:** nothing reacts by itself — it pushes the
  reactions through with `EhOsContract.Testing.drain/1` at the moment of each step — and
  the engine reads services from `GraphLab.Entities`, not from the catalogue the host configures. The
  host's configuration stays as it is.
  """

  use Mix.Task
  use Boundary, classify_to: GraphLab

  import Ecto.Query

  alias EhOsContract.{Actor, Clock, Rejection, Testing}
  alias GraphLab.Contracts.{ClinicalDocumentation, ExternalPayers, Scheduling, Settlement, Till}
  alias GraphLab.Contracts.ClinicalDocumentation.Commands.{CloseVisitClinically, CodeDiagnosis}

  alias GraphLab.Contracts.ExternalPayers.Commands.{
    ExcludeVisitFromInvoice,
    IssuePayerInvoice,
    MarkSettledWithPayer
  }

  alias GraphLab.Contracts.Scheduling.Commands.{
    BookVisit,
    CancelVisit,
    ConfirmVisit,
    RecordNoShow
  }

  alias GraphLab.Contracts.Scheduling.Events.{PatientArrived, VisitCompleted}
  alias GraphLab.Contracts.Settlement.Commands.{BookCorrection, CloseSettlement, RecordPayment}
  alias GraphLab.Contracts.Till.Commands.{CloseTillDay, CountCash, OpenTillDay, PayOutRefund}

  @reception Actor.credential(
               "reception-ola",
               ~w(graph-lab.book_visit graph-lab.confirm_visit graph-lab.cancel_visit
                  graph-lab.record_no_show graph-lab.patient_arrived graph-lab.record_payment
                  graph-lab.close_settlement graph-lab.book_correction
                  graph-lab.mark_settled_with_payer graph-lab.open_till_day graph-lab.count_cash
                  graph-lab.pay_out_refund)
             )

  @specialist Actor.credential(
                "specialist-ewa",
                ~w(graph-lab.visit_completed graph-lab.code_diagnosis
                   graph-lab.close_visit_clinically)
              )

  @manager Actor.credential(
             "manager-iza",
             ~w(graph-lab.close_till_day graph-lab.exclude_visit_from_invoice
                graph-lab.issue_payer_invoice)
           )

  @physiotherapy "service-physiotherapy"
  @fitness "service-fitness"
  @luxmed "payer-luxmed"

  # The namespaces the dashboard leaves out to show the test set alone, and the audience
  # that names the set's domain: the credential verifier stops a host whose audience names
  # none of the domains it runs, and TaxVision's is left out.
  @others ["Taxvision.", "Rehmed.", "AppuniteEquipment."]
  @audience "graph-lab/dev"

  @impl Mix.Task
  def run(_args) do
    unless Mix.env() == :dev do
      Mix.raise(
        "mix graph_lab.traffic writes the development database only; run it with MIX_ENV=dev"
      )
    end

    Mix.Task.run("app.config")
    Application.put_env(:eh_os_contract, :subscriptions, :manual)
    Application.put_env(:eh_os_contract, :entities, GraphLab.Entities)
    oban = Application.fetch_env!(:eh_os_contract_host, Oban)
    Application.put_env(:eh_os_contract_host, Oban, Keyword.put(oban, :testing, :manual))
    Mix.Task.run("app.start")

    refuse_a_second_run!()

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    # The first drain is the deploy: every consumer subscribes before the first event.
    Clock.at(DateTime.add(now, -170 * 3600), fn -> Testing.drain() end)

    for {hours_ago, what, step} <- Enum.sort_by(steps(now), &elem(&1, 0), :desc) do
      at = DateTime.add(now, -round(hours_ago * 3600))
      Mix.shell().info("#{Calendar.strftime(at, "%Y-%m-%d %H:%M")} UTC  #{what}")
      Clock.at(at, step)
      Clock.at(at, fn -> Testing.drain() end)
    end

    Mix.shell().info("""

    Done. The dashboard with the test set alone:

        ERL_AFLAGS='-eh_os_contract exclude #{erlang_strings(@others)} -eh_os_contract_auth audience #{erlang_string(@audience)}' mix phx.server

    then http://localhost:4010/dashboard/graph
    """)
  end

  # Each step: how many hours ago it happened, what happened, and the call.
  defp steps(now) do
    period = Calendar.strftime(DateTime.add(now, -126 * 3600), "%Y-%m")
    day = fn hours_ago -> now |> DateTime.add(-hours_ago * 3600) |> DateTime.to_date() end

    visits(period) ++
      [
        # External payers: Ben's and Irena's visits are charged to LuxMed in one period.
        {119, "Ben's visit marked settled with LuxMed",
         fn -> mark_settled_with_payer("ben", period) end},
        {30, "the LuxMed invoice is refused: Irena's visit is neither marked nor excluded",
         fn ->
           refused(
             ExternalPayers,
             %IssuePayerInvoice{payer_id: @luxmed, period_id: period, invoice_id: "fv-luxmed-1"},
             @manager,
             :every_delivered_visit_settled_or_excluded
           )
         end},
        {29, "Irena's visit excluded from the invoice",
         fn ->
           ok(
             ExternalPayers,
             %ExcludeVisitFromInvoice{
               payer_id: @luxmed,
               period_id: period,
               visit_id: id("irena"),
               reason: "the patient used up the payer's allowance elsewhere"
             },
             @manager
           )
         end},
        {28, "the LuxMed invoice issued",
         fn ->
           ok(
             ExternalPayers,
             %IssuePayerInvoice{payer_id: @luxmed, period_id: period, invoice_id: "fv-luxmed-1"},
             @manager
           )
         end}
      ] ++ till(day)
  end

  defp visits(period) do
    [
      # Anna: the whole way, kept — confirmed, reported to P1, paid, then a refund.
      {150, "Anna booked for physiotherapy", fn -> book("anna", @physiotherapy) end},
      {149, "Anna's visit confirmed by phone", fn -> confirm("anna") end},
      {146, "Anna arrived", fn -> arrived("anna") end},
      {145, "Anna left the room", fn -> left("anna") end},
      {144.5, "Anna's diagnosis coded", fn -> code("anna") end},
      {144, "Anna's visit closed clinically", fn -> close_clinically("anna", true) end},
      {143.5, "Anna paid by card", fn -> pay("anna", :card, 20_000) end},
      {143, "Anna's visit settled", fn -> settle("anna", 20_000) end},
      {120, "Anna's settlement corrected by 10 zł down", fn -> correct("anna", -1_000) end},
      {119.5, "Anna's refund paid out",
       fn -> ok(Till, %PayOutRefund{visit_id: id("anna")}, @reception) end},

      # Ben: fitness, nothing owed to P1, LuxMed pays.
      {126, "Ben booked for fitness", fn -> book("ben", @fitness) end},
      {122, "Ben arrived", fn -> arrived("ben") end},
      {121, "Ben left the room", fn -> left("ben") end},
      {120.5, "Ben's visit closed clinically, without codes",
       fn -> close_clinically("ben", false) end},
      {120.2, "Ben's visit closed for LuxMed", fn -> settle_for_payer("ben", period) end},

      # Irena: physiotherapy for LuxMed, later excluded from the invoice.
      {100, "Irena booked for physiotherapy", fn -> book("irena", @physiotherapy) end},
      {98, "Irena arrived", fn -> arrived("irena") end},
      {97, "Irena left the room", fn -> left("irena") end},
      {96, "Irena's visit closed clinically", fn -> close_clinically("irena", true) end},
      {95, "Irena's visit closed for LuxMed", fn -> settle_for_payer("irena", period) end},

      # Filip: the report to P1 goes three days after the visit — the promise is broken.
      {101, "Filip booked for physiotherapy", fn -> book("filip", @physiotherapy) end},
      {99, "Filip arrived", fn -> arrived("filip") end},
      {98.5, "Filip left the room", fn -> left("filip") end},
      {98.2, "Filip paid in cash", fn -> pay("filip", :cash, 20_000) end},
      {98, "Filip's visit settled", fn -> settle("filip", 20_000) end},
      {26, "Filip's visit closed clinically, late", fn -> close_clinically("filip", true) end},

      # Celina cancels; Dawid confirms and does not come.
      {80, "Celina booked", fn -> book("celina", @physiotherapy) end},
      {70, "Celina cancelled",
       fn -> ok(Scheduling, %CancelVisit{visit_id: id("celina")}, @reception) end},
      {75, "Dawid booked", fn -> book("dawid", @fitness) end},
      {74, "Dawid's visit confirmed by phone", fn -> confirm("dawid") end},
      {50, "Dawid did not come",
       fn -> ok(Scheduling, %RecordNoShow{visit_id: id("dawid")}, @reception) end},

      # Ewa: the specialist records her leaving, reception never saw her arrive (a move the
      # lifecycle does not allow); nobody closes or settles the visit, so both chases fire
      # and both promises break.
      {72, "Ewa booked for physiotherapy", fn -> book("ewa", @physiotherapy) end},
      {70.5, "Ewa left the room, her arrival never recorded", fn -> left("ewa") end},

      # Jan: closed clinically before his leaving was recorded — stages out of order.
      {31, "Jan booked for physiotherapy", fn -> book("jan", @physiotherapy) end},
      {29.5, "Jan arrived", fn -> arrived("jan") end},
      {28.5, "Jan's visit closed clinically", fn -> close_clinically("jan", true) end},
      {27.5, "Jan left the room, recorded after the close", fn -> left("jan") end},
      {27, "Jan paid by transfer", fn -> pay("jan", :transfer, 20_000) end},
      {26.5, "Jan's visit settled", fn -> settle("jan", 20_000) end},

      # Grażyna: booked while the SMS gateway was down — her reminder fails until Oban gives up.
      {20, "Grażyna booked, the SMS gateway down",
       fn -> gateway_down(fn -> book("grazyna", @fitness) end) end},

      # Henryk left an hour ago: both chases' timers wait. Krystyna's visit is ahead.
      {3, "Henryk booked", fn -> book("henryk", @physiotherapy) end},
      {2, "Henryk arrived", fn -> arrived("henryk") end},
      {1, "Henryk left the room", fn -> left("henryk") end},
      {2.5, "Krystyna booked", fn -> book("krystyna", @physiotherapy) end},
      {0.5, "Krystyna's visit confirmed by phone", fn -> confirm("krystyna") end}
    ]
  end

  # The till: a day closed as it should be, a day left open overnight, and today's.
  defp till(day) do
    closed = day.(152)
    open = day.(30)
    today = day.(0)

    [
      {152, "the till opened on #{closed}",
       fn -> ok(Till, %OpenTillDay{day_id: "#{closed}"}, @reception) end},
      {140, "the till's cash counted on #{closed}", fn -> count(closed, 120_000) end},
      {139, "the till closed on #{closed}",
       fn -> ok(Till, %CloseTillDay{day_id: "#{closed}"}, @manager) end},
      {138, "a count after the close is refused",
       fn ->
         refused(
           Till,
           %CountCash{day_id: "#{closed}", counted: 125_000},
           @reception,
           :a_closed_day_does_not_change
         )
       end},
      {30.5, "the till opened on #{open}",
       fn -> ok(Till, %OpenTillDay{day_id: "#{open}"}, @reception) end},
      {20.5, "the till's cash counted on #{open}, and the day never closed",
       fn -> count(open, 80_000) end},
      {0.2, "the till opened on #{today}",
       fn -> ok(Till, %OpenTillDay{day_id: "#{today}"}, @reception) end}
    ]
  end

  # The library gives the visit its number; the later steps of the visit find it by name.
  defp book(name, service) do
    booking = %BookVisit{
      patient_id: "patient-#{name}",
      service_id: service,
      specialist_id: "specialist-ewa",
      scheduled_at: DateTime.add(Clock.now(), 2 * 3600)
    }

    case EhOsContract.dispatch(Scheduling, booking,
           actor: @reception,
           idempotency_key: "graph-lab-booking:#{name}"
         ) do
      {:ok, %{identity: %{visit_id: id}}} -> Process.put({__MODULE__, name}, id)
      other -> Mix.raise("#{name}'s booking was not decided: #{inspect(other)}")
    end
  end

  defp confirm(name), do: ok(Scheduling, %ConfirmVisit{visit_id: id(name)}, @reception)

  defp arrived(name), do: recorded(Scheduling, %PatientArrived{visit_id: id(name)}, @reception)

  defp left(name), do: recorded(Scheduling, %VisitCompleted{visit_id: id(name)}, @specialist)

  defp code(name) do
    ok(
      ClinicalDocumentation,
      %CodeDiagnosis{
        visit_id: id(name),
        patient_id: "patient-#{name}",
        icd10: "M54.5",
        icd9: "93.39"
      },
      @specialist
    )
  end

  defp close_clinically(name, codes?) do
    codes = if codes?, do: %{icd10: "M54.5", icd9: "93.39"}, else: %{}

    close =
      struct!(
        CloseVisitClinically,
        Map.merge(codes, %{
          visit_id: id(name),
          patient_id: "patient-#{name}",
          pesel: pesel(name),
          practitioner_number: "practitioner-ewa"
        })
      )

    ok(ClinicalDocumentation, close, @specialist)
  end

  defp pay(name, method, amount),
    do:
      ok(
        Settlement,
        %RecordPayment{visit_id: id(name), method: method, amount: amount},
        @reception
      )

  # The application's own dispatch gives the host-supplied total itself.
  defp settle(name, total),
    do: ok(Settlement, %CloseSettlement{visit_id: id(name), total: total}, @reception)

  defp settle_for_payer(name, period) do
    ok(
      Settlement,
      %CloseSettlement{visit_id: id(name), total: 18_000, payer_id: @luxmed, period_id: period},
      @reception
    )
  end

  defp correct(name, delta),
    do: ok(Settlement, %BookCorrection{visit_id: id(name), delta: delta}, @reception)

  defp mark_settled_with_payer(name, period) do
    ok(
      ExternalPayers,
      %MarkSettledWithPayer{payer_id: @luxmed, period_id: period, visit_id: id(name)},
      @reception
    )
  end

  defp count(day, counted),
    do: ok(Till, %CountCash{day_id: "#{day}", counted: counted}, @reception)

  # The send fails while the step and its drain run, so Oban spends its three attempts.
  defp gateway_down(fun) do
    key = GraphLab.PatientMessaging.SendSms
    Application.put_env(:eh_os_contract_host, key, gateway: :down)

    try do
      fun.()
      Testing.drain()
    after
      Application.delete_env(:eh_os_contract_host, key)
    end
  end

  defp ok(contract, command, actor) do
    case EhOsContract.dispatch(contract, command, actor: actor) do
      {:ok, _receipt} -> :ok
      other -> Mix.raise("#{inspect(command.__struct__)} was not decided: #{inspect(other)}")
    end
  end

  defp refused(contract, command, actor, invariant) do
    case EhOsContract.dispatch(contract, command, actor: actor) do
      {:error, %Rejection{invariant: ^invariant}} ->
        :ok

      other ->
        Mix.raise("#{inspect(command.__struct__)} was meant to be refused: #{inspect(other)}")
    end
  end

  defp recorded(contract, event, actor) do
    case EhOsContract.record(contract, event, actor: actor) do
      {:ok, _receipt} -> :ok
      other -> Mix.raise("#{inspect(event.__struct__)} was not recorded: #{inspect(other)}")
    end
  end

  defp id(name), do: Process.get({__MODULE__, name}) || Mix.raise("#{name} was never booked")

  defp pesel(name),
    do: "8" <> String.pad_leading("#{:erlang.phash2(name, 1_000_000_000)}", 10, "0")

  defp refuse_a_second_run! do
    repo = EhOsContract.Config.fetch!(:repo)

    if repo.exists?(from(e in EhOsContract.Event, where: like(e.type, "graph-lab.%"))) do
      Mix.raise(
        "The development database already holds the test set's runs. To fill it again, empty " <>
          "it first with mix ecto.reset, which empties all of it"
      )
    end
  end

  # Strings as Erlang binaries in bytes: the shell keeps no quotes inside ERL_AFLAGS.
  defp erlang_strings(strings), do: "[" <> Enum.map_join(strings, ",", &erlang_string/1) <> "]"

  defp erlang_string(string), do: "<<#{Enum.join(:binary.bin_to_list(string), ",")}>>"
end
