defmodule Mix.Tasks.Sandbox.Traffic do
  @shortdoc "Fills the development database with weeks of the case studies' runs, drift included"

  @moduledoc """
  Fills the development database with about six weeks of runs of the sandbox's three
  invented case studies, so that the dashboard's screens count something, drift included
  (publication programme, #389):

  - **paths never taken**: nobody places a hold on a withdrawn copy or closes a billing
    period by hand;
  - **a move the lifecycle does not allow**: the carrier reports a parcel delivered that
    the dispatcher never handed over;
  - **broken promises**: a parcel handed over two days after its payment, a copy still
    out after three weeks, a late fee neither paid nor waived in thirty days;
  - **promises kept the other way**: a late fee waived, a payment written off;
  - **promises suspended**: an invoice the gateway would not charge, inside a window in
    which the gateway was down, and an order unshipped while the carrier was;
  - **a process's deadline**: an order placed, never paid and never cancelled, past its
    two weeks;
  - **stages out of order**: a delivery reported for an order the warehouse never picked;
  - **a step that fails**: the gateway refusing two subscriptions' charges, until Oban
    gives up on them;
  - **refusals**: a loan on a suspended card, a second hold on a held copy, a pick list
    confirmed by a picker it is not assigned to, usage recorded on a cancelled
    subscription;
  - **what waits**: the overdue chase's next reminder, and every subscription's next
    period end.

  ## When to run it

  The runs go back about six weeks from the last full hour, each event stamped when it
  happened (`EhOsContract.Clock`), and what reacts to them runs then too: the task pushes
  the reactions through with `EhOsContract.Testing.drain/1` at each step and every hour
  between, so a timer fires on time. Six weeks, because the longest promise it breaks is
  thirty days, and billing closes its periods on the first of the month: the window always
  holds a first of the month at least four days old, so its invoices' three days are over.
  Run in the first four days of a month, it holds that month's first too, and billing
  closes a second period at it.

  From then on the data ages: a dashboard left running fires the timers that wait, and a
  promise still pending breaks once its window passes. So run it right before looking,
  on a database that holds nothing else:

      $ MIX_ENV=dev EH_OS_CONTRACT_DEV_DB=eh_os_contract_host_dev_traffic mix ecto.reset
      $ MIX_ENV=dev EH_OS_CONTRACT_DEV_DB=eh_os_contract_host_dev_traffic mix sandbox.traffic
      $ MIX_ENV=dev EH_OS_CONTRACT_DEV_DB=eh_os_contract_host_dev_traffic mix phx.server

  **The default development database is shared by every checkout of this repository on
  the machine**, and `mix ecto.reset` empties it for all of them; `EH_OS_CONTRACT_DEV_DB`
  names another (`config/dev.exs`). Mind its spelling: misspelled, the variable is not
  read, and `mix ecto.reset` empties the shared default. The task refuses a test
  database by its name, before anything is written. The task refuses a log that holds anything at all,
  since its hourly drains would push every other run's reactions through at the weeks'
  times; and it refuses while anything else is connected to the database, a dev server
  above all, since that server's subscriptions and Oban would react to the task's events
  as they arrive, stamped with today's time. Those two refusals come after the
  application's boot, which records the deployed versions as any dev server's boot does.

  Events carry the time of their step; two things carry the time the task ran: every
  command's record, accepted or refused, which the database stamps, and the process
  modules' "deployed since". A view of a period therefore counts the weeks' decisions as
  made today, while it counts their events when they happened.

  The steps are each domain's (`Lending.Traffic`, `Billing.Traffic`, `Fulfilment.Traffic`),
  as data: what to dispatch, refuse, record or observe as down, and when. The task runs
  them and checks each outcome; an unexpected one stops the run.

  **What it changes for its own run only:** nothing reacts by itself, since subscriptions
  and Oban are manual, and billing charges through `Billing.Traffic.Gateway`, which refuses
  two subscriptions and takes every other charge. The host's configuration stays as it is.
  """

  use Mix.Task
  use Boundary, top_level?: true, deps: [EhOsContract, Lending, Billing, Fulfilment], exports: []

  alias EhOsContract.{Clock, Dependency, Rejection, Testing}

  # How far back the runs go, in hours, and so the first drain: the deploy, at which
  # every consumer subscribes before the first event. Six weeks: see the moduledoc.
  @hours 45 * 24

  # The name this task's own connections give the database, so that it can tell them from
  # anyone else's.
  @connection "sandbox.traffic"

  @impl Mix.Task
  def run(_args) do
    unless Mix.env() == :dev do
      Mix.raise(
        "mix sandbox.traffic writes the development database only; run it with MIX_ENV=dev"
      )
    end

    Mix.Task.run("app.config")
    repo = Application.fetch_env!(:eh_os_contract_host, EhOsContractHost.Repo)

    # Before the application starts, since its boot already writes the deployment rows:
    # a test database's log is empty between runs, so the refusals below would let it
    # through, and rows committed there break every checkout's tests.
    if repo[:database] =~ ~r/(^|_)test(_|$)/ do
      Mix.raise("mix sandbox.traffic will not write #{repo[:database]}, a test database")
    end

    parameters = Keyword.put(repo[:parameters] || [], :application_name, @connection)

    Application.put_env(
      :eh_os_contract_host,
      EhOsContractHost.Repo,
      Keyword.put(repo, :parameters, parameters)
    )

    Application.put_env(:eh_os_contract, :subscriptions, :manual)
    oban = Application.fetch_env!(:eh_os_contract_host, Oban)
    Application.put_env(:eh_os_contract_host, Oban, Keyword.put(oban, :testing, :manual))

    Application.put_env(:eh_os_contract_host, Billing.Adapters.PaymentGateway,
      impl: Billing.Traffic.Gateway
    )

    Mix.Task.run("app.start")

    refuse_a_shared_database!()

    now = %{DateTime.truncate(DateTime.utc_now(), :second) | minute: 0, second: 0}
    steps = Lending.Traffic.steps() ++ Billing.Traffic.steps(now) ++ Fulfilment.Traffic.steps()
    drains = for hours_ago <- @hours..1//-1, do: {hours_ago, nil, nil}

    for {hours_ago, what, operations} <- Enum.sort_by(steps ++ drains, &elem(&1, 0), :desc) do
      at = DateTime.add(now, -round(hours_ago * 3600))

      if operations do
        Mix.shell().info("#{Calendar.strftime(at, "%Y-%m-%d %H:%M")} UTC  #{what}")
        Clock.at(at, fn -> Enum.each(operations.(), &run_operation/1) end)
      end

      Clock.at(at, fn -> drain() end)
    end

    # Once more at the real time, so the timers still waiting are scheduled against it
    # rather than against the last hour.
    drain()

    database = Application.fetch_env!(:eh_os_contract_host, EhOsContractHost.Repo)[:database]

    Mix.shell().info("""

    Done, in #{database}. The dashboard on it:

        EH_OS_CONTRACT_DEV_DB=#{database} mix phx.server

    then http://localhost:4010/dashboard
    """)
  end

  # The effects the gateway refuses fail on purpose, as Oban's; a subscription that fails
  # is a policy or a read model broken, and the log after it would be partial.
  defp drain do
    case Testing.drain() do
      %{failing: []} ->
        :ok

      %{failing: failing} ->
        Mix.raise("subscriptions failing at #{Clock.now()}: #{inspect(failing)}")
    end
  end

  defp run_operation({:ok, contract, command, actor}) do
    case EhOsContract.dispatch(contract, command, actor: actor) do
      {:ok, _receipt} -> :ok
      other -> Mix.raise("#{inspect(command.__struct__)} was not decided: #{inspect(other)}")
    end
  end

  defp run_operation({:refused, contract, command, actor, invariant}) do
    case EhOsContract.dispatch(contract, command, actor: actor) do
      {:error, %Rejection{invariant: ^invariant}} ->
        :ok

      other ->
        Mix.raise("#{inspect(command.__struct__)} was meant to be refused: #{inspect(other)}")
    end
  end

  defp run_operation({:recorded, contract, event, actor}) do
    case EhOsContract.record(contract, event, actor: actor) do
      {:ok, _receipt} -> :ok
      other -> Mix.raise("#{inspect(event.__struct__)} was not recorded: #{inspect(other)}")
    end
  end

  defp run_operation({:outage, contract, external, reason}),
    do: Dependency.unavailable!(contract, external, reason)

  # The task fills an empty log, alone. A log holding anything would have its reactions
  # pushed through at the weeks' times; anyone else connected, a dev server above all,
  # would react to the task's events at today's.
  defp refuse_a_shared_database! do
    repo = EhOsContract.Config.fetch!(:repo)

    if repo.exists?(EhOsContract.Event) do
      Mix.raise(
        "The development database's log is not empty. Empty it first with mix ecto.reset; " <>
          "the default database is every checkout's on this machine, so name one of your " <>
          "own with EH_OS_CONTRACT_DEV_DB"
      )
    end

    %{rows: [[others]]} =
      repo.query!(
        "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() " <>
          "AND backend_type = 'client backend' AND pid <> pg_backend_pid() " <>
          "AND coalesce(application_name, '') <> $1",
        [@connection]
      )

    if others > 0 do
      Mix.raise(
        "#{others} other connection(s) to the development database: stop the dev server " <>
          "(and anything else using it) first, since it would react to the task's events"
      )
    end
  end
end
