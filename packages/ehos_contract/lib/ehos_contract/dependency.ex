defmodule EhosContract.Dependency do
  @moduledoc """
  Observations that a declared external dependency was unavailable.

  A domain declares its `external` systems and what their being unavailable looks like
  (`unavailable_looks_like`), and without a reader the sentence *"a timeout or an empty
  response: verification is suspended, not negative"* would be prose in Elixir syntax.
  This is its reader, and the fourth promise verdict is what it buys.

  ## Why the engine needs this at all

  A promise says *after X, eventually Y within N days*. When Y does not arrive, there are
  two completely different reasons and the log cannot tell them apart: the client's process
  stalled, or the authority the process depends on was not answering. Reported as one
  thing, they are reported as the first — so the evidence report tells a client they broke
  their own agreement while somebody else's server was down.

  That is the most expensive false positive this product can produce, because the report's
  only asset is being believed.

  ## Over-recording is worse than under-recording, and that decides the API

  A suspension **removes** a violation from the report. So a mechanism that recorded
  unavailability liberally would quietly stop reporting real problems — failing in the
  direction where nobody notices, which is the opposite of what the rest of this engine is
  built to do.

  Hence `observe/3` records only what an adapter states explicitly: `{:error, :unavailable}`
  and nothing else. A timeout the adapter reports as `{:error, :timeout}` is not an
  unavailability observation until somebody decides it is and says so in the adapter.

  ## Observations, not intervals

  An adapter knows one call failed. It never knows when the service returned, because
  nothing tells it — learning that requires asking repeatedly, which is a health checker
  and a different product. So each row is a moment, and "was this down during the window"
  is answered by whether any moment falls inside it.

  Nothing here is keyed by run. A registry being down does not happen to one company's
  month; it happens to everyone at once.
  """

  use Ecto.Schema

  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "ehos_contract_dependency_observations" do
    field(:contract, :string)
    field(:external, :string)
    field(:reason, :string)
    field(:observed_at, :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  @doc """
  Runs a call to an external system and records an observation if it reports being
  unavailable.

  Wrapping rather than asking each call site to remember, for the reason that keeps
  recurring here: a rule nobody is forced to follow is a rule that lapses — structure
  instead of discipline.

  Only `{:error, :unavailable}` counts. Every other result, including other errors, passes
  through untouched and unrecorded, because a suspension deletes a violation from the
  report and guessing in that direction hides real problems.

  The observation is stamped with `EhosContract.Clock.now/0`: the moment
  `EhosContract.Clock.at/2` sets, as for the events the same code appends, or now.

      def charge(customer, amount) do
        EhosContract.Dependency.observe(MyApp.Contracts.Payments, :payment_gateway, fn ->
          MyApp.Gateway.charge(customer, amount)
        end)
      end
  """
  @spec observe(module(), atom(), (-> term())) :: term()
  def observe(contract, external, fun) do
    case fun.() do
      {:error, :unavailable} = result ->
        unavailable!(contract, external, "the adapter reported :unavailable")
        result

      result ->
        result
    end
  end

  @doc """
  Records one observation that a dependency was unavailable.

  Refuses a dependency the contract does not use. That is a runtime check because the
  caller is an adapter and the name arrives as a value — but it is the same rule the
  compile gate applies to `depends_on`: an observation about something the contract
  never touches could not be about it, so recording it would be writing to a place
  nothing reads.

  A contract's externals are declared in its domain, and the contract uses one in two
  ways: an event `depends_on` it, or an effect `calls:` it. A promise reads an
  observation (`EhosContract.Trace`) when the event it awaits depends on the external,
  or when the promise `waits_on` it and the contract is one its process includes. An
  observation about an external only an effect calls suspends a promise only through
  the second, and is recorded all the same, because the adapter that makes the call
  is the one wrapped in `observe/3`, and refusing there would crash the effect in the
  middle of the outage it reports.

  A domain, or any module that is not a contract, is refused by name. `now` is the
  moment the outage was seen, `EhosContract.Clock.now/0` unless given.
  """
  # Recording an observation about an external only an effect calls was decided by the
  # user, 29 September 2026, in the review of plan E11a.
  @spec unavailable!(module(), atom()) :: t()
  @spec unavailable!(module(), atom(), String.t() | nil) :: t()
  @spec unavailable!(module(), atom(), String.t() | nil, DateTime.t()) :: t()
  def unavailable!(contract, external, reason \\ nil, now \\ EhosContract.Clock.now()) do
    unless external in used(contract) do
      raise ArgumentError,
            "#{inspect(contract)} uses no external #{inspect(external)}: no event of it " <>
              "`depends_on:` it and no effect `calls:` it, so an observation about it would " <>
              "be about nothing the contract does."
    end

    repo().insert!(%__MODULE__{
      contract: EhosContract.Model.fetch(contract).id,
      external: to_string(external),
      reason: reason,
      observed_at: now
    })
  end

  @spec used(module()) :: [atom()]
  defp used(contract) do
    case EhosContract.Model.fetch(contract) do
      %{kind: :contract, units: _} = model ->
        Enum.flat_map(model.events, &List.wrap(&1.depends_on)) ++
          Enum.flat_map(model.effects, &List.wrap(&1.calls))

      %{kind: kind} ->
        raise ArgumentError,
              "#{inspect(contract)} is a #{kind}, not a contract; an observation is recorded " <>
                "under the contract whose event or effect uses the external"
    end
  end

  # The moments each dependency of a contract was seen unavailable, by dependency name.
  #
  # One query for the whole evaluation, then filtered per run in memory: a promise is
  # evaluated once per run, and a query per run would make the report's cost grow with the
  # client's traffic.
  # Called by trace.ex.
  @doc false
  @spec observations_by_external(module(), keyword()) :: %{String.t() => [DateTime.t()]}
  def observations_by_external(contract, opts \\ []) do
    name = EhosContract.Model.fetch(contract).id

    from(o in __MODULE__, where: o.contract == ^name, select: {o.external, o.observed_at})
    |> bound(:>=, Keyword.get(opts, :since))
    |> bound(:<=, Keyword.get(opts, :until))
    |> repo().all()
    |> Enum.group_by(fn {external, _at} -> external end, fn {_external, at} -> at end)
  end

  # The moments each `{contract, external}` of `pairs` was seen unavailable, in one query
  # for a promise's whole evaluation: what its awaited events depend on, and what it
  # `waits_on` as observed by each contract its process includes. Not bounded in time,
  # as `observations_by_external/2` is not when a promise is judged.
  # Called by trace.ex.
  @doc false
  @spec observations([{module(), atom()}]) :: [DateTime.t()]
  def observations([]), do: []

  def observations(pairs) do
    wanted =
      MapSet.new(pairs, fn {contract, external} ->
        {EhosContract.Model.fetch(contract).id, to_string(external)}
      end)

    {contracts, externals} = Enum.unzip(wanted)

    from(o in __MODULE__,
      where: o.contract in ^Enum.uniq(contracts) and o.external in ^Enum.uniq(externals),
      select: {o.contract, o.external, o.observed_at}
    )
    |> repo().all()
    |> Enum.filter(fn {contract, external, _at} -> {contract, external} in wanted end)
    |> Enum.map(fn {_contract, _external, at} -> at end)
  end

  @spec bound(Ecto.Query.t(), :>= | :<=, DateTime.t() | nil) :: Ecto.Query.t()
  defp bound(query, _direction, nil), do: query
  defp bound(query, :>=, at), do: where(query, [o], o.observed_at >= ^at)
  defp bound(query, :<=, at), do: where(query, [o], o.observed_at <= ^at)

  # **Read at run time, not at compile time — and that changed when the engine
  # became its own application (2026-08-20).** `Application.compile_env!/2`
  # resolved to the host's repo module while compiling this package, and a package
  # compiles before the application that configures it: every call site warned that
  # the host's repo module was undefined, and in a real consumer it would warn about
  # theirs. A library cannot hold a compile-time reference to a module its user
  # has not written yet.
  #
  # What is lost is `compile_env!`'s check that configuration has not changed since
  # the build. What is gained is that this compiles standing alone, which is the
  # whole point of a package.
  defp repo, do: EhosContract.Config.fetch!(:repo)
end
