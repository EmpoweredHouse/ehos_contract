defmodule Mix.Tasks.GraphLab.Traffic do
  @shortdoc "Fills the development database with runs of the graph's test set, drift included"

  @moduledoc """
  Fills the development database with runs of the test set for drawing the graph
  (`GraphLab`), so that the numbers the graph lays over its contracts and processes count
  something, drift included:

  - **paths taken, and some never**: nobody adds a service in the room or hands a visit
    over, and no patient confirms in the patient app — no bus brings the app's message to
    this host, so that path stays untraversed;
  - **a move the lifecycle does not allow**: a patient leaving the room whom reception
    never saw arrive (Ewa);
  - **broken promises**: a report to P1 sent three days after the visit (Filip), a visit
    nobody closed or settled (Ewa), till days left open past the evening;
  - **a process's deadline**: a till day closed after its two days, and one still open
    past them;
  - **stages out of order**: a visit closed clinically before the patient's leaving was
    recorded (Jan). The documentation chase then starts after the close that ends it, and
    creates a task for a visit already closed; and the visit's promise to P1 has nothing
    left to keep it, since the report went before the leaving it counts from;
  - **a step that fails**: an SMS sent while the gateway was down, which Oban gave up on
    (Grażyna);
  - **refusals**: an invoice with a visit neither marked nor excluded, a count of a
    closed till, a second refund for one visit — whose correction stands;
  - **what waits**: the chases' timers of a visit that ended an hour ago (Henryk); run
    between 20:00 and 21:00 in Warsaw, his visit ends at the full hour instead, after the
    clinic's evening, so the settlement chase waits for the next one.

  ## When to run it

  The runs go back about a week from the last full hour, each event stamped when it
  happened (`EhOsContract.Clock`), and what reacts to them runs then too: the task pushes
  the reactions through with `EhOsContract.Testing.drain/1` at each step and every half
  hour between, so a timer fires on time. From then on the data ages: a dashboard left
  running fires the timers that wait, and a promise still pending breaks once its window
  passes. So run it right before testing, against the development database only:

      $ cd sandbox && mix ecto.reset && mix graph_lab.traffic

  **The development database is shared by every checkout of this repository on the
  machine**, so `mix ecto.reset` empties it for all of them. The task refuses a log that
  holds anything at all, since its half-hourly drains would push every other tree's
  reactions through at the week's times; and it refuses while anything else is connected
  to the database, a dev server above all, since that server's subscriptions and Oban
  would react to the task's events as they arrive, stamped with today's time.

  It prints the command that starts the dashboard with the test set alone: the other
  client trees left out (`config :eh_os_contract, exclude:`), and the credential
  verifier's audience naming the set's domain, both on the command line.

  Events carry the time of their step; two things carry the time the task ran: every
  command's record, accepted or refused, which the database stamps, and the process
  modules' "deployed since". A view of a period therefore counts the week's decisions
  as made today, while it counts their events when they happened.

  **What it changes for its own run only:** nothing reacts by itself — subscriptions and
  Oban are manual — and the engine reads services from `GraphLab.Entities`, not from the
  catalogue the host configures. The host's configuration stays as it is.
  """

  use Mix.Task
  use Boundary, classify_to: GraphLab

  alias EhOsContract.{Actor, Clock, Rejection, Testing}
  alias GraphLab.Contracts.{ClinicalDocumentation, ExternalPayers, Scheduling, Settlement, Till}

  alias GraphLab.Contracts.ClinicalDocumentation.Commands.{
    CloseVisitClinically,
    CodeDiagnosis,
    WriteNote
  }

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
                  graph-lab.close_till_day graph-lab.pay_out_refund)
             )

  @specialist Actor.credential(
                "specialist-ewa",
                ~w(graph-lab.visit_completed graph-lab.code_diagnosis graph-lab.write_note
                   graph-lab.close_visit_clinically)
              )

  @luxmed "payer-luxmed"

  # The manager is granted LuxMed, the one payer the runs charge.
  @manager Actor.credential(
             "manager-iza",
             ~w(graph-lab.exclude_visit_from_invoice graph-lab.issue_payer_invoice),
             %{
               "graph-lab.exclude_visit_from_invoice" => %{"payer_id" => [@luxmed]},
               "graph-lab.issue_payer_invoice" => %{"payer_id" => [@luxmed]}
             }
           )

  @physiotherapy "service-physiotherapy"
  @fitness "service-fitness"

  # How far back the runs go, in hours, and so the first drain: the deploy, at which every
  # consumer subscribes before the first event.
  @hours 170

  # The namespaces the dashboard leaves out to show the test set alone, and the audience
  # that names the set's domain: the credential verifier stops a host whose audience names
  # none of the domains it runs, and TaxVision's is left out.
  @others ["Taxvision.", "Rehmed.", "AppuniteEquipment."]
  @audience "graph-lab/dev"

  # The name this task's own connections give the database, so that it can tell them from
  # anyone else's.
  @connection "graph_lab.traffic"

  @impl Mix.Task
  def run(_args) do
    unless Mix.env() == :dev do
      Mix.raise(
        "mix graph_lab.traffic writes the development database only; run it with MIX_ENV=dev"
      )
    end

    Mix.Task.run("app.config")
    repo = Application.fetch_env!(:eh_os_contract_host, Taxvision.Repo)
    parameters = Keyword.put(repo[:parameters] || [], :application_name, @connection)

    Application.put_env(
      :eh_os_contract_host,
      Taxvision.Repo,
      Keyword.put(repo, :parameters, parameters)
    )

    Application.put_env(:eh_os_contract, :subscriptions, :manual)
    Application.put_env(:eh_os_contract, :entities, GraphLab.Entities)
    oban = Application.fetch_env!(:eh_os_contract_host, Oban)
    Application.put_env(:eh_os_contract_host, Oban, Keyword.put(oban, :testing, :manual))
    Mix.Task.run("app.start")

    refuse_a_shared_database!()

    # The last full hour, so the half-hourly drains fall on the clock's half hours, where
    # the settlement chase's evening is.
    now = %{DateTime.truncate(DateTime.utc_now(), :second) | minute: 0, second: 0}
    drains = for half <- (2 * @hours)..1//-1, do: {half / 2, nil, nil}

    for {hours_ago, what, step} <- Enum.sort_by(steps(now) ++ drains, &elem(&1, 0), :desc) do
      at = DateTime.add(now, -round(hours_ago * 3600))

      if step do
        Mix.shell().info("#{Calendar.strftime(at, "%Y-%m-%d %H:%M")} UTC  #{what}")
        Clock.at(at, step)
      end

      Clock.at(at, fn -> Testing.drain() end)
    end

    # Once more at the real time, so the timers still waiting are scheduled against it
    # rather than against the last half hour.
    Testing.drain()

    Mix.shell().info("""

    Done. The dashboard with the test set alone:

        ERL_AFLAGS='-eh_os_contract exclude #{erlang_strings(@others)} -eh_os_contract_auth audience #{erlang_string(@audience)}' mix phx.server

    then http://localhost:4010/dashboard/graph
    """)
  end

  # Each step: how many hours ago it happened, what happened, and the call.
  defp steps(now) do
    period = Calendar.strftime(DateTime.add(now, -126 * 3600), "%Y-%m")
    # A till day is named by the clinic's date, in Warsaw.
    day = fn hours_ago ->
      now
      |> DateTime.add(-round(hours_ago * 3600))
      |> DateTime.shift_zone!("Europe/Warsaw")
      |> DateTime.to_date()
    end

    visits(period, henryk(now)) ++ payers(period) ++ till(day)
  end

  # How much later Henryk's visit ends than an hour ago. The settlement chase is due at
  # the clinic's evening, 20:00 in Warsaw, or the next one for a visit ending after it; a
  # visit ending in the hour before it, with the task run after it, would leave nothing
  # waiting. So, run then, his visit ends at the full hour, after the evening.
  defp henryk(now) do
    if DateTime.shift_zone!(now, "Europe/Warsaw").hour == 20, do: 1, else: 0
  end

  defp visits(period, later) do
    [
      # Anna: the whole way, kept — confirmed, noted, reported to P1, paid, then corrected
      # twice: the first correction is refunded, the second's refund is refused.
      {150, "Anna booked for physiotherapy", fn -> book("anna", @physiotherapy, 4) end},
      {149, "Anna's visit confirmed by phone", fn -> confirm("anna") end},
      {146, "Anna arrived", fn -> arrived("anna") end},
      {145, "Anna left the room", fn -> left("anna") end},
      {144.9, "Anna paid by card", fn -> pay("anna", :card, 20_000) end},
      {144.8, "Anna's visit settled", fn -> settle("anna", 20_000) end},
      {144.7, "Anna's note written", fn -> note("anna") end},
      {144.5, "Anna's diagnosis coded", fn -> code("anna") end},
      {144, "Anna's visit closed clinically", fn -> close_clinically("anna", true) end},
      {120, "Anna's settlement corrected by 10 zł down", fn -> correct("anna", -1_000) end},
      {119.5, "Anna's refund paid out",
       fn -> ok(Till, %PayOutRefund{visit_id: id("anna")}, @reception) end},
      {119, "Anna's settlement corrected by 5 zł more: the till refuses a second refund",
       fn -> correct("anna", -500) end},

      # Ben: fitness, nothing owed to P1, LuxMed pays.
      {126, "Ben booked for fitness", fn -> book("ben", @fitness, 4) end},
      {122, "Ben arrived", fn -> arrived("ben") end},
      {121, "Ben left the room", fn -> left("ben") end},
      {120.5, "Ben's visit closed clinically, without codes",
       fn -> close_clinically("ben", false) end},
      {120.2, "Ben's visit closed for LuxMed", fn -> settle_for_payer("ben", period) end},

      # Irena: physiotherapy for LuxMed, later excluded from the invoice.
      {100, "Irena booked for physiotherapy", fn -> book("irena", @physiotherapy, 2) end},
      {98, "Irena arrived", fn -> arrived("irena") end},
      {97, "Irena left the room", fn -> left("irena") end},
      {96.8, "Irena's visit closed for LuxMed", fn -> settle_for_payer("irena", period) end},
      {96.5, "Irena's note written", fn -> note("irena") end},
      {96, "Irena's visit closed clinically", fn -> close_clinically("irena", true) end},

      # Filip: the report to P1 goes three days after the visit — the promise is broken.
      {101, "Filip booked for physiotherapy", fn -> book("filip", @physiotherapy, 2) end},
      {99, "Filip arrived", fn -> arrived("filip") end},
      {98.5, "Filip left the room", fn -> left("filip") end},
      {98.2, "Filip paid in cash", fn -> pay("filip", :cash, 20_000) end},
      {98, "Filip's visit settled", fn -> settle("filip", 20_000) end},
      {26, "Filip's visit closed clinically, late", fn -> close_clinically("filip", true) end},

      # Celina cancels; Dawid confirms and does not come.
      {80, "Celina booked", fn -> book("celina", @physiotherapy, 20) end},
      {70, "Celina cancelled",
       fn -> ok(Scheduling, %CancelVisit{visit_id: id("celina")}, @reception) end},
      {75, "Dawid booked", fn -> book("dawid", @fitness, 25) end},
      {74, "Dawid's visit confirmed by phone", fn -> confirm("dawid") end},
      {50, "Dawid did not come",
       fn -> ok(Scheduling, %RecordNoShow{visit_id: id("dawid")}, @reception) end},

      # Ewa: the specialist records her leaving, reception never saw her arrive (a move the
      # lifecycle does not allow); nobody closes or settles the visit, so both chases fire
      # and both promises break.
      {72, "Ewa booked for physiotherapy", fn -> book("ewa", @physiotherapy, 1) end},
      {70.5, "Ewa left the room, her arrival never recorded", fn -> left("ewa") end},

      # Jan: closed clinically before his leaving was recorded — stages out of order, a
      # task for a closed visit, and a promise nothing can keep (see the moduledoc).
      {31, "Jan booked for physiotherapy", fn -> book("jan", @physiotherapy, 1.5) end},
      {29.5, "Jan arrived", fn -> arrived("jan") end},
      {28.7, "Jan's note written", fn -> note("jan") end},
      {28.5, "Jan's visit closed clinically", fn -> close_clinically("jan", true) end},
      {27.5, "Jan left the room, recorded after the close", fn -> left("jan") end},
      {27, "Jan paid by transfer", fn -> pay("jan", :transfer, 20_000) end},
      {26.5, "Jan's visit settled", fn -> settle("jan", 20_000) end},

      # Grażyna: booked for tomorrow while the SMS gateway was down — her reminder fails
      # until Oban gives up.
      {20, "Grażyna booked, the SMS gateway down",
       fn -> gateway_down(fn -> book("grazyna", @fitness, 44) end) end},

      # Henryk left an hour ago: both chases' timers wait. Krystyna's visit is tomorrow.
      {3 - later, "Henryk booked", fn -> book("henryk", @physiotherapy, 1) end},
      {2 - later, "Henryk arrived", fn -> arrived("henryk") end},
      {1.2 - later, "Henryk's note written", fn -> note("henryk") end},
      {1 - later, "Henryk left the room", fn -> left("henryk") end},
      {2.5, "Krystyna booked for tomorrow", fn -> book("krystyna", @physiotherapy, 26.5) end},
      {0.5, "Krystyna's visit confirmed by phone", fn -> confirm("krystyna") end}
    ]
  end

  # Ben's and Irena's visits are charged to LuxMed in one period.
  defp payers(period) do
    [
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
    ]
  end

  # The till: a day closed as it should be; one closed after its two days; one left open
  # past them; one left open overnight; and today's. Opened at least 24 hours apart, so no
  # two share a date.
  defp till(day) do
    closed = day.(152)
    late = day.(100)
    abandoned = day.(60)
    overnight = day.(30.5)
    today = day.(0.5)

    [
      {152, "the till opened on #{closed}", fn -> open_till(closed) end},
      {140, "the till's cash counted on #{closed}", fn -> count(closed, 120_000) end},
      {139, "the till closed on #{closed}", fn -> close_till(closed) end},
      {138, "a count after the close is refused",
       fn ->
         refused(
           Till,
           %CountCash{day_id: "#{closed}", counted: 125_000},
           @reception,
           :only_an_open_day_changes
         )
       end},
      {100, "the till opened on #{late}", fn -> open_till(late) end},
      {60.5, "the till's cash counted on #{late}", fn -> count(late, 95_000) end},
      {45, "the till of #{late} closed, after its two days", fn -> close_till(late) end},
      {60, "the till opened on #{abandoned}, and never closed", fn -> open_till(abandoned) end},
      {30.5, "the till opened on #{overnight}", fn -> open_till(overnight) end},
      {20.5, "the till's cash counted on #{overnight}, and the day not closed",
       fn -> count(overnight, 80_000) end},
      {0.5, "the till opened on #{today}", fn -> open_till(today) end}
    ]
  end

  # The library gives the visit its number; the later steps of the visit find it by name.
  # The visit is `in_hours` after the booking.
  defp book(name, service, in_hours) do
    booking = %BookVisit{
      patient_id: "patient-#{name}",
      service_id: service,
      specialist_id: "specialist-ewa",
      scheduled_at: DateTime.add(Clock.now(), round(in_hours * 3600))
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

  defp note(name) do
    ok(
      ClinicalDocumentation,
      %WriteNote{
        visit_id: id(name),
        patient_id: "patient-#{name}",
        text: "History and examination"
      },
      @specialist
    )
  end

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

  # A correction downwards owes the patient a refund through the till's policy; a refusal
  # of that refund leaves the correction standing.
  defp correct(name, delta),
    do: ok(Settlement, %BookCorrection{visit_id: id(name), delta: delta}, @reception)

  defp mark_settled_with_payer(name, period) do
    ok(
      ExternalPayers,
      %MarkSettledWithPayer{payer_id: @luxmed, period_id: period, visit_id: id(name)},
      @reception
    )
  end

  defp open_till(day), do: ok(Till, %OpenTillDay{day_id: "#{day}"}, @reception)

  defp count(day, counted),
    do: ok(Till, %CountCash{day_id: "#{day}", counted: counted}, @reception)

  defp close_till(day), do: ok(Till, %CloseTillDay{day_id: "#{day}"}, @reception)

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

  # The task fills an empty log, alone. A log holding anything — the set's runs from
  # before, or another tree's — would have its reactions pushed through at the week's
  # times; anyone else connected, a dev server above all, would react to the task's events
  # at today's.
  defp refuse_a_shared_database! do
    repo = EhOsContract.Config.fetch!(:repo)

    if repo.exists?(EhOsContract.Event) do
      Mix.raise(
        "The development database's log is not empty. Empty it first with mix ecto.reset, " <>
          "which empties it for every checkout on this machine"
      )
    end

    %{rows: [[others]]} =
      repo.query!(
        "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() " <>
          "AND pid <> pg_backend_pid() AND coalesce(application_name, '') <> $1",
        [@connection]
      )

    if others > 0 do
      Mix.raise(
        "#{others} other connection(s) to the development database: stop the dev server " <>
          "(and anything else using it) first, since it would react to the task's events"
      )
    end
  end

  # Strings as Erlang binaries in bytes: the shell keeps no quotes inside ERL_AFLAGS.
  defp erlang_strings(strings), do: "[" <> Enum.map_join(strings, ",", &erlang_string/1) <> "]"

  defp erlang_string(string), do: "<<#{Enum.join(:binary.bin_to_list(string), ",")}>>"
end
