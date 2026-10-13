defmodule EhOsContract.Process.Rules do
  # The rules a process module must satisfy to compile (plan DD, P2b, #205): layer L2,
  # under the codes the contract's rules use for the same thing.
  #
  # A transformer, as the contract's rules are, and every violation is reported at
  # once, in one error that names each declaration's file and line
  # (`EhOsContract.DslRules`).
  #
  # - **D11.** `id:` is the application's namespace, then dotted snake_case segments,
  #   unversioned, at most 100 bytes: the contract's rule for its own id
  #   (`EhOsContract.Contract.Rules.Boundaries`). Whether the namespace is the domain's
  #   `name:` needs the domain, which is named without a compile dependency, so that
  #   part is left to the rules between modules (L3).
  # - **N1.** Stages, promises and included events are named in snake_case, each once
  #   in the process. An included event is named by its name alone in `ends_on` and in
  #   a promise, so two includes resolving to one name are refused, whichever
  #   contracts they come from. A label given is not blank.
  # - **R2.** The process correlates on at least one field, declared once and naming
  #   each field once: with none, every event it includes would land in one run.
  # - **F9.** At most `EhOsContract.Key.max_fields/0` correlation fields: the run's key
  #   is one index entry.
  # - **R3.** The process has stages, and each stage includes at least one event: a
  #   stage is a step of the run, made of the contracts' events. Each entry of a stage's
  #   `include:` names a contract by its module and at least one of its events; whether
  #   the contract exists is left to the rules between modules.
  # - **R5.** A promise's `from`, `eventually` and `or_else`, and each event of
  #   `ends_on`, is an event the process includes; `ends_on` is declared at most once.
  # - **R6.** `within` and `deadline` count a non-negative number of a fixed unit
  #   (`EhOsContract.Duration`); `deadline` is declared at most once, and only with
  #   `ends_on`, since it measures a run to its end (the user's decision of
  #   7 October 2026).
  # - **S1, S2, S3, S11: scenarios** (plan DD, S2, #251). A scenario judges exactly one
  #   promise of the module, at a moment (S1), each description once (S1); its givens
  #   are events the process includes (S2); every `at:` is an ISO 8601 timestamp with an
  #   offset, and a given's never earlier than the given before it (S3). Its shape
  #   (S11): a verdict, one of the four `EhOsContract.Trace` gives; `via:` only on
  #   `:satisfied`, `:eventually` or `:or_else`, and `:or_else` only for a promise that
  #   has one; a verdict the promise can get, so none but `:satisfied` or `:pending`
  #   without `within`, and `:suspended` only with an outage; a given of the promise's
  #   `from`, without which no run is judged; and nothing after the moment of
  #   judgement, which a verdict cannot have seen.
  #
  # What one module cannot see — that each included event exists in its contract and
  # carries the `correlate` fields, that the accountable actor is the domain's, that a
  # scenario's data fits the event its contract declares and an outage is of a system
  # the promise depends on — is left to the rules between modules.
  @moduledoc false

  use Spark.Dsl.Transformer

  alias EhOsContract.Duration
  alias EhOsContract.DslRules
  alias EhOsContract.Contract.Rules.{Boundaries, Scenarios}
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
        correlation(d) ++ stages(d) ++ events_of_the_run(d) ++ durations(d) ++ scenarios(d)

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
      deadlines: of.(Dsl.Deadline),
      scenarios: of.(Dsl.Scenario)
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

    repeated =
      for field <- correlate.fields |> DslRules.duplicates(& &1) |> Enum.uniq() do
        {"R2: #{where(d)} correlates on #{inspect(field)} twice; a run's key names each " <>
           "field once", correlate}
      end

    empty ++ long ++ twice ++ repeated
  end

  # --- R3 ----------------------------------------------------------------------------

  defp stages(%{stages: []} = d) do
    [
      {"R3: #{where(d)} declares no stage, so its runs have no events; a stage includes " <>
         "the contracts' events, `stage :name, include: [{Contract, :event}]`", d.at}
    ]
  end

  defp stages(d) do
    empty =
      for s <- d.stages, includes(s) == [] do
        {"R3: #{where(d)}: stage #{inspect(s.name)} includes no event; a stage is a step of " <>
           "the run, made of the contracts' events, `include: [{Contract, :event}]`", s}
      end

    # A stage with no event at all is refused above; an empty entry beside others that
    # name events would otherwise be dropped without a word.
    entries =
      for s <- d.stages,
          includes(s) != [],
          {contract, events} <- s.include,
          List.wrap(events) == [] do
        {"R3: #{where(d)}: stage #{inspect(s.name)} includes #{inspect(contract)} with " <>
           "no event; name the events it includes, `{Contract, :event}`", s}
      end

    contracts =
      for s <- d.stages, {contract, _events} <- s.include, not module_alias?(contract) do
        {"R3: #{where(d)}: stage #{inspect(s.name)} includes #{inspect(contract)}, which " <>
           "names no contract; name the contract by its module, `{Contract, :event}`", s}
      end

    empty ++ entries ++ contracts
  end

  defp module_alias?(contract),
    do: is_atom(contract) and String.starts_with?(Atom.to_string(contract), "Elixir.")

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

    twice =
      for e <- Enum.drop(d.ends_on, 1) do
        {"R5: #{where(d)} declares ends_on twice; one lists every event that ends a run", e}
      end

    promised ++ ending ++ twice
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
          problem <- EhOsContract.Contract.Rules.Durations.problems(duration, Duration.units()) do
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

  # --- S1, S2, S3, S11: scenarios ----------------------------------------------------

  @verdicts [:satisfied, :violated, :pending, :suspended]
  @routes [:eventually, :or_else]

  defp scenarios(d) do
    run = MapSet.new(for s <- d.stages, {_, event} <- includes(s), do: event)

    twice =
      for s <- DslRules.duplicates(d.scenarios, & &1.description) do
        {~s|S1: #{where(d)} has two scenarios described "#{s.description}"; the description | <>
           "names each one", s}
      end

    Enum.flat_map(d.scenarios, &scenario(&1, d, run)) ++ twice
  end

  defp scenario(scenario, d, run) do
    where = ~s|scenario "#{scenario.description}"|

    givens =
      for g <- scenario.given, not MapSet.member?(run, g.event) do
        {"S2: #{where}: given #{inspect(g.event)} is not an event of the run of #{where(d)}, " <>
           "which includes #{inspect(Enum.sort(run))}", g}
      end

    outages =
      for o <- scenario.outages, {:error, problem} <- [moment(o.at)] do
        {"S3: #{where}: outage #{inspect(o.external)}, at: #{problem}", o}
      end

    givens ++ Scenarios.dated(where, scenario.given) ++ outages ++ judged(where, scenario, d)
  end

  defp judged(where, %{trigger: []} = scenario, _d) do
    [
      {"S1: #{where} judges no promise; name the promise and the moment it is judged, " <>
         ~s|`promise :name, at: "2026-09-10T09:00:00Z"`|, scenario}
    ]
  end

  defp judged(where, %{trigger: [_, _ | _] = many} = scenario, _d) do
    [{"S1: #{where} judges #{length(many)} promises; a scenario judges exactly one", scenario}]
  end

  defp judged(where, %{trigger: [judged]} = scenario, d) do
    names = Enum.map(d.promises, & &1.name)

    case Enum.find(d.promises, &(&1.name == judged.name)) do
      nil ->
        [
          {"S1: #{where} judges promise #{inspect(judged.name)}, which #{where(d)} does not " <>
             "make; #{promised(judged.name, names)}", judged}
        ]

      promise ->
        at =
          case moment(judged.at) do
            {:ok, _at} -> []
            {:error, problem} -> [{"S3: #{where}: promise, at: #{problem}", judged}]
          end

        at ++ shape(where, scenario, promise, judged)
    end
  end

  defp promised(_name, []), do: "it makes none"

  defp promised(name, names) do
    case DslRules.closest(name, names) do
      nil -> "it makes #{inspect(names)}"
      suggestion -> "did you mean #{inspect(suggestion)}?"
    end
  end

  # S11.
  defp shape(where, scenario, promise, judged) do
    verdict =
      cond do
        scenario.verdict == nil ->
          [
            {"S11: #{where} says no verdict; say what the promise gets, `verdict:` one of " <>
               "#{inspect(@verdicts)}", scenario}
          ]

        scenario.verdict not in @verdicts ->
          [
            {"S11: #{where}: verdict #{inspect(scenario.verdict)} is not one of " <>
               "#{inspect(@verdicts)}", scenario}
          ]

        true ->
          []
      end

    via =
      cond do
        scenario.via == nil ->
          []

        scenario.verdict not in @verdicts ->
          []

        scenario.verdict != :satisfied ->
          [
            {"S11: #{where}: via: is the route by which a promise was kept, and a promise " <>
               "#{inspect(scenario.verdict)} was not kept; leave via: out", scenario}
          ]

        scenario.via not in @routes ->
          [
            {"S11: #{where}: via #{inspect(scenario.via)} is not one of #{inspect(@routes)}",
             scenario}
          ]

        scenario.via == :or_else and promise.or_else == nil ->
          [
            {"S11: #{where}: via :or_else, and promise #{inspect(promise.name)} has no " <>
               "or_else; it is kept only by #{inspect(promise.eventually)}", scenario}
          ]

        true ->
          []
      end

    opened =
      if Enum.any?(scenario.given, &(&1.event == promise.from)),
        do: [],
        else: [
          {"S11: #{where} gives no #{inspect(promise.from)}, which opens promise " <>
             "#{inspect(promise.name)}; without it no run is judged", scenario}
        ]

    verdict ++
      via ++
      reachable(where, scenario, promise) ++
      opened ++
      after_judgement(where, scenario, judged)
  end

  # A verdict judge/3 cannot give these declarations: one with no `within` has no window
  # to close, so it is never broken or excused, and only an outage excuses one.
  defp reachable(where, scenario, promise) do
    cond do
      scenario.verdict in [:violated, :suspended] and promise.within == nil ->
        [
          {"S11: #{where}: verdict #{inspect(scenario.verdict)}, and promise " <>
             "#{inspect(promise.name)} has no within, so its window never closes; it is only " <>
             ":satisfied or :pending", scenario}
        ]

      scenario.verdict == :suspended and scenario.outages == [] ->
        [
          {"S11: #{where}: verdict :suspended, and no outage excuses the promise; say when the " <>
             ~s|system was down, `outage :external, at: "…"`|, scenario}
        ]

      true ->
        []
    end
  end

  # Nothing the verdict is about happened after it was given. A moment that is no
  # timestamp is S3's, and compared with nothing.
  defp after_judgement(where, scenario, judged) do
    case moment(judged.at) do
      {:ok, now} ->
        given =
          for {g, %DateTime{} = at} <-
                Enum.zip(scenario.given, Scenarios.moments(scenario.given)),
              DateTime.compare(at, now) == :gt,
              do: {"given #{inspect(g.event)}", at, g}

        outages =
          for o <- scenario.outages,
              {:ok, at} <- [moment(o.at)],
              DateTime.compare(at, now) == :gt,
              do: {"outage #{inspect(o.external)}", at, o}

        for {what, at, declaration} <- given ++ outages do
          {"S11: #{where}: #{what} at #{DateTime.to_iso8601(at)} is after the moment the " <>
             "promise is judged, #{DateTime.to_iso8601(now)}; a verdict sees only what " <>
             "happened by then", declaration}
        end

      {:error, _problem} ->
        []
    end
  end

  defp moment(at) do
    case DateTime.from_iso8601(at) do
      {:ok, at, _offset} -> {:ok, at}
      {:error, _} -> {:error, hd(EhOsContract.Contract.Data.problems(:timestamp, at))}
    end
  end
end
