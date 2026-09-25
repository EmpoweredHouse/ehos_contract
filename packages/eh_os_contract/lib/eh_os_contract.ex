defmodule EhOsContract do
  @moduledoc """
  The package's public surface.

  What would be the `eh_os_contract` hex package — kept in `lib/eh_os_contract/` beside the client
  application in `lib/taxvision/`, with the boundary enforced by `boundary` from
  the first commit. The structure is the one notes §15 foresee for the first
  client, so moving it out beside the client's repository is a `git mv`.
  """

  use Boundary,
    deps: [],
    exports: [
      AsyncAPI,
      Check,
      Clock,
      Conformance,
      Conformance.Wire,
      Contract,
      ContractExample,
      Deployment,
      Domain,
      {Domain.Dsl, []},
      Duration,
      Emission,
      Emitter,
      Event,
      EventHandling,
      Graph,
      Handler,
      Implementation,
      Instance,
      Job,
      Meta,
      Migrations,
      Model,
      Next.Contract,
      {Next.Contract.Dsl, []},
      Payload,
      Registry,
      Rejection,
      Report,
      Report.Sentence,
      Store,
      Store.Postgres,
      Store.Suite,
      Trace
    ]

  # Read from `mix.exs` at compile time rather than through
  # `Application.spec(:eh_os_contract, :vsn)`, which returns a charlist and needs the
  # application loaded — neither of which a report renderer should have to care
  # about. This is the package reading its own project file, so it carries no
  # host configuration into a compile-time attribute.
  @version Mix.Project.config()[:version]

  @doc """
  The engine version, as published.

  A conformance report is an arithmetic result, and this repository has already
  changed what counts as drift more than once — zero runs, work still queued,
  "never attempted" against "attempted and failing", the fourth verdict. Two
  clients on two engine versions get two answers to the same question, and the
  report is evidence somebody may be asked to defend. The version says which
  arithmetic produced it. `CHANGELOG.md` says what each one changed.
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Boots the engine inside the host's supervision tree, after the host's repo and Oban:

      children = [
        MyApp.Repo,
        {Oban, Application.fetch_env!(:my_app, Oban)},
        EhOsContract,
        MyAppWeb.Endpoint
      ]

  Two things have to happen at boot, in this order, and a host used to call both by
  hand: `EhOsContract.Registry.load!/1` scans the running binary for contracts and
  handlers, and `EhOsContract.Deployment.record!/1` writes what that binary declared
  and since when. Forgetting the first leaves an empty graph; forgetting the second
  leaves the report unable to tell history from drift. As a child the pair cannot
  be half-remembered, and its position in the list states the dependency on the
  repo that a comment used to.

  The child does its work while the supervisor starts and then returns `:ignore` —
  there is no process to keep alive. If either step raises, the host fails to boot,
  which is the point: a host running with an unscanned registry reports nothing and
  looks healthy.
  """
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    %{id: __MODULE__, start: {__MODULE__, :boot, []}, restart: :temporary}
  end

  @doc false
  @spec boot() :: :ignore
  def boot do
    EhOsContract.Registry.load!()
    EhOsContract.Deployment.record!()
    :ignore
  end

  @doc "An intention to emit an event, returned by a pure decision function."
  @spec event(atom(), map()) :: EhOsContract.Emission.t()
  def event(name, payload \\ %{}), do: %EhOsContract.Emission{name: name, payload: payload}

  defdelegate emit(contract, type, payload, ctx \\ %{}), to: EhOsContract.Emitter
  defdelegate emit!(contract, type, payload, ctx \\ %{}), to: EhOsContract.Emitter
  defdelegate emit_all(contract, emissions, ctx \\ %{}), to: EhOsContract.Emitter
end
