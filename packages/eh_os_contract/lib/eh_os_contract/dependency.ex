defmodule EhOsContract.Dependency do
  @moduledoc """
  Observations that a declared external dependency was unavailable.

  `external` and `unavailable_looks_like` have been in the contract since the first day
  and nothing read them — the sentence *"a timeout or an empty response: verification is
  suspended, not negative"* was prose in Elixir syntax. This is its reader, and the fourth
  assertion verdict is what it buys.

  ## Why the engine needs this at all

  A `trace` says *after X, eventually Y within N days*. When Y does not arrive, there are
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

  schema "eh_os_contract_dependency_observations" do
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
  recurring here: a rule nobody is forced to follow is a rule that lapses. The same shape
  as `EhOsContract.Telemetry.handler_span/2` — structure instead of discipline.

  Only `{:error, :unavailable}` counts. Every other result, including other errors, passes
  through untouched and unrecorded, because a suspension deletes a violation from the
  report and guessing in that direction hides real problems.
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

  Refuses a dependency the contract does not declare. That is a runtime check because the
  caller is an adapter and the name arrives as a value — but it is the same rule the
  compile gate applies to `depends_on`: an observation about something undeclared cannot
  reach any assertion, so recording it would be writing to a place nothing reads.
  """
  @spec unavailable!(module(), atom(), String.t() | nil) :: t()
  def unavailable!(contract, external, reason \\ nil, now \\ DateTime.utc_now()) do
    unless Enum.any?(contract.externals(), &(&1.name == external)) do
      raise ArgumentError,
            "#{inspect(contract)} does not declare `external #{inspect(external)}`, so an " <>
              "observation about it could never reach an assertion. Declare the dependency " <>
              "in the contract, which is also where the client says what its being " <>
              "unavailable looks like."
    end

    repo().insert!(%__MODULE__{
      contract: inspect(contract),
      external: to_string(external),
      reason: reason,
      observed_at: now
    })
  end

  @doc """
  The moments each dependency of a contract was seen unavailable, by dependency name.

  One query for the whole evaluation, then filtered per run in memory — the same shape as
  `EhOsContract.HandlerFailure.runs_by_handler/1`, and for the same reason: an assertion is
  evaluated once per run, and a query per run would make the report's cost grow with the
  client's traffic.
  """
  @spec observations_by_external(module(), keyword()) :: %{String.t() => [DateTime.t()]}
  def observations_by_external(contract, opts \\ []) do
    name = inspect(contract)

    from(o in __MODULE__, where: o.contract == ^name, select: {o.external, o.observed_at})
    |> bound(:>=, Keyword.get(opts, :since))
    |> bound(:<=, Keyword.get(opts, :until))
    |> repo().all()
    |> Enum.group_by(fn {external, _at} -> external end, fn {_external, at} -> at end)
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
  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end
