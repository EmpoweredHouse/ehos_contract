defmodule EhOsContract.Process.Rules do
  @moduledoc """
  The rules a process module must satisfy to compile (plan DD, P2b, #205): layer L2,
  under the codes the contract's rules use for the same thing.

  A transformer, as the contract's rules are, and every violation is reported at
  once, in one error that names each declaration's file and line
  (`EhOsContract.DslRules`).

  - **D11.** `id:` is the application's namespace, then dotted snake_case segments,
    unversioned, at most 100 bytes: the contract's rule for its own id
    (`EhOsContract.Contract.Rules.Boundaries`). Whether the namespace is the domain's
    `name:` needs the domain, which is named without a compile dependency, so that
    part is left to the rules between modules (L3).
  - **N1.** Stages, promises and included events are named in snake_case, each once
    in the process. An included event is named by its name alone in `ends_on` and in
    a promise, so two includes resolving to one name are refused, whichever
    contracts they come from. A label given is not blank.
  - **R2.** The process correlates on at least one field, declared once: with none,
    every event it includes would land in one run.
  - **F9.** At most `EhOsContract.Key.max_fields/0` correlation fields: the run's key
    is one index entry.
  - **R3.** The process has stages, and each stage includes at least one event: a
    stage is a step of the run, made of the contracts' events.
  - **R5.** A promise's `from`, `eventually` and `or_else`, and each event of
    `ends_on`, is an event the process includes.
  - **R6.** `within` and `deadline` count a non-negative number of a fixed unit
    (`EhOsContract.Duration`); `deadline` is declared at most once, and only with
    `ends_on`, since it measures a run to its end (the user's decision of
    7 October 2026).

  What one module cannot see — that each included event exists in its contract and
  carries the `correlate` fields, that the accountable actor is the domain's — is
  left to the rules between modules.
  """

  use Spark.Dsl.Transformer

  alias EhOsContract.Duration
  alias EhOsContract.DslRules
  alias EhOsContract.Contract.Rules.Boundaries
  alias EhOsContract.Process.Dsl
  alias Spark.Dsl.Transformer

  @impl true
  def before?(EhOsContract.Process.Build), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl) do
    d = declarations(dsl)

    violations =
      Boundaries.id_form(%{value: d.id, at: d.at}, "process") ++
        names(d) ++
        correlation(d) ++ stages(d) ++ events_of_the_run(d) ++ durations(d)

    DslRules.result(dsl, [:process], violations)
  end

  @doc false
  # The process module's declarations, by kind, with its `use` options and where the
  # `use` stands.
  @spec declarations(map()) :: map()
  def declarations(dsl) do
    entities = Transformer.get_entities(dsl, [:process])
    of = fn struct -> for %{__struct__: ^struct} = e <- entities, do: e end
    persisted = Transformer.get_persisted(dsl, :eh_os_contract_process)

    Map.merge(persisted, %{
      module: Transformer.get_persisted(dsl, :module),
      at: use_at(dsl),
      correlates: of.(Dsl.Correlate),
      stages: of.(Dsl.Stage),
      ends_on: of.(Dsl.EndsOn),
      promises: of.(EhOsContract.Contract.Dsl.Promise),
      deadlines: of.(Dsl.Deadline)
    })
  end

  @doc false
  # Every event a stage includes, in order, as `{contract, event}`.
  @spec includes(struct()) :: [{module(), atom()}]
  def includes(%Dsl.Stage{include: include}) do
    for {contract, events} <- include, event <- List.wrap(events), do: {contract, event}
  end

  defp use_at(dsl) do
    case {Transformer.get_persisted(dsl, :file),
          Transformer.get_persisted(dsl, :eh_os_contract_line)} do
      {file, line} when is_binary(file) and is_integer(line) ->
        :erl_anno.set_file(String.to_charlist(file), :erl_anno.new(line))

      _ ->
        nil
    end
  end

  defp where(d), do: "process #{inspect(d.id)}"

  # --- N1 ----------------------------------------------------------------------------

  defp names(d) do
    included = for s <- d.stages, {contract, event} <- includes(s), do: {contract, event, s}

    snake_case =
      for(s <- d.stages, not DslRules.name?(s.name), do: {"stage", s.name, s}) ++
        for(p <- d.promises, not DslRules.name?(p.name), do: {"promise", p.name, p}) ++
        for {_contract, event, s} <- included,
            not DslRules.name?(event),
            do: {"included event", event, s}

    twice =
      for(
        s <- DslRules.duplicates(d.stages, & &1.name),
        do: {"N1: #{where(d)} has two stages named #{inspect(s.name)}", s}
      ) ++
        for(
          p <- DslRules.duplicates(d.promises, & &1.name),
          do: {"N1: #{where(d)} has two promises named #{inspect(p.name)}", p}
        ) ++ included_twice(d, included)

    label =
      if DslRules.blank?(d.label),
        do: [{"N1: #{where(d)} has a blank label; say what the business calls it", d.at}],
        else: []

    for(
      {kind, name, at} <- snake_case,
      do: {"N1: #{kind} #{inspect(name)} is not snake_case", at}
    ) ++
      twice ++ label ++ DslRules.blank_labels(d.stages, "N1")
  end

  # An included event is named by its name alone, so its name is the process's: one
  # included twice, from one contract or two, is refused at the later include.
  defp included_twice(d, included) do
    first = included |> Enum.reverse() |> Map.new(fn {c, e, s} -> {e, {c, s}} end)

    for {contract, event, stage} <- DslRules.duplicates(included, &elem(&1, 1)) do
      {first_contract, first_stage} = Map.fetch!(first, event)

      {"N1: #{where(d)} includes #{inspect(event)} twice: from #{inspect(contract)} in stage " <>
         "#{inspect(stage.name)}, and from #{inspect(first_contract)} in stage " <>
         "#{inspect(first_stage.name)}; an included event is named once in the process", stage}
    end
  end

  # --- R2, F9 ------------------------------------------------------------------------

  defp correlation(%{correlates: []} = d) do
    [
      {"R2: #{where(d)} correlates on no field, so every event it includes would belong to " <>
         "one run; name the fields that tell one run from another, `correlate :field`", d.at}
    ]
  end

  defp correlation(%{correlates: [correlate | again]} = d) do
    max = EhOsContract.Key.max_fields()

    empty =
      if correlate.fields == [],
        do: [
          {"R2: #{where(d)} correlates on no field, so every event it includes would belong " <>
             "to one run; name the fields that tell one run from another", correlate}
        ],
        else: []

    long =
      if length(correlate.fields) > max,
        do: [
          {"F9: #{where(d)}: correlate has #{length(correlate.fields)} fields, and a key has at " <>
             "most #{max}: it is one index entry, which more fields of an :id at its bound " <>
             "would overflow", correlate}
        ],
        else: []

    twice =
      for c <- again do
        {"R2: #{where(d)} declares correlate twice; name every field in one, in order", c}
      end

    empty ++ long ++ twice
  end

  # --- R3 ----------------------------------------------------------------------------

  defp stages(%{stages: []} = d) do
    [
      {"R3: #{where(d)} declares no stage, so its runs have no events; a stage includes " <>
         "the contracts' events, `stage :name, include: [{Contract, :event}]`", d.at}
    ]
  end

  defp stages(d) do
    for s <- d.stages, includes(s) == [] do
      {"R3: #{where(d)}: stage #{inspect(s.name)} includes no event; a stage is a step of " <>
         "the run, made of the contracts' events, `include: [{Contract, :event}]`", s}
    end
  end

  # --- R5 ----------------------------------------------------------------------------

  defp events_of_the_run(d) do
    run = MapSet.new(for s <- d.stages, {_, event} <- includes(s), do: event)

    promised =
      for promise <- d.promises,
          {key, event} <- [
            from: promise.from,
            eventually: promise.eventually,
            or_else: promise.or_else
          ],
          event != nil,
          not MapSet.member?(run, event) do
        {"R5: promise #{inspect(promise.name)}: #{key} #{inspect(event)} is not an event of " <>
           "the run of #{where(d)}, which includes #{inspect(Enum.sort(run))}", promise}
      end

    ending =
      for e <- d.ends_on, event <- e.events, not MapSet.member?(run, event) do
        {"R5: #{where(d)} ends on #{inspect(event)}, which it does not include; it includes " <>
           "#{inspect(Enum.sort(run))}", e}
      end

    promised ++ ending
  end

  # --- R6 ----------------------------------------------------------------------------

  defp durations(d) do
    fixed =
      for(
        p <- d.promises,
        p.within != nil,
        do: {"promise #{inspect(p.name)}: within", p.within, p}
      ) ++
        for dl <- d.deadlines, do: {"#{where(d)}: deadline", dl.within, dl}

    counted =
      for {what, duration, declaration} <- fixed,
          problem <- EhOsContract.Contract.Rules.Process.problems(duration, Duration.units()) do
        {"R6: #{what} #{problem}", declaration}
      end

    twice =
      for dl <- Enum.drop(d.deadlines, 1),
          do: {"R6: #{where(d)} declares deadline twice", dl}

    unended =
      case {d.deadlines, Enum.flat_map(d.ends_on, & &1.events)} do
        {[deadline | _], []} ->
          [
            {"R6: #{where(d)} declares a deadline, which measures a run to its end, and " <>
               "nothing ends this one; name the events that do, `ends_on [:event]`", deadline}
          ]

        _ ->
          []
      end

    counted ++ twice ++ unended
  end
end
