defmodule PNS.Deployment do
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

  Both hashes now come from `PNS.Digest`, so neither depends on term encoding,
  module load order or OTP release. That was originally true here and not of
  `version/0`, which used `:erlang.term_to_binary/1` — an OTP upgrade could have
  reclassified the whole log as belonging to an older agreement. Fixed by moving
  both to one canonical form rather than by hardening one of them.
  """

  use Ecto.Schema

  import Ecto.Query

  @repo Application.compile_env!(:pns_prototype, :repo)

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "pns_deployments" do
    field :contract, :string
    field :contract_version, :string
    field :wiring_version, :string
    field :events, {:array, :string}
    field :edges, {:array, :string}
    field :first_seen_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{}
  @type change :: %{
          events_added: [String.t()],
          events_removed: [String.t()],
          paths_added: [String.t()],
          paths_removed: [String.t()]
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
      for contract <- PNS.Registry.contracts() do
        events = contract.event_names() |> Enum.map(&to_string/1) |> Enum.sort()
        edges = contract |> edge_labels() |> Enum.sort()

        %{
          id: Ecto.UUID.generate(),
          contract: inspect(contract),
          contract_version: contract.version(),
          # Sorted above, so the list order carries no meaning by the time it gets
          # here — which is the one case where `PNS.Digest` needs the caller's help,
          # since it preserves list order on purpose.
          wiring_version: PNS.Digest.hash(edges),
          events: events,
          edges: edges,
          first_seen_at: now
        }
      end

    repo().insert_all(__MODULE__, rows,
      on_conflict: :nothing,
      conflict_target: [:contract, :contract_version, :wiring_version]
    )

    :ok
  end

  @doc "Every recorded deployment of a contract, oldest first."
  @spec all(module()) :: [t()]
  def all(contract) do
    name = inspect(contract)

    repo().all(
      from d in __MODULE__,
        where: d.contract == ^name,
        order_by: [asc: d.first_seen_at]
    )
  end

  @doc """
  Whether an edge was declared under **any** recorded deployment.

  This is what separates legitimate history from drift for paths. `false` means
  either genuine drift or a log older than this table; the caller decides how to
  read that, and `PNS.Graph` says which.
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
  """
  @spec diff(t(), t()) :: change()
  def diff(%__MODULE__{} = old, %__MODULE__{} = new) do
    %{
      events_added: new.events -- old.events,
      events_removed: old.events -- new.events,
      paths_added: new.edges -- old.edges,
      paths_removed: old.edges -- new.edges
    }
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
    current = Enum.find(recorded, &(&1.contract_version == contract.version()))
    in_log = versions_in_log(contract, opts)

    %{
      contract: contract,
      deployed: %{
        contract_version: contract.version(),
        wiring_version: current && current.wiring_version,
        since: current && Enum.find_value(in_log, &(&1.contract_version == current.contract_version && &1.first_at))
      },
      in_log: in_log,
      changed: last_change(recorded),
      from_earlier_versions:
        in_log
        |> Enum.reject(&(&1.contract_version == contract.version()))
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
    from(e in PNS.Event, where: e.contract == ^name)
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
    for handler <- PNS.Registry.handlers(),
        handler.contract == contract,
        published <- handler.publishes do
      edge_label(handler.event, published)
    end
  end

  @spec edge_label(atom() | String.t(), atom() | String.t()) :: String.t()
  defp edge_label(from, to), do: "#{from}->#{to}"

  defp repo, do: @repo
end
