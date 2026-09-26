defmodule EhOsContract.Deployment do
  @moduledoc """
  Which version is deployed, since when, and what changed — the screen's fourth
  question.

  ## Why the contract version is not enough on its own

  `contract_version` is a hash of the contract's declarations, stamped on every
  event. It answers *which agreement was in force when this happened*, and that
  is the question it should answer.

  It cannot answer *was this path declared at the time*, and the reason is
  structural: paths come from handlers' `publishes:` declarations, and handlers
  are not part of the contract. Delete a handler and the graph loses an edge
  while every version stamped anywhere stays identical. The overlay then sees an
  observed edge that is no longer declared, finds the contract version still
  current, and reports **drift** — for a path that was legitimately declared
  when it ran.

  So a deployment has two identities. The contract version is the agreement; the
  wiring version is the code. A refactor moves one and not the other, which is
  exactly the distinction the client cares about.

  ## What is recorded, and what that costs

  One row per distinct wiring that has booted, written at startup. Nothing is
  recorded per event, so this costs one insert per deploy rather than a column on
  every event — and the log stays the artifact it was.

  The price is that provenance is only as good as the record: a log written
  before this table existed has no deployment covering it, and those edges fall
  back to the older heuristic based on `contract_version` alone. That fallback is
  documented rather than silent, because a report that guesses without saying so
  is worse than one that admits the gap.

  Both hashes now come from `EhOsContract.Digest`, so neither depends on term encoding,
  module load order or OTP release. That was originally true here and not of
  `version/0`, which used `:erlang.term_to_binary/1` — an OTP upgrade could have
  reclassified the whole log as belonging to an older agreement. Fixed by moving
  both to one canonical form rather than by hardening one of them.
  """

  use Ecto.Schema

  import Ecto.Query

  alias EhOsContract.Model

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "eh_os_contract_deployments" do
    field(:contract, :string)
    field(:contract_version, :string)
    field(:wiring_version, :string)
    field(:events, {:array, :string})
    field(:edges, {:array, :string})
    # One digest per declaration, from the contract's generated `declaration_digests/0`
    # — a function on each contract module, not on `EhOsContract.Contract`. Nullable,
    # because a row written before this column existed does not know what its
    # contract declared, and `%{}` would claim it declared nothing.
    field(:declaration_digests, :map)
    field(:first_seen_at, :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}
  @type declaration_change :: %{
          added: [String.t()],
          removed: [String.t()],
          changed: [String.t()]
        }
  @type change :: %{
          events_added: [String.t()],
          events_removed: [String.t()],
          paths_added: [String.t()],
          paths_removed: [String.t()],
          declarations: declaration_change() | :not_recorded
        }

  @doc """
  Records the currently deployed wiring for every registered contract.

  Idempotent: booting the same code twice leaves one row, so `first_seen_at` is
  the first time this wiring ran rather than the last time the node restarted.
  Called at startup, because the graph has to come from the binary that runs.
  """
  @spec record!(DateTime.t()) :: :ok
  def record!(now \\ DateTime.utc_now()) do
    rows =
      for(contract <- EhOsContract.Registry.v2_contracts(), do: v2_row(contract, now)) ++
        for contract <- EhOsContract.Registry.contracts() do
          events = contract |> Model.event_names() |> Enum.map(&to_string/1) |> Enum.sort()
          edges = contract |> edge_labels() |> Enum.sort()

          %{
            id: Ecto.UUID.generate(),
            contract: inspect(contract),
            contract_version: Model.version(contract),
            # Sorted above, so the list order carries no meaning by the time it gets
            # here — which is the one case where `EhOsContract.Digest` needs the caller's help,
            # since it preserves list order on purpose.
            wiring_version: EhOsContract.Digest.hash(edges),
            events: events,
            edges: edges,
            declaration_digests: Model.digests(contract),
            first_seen_at: now
          }
        end

    # `{:replace, ...}` rather than `:nothing`, and the difference matters exactly
    # once: the first boot after the column exists meets a row recorded before it,
    # and `:nothing` would leave that row's digests null forever — blind for the
    # version that is actually deployed, which is the one anybody asks about.
    #
    # Replacing is sound because the value is a function of the conflict target.
    # `contract_version` is a hash of the same declarations, so a row carrying
    # today's version *has* today's declarations. `first_seen_at` is untouched, so
    # no history is rewritten. Were that functional dependency ever to stop
    # holding, this would become falsification of history rather than a backfill.
    repo().insert_all(__MODULE__, rows,
      on_conflict: {:replace, [:declaration_digests]},
      conflict_target: [:contract, :contract_version, :wiring_version]
    )

    :ok
  end

  # A v2 contract's paths are its steps (`EhOsContract.Paths`), declared by the
  # contract itself, so they move its version. What only the code says is which
  # module implements each declaration: that, with the steps, is its wiring. A
  # promise gets a digest of its own here, so a changed promise has a boundary
  # (`declaration_boundaries/1`) where the model only digests the whole process.
  @spec v2_row(module(), DateTime.t()) :: map()
  defp v2_row(contract, now) do
    model = Model.fetch(contract)
    edges = contract |> v2_edge_labels() |> Enum.sort()

    bindings =
      for {{^contract, kind, name}, modules} <-
            EhOsContract.Implementations.index(contract).declarations,
          module <- modules,
          do: "#{kind}:#{name}=#{inspect(module)}"

    promises =
      for promise <- (model.process && model.process.promises) || [],
          into: %{},
          do: {"promise:#{promise.name}", promise_digest(promise)}

    %{
      id: Ecto.UUID.generate(),
      contract: inspect(contract),
      contract_version: model.version,
      wiring_version: EhOsContract.Digest.hash(edges ++ Enum.sort(bindings)),
      events: model.events |> Enum.map(&to_string(&1.name)) |> Enum.sort(),
      edges: edges,
      declaration_digests: Map.merge(model.digests, promises),
      first_seen_at: now
    }
  end

  @doc """
  A promise's digest at a deploy: of its rule — `from`, `eventually`, `within`,
  `or_else` — and nothing else. Confirming it (`unverified`) or citing a new `source`
  changes no run's verdict, so it must not draw a boundary that stops judging the
  runs before it. Public for its test.
  """
  @spec promise_digest(map()) :: String.t()
  def promise_digest(promise),
    do: promise |> Map.take([:from, :eventually, :within, :or_else]) |> EhOsContract.Digest.hash()

  @doc """
  A v2 contract's declared steps as the labels a deployment records:
  `"<kind>:<name>-><kind>:<name>"`, with the consumer between them for a reaction,
  a timer and an effect.
  """
  @spec v2_edge_labels(module()) :: [String.t()]
  def v2_edge_labels(contract) do
    for step <- EhOsContract.Paths.declared(contract) do
      [step.from, step.via, step.to]
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join("->", &"#{&1.kind}:#{&1.name}")
    end
  end

  @doc "Every recorded deployment of a contract, oldest first."
  @spec all(module()) :: [t()]
  def all(contract) do
    name = inspect(contract)

    repo().all(
      from(d in __MODULE__,
        where: d.contract == ^name,
        order_by: [asc: d.first_seen_at]
      )
    )
  end

  @doc """
  Whether an edge was declared under **any** recorded deployment.

  This is what separates legitimate history from drift for paths. `false` means
  either genuine drift or a log older than this table; the caller decides how to
  read that, and `EhOsContract.Graph` says which.
  """
  @spec declared_edge?(module(), {atom() | String.t(), atom() | String.t()}) :: boolean()
  def declared_edge?(contract, {from, to}) do
    label = edge_label(from, to)
    Enum.any?(all(contract), &(label in &1.edges))
  end

  @doc """
  What changed between two recorded deployments.

  Paths are reported separately from events because they move independently: a
  handler can add a path without the contract changing at all.

  `declarations` is the part event names and edges could never show. A `trace`
  whose `within` moved, an event whose `retain` or `identity` moved, a process
  whose `instance` moved, a payload type that changed — all of them move
  `contract_version` and none of them adds or removes an event or a path, so
  until this key existed the diff reported a change to the agreement as four
  empty lists.

  It is `:not_recorded` when either side predates the column. "Compared, nothing
  moved" and "could not be compared" are different statements, and collapsing
  them would put a false negative exactly where the mechanism is meant to speak.
  """
  @spec diff(t(), t()) :: change()
  def diff(%__MODULE__{} = old, %__MODULE__{} = new) do
    %{
      events_added: new.events -- old.events,
      events_removed: old.events -- new.events,
      paths_added: new.edges -- old.edges,
      paths_removed: old.edges -- new.edges,
      declarations: declaration_diff(old.declaration_digests, new.declaration_digests)
    }
  end

  @spec declaration_diff(map() | nil, map() | nil) :: declaration_change() | :not_recorded
  defp declaration_diff(nil, _new), do: :not_recorded
  defp declaration_diff(_old, nil), do: :not_recorded

  defp declaration_diff(old, new) do
    %{
      added: new |> Map.keys() |> Kernel.--(Map.keys(old)) |> Enum.sort(),
      removed: old |> Map.keys() |> Kernel.--(Map.keys(new)) |> Enum.sort(),
      changed:
        new
        |> Enum.filter(fn {key, digest} -> Map.has_key?(old, key) and old[key] != digest end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()
    }
  end

  @doc """
  When each declaration last changed, for one contract.

  The answer `EhOsContract.Conformance` needs in order to stop folding runs judged under a
  superseded promise into the same counts as runs judged under the current one.

  Three exclusions, each of which would otherwise be a lie. Rows with no recorded
  digests drop out **before** pairing, so the day the column arrived does not read
  as "every declaration changed at once". A key absent from the older row is a
  birth rather than a change, because no run can have been judged under a rule
  that did not yet exist. And a later change overwrites an earlier one, so the
  value is the *last* time this declaration moved, not the first.
  """
  @spec declaration_boundaries(module()) :: %{String.t() => DateTime.t()}
  def declaration_boundaries(contract) do
    contract
    |> all()
    |> Enum.reject(&is_nil(&1.declaration_digests))
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(%{}, fn [old, new], boundaries ->
      for {key, digest} <- new.declaration_digests,
          Map.has_key?(old.declaration_digests, key),
          old.declaration_digests[key] != digest,
          into: boundaries do
        {key, new.first_seen_at}
      end
    end)
  end

  @doc """
  The fourth question, assembled for one contract: what is deployed, since when,
  which versions the log holds, and what the last change was.

  `since` is the first time an event was seen under the deployed wiring, not a
  deploy timestamp — the engine is not told about deploys, it observes them. A
  deployment that has emitted nothing yet has `since: nil`, which is honest: it
  is deployed and unproven.
  """
  @spec report(module(), keyword()) :: map()
  def report(contract, opts \\ []) do
    recorded = all(contract)
    current = Enum.find(recorded, &(&1.contract_version == Model.version(contract)))
    in_log = versions_in_log(contract, opts)

    %{
      contract: contract,
      deployed: %{
        contract_version: Model.version(contract),
        wiring_version: current && current.wiring_version,
        since:
          current &&
            Enum.find_value(
              in_log,
              &(&1.contract_version == current.contract_version && &1.first_at)
            )
      },
      in_log: in_log,
      changed: last_change(recorded),
      from_earlier_versions:
        in_log
        |> Enum.reject(&(&1.contract_version == Model.version(contract)))
        |> Enum.map(& &1.events)
        |> Enum.sum()
    }
  end

  @doc "Contract versions present in the log, with counts and time ranges."
  @spec versions_in_log(module(), keyword()) :: [map()]
  def versions_in_log(contract, opts \\ []) do
    name = inspect(contract)

    # Built by composition rather than with `is_nil(^since) or ...`: Ecto refuses
    # to compare a field with a pinned nil, and rightly so — the comparison would
    # silently be neither true nor false.
    from(e in EhOsContract.Event, where: e.contract == ^name)
    |> bound(:>=, Keyword.get(opts, :since))
    |> bound(:<=, Keyword.get(opts, :until))
    |> group_by([e], e.contract_version)
    |> order_by([e], asc: min(e.occurred_at))
    |> select([e], %{
      contract_version: e.contract_version,
      events: count(e.id),
      first_at: min(e.occurred_at),
      last_at: max(e.occurred_at)
    })
    |> repo().all()
  end

  @spec bound(Ecto.Query.t(), :>= | :<=, DateTime.t() | nil) :: Ecto.Query.t()
  defp bound(query, _direction, nil), do: query
  defp bound(query, :>=, at), do: where(query, [e], e.occurred_at >= ^at)
  defp bound(query, :<=, at), do: where(query, [e], e.occurred_at <= ^at)

  @spec last_change([t()]) :: change() | nil
  defp last_change([_ | _] = recorded) do
    case Enum.take(recorded, -2) do
      [old, new] -> diff(old, new)
      _ -> nil
    end
  end

  defp last_change(_), do: nil

  @spec edge_labels(module()) :: [String.t()]
  defp edge_labels(contract) do
    for handler <- EhOsContract.Registry.handlers(),
        handler.contract == contract,
        published <- handler.publishes do
      edge_label(handler.event, published)
    end
  end

  @spec edge_label(atom() | String.t(), atom() | String.t()) :: String.t()
  defp edge_label(from, to), do: "#{from}->#{to}"

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
