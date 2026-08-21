defmodule Mix.Tasks.Pns.Check do
  @shortdoc "Whole-program checks over the contract and the handlers"

  @moduledoc """
  Everything that requires seeing **every** module at once.

  The split is forced by the compilation model rather than chosen: a macro sees
  one file, so it checks what one file can show. That every declared event has a
  handler or is terminal, that there are no orphans, and that the declarations
  agree with reality — all of that belongs here.
  """

  use Boundary, classify_to: PNS
  use Mix.Task

  @vendors ~w(zitadel keycloak workos auth0 okta authentik fusionauth supertokens)

  @impl Mix.Task
  def run(_args) do
    # Erlang keeps stdout in latin1 when the output is not a terminal, so
    # `mix pns.check > report.txt` truncates every codepoint to a byte. Event
    # labels come from the contract and are written in the client's language.
    :io.setopts(:standard_io, encoding: :unicode)

    Mix.Task.run("compile")
    Application.load(:pns)
    PNS.Registry.load!()

    findings =
      []
      |> check_events_have_handlers()
      |> check_owners_exist()
      |> check_rule_functions_exist()
      |> check_traces_resolve()
      |> check_backward_edges()
      |> check_competing_sync_handlers()
      |> check_assertions_finer_than_their_run()
      |> check_facts_not_keyed_by_their_run()
      |> check_retain_on_free_text()
      |> check_no_vendor_in_config()
      |> check_unverified_declarations()

    report(findings)
  end

  # Every declared event has a handler or is terminal.
  defp check_events_have_handlers(findings) do
    for event <- PNS.Registry.declared_events(), reduce: findings do
      acc ->
        handlers = PNS.Registry.handlers_for(event.name)
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
              {:info,
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
    PNS.Registry.declared_events()
    |> Enum.reject(&is_nil(&1.owner))
    |> Enum.reject(&Code.ensure_loaded?(&1.owner))
    |> Enum.group_by(& &1.owner, & &1.name)
    |> Enum.reduce(findings, fn {owner, events}, acc ->
      count = if length(events) == 1, do: "1 event", else: "#{length(events)} events"

      [
        {:info,
         "owner #{inspect(owner)} does not exist as a module, and is declared for " <>
           "#{count}: #{inspect(events)}"}
        | acc
      ]
    end)
  end

  # A `rule` names an MFA, so nobody checks for us that the function exists.
  defp check_rule_functions_exist(findings) do
    for contract <- PNS.Registry.contracts(), rule <- contract.rules(), reduce: findings do
      acc ->
        {module, function, arity} = rule.function

        if Code.ensure_loaded?(module) and function_exported?(module, function, arity) do
          acc
        else
          [
            {:error,
             "rule #{inspect(rule.name)} names #{inspect(module)}.#{function}/#{arity}, " <>
               "which does not exist"}
            | acc
          ]
        end
    end
  end

  defp check_traces_resolve(findings) do
    all_events = PNS.Registry.declared_events() |> Enum.map(& &1.name) |> MapSet.new()

    for contract <- PNS.Registry.contracts(), trace <- contract.traces(), reduce: findings do
      acc ->
        missing =
          [trace.from, trace.eventually, trace.or_else]
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(&MapSet.member?(all_events, &1))

        if missing == [] do
          acc
        else
          [{:error, "trace #{inspect(trace.name)} does not resolve #{inspect(missing)}"} | acc]
        end
    end
  end

  # The logic lives in `PNS.Check`, not here: as a private function of a mix task
  # it was logic with no test, and this is the check the ADR §15 review trigger
  # rests on.
  defp check_backward_edges(findings) do
    Enum.reduce(PNS.Check.backward_edges(), findings, fn edge, acc ->
      [
        {:warn,
         "backward edge in #{inspect(edge.module)} — #{edge.process}: " <>
           "publishes in #{edge.publishes_in}, subscribes in #{edge.subscribes_in}"}
        | acc
      ]
    end)
  end

  defp check_competing_sync_handlers(findings) do
    Enum.reduce(PNS.Check.competing_sync_handlers(), findings, fn item, acc ->
      order = item.modules |> Enum.map(&inspect/1) |> Enum.join(", ")

      [
        {:warn,
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
  # catch-all: see `PNS.Contract.payload_types/0`.
  defp check_retain_on_free_text(findings) do
    for event <- PNS.Registry.declared_events(),
        {field, type} <- event.payload,
        type == :string,
        not Map.has_key?(event.retain, field),
        reduce: findings do
      acc ->
        [
          {:info,
           "#{inspect(event.name)}.#{field} is free text with no `retain` — " <>
             "it reaches the log verbatim"}
          | acc
        ]
    end
  end

  # An assertion whose subject is finer than the run it is counted in. A warning
  # rather than an error, because the fix is a modelling decision and sometimes
  # there is nothing to write instead — but it must be visible on every run, since
  # this is the one shape of mistake in the DSL that reports **satisfied** while
  # the data says otherwise.
  defp check_assertions_finer_than_their_run(findings) do
    for f <- PNS.Check.assertions_finer_than_their_run(), reduce: findings do
      acc ->
        [
          {:warn,
           "assertion #{inspect(f.trace)} is finer than its run: `#{f.from}` is identified by " <>
             "#{inspect(f.identity)} while process #{inspect(f.process)} is a run per " <>
             "#{inspect(f.instance)}. One verdict is produced per run, so a single fulfilment " <>
             "satisfies every promise in it (#{inspect(f.contract)})"}
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
    for f <- PNS.Check.facts_not_keyed_by_their_run(), reduce: findings do
      acc ->
        [
          {:warn,
           "event #{inspect(f.event)} is identified by #{inspect(f.identity)}, which does not " <>
             "contain #{inspect(f.missing)} — the field(s) process #{inspect(f.process)} keys a " <>
             "run by (`instance: #{inspect(f.instance)}`). Two of these facts in two different " <>
             "runs then share one identity, so the asynchronous idempotency key cannot tell " <>
             "them apart and the second one is deduplicated away (#{inspect(f.contract)})"}
          | acc
        ]
    end
  end

  # Declarations the process owner has not confirmed. Not an error — a deliberate
  # transitional state. But it has to be visible on every run, because a false
  # metric is worse than a missing one: it is the metric the product sells.
  defp check_unverified_declarations(findings) do
    for contract <- PNS.Registry.contracts(),
        process <- contract.processes(),
        field <- process.unverified,
        reduce: findings do
      acc ->
        [
          {:warn,
           "process #{inspect(process.name)}: `#{field}` = #{inspect(Map.get(process, field))} " <>
             "is not confirmed by the process owner — it does not count towards the evidence report"}
          | acc
        ]
    end
  end

  # The identity seam: a vendor's name in the engine's configuration schema breaks it.
  defp check_no_vendor_in_config(findings) do
    haystack = :pns |> Application.get_all_env() |> inspect() |> String.downcase()

    case Enum.filter(@vendors, &String.contains?(haystack, &1)) do
      [] ->
        findings

      found ->
        [
          {:error, "identity vendor name in the engine's configuration: #{inspect(found)} — seam broken"}
          | findings
        ]
    end
  end

  defp report(findings) do
    for {level, message} <- Enum.reverse(findings) do
      prefix =
        case level do
          :error -> "ERROR"
          :warn -> "WARN "
          :info -> "info "
        end

      Mix.shell().info("#{prefix} #{message}")
    end

    counts = Enum.frequencies_by(findings, &elem(&1, 0))

    Mix.shell().info(
      "\npns.check: #{Map.get(counts, :error, 0)} errors, " <>
        "#{Map.get(counts, :warn, 0)} warnings, #{Map.get(counts, :info, 0)} notices"
    )

    if Map.get(counts, :error, 0) > 0, do: exit({:shutdown, 1})
  end
end
