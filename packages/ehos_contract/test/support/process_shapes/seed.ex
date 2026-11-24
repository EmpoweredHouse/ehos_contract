defmodule ProcessShapes.Seed do
  @moduledoc """
  Runs of the process shapes, written the way the tests on them need (v2 plan, E7c):
  dispatched through the shapes' commands, or, for one fact alone at a moment a test
  chooses, appended to the log directly.

  **A test deploys first** (`deploy/0`): the first `EhosContract.Testing.drain/1`
  registers the subscriptions, and a new policy leaves what is already in the log
  alone, so a refusal dispatched before it would never be notified.
  """

  alias EhosContract.{Actor, Testing}
  alias ProcessShapes.{Promised, Timed}

  @actor Actor.credential("u-1", [
           "process_shapes.submit_request",
           "process_shapes.decide_request",
           "process_shapes.start_run",
           "process_shapes.finish_run",
           "process_shapes.open_batch",
           "process_shapes.close_batch"
         ])

  @doc "Registers the subscriptions, which is what a deploy does."
  @spec deploy() :: :ok
  def deploy do
    _ = Testing.drain()
    :ok
  end

  @doc "A request arrives and is decided, `:request_approved` or `:request_refused`."
  @spec request(String.t(), :request_approved | :request_refused) :: :ok
  def request(id, decision) do
    dispatch(Promised, %Promised.Commands.SubmitRequest{request_id: id})

    dispatch(Promised, %Promised.Commands.DecideRequest{
      request_id: id,
      approve: decision == :request_approved
    })
  end

  @doc "Runs what waits after the transaction: the subscriptions and their jobs."
  @spec run_queue() :: :ok
  def run_queue do
    %{failing: []} = Testing.drain()
    :ok
  end

  @doc """
  One fact of request handling at a moment, written into the log directly, since
  that is the only way to place one event alone at a time a test chooses. Its run,
  `ProcessShapes.Handling`'s, comes with it, as dispatch would file it.
  """
  @spec fact(atom(), String.t(), DateTime.t()) :: EhosContract.Event.t()
  def fact(name, request_id, at) do
    repo = Application.fetch_env!(:ehos_contract, :repo)

    entry = %{
      type: "process_shapes.promised.#{name}",
      contract: EhosContract.Model.fetch(Promised).id,
      contract_version: EhosContract.Model.fetch(Promised).version,
      runs: [{"process_shapes.handling", "process_shapes.handling|#{request_id}"}],
      correlation_id: Ecto.UUID.generate(),
      actor: EhosContract.Event.system_actor(),
      payload: %{"request_id" => request_id},
      occurred_at: at
    }

    {:ok, {:ok, [event]}} =
      repo.transaction(fn -> EhosContract.Store.append(repo, [entry], :none) end)

    event
  end

  @doc "A timed run starts at a moment."
  @spec start_run(String.t(), DateTime.t()) :: :ok
  def start_run(id, at),
    do: at(at, fn -> dispatch(Timed, %Timed.Commands.StartRun{run_id: id}) end)

  @doc "A timed run finishes at a moment."
  @spec finish_run(String.t(), DateTime.t()) :: :ok
  def finish_run(id, at),
    do: at(at, fn -> dispatch(Timed, %Timed.Commands.FinishRun{run_id: id}) end)

  defp at(at, fun) do
    EhosContract.Clock.at(at, fun)
    :ok
  end

  defp dispatch(contract, command) do
    {:ok, _} = EhosContract.dispatch(contract, command, actor: @actor)
    :ok
  end
end
