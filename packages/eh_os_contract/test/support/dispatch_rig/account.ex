defmodule DispatchRig.Account do
  @moduledoc """
  **Invented.** The decider of `DispatchRig.Ledger`'s account.

  Two things here exist only for tests. `misbehave/2` builds an event the command
  does not emit without `emit/1`, which would have refused it at compile time.
  And a test can make the next `deposit/2` append to the same stream behind the
  decision's back, `Process.put(:dispatch_rig_race, true)`, so that the append
  meets a stream that moved: the conflict dispatch retries. And it can make the
  next deposit decide an event for another account,
  `Process.put(:dispatch_rig_stray, "a-2")`, which dispatch has to refuse.
  """

  use DispatchRig.Ledger, aggregate: :account

  @impl true
  def open_account(%OpenAccount{account_id: id, branch_id: branch}, _state),
    do: emit(%AccountOpened{account_id: id, branch_id: branch})

  @impl true
  def deposit(%Deposit{account_id: id, amount: amount}, _state) do
    if Process.delete(:dispatch_rig_race), do: race(id)
    emit(%Deposited{account_id: Process.delete(:dispatch_rig_stray) || id, amount: amount})
  end

  @impl true
  def withdraw(%Withdraw{account_id: id, amount: amount}, %State{balance: balance}) do
    if amount > balance,
      do: reject(:balance_never_negative),
      else: emit(%Withdrawn{account_id: id, amount: amount})
  end

  @impl true
  def flag_account(%FlagAccount{account_id: id}, _state),
    do: emit(%AccountFlagged{account_id: id})

  @impl true
  def misbehave(%Misbehave{account_id: id}, _state),
    do: {:ok, [%Withdrawn{account_id: id, amount: 1}]}

  @impl true
  def evolve(state, %Deposited{amount: amount}), do: %{state | balance: state.balance + amount}
  def evolve(state, %Withdrawn{amount: amount}), do: %{state | balance: state.balance - amount}

  def evolve(state, %InterestRecorded{amount: amount}),
    do: %{state | balance: state.balance + amount}

  def evolve(state, _opened), do: state

  # Another writer's event in the stream, appended at the version the decision read.
  defp race(id) do
    repo = Application.fetch_env!(:eh_os_contract, :repo)
    stream = EhOsContract.Key.stream(:account, [id])
    version = length(EhOsContract.Store.read_stream(repo, stream, 0))

    {:ok, _} =
      EhOsContract.Store.append(
        repo,
        [
          %{
            type: "ledger.deposited",
            contract: inspect(DispatchRig.Ledger),
            contract_version: "race",
            correlation_id: Ecto.UUID.generate(),
            actor: "system:race",
            occurred_at: EhOsContract.Clock.now(),
            payload: %{"account_id" => id, "amount" => 1}
          }
        ],
        {:stream, stream, version}
      )
  end
end
