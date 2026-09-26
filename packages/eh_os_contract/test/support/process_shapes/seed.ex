defmodule ProcessShapes.Seed do
  @moduledoc """
  The same runs, written into a v1 process shape and into its v2 port (v2 plan, E7c).

  The acceptance criterion of E7c is that the same scenarios give the same numbers of
  verdicts on the new log. A test states a scenario once, through the functions here,
  for `:v1` and for `:v2`, and compares what the readers answer. v1 emits; v2
  dispatches, and the refusal notice waits for `drain/1` where v1's waits for its job.

  **A v2 test deploys first** (`deploy/1`): the first `EhOsContract.Testing.drain/1`
  registers the subscriptions, and a new policy leaves what is already in the log
  alone, so a refusal dispatched before it would never be notified.

  Goes when v1 does (E11), with `:v1` and the v1 shapes.
  """

  alias EhOsContract.{Actor, Testing}
  alias ProcessShapes.Next

  @actor Actor.credential("u-1", [
           "process_shapes.submit_request",
           "process_shapes.decide_request",
           "process_shapes.start_run",
           "process_shapes.finish_run",
           "process_shapes.open_batch",
           "process_shapes.close_batch"
         ])

  @doc "The shape of request handling: the contract module each side is written in."
  @spec promised(:v1 | :v2) :: module()
  def promised(:v1), do: ProcessShapes.Promised
  def promised(:v2), do: Next.Promised

  @doc "The shape of a timed run."
  @spec timed(:v1 | :v2) :: module()
  def timed(:v1), do: ProcessShapes.Timed
  def timed(:v2), do: Next.Timed

  @doc "The shape of a batch run."
  @spec bare(:v1 | :v2) :: module()
  def bare(:v1), do: ProcessShapes.Bare
  def bare(:v2), do: Next.Bare

  @doc "Registers the subscriptions, which on v2 is the deploy. Nothing to do on v1."
  @spec deploy(:v1 | :v2) :: :ok
  def deploy(:v1), do: :ok

  def deploy(:v2) do
    _ = Testing.drain()
    :ok
  end

  @doc "A request arrives and is decided, `:request_approved` or `:request_refused`."
  @spec request(:v1 | :v2, String.t(), :request_approved | :request_refused) :: :ok
  def request(:v1, id, decision) do
    {:ok, _} =
      EhOsContract.emit_all(ProcessShapes.Promised, [
        EhOsContract.event(:request_received, %{request_id: id}),
        EhOsContract.event(decision, %{request_id: id})
      ])

    :ok
  end

  def request(:v2, id, decision) do
    dispatch(Next.Promised, %Next.Promised.Commands.SubmitRequest{request_id: id})

    dispatch(Next.Promised, %Next.Promised.Commands.DecideRequest{
      request_id: id,
      approve: decision == :request_approved
    })
  end

  @doc "Runs what waits after the transaction: v1's jobs, v2's subscriptions and jobs."
  @spec run_queue(:v1 | :v2) :: :ok
  def run_queue(:v1) do
    _ = Oban.drain_queue(queue: :events)
    :ok
  end

  def run_queue(:v2) do
    %{failing: []} = Testing.drain()
    :ok
  end

  @doc """
  One fact of request handling at a moment, written into the log directly, since
  that is the only way to place one event alone at a time a test chooses. Its home
  run comes with it, as with any append.
  """
  @spec fact(:v1 | :v2, atom(), String.t(), DateTime.t()) :: EhOsContract.Event.t()
  def fact(shape, name, request_id, at) do
    contract = promised(shape)
    repo = Application.fetch_env!(:eh_os_contract, :repo)

    entry = %{
      type: stored(shape, "handling", name),
      contract: inspect(contract),
      contract_version: EhOsContract.Model.fetch(contract).version,
      process: "handling",
      instance_id: "handling|#{request_id}",
      correlation_id: Ecto.UUID.generate(),
      actor: EhOsContract.Event.system_actor(),
      payload: %{"request_id" => request_id},
      occurred_at: at
    }

    {:ok, {:ok, [event]}} =
      repo.transaction(fn -> EhOsContract.Store.append(repo, [entry], :none) end)

    event
  end

  @doc "A timed run starts at a moment."
  @spec start_run(:v1 | :v2, String.t(), DateTime.t()) :: :ok
  def start_run(:v1, id, at),
    do: at(at, fn -> EhOsContract.emit!(ProcessShapes.Timed, :run_started, %{run_id: id}) end)

  def start_run(:v2, id, at),
    do: at(at, fn -> dispatch(Next.Timed, %Next.Timed.Commands.StartRun{run_id: id}) end)

  @doc "A timed run finishes at a moment."
  @spec finish_run(:v1 | :v2, String.t(), DateTime.t()) :: :ok
  def finish_run(:v1, id, at),
    do: at(at, fn -> EhOsContract.emit!(ProcessShapes.Timed, :run_finished, %{run_id: id}) end)

  def finish_run(:v2, id, at),
    do: at(at, fn -> dispatch(Next.Timed, %Next.Timed.Commands.FinishRun{run_id: id}) end)

  @doc "The type an event of a shape is stored under: its name in v1, prefixed in v2."
  @spec stored(:v1 | :v2, String.t(), atom()) :: String.t()
  def stored(:v1, _process, name), do: Atom.to_string(name)
  def stored(:v2, process, name), do: "#{process}.#{name}"

  defp at(at, fun) do
    EhOsContract.Clock.at(at, fun)
    :ok
  end

  defp dispatch(contract, command) do
    {:ok, _} = EhOsContract.dispatch(contract, command, actor: @actor)
    :ok
  end
end
