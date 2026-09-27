defmodule Mix.Tasks.EhOsContract.Check do
  @shortdoc "Whole-program checks over the contract and the handlers"

  @moduledoc """
  Everything that requires seeing **every** module at once.

  The split is forced by the compilation model rather than chosen: a macro sees
  one file, so it checks what one file can show. That every declared event has a
  handler or is terminal, that there are no orphans, and that the declarations
  agree with reality — all of that belongs here. A project that does not register
  the compiler `:eh_os_contract` gets its rules (L3) here too, as errors.

  Every finding names its rule (`EhOsContract.Check.Catalog`, documented in
  `docs/rules.md`) and, where it can, the file and line of the declaration it is
  about. Nothing silences a rule; a finding goes when the model changes.

      mix eh_os_contract.check                         # errors fail the task
      mix eh_os_contract.check --warnings-as-errors    # so do warnings
      mix eh_os_contract.check --format json           # one JSON array, see render/2

  `--format json` prints the array and nothing else, but the compile this task runs
  first prints what it prints: compile beforehand when the output is read by a
  program. `--warnings-as-errors` changes the exit status and nothing it prints.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  alias EhOsContract.Check.{Catalog, Finding}

  @impl Mix.Task
  def run(args) do
    {opts, _rest} =
      OptionParser.parse!(args, strict: [format: :string, warnings_as_errors: :boolean])

    unless opts[:format] in [nil, "human", "json"],
      do: Mix.raise("--format is human or json, got #{inspect(opts[:format])}")

    # Erlang keeps stdout in latin1 when the output is not a terminal, so
    # `mix eh_os_contract.check > report.txt` truncates every codepoint to a byte. Event
    # labels come from the contract and are written in the client's language.
    :io.setopts(:standard_io, encoding: :unicode)

    Mix.Task.run("compile")
    Application.load(:eh_os_contract)
    EhOsContract.Registry.load!()

    findings =
      []
      |> check_something_to_check()
      |> check_names_declared_twice()
      |> check_events_have_handlers()
      |> check_owners_exist()
      |> check_rule_functions_exist()
      |> check_traces_resolve()
      |> check_backward_edges()
      |> check_competing_sync_handlers()
      |> check_assertions_finer_than_their_run()
      |> check_facts_not_keyed_by_their_run()
      |> check_unfalsifiable_assertions()
      |> check_unobservable_deadlines()
      |> check_processes_without_accountable()
      |> check_retain_on_free_text()
      |> check_unverified_declarations()

    # A v1 check says which rule it found and what; the rule's level is the catalog's.
    findings = for {rule, message} <- findings, do: Finding.new(rule, message)
    v2 = EhOsContract.Registry.v2_contracts()

    compiler =
      EhOsContract.Check.compiler_findings(
        Mix.Project.config()[:compilers] || Mix.compilers(),
        Mix.Tasks.Compile.EhOsContract.modules(Mix.Project.compile_path())
      )

    report(
      compiler ++
        EhOsContract.Check.v2_findings(v2) ++
        EhOsContract.Check.Completeness.findings(v2) ++
        EhOsContract.Check.Contracts.findings(v2) ++ findings,
      opts
    )
  end

  # **Nothing found is not the same as nothing wrong, and the report cannot tell
  # them apart.** `0 errors, 0 warnings, 0 notices` is what a healthy repository
  # prints and also what an engine pointed at the wrong application prints — which
  # is what this engine did on the day it first compiled as a package, scanning
  # itself and reporting a perfectly healthy empty graph.
  #
  # The applications are named in the finding because that is where the mistake
  # actually is: the contracts exist, the configuration points elsewhere.
  defp check_something_to_check(findings) do
    if EhOsContract.Check.no_contracts?() do
      configured = Application.get_env(:eh_os_contract, :applications) || []

      [
        {"no-contracts",
         "no contracts found in #{inspect(configured)}, so every check below has an empty list " <>
           "to work on and will report nothing. A clean report and a misconfigured scan look " <>
           "identical — set `config :eh_os_contract, applications: [...]` to the applications that hold " <>
           "your contracts"}
        | findings
      ]
    else
      findings
    end
  end

  # Two names in one namespace. Errors rather than warnings, and that is the one
  # place in this task where the engine overrules the author rather than reporting
  # to them: an event name is what dispatch selects on and a process name is what a
  # run identity is built from, so neither collision is expressible correctly. What
  # they produce is somebody else's handler running inside your transaction, and one
  # process's runs counted as another's — both of which show up somewhere other than
  # where they are.
  defp check_names_declared_twice(findings) do
    events =
      for c <- EhOsContract.Check.event_names_declared_twice() do
        {"event-declared-twice",
         "event #{inspect(c.name)} is declared by #{length(c.contracts)} contracts: " <>
           "#{inspect(c.contracts)}. Handlers are selected by event name alone, so emitting it " <>
           "from one contract runs the other's handlers as well"}
      end

    processes =
      for c <- EhOsContract.Check.process_names_declared_twice() do
        {"process-declared-twice",
         "process #{inspect(c.name)} is declared by #{length(c.contracts)} contracts: " <>
           "#{inspect(c.contracts)}. A run identity is `\"<process>|<values>\"` and carries no " <>
           "contract, so runs of one are counted as runs of the other and the log cannot be " <>
           "separated afterwards"}
      end

    commands =
      for c <- EhOsContract.Check.command_names_declared_twice() do
        {"command-declared-twice",
         "command #{inspect(c.name)} is declared by #{length(c.contracts)} contracts: " <>
           "#{inspect(c.contracts)}. The capability is derived from the name, so one permission " <>
           "would authorise two different things"}
      end

    Enum.reduce(events ++ processes ++ commands, findings, &[&1 | &2])
  end

  # A finished report with nowhere to go. Not a compile gate on purpose — see
  # `EhOsContract.Check.processes_without_accountable/1` for the argument and the precedent.
  defp check_processes_without_accountable(findings) do
    for f <- EhOsContract.Check.processes_without_accountable(), reduce: findings do
      acc ->
        [
          {"process-without-accountable",
           "process #{inspect(f.process)} names no `accountable` role, so a finding about it " <>
             "has no addressee (#{inspect(f.contract)})"}
          | acc
        ]
    end
  end

  # Every declared event has a handler or is terminal.
  defp check_events_have_handlers(findings) do
    for event <- EhOsContract.Registry.declared_events(), reduce: findings do
      acc ->
        handlers = EhOsContract.Registry.handlers_for(event.name)
        terminal? = event.terminal

        cond do
          handlers != [] ->
            acc

          terminal? ->
            acc

          true ->
            # This is not an error: a declared, unhandled event is an explicit
            # demonstration of the "declared, never observed" layer. But it has
            # to be visible, because the difference between "on purpose" and
            # "forgotten" lives in the author's head rather than in the code.
            [
              {"event-without-handler",
               "event #{inspect(event.name)} has no handler and is not marked terminal " <>
                 "(#{inspect(event.contract)})"}
              | acc
            ]
        end
    end
  end

  # `owner` was the one event declaration **no mechanism read** — one place copied
  # it into a graph node and that was that. The consequence: a contract named an
  # owner whose module never existed, and both compilation and the check passed. A
  # declaration nobody checks is a comment in Elixir syntax.
  #
  # `info`, not an error: the owner of a stage not yet implemented is a normal
  # state mid-rollout, exactly like an event with no handler.
  #
  # Grouped **by module, not by event**, and that is not cosmetic. The per-event
  # version produced fourteen lines for two contracts, ten of which repeated the
  # same information. That is how the retention check started, before it turned
  # out that a check shouting about everything gets switched off within a week.
  defp check_owners_exist(findings) do
    EhOsContract.Registry.declared_events()
    |> Enum.reject(&is_nil(&1.owner))
    |> Enum.reject(&Code.ensure_loaded?(&1.owner))
    |> Enum.group_by(& &1.owner, & &1.name)
    |> Enum.reduce(findings, fn {owner, events}, acc ->
      count = if length(events) == 1, do: "1 event", else: "#{length(events)} events"

      [
        {"owner-not-a-module",
         "owner #{inspect(owner)} does not exist as a module, and is declared for " <>
           "#{count}: #{inspect(events)}"}
        | acc
      ]
    end)
  end

  # A `rule` names an MFA, so nobody checks for us that the function exists.
  defp check_rule_functions_exist(findings) do
    for contract <- EhOsContract.Registry.contracts(),
        rule <- EhOsContract.Model.rules(contract),
        reduce: findings do
      acc ->
        {module, function, arity} = rule.function

        if Code.ensure_loaded?(module) and function_exported?(module, function, arity) do
          acc
        else
          [
            {"rule-function-missing",
             "rule #{inspect(rule.name)} names #{inspect(module)}.#{function}/#{arity}, " <>
               "which does not exist"}
            | acc
          ]
        end
    end
  end

  defp check_traces_resolve(findings) do
    all_events = EhOsContract.Registry.declared_events() |> Enum.map(& &1.name) |> MapSet.new()

    for contract <- EhOsContract.Registry.contracts(),
        trace <- EhOsContract.Model.traces(contract),
        reduce: findings do
      acc ->
        missing =
          [trace.from, trace.eventually, trace.or_else]
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(&MapSet.member?(all_events, &1))

        if missing == [] do
          acc
        else
          [
            {"trace-unresolved",
             "trace #{inspect(trace.name)} does not resolve #{inspect(missing)}"}
            | acc
          ]
        end
    end
  end

  # The logic lives in `EhOsContract.Check`, not here: as a private function of a mix task
  # it was logic with no test, and this is the check the ADR §15 review trigger
  # rests on.
  defp check_backward_edges(findings) do
    Enum.reduce(EhOsContract.Check.backward_edges(), findings, fn edge, acc ->
      [
        {"backward-edge",
         "backward edge in #{inspect(edge.module)} — #{edge.process}: " <>
           "publishes in #{edge.publishes_in}, subscribes in #{edge.subscribes_in}"}
        | acc
      ]
    end)
  end

  defp check_competing_sync_handlers(findings) do
    Enum.reduce(EhOsContract.Check.competing_sync_handlers(), findings, fn item, acc ->
      order = item.modules |> Enum.map(&inspect/1) |> Enum.join(", ")

      [
        {"competing-sync-handlers",
         "#{inspect(item.event)} has #{length(item.modules)} synchronous handlers. They run in " <>
           "this order: #{order} — alphabetically by module name, which reproduces but says " <>
           "nothing about the process. If the order matters, declare it: have one publish an " <>
           "event the other subscribes to, so the sequence is a path the overlay can see"}
        | acc
      ]
    end)
  end

  # A report, not an error. A compile gate on personal fields was recommended in
  # review and **rejected**: missing evidence is a silent product failure, while
  # excess data is visible and fixable.
  #
  # The first version flagged every `:string` field and produced 33 notices for 11
  # events, including every `company_id`. A check that shouts about everything
  # gets switched off within a week. Signal requires the contract to **separate an
  # identifier from free text** — so `:id`, `:timestamp`, `:integer` and `:enum` are
  # separate types, and `:string` means "text a human typed". This is the second
  # reader of the payload type vocabulary and the reason `:string` cannot become a
  # catch-all: see `EhOsContract.Contract.payload_types/0`.
  defp check_retain_on_free_text(findings) do
    for event <- EhOsContract.Registry.declared_events(),
        {field, type} <- event.payload,
        type == :string,
        not Map.has_key?(event.retain, field),
        reduce: findings do
      acc ->
        [
          {"free-text-without-retain",
           "#{inspect(event.name)}.#{field} is free text with no `retain` — " <>
             "it reaches the log verbatim"}
          | acc
        ]
    end
  end

  # An assertion whose subject is finer than the run it is counted in. `EhOsContract.Trace`
  # quantifies these — every item gets its own window, and the run is satisfied only
  # if all of them are — so this is no longer the false-satisfied defect it was before
  # 21 August. Still a warning rather than an `info`, because quantification pairs an
  # `eventually`/`or_else` occurrence to an item by matching identity field values in
  # its payload: a hit that does not carry those fields cannot resolve any item, so a
  # process owner reading this should confirm `eventually`/`or_else` actually carry
  # the fields `identity` names.
  defp check_assertions_finer_than_their_run(findings) do
    for f <- EhOsContract.Check.assertions_finer_than_their_run(), reduce: findings do
      acc ->
        [
          {"promise-finer-than-run",
           "assertion #{inspect(f.trace)} is finer than its run: `#{f.from}` is identified by " <>
             "#{inspect(f.identity)} while process #{inspect(f.process)} is a run per " <>
             "#{inspect(f.instance)}. Evaluated per item now — confirm `eventually`/`or_else` " <>
             "carry #{inspect(f.identity)} too, or a hit missing them cannot resolve any item " <>
             "(#{inspect(f.contract)})"}
          | acc
        ]
    end
  end

  # A fact whose identity does not contain the run it belongs to. A warning rather
  # than an error for the same reason as its neighbour above — an identity is a
  # modelling claim and the engine is not entitled to overrule it — but it has to be
  # visible, because what it costs is invisible everywhere else: the asynchronous
  # idempotency key is built from `identity` alone, so the second run's fact reads as
  # a repeat of the first and its handler simply never runs.
  defp check_facts_not_keyed_by_their_run(findings) do
    for f <- EhOsContract.Check.facts_not_keyed_by_their_run(), reduce: findings do
      acc ->
        [
          {"fact-not-keyed-by-run",
           "event #{inspect(f.event)} is identified by #{inspect(f.identity)}, which does not " <>
             "contain #{inspect(f.missing)} — the field(s) process #{inspect(f.process)} keys a " <>
             "run by (`instance: #{inspect(f.instance)}`). Two of these facts in two different " <>
             "runs then share one identity, so the asynchronous idempotency key cannot tell " <>
             "them apart and the second one is deduplicated away (#{inspect(f.contract)})"}
          | acc
        ]
    end
  end

  # An assertion with no `within` has no failing case: any occurrence satisfies it,
  # and where nothing occurs the verdict stays `:pending` for ever, because the
  # window a violation needs to be past never closes. `info` rather than a warning —
  # "eventually, and nobody has agreed a number" is an honest thing to say, and the
  # line exists so that it is said out loud rather than read as a promise being kept.
  defp check_unfalsifiable_assertions(findings) do
    for f <- EhOsContract.Check.unfalsifiable_assertions(), reduce: findings do
      acc ->
        [
          {"promise-without-within",
           "assertion #{inspect(f.trace)} has no `within`, so it has no failing case: any " <>
             "#{inspect(f.eventually)} after #{inspect(f.from)} satisfies it and a run with " <>
             "none stays pending for ever (#{inspect(f.contract)})"}
          | acc
        ]
    end
  end

  # A promise about duration that nothing can observe being kept or broken. The
  # aggregate stays silent for this process, and without this line the silence has
  # no visible cause.
  defp check_unobservable_deadlines(findings) do
    for f <- EhOsContract.Check.unobservable_deadlines(), reduce: findings do
      acc ->
        [
          {"deadline-without-terminal-event",
           "process #{inspect(f.process)} declares `deadline` = #{inspect(f.deadline)} and no " <>
             "event of it is `terminal: true`, so no run can be observed to end and the " <>
             "duration cannot be measured (#{inspect(f.contract)})"}
          | acc
        ]
    end
  end

  # Declarations the process owner has not confirmed. Not an error — a deliberate
  # transitional state. But it has to be visible on every run, because a false
  # metric is worse than a missing one: it is the metric the product sells.
  #
  # `field` names either a process key (`cadence`/`deadline`) or, since 21 August
  # 2026, a `trace`'s own name — the two need different sentences, because a
  # trace has no value on the process struct to print: `Map.get(process, field)`
  # would silently read `nil` for one and say nothing true about the other.
  defp check_unverified_declarations(findings) do
    for contract <- EhOsContract.Registry.contracts(),
        process <- EhOsContract.Model.processes(contract),
        field <- process.unverified,
        reduce: findings do
      acc -> [{"unverified-declaration", unverified_message(contract, process, field)} | acc]
    end
  end

  @spec unverified_message(module(), map(), atom()) :: String.t()
  defp unverified_message(contract, process, field) do
    if EhOsContract.Model.trace(contract, field) do
      "process #{inspect(process.name)}: assertion #{inspect(field)} is not confirmed by the " <>
        "process owner — it is still evaluated, but it does not count towards the evidence " <>
        "report's aggregate"
    else
      "process #{inspect(process.name)}: `#{field}` = #{inspect(Map.get(process, field))} " <>
        "is not confirmed by the process owner — it does not count towards the evidence report"
    end
  end

  @doc """
  The findings in the order they are printed: errors, then warnings, then notices,
  each group sorted by its text.

  A fixed order rather than the order the checks produced them. Some checks group
  by module into a map, and on OTP 26 and later a small map keyed by atoms iterates
  in the order the atoms were created, not alphabetically. A new module anywhere in
  the build could therefore swap two lines of this report between runs of the same
  code (v2 plan, E1). The plan compares this output commit to commit, so it has to
  come out the same for the same findings.
  """
  @spec ordered([Finding.t()]) :: [Finding.t()]
  def ordered(findings) do
    rank = %{error: 0, warn: 1, info: 2}
    Enum.sort_by(findings, &{Map.fetch!(rank, &1.level), &1.message, &1.rule})
  end

  @doc """
  What the task prints for `findings`, as `format` says: `:human`, two lines a
  finding and a count; `:json`, one array and nothing else (plan EL1).

  A finding's second line says where the declaration it is about was written, when
  anything does, and where its rule is documented. In JSON a finding is `rule`,
  `level` (`"error"`, `"warning"` or `"notice"`), `message`, `file` and `line` (`null`
  when nothing says where) and `documentation` (`null` for a repeated compiler rule,
  which the catalog does not document).
  """
  @spec render([Finding.t()], :human | :json) :: String.t()
  def render(findings, :human) do
    lines =
      for finding <- ordered(findings) do
        prefix =
          case finding.level do
            :error -> "ERROR"
            :warn -> "WARN "
            :info -> "info "
          end

        where =
          case Finding.place(finding) do
            nil -> []
            {file, line} -> ["#{file}:#{line}"]
          end

        second = Enum.join(where ++ List.wrap(documentation(finding)), " · ")
        "#{prefix} #{finding.rule}: #{finding.message}\n      #{second}\n"
      end

    counts = Enum.frequencies_by(findings, & &1.level)

    Enum.join(lines) <>
      "\neh_os_contract.check: #{Map.get(counts, :error, 0)} errors, " <>
      "#{Map.get(counts, :warn, 0)} warnings, #{Map.get(counts, :info, 0)} notices"
  end

  def render(findings, :json) do
    findings
    |> ordered()
    |> Enum.map(fn finding ->
      {file, line} = Finding.place(finding) || {nil, nil}

      Jason.OrderedObject.new(
        rule: finding.rule,
        level: Map.fetch!(%{error: "error", warn: "warning", info: "notice"}, finding.level),
        message: finding.message,
        file: file,
        line: line,
        documentation: documentation(finding)
      )
    end)
    |> Jason.encode!(pretty: true)
  end

  defp documentation(%Finding{rule: rule}) do
    if Enum.any?(Catalog.rules(), &(&1.id == rule)), do: Catalog.url(rule)
  end

  @doc """
  Whether `findings` fail the task: any error does, and a warning does when
  `warnings_as_errors` is set. Notices never do. The output is the same either way.
  """
  @spec failed?([Finding.t()], boolean()) :: boolean()
  def failed?(findings, warnings_as_errors) do
    Enum.any?(findings, &(&1.level == :error or (warnings_as_errors and &1.level == :warn)))
  end

  defp report(findings, opts) do
    format = if opts[:format] == "json", do: :json, else: :human
    Mix.shell().info(render(findings, format))
    if failed?(findings, opts[:warnings_as_errors] || false), do: exit({:shutdown, 1})
  end
end
