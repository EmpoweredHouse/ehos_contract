defmodule EhOsContract.Graph do
  @moduledoc """
  The contracts' graphs as Mermaid diagrams (notes §5, §9): one process's declared
  shape, a contract's steps, one unit, an aggregate's lifecycle, a domain's context
  map and its contracts as one system.

  The picture of a contract and of a system can lay the log over the declarations:
  declared = possible (a superset), observed = actual (a weighted subset). **The
  join of the two is the product.**

  This module **does not draw a dashboard**. It produces the diagrams a dashboard
  would stand on.
  """

  import Ecto.Query

  alias EhOsContract.Graph.Mermaid

  @doc """
  One process's **declared shape** as a mermaid diagram: stages as lanes, the
  events in them, how it can end, and each assertion as an arrow carrying its
  window.

  ## This is not the graph that was rejected

  `PLAN.md` records a dated finding that a diagram was not worth building: eleven
  events gave three edges and it said nothing a sorted list did not. That was the
  **handler graph** — edges from handler registrations — drawn for the team's
  evidence screen. This is a different picture for a different reader.

  The distinction is not a nicety, it is the whole reason this can be worth
  drawing. A contract with no implementation has **no handler edges at all**, so
  the rejected picture of a contract written before its implementation is a row of
  unconnected boxes. The sequence in a contract does not live in its edges; it
  lives in `stages`, `terminal` and `promise`, and none of the three appeared on the
  handler graph.

  ## Who it is for

  The process owner, before anything is built — the reader `docs/warsztat-rehmed.md`
  is written for. So the nodes carry `label`, which is the one place in the whole
  system written in the client's language, and the assertion arrows carry the
  number, because a claim with a number is the only thing somebody can correct.

  **A picture is easier to nod at than to correct**, which is why this is meant to
  sit above the assertion sentences rather than replace them. The measure of a
  validation session is corrections, not agreement.

  ## What it deliberately does not show

  Fields, `identity`, `personal:`, `rule`. Those are for whoever writes the code.
  A diagram showing everything the contract holds would be the module again, and
  the module is what the reader could not read.

  ## What it shows

  The process's stages as lanes (plan E7c), each titled by its label where it has
  one; the contract's own events in the stage group they sit in, and the events it
  includes where the `include` sits; each `promise` as an arrow; the externals from
  the domain.
  """
  @spec declared_to_mermaid(module(), atom()) :: String.t()
  def declared_to_mermaid(contract, process_name),
    do: contract |> EhOsContract.Graph.Declared.build(process_name) |> Mermaid.declared()

  @doc """
  A v2 contract's full graph as a Mermaid diagram (plan EG1): the steps of
  `EhOsContract.Paths` — commands, events, the policies, process managers and effects
  that react, and timers, each kind in its Event Storming colour — and around them
  the actors, read models, queries and external systems the contract names, each
  unit's commands and events in a group of their own. `overlay: true` lays the log
  over the steps, `since:` and `until:` bound it. See `EhOsContract.Graph.Contract`.
  """
  @spec contract_to_mermaid(module(), keyword()) :: String.t()
  def contract_to_mermaid(contract, opts \\ []),
    do: EhOsContract.Graph.Contract.to_mermaid(contract, opts)

  @doc """
  Unit `unit` of a v2 contract as a Mermaid diagram (plan EG1): its state, commands,
  events and invariants, with how many scenarios pin each path. See
  `EhOsContract.Graph.Unit`.
  """
  @spec unit_to_mermaid(module(), atom()) :: String.t()
  def unit_to_mermaid(contract, unit), do: EhOsContract.Graph.Unit.to_mermaid(contract, unit)

  @doc """
  An aggregate's lifecycle as a Mermaid diagram (plan LC4b): where it starts, its
  statuses, its ends and the transitions between them; with `overlay: true` (and
  `:since`, `:until`) the report's counts on each transition, and the moves it does
  not allow as dotted arrows. See `EhOsContract.Graph.Lifecycle`.
  """
  @spec lifecycle_to_mermaid(module(), atom(), keyword()) :: String.t()
  def lifecycle_to_mermaid(contract, unit, opts \\ []),
    do: EhOsContract.Graph.Lifecycle.to_mermaid(contract, unit, opts)

  @doc """
  A domain's context map as a Mermaid diagram (plan EG2): its subdomains as groups of
  their contexts, its external systems, and the relations between them. See
  `EhOsContract.Graph.ContextMap`.
  """
  @spec context_map_to_mermaid(module()) :: String.t()
  def context_map_to_mermaid(domain), do: EhOsContract.Graph.ContextMap.to_mermaid(domain)

  @doc """
  A domain's v2 contracts as one Mermaid diagram (plan EG2): each context a group of
  its contracts, and what one consumes from another, or through a publication, as
  the edges between them. `overlay: true` lays the log over it, `since:` and
  `until:` bound it. See `EhOsContract.Graph.System`.
  """
  @spec system_to_mermaid(module(), [module()], keyword()) :: String.t()
  def system_to_mermaid(domain, contracts, opts \\ []),
    do: EhOsContract.Graph.System.to_mermaid(domain, contracts, opts)

  @doc """
  `query`, over events bound as `:event`, narrowed to the period `opts` names with
  `:since` and `:until`, as every reader of the log narrows it.
  """
  @spec bounded(Ecto.Query.t(), keyword()) :: Ecto.Query.t()
  def bounded(query, opts),
    do: query |> maybe_since(opts[:since]) |> maybe_until(opts[:until])

  @spec maybe_since(Ecto.Query.t(), DateTime.t() | nil) :: Ecto.Query.t()
  defp maybe_since(query, nil), do: query
  defp maybe_since(query, since), do: where(query, [event: e], e.occurred_at >= ^since)

  # The evidence report is **for a period**, so it needs both bounds. `since`
  # alone means "from X until now", so a July report regenerated in September
  # would include August — and a proof that changes when reprinted is not a proof.
  @spec maybe_until(Ecto.Query.t(), DateTime.t() | nil) :: Ecto.Query.t()
  defp maybe_until(query, nil), do: query
  defp maybe_until(query, until), do: where(query, [event: e], e.occurred_at <= ^until)
end
