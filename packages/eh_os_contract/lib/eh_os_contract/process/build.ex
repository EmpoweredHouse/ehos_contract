defmodule EhOsContract.Process.Build do
  @moduledoc """
  Builds a process module's model and compiles it into the module as
  `__eh_os_contract_model__/0` (plan DD, P2b, #205).

  Runs last, after every rule, so the model is only built from a process that is well
  formed. It is plain data, as a contract's is (`EhOsContract.Contract.Build`):

      %{format: 1, kind: :process, module: Rehmed.Processes.ClinicalVisit,
        id: "rehmed.clinical_visit", label: "…", domain: Rehmed.Domain,
        accountable: :manager, source: nil, correlate: [:visit_id],
        stages: [%{name: :departure, label: nil,
                   includes: [%{contract: Rehmed.Contracts.Scheduling, event: :visit_completed}]}],
        ends_on: [:p1_report_sent], promises: [%{name: …, within: %{amount: 2, unit: :day}}],
        deadline: nil, version: "…", digests: %{"process" => "…", "stage:departure" => "…"}}

  Durations are `%{amount: 2, unit: :day}`, and the deadline also says whether it is
  `unverified`.

  **The digest does not see declaration order where it means nothing**, as a
  contract's does not (`EhOsContract.Digest`): promises, the events of `ends_on` and a
  stage's includes are sets to it. What keeps its order is what has one: `correlate`,
  which makes the run's key, and the stages, whose order makes a backward step
  backward. Each declaration also has its own digest, keyed `"<kind>:<name>"`, and
  the process's own options `"process"`.
  """

  use Spark.Dsl.Transformer

  alias EhOsContract.Digest
  alias EhOsContract.Process.Rules
  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl) do
    model = model(dsl)

    {:ok,
     dsl
     |> Transformer.persist(:eh_os_contract_model, model)
     |> Transformer.eval(
       [],
       quote do
         @doc false
         def __eh_os_contract_model__, do: unquote(Macro.escape(model))
       end
     )}
  end

  @doc false
  @spec model(map()) :: map()
  def model(dsl) do
    d = Rules.declarations(dsl)

    stages =
      for s <- d.stages do
        %{
          name: s.name,
          label: s.label,
          includes:
            for({contract, event} <- Rules.includes(s), do: %{contract: contract, event: event})
        }
      end

    own = %{
      id: d.id,
      label: d.label,
      domain: d.domain,
      accountable: d.accountable,
      source: d.source,
      correlate: Enum.flat_map(d.correlates, & &1.fields),
      ends_on: ends_on(d.ends_on),
      deadline: deadline(d.deadlines)
    }

    promises = Enum.map(d.promises, &promise/1)

    own
    |> Map.merge(%{
      format: 1,
      kind: :process,
      module: d.module,
      stages: stages,
      promises: promises,
      version: version(own, stages, promises),
      digests: digests(own, stages, promises)
    })
  end

  defp promise(promise) do
    promise
    |> Map.from_struct()
    |> Map.delete(:__spark_metadata__)
    |> Map.update!(:within, &duration/1)
  end

  # Declared at most once; the rules have refused a second before this runs.
  defp ends_on([]), do: []
  defp ends_on([ends_on | _]), do: Enum.uniq(ends_on.events)

  defp deadline([]), do: nil

  defp deadline([deadline | _]) do
    case duration(deadline.within) do
      %{} = duration -> Map.put(duration, :unverified, deadline.unverified)
      other -> other
    end
  end

  # `{2, :day}` as data; the rules have refused anything else before this runs.
  defp duration({amount, unit}) when is_integer(amount) and is_atom(unit),
    do: %{amount: amount, unit: unit}

  defp duration(other), do: other

  # --- the digest ----------------------------------------------------------------------

  # The order of the stages is kept in the process's own part: hashed as a group, the
  # stages are a set.
  defp version(own, stages, promises) do
    Digest.hash_groups(
      process: [digest_form(own, stages)],
      stages: Enum.map(stages, &digest_form/1),
      promises: Enum.map(promises, &digest_form/1)
    )
  end

  defp digests(own, stages, promises) do
    Map.new(
      [{"process", Digest.hash(digest_form(own, stages))}] ++
        for(s <- stages, do: {"stage:#{s.name}", Digest.hash(digest_form(s))}) ++
        for(p <- promises, do: {"promise:#{p.name}", Digest.hash(digest_form(p))})
    )
  end

  defp digest_form(own, stages),
    do: own |> digest_form() |> Map.put(:stages, Enum.map(stages, & &1.name))

  @sets [:ends_on, :includes]

  defp digest_form(%{} = declaration) do
    Map.new(declaration, fn
      {key, list} when key in @sets and is_list(list) ->
        {key, Enum.sort_by(list, &Digest.canonical/1)}

      other ->
        other
    end)
  end
end
