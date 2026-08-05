defmodule PNS.Contract do
  @moduledoc """
  The contract as an Elixir module (ADR §2, notes §1).

  Declarations accumulate in module attributes, and `@before_compile` generates
  the query functions. Those are called at two different moments: at compile time
  by the handler macro, and at run time by the conformance queries.

  The gate from ADR §18 lives here: **a rule with no example does not compile.**
  """

  # One source of truth for the DSL surface: which keys exist, which are
  # required, and what an omitted key falls back to. Everything else reads from
  # here — the key validation below, `vocabulary/0`, and the generated reference
  # in `docs/contract.md`. Two lists would be two things to drift apart, which is
  # the failure this product exists to detect.
  @schema %{
    event: %{
      required: [:label],
      optional: [:owner, :payload, :retain, :depends_on, :identity, :process, :stage, :terminal],
      defaults: %{payload: %{}, retain: %{}, terminal: false}
    },
    process: %{
      required: [:label, :instance],
      optional: [:stages, :cadence, :deadline, :unverified],
      defaults: %{stages: [], unverified: []}
    },
    external: %{
      required: [:label],
      optional: [:expected_latency, :unavailable_looks_like],
      defaults: %{}
    },
    rule: %{
      required: [:label, :function],
      optional: [:source],
      defaults: %{}
    },
    example: %{
      required: [:rule, :command],
      optional: [:given, :then, :rejected_with],
      defaults: %{given: %{}}
    },
    trace: %{
      required: [:from, :eventually],
      optional: [:within, :or_else],
      defaults: %{}
    }
  }

  @event_keys @schema.event.required ++ @schema.event.optional
  @process_keys @schema.process.required ++ @schema.process.optional
  @external_keys @schema.external.required ++ @schema.external.optional
  @rule_keys @schema.rule.required ++ @schema.rule.optional
  @example_keys @schema.example.required ++ @schema.example.optional

  @typedoc "A declaration kind: the name of one DSL construct."
  @type declaration :: :event | :process | :external | :rule | :example | :trace

  @doc """
  The DSL surface as data: keys per declaration, which are required, and the
  fallback for each omitted optional key.

  Exists so the reference in `docs/contract.md` can be generated rather than
  written by hand. A hand-written key table is a second source of truth, and
  every one of those in this project has eventually disagreed with the code.
  """
  @spec schema() :: %{declaration() => map()}
  def schema, do: @schema

  @doc """
  The whole DSL vocabulary as data, derived from `schema/0`.

  Exists so the **universality gate can be pinned by a test**. The stage 1.2
  criterion reads "zero new words to describe another domain", and a criterion
  nobody checks is a sentence in prose. A test pins this map, so adding a
  domain-specific word to the DSL breaks it the same day rather than at a review
  next quarter.

  It is also where the record of why there is **no `population`** lives — the one
  word that failed that test, and the one that tends to come back.
  """
  @spec vocabulary() :: %{declaration() => [atom()]}
  def vocabulary do
    Map.new(@schema, fn {declaration, keys} -> {declaration, keys.required ++ keys.optional} end)
  end

  @doc false
  defmacro __using__(_opts) do
    quote do
      import PNS.Contract, only: [event: 2, process: 2, trace: 2, external: 2, rule: 2, example: 2]

      Module.register_attribute(__MODULE__, :pns_events, accumulate: true)
      Module.register_attribute(__MODULE__, :pns_processes, accumulate: true)
      Module.register_attribute(__MODULE__, :pns_traces, accumulate: true)
      Module.register_attribute(__MODULE__, :pns_externals, accumulate: true)
      Module.register_attribute(__MODULE__, :pns_rules, accumulate: true)
      Module.register_attribute(__MODULE__, :pns_examples, accumulate: true)

      @before_compile PNS.Contract
    end
  end

  @doc "An event: a fact that happened. Named in the past tense."
  defmacro event(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      @pns_events PNS.Contract.build_event(name, opts)
    end
  end

  @doc "A process: the dashboard's navigation unit and the contract's unit of division."
  defmacro process(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      @pns_processes PNS.Contract.build_process(name, opts)
    end
  end

  @doc "An external dependency, named after the business fact rather than the vendor (ADR §11-12)."
  defmacro external(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      @pns_externals PNS.Contract.build_external(name, opts)
    end
  end

  @doc """
  A rule names **one pure function and nothing else**, through an MFA tuple.

  MFA rather than a capture: a capture would make the contract a compile-time
  dependency of the domain, and handlers depend on the contract — so every domain
  change would recompile every handler.
  """
  defmacro rule(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      @pns_rules PNS.Contract.build_rule(name, opts)
    end
  end

  @doc """
  An example pins a rule with a case that can be read aloud to the process owner
  and executed as a test.
  """
  defmacro example(description, opts) do
    quote bind_quoted: [description: description, opts: opts] do
      @pns_examples PNS.Contract.build_example(description, opts)
    end
  end

  @doc """
  An assertion over an observed run. The block is taken apart at compile time, so
  `from`/`eventually`/`or_else` do not exist at run time.
  """
  defmacro trace(name, do: block) do
    steps = trace_steps(block)

    quote bind_quoted: [name: name, steps: Macro.escape(steps)] do
      @pns_traces Map.put(steps, :name, name)
    end
  end

  # --- building declarations (called while the contract compiles) ---

  @doc false
  @spec build_event(atom(), keyword()) :: map()
  def build_event(name, opts) do
    validate_keys!(opts, @event_keys, "event #{inspect(name)}")

    %{
      name: name,
      label: fetch!(opts, :label, "event #{inspect(name)}"),
      owner: Keyword.get(opts, :owner),
      payload: Keyword.get(opts, :payload, %{}),
      retain: Keyword.get(opts, :retain, %{}),
      depends_on: Keyword.get(opts, :depends_on),
      # `identity` says **what makes two occurrences of this event the same
      # business fact**. The idempotency key comes from it.
      #
      # It sits on the event rather than on the handler, and that is a correction
      # to the first version: "are two divergences in one month one notification
      # or two" is a question for the process owner, not for the developer writing
      # the handler. ADR §9-10 states outright that idempotency is a property of
      # the contract; the notes said it was the handler's. The ADR is right.
      #
      # There is a practical consequence too: a fact has one identity, while one
      # event can have many handlers. Held on the handler it would drift between
      # them.
      identity: opts |> Keyword.get(:identity) |> then(&(&1 && List.wrap(&1))),
      # **Where this event sits in the process — on the event, not on the process.**
      #
      # The first version had it the other way round: a process listed its events
      # in `stages:`, so every event name was written twice in the contract, and
      # adding an event took two edits a hundred lines apart. The rule is the same
      # one as for `identity` and `instance`: a declaration goes where there is
      # one of it. There is one stage per event.
      #
      # The side effect is better than the readability: "an event belongs to at
      # most one process" stops being a compile-time gate and becomes something
      # inexpressible. That was a stop condition in ADR §15.
      process: Keyword.get(opts, :process),
      stage: Keyword.get(opts, :stage),
      # `terminal: true` — the process ends on this event. Also a property of the
      # event rather than of a list kept somewhere else.
      terminal: Keyword.get(opts, :terminal, false)
    }
  end

  @doc false
  @spec build_process(atom(), keyword()) :: map()
  def build_process(name, opts) do
    validate_keys!(opts, @process_keys, "process #{inspect(name)}")

    where = "process #{inspect(name)}"

    %{
      name: name,
      label: fetch!(opts, :label, where),
      # **Gates are sequential, events are not** — and that is the only thing
      # `stages:` declares: the order **between** stages. The contract claims
      # nothing about order within a stage.
      #
      # The workshop says it outright: the stages are not fully sequential, the
      # gates are. KSeF pulls continuously and matching is stitched on as it goes.
      # The first version had a flat ordered list of events, and backward-edge
      # detection rested on that order — so the check enforced our idea presented
      # as the client's model.
      #
      # Which event is in which stage is said by the event itself. What is left
      # here is only the order of stages, because that is the one thing an event
      # cannot say about itself.
      #
      # No `stages:` means exactly this: one stage, and zero claims about order.
      # Events of such a process then give no `stage:`.
      stages: Keyword.get(opts, :stages, []),
      # `instance` names the payload fields that say **which run** an event
      # belongs to. It is required, because both of the things that make this a
      # product are counted within a run: the `trace` assertion and the
      # declared-versus-observed overlay. A process with no run identity is one
      # PNS can only describe as "some event of this type happened" — which is
      # exactly the state stage 1.1 fixed.
      #
      # It sits on the process rather than on the event, and that is a different
      # question from `identity`: a fact's identity belongs to the fact, a run's
      # identity to the process. Repeated on every event it would drift between
      # them.
      instance: opts |> fetch!(:instance, where) |> List.wrap(),
      # cadence: how often an instance is due — the "never observed" window is
      # computed from it. Without one, a monthly closing reads as a dead path six
      # days after the last run (notes §9).
      cadence: Keyword.get(opts, :cadence),
      deadline: Keyword.get(opts, :deadline),
      # Declarations the **process owner has not confirmed**. They stay in the
      # contract, because without them the mechanism has nothing to watch, but
      # they must not count towards the evidence report: a false metric is worse
      # than a missing one, because it is a metric the product sells.
      unverified: Keyword.get(opts, :unverified, [])
    }
  end

  @doc false
  @spec build_external(atom(), keyword()) :: map()
  def build_external(name, opts) do
    validate_keys!(opts, @external_keys, "external #{inspect(name)}")

    %{
      name: name,
      label: fetch!(opts, :label, "external #{inspect(name)}"),
      expected_latency: Keyword.get(opts, :expected_latency),
      unavailable_looks_like: Keyword.get(opts, :unavailable_looks_like)
    }
  end

  @doc false
  @spec build_rule(atom(), keyword()) :: map()
  def build_rule(name, opts) do
    validate_keys!(opts, @rule_keys, "rule #{inspect(name)}")
    mfa = fetch!(opts, :function, "rule #{inspect(name)}")

    case mfa do
      {m, f, a} when is_atom(m) and is_atom(f) and is_integer(a) ->
        :ok

      other ->
        raise ArgumentError,
              "rule #{inspect(name)}: `function:` must be an MFA tuple {Module, :function, arity}, " <>
                "got #{inspect(other)}. A capture (&Mod.fun/1) is forbidden — it would make the " <>
                "contract a compile-time dependency of the domain."
    end

    %{
      name: name,
      label: fetch!(opts, :label, "rule #{inspect(name)}"),
      function: mfa,
      source: Keyword.get(opts, :source)
    }
  end

  @doc false
  @spec build_example(String.t(), keyword()) :: map()
  def build_example(description, opts) do
    validate_keys!(opts, @example_keys, "example #{inspect(description)}")

    outcome =
      case {Keyword.fetch(opts, :then), Keyword.fetch(opts, :rejected_with)} do
        {{:ok, events}, :error} ->
          {:emits, events}

        {:error, {:ok, reason}} ->
          {:rejected, reason}

        {{:ok, _}, {:ok, _}} ->
          raise ArgumentError,
                "example #{inspect(description)}: `then:` or `rejected_with:`, not both"

        {:error, :error} ->
          raise ArgumentError,
                "example #{inspect(description)}: missing `then:` or `rejected_with:`"
      end

    %{
      description: description,
      rule: fetch!(opts, :rule, "example #{inspect(description)}"),
      given: Keyword.get(opts, :given, %{}),
      command: fetch!(opts, :command, "example #{inspect(description)}"),
      outcome: outcome
    }
  end

  @spec fetch!(keyword(), atom(), String.t()) :: term()
  defp fetch!(opts, key, where) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "#{where}: missing required `#{key}:`"
    end
  end

  @spec validate_keys!(keyword(), [atom()], String.t()) :: :ok
  defp validate_keys!(opts, allowed, where) do
    case Keyword.keys(opts) -- allowed do
      [] -> :ok
      extra -> raise ArgumentError, "#{where}: unknown keys #{inspect(extra)}, allowed #{inspect(allowed)}"
    end
  end

  @spec trace_steps(Macro.t()) :: map()
  defp trace_steps(block) do
    exprs =
      case block do
        {:__block__, _, exprs} -> exprs
        single -> [single]
      end

    Enum.reduce(exprs, %{from: nil, eventually: nil, within: nil, or_else: nil}, fn
      {:from, _, [event]}, acc ->
        %{acc | from: event}

      {:eventually, _, [event, opts]}, acc ->
        %{acc | eventually: event, within: Keyword.get(opts, :within)}

      {:eventually, _, [event]}, acc ->
        %{acc | eventually: event}

      {:or_else, _, [event]}, acc ->
        %{acc | or_else: event}

      other, _acc ->
        raise ArgumentError,
              "trace: unknown instruction #{Macro.to_string(other)}. " <>
                "Allowed: from/1, eventually/1-2, or_else/1"
    end)
  end

  # --- generating the query functions ---

  @doc false
  defmacro __before_compile__(env) do
    events = attr(env, :pns_events)
    processes = attr(env, :pns_processes)
    traces = attr(env, :pns_traces)
    externals = attr(env, :pns_externals)
    rules = attr(env, :pns_rules)
    examples = attr(env, :pns_examples)

    validate!(env, events, processes, traces, externals, rules, examples)

    version =
      [events, processes, traces, externals, rules, examples]
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    quote do
      @doc false
      def __pns_contract__, do: true

      @doc "Every declared event, in declaration order."
      @spec events() :: [map()]
      def events, do: unquote(Macro.escape(events))

      @doc "The names of every declared event."
      @spec event_names() :: [atom()]
      def event_names, do: unquote(Enum.map(events, & &1.name))

      @doc "Whether this contract declares an event under that name."
      @spec event?(atom()) :: boolean()
      def event?(name), do: name in unquote(Enum.map(events, & &1.name))

      @doc "One declared event by name. Raises when the contract does not declare it."
      @spec event(atom()) :: map()
      def event(name) do
        Enum.find(events(), &(&1.name == name)) ||
          raise ArgumentError, "#{inspect(__MODULE__)}: no such event #{inspect(name)}"
      end

      @doc "Every declared process, in declaration order."
      @spec processes() :: [map()]
      def processes, do: unquote(Macro.escape(processes))

      @doc "One declared process by name, or `nil`."
      @spec process(atom()) :: map() | nil
      def process(name), do: Enum.find(processes(), &(&1.name == name))

      @doc """
      The process an event belongs to — that is, where its run identity comes
      from. An event names **one** process, so the answer is unambiguous by
      construction rather than thanks to a check.
      """
      @spec process_of(atom()) :: map() | nil
      def process_of(event_name) do
        case Enum.find(events(), &(&1.name == event_name)) do
          %{process: nil} -> nil
          %{process: name} -> process(name)
          nil -> nil
        end
      end

      @doc "The events belonging to a process. The inverse of `process_of/1`."
      @spec events_of(atom()) :: [map()]
      def events_of(process_name), do: Enum.filter(events(), &(&1.process == process_name))

      @doc "Every declared trace assertion."
      @spec traces() :: [map()]
      def traces, do: unquote(Macro.escape(traces))

      @doc "Every declared external dependency."
      @spec externals() :: [map()]
      def externals, do: unquote(Macro.escape(externals))

      @doc "One declared external dependency by name, or `nil`."
      @spec external(atom()) :: map() | nil
      def external(name), do: Enum.find(externals(), &(&1.name == name))

      @doc "Every declared rule."
      @spec rules() :: [map()]
      def rules, do: unquote(Macro.escape(rules))

      @doc "One declared rule by name, or `nil`."
      @spec rule(atom()) :: map() | nil
      def rule(name), do: Enum.find(rules(), &(&1.name == name))

      @doc "Every declared example."
      @spec examples() :: [map()]
      def examples, do: unquote(Macro.escape(examples))

      @doc "The examples pinning one rule."
      @spec examples_for(atom()) :: [map()]
      def examples_for(rule_name), do: Enum.filter(examples(), &(&1.rule == rule_name))

      @doc """
      A hash of every declaration, computed at compile time. This is the
      `contract_version` stamped on every event — it cannot be forgotten or
      maintained by hand.
      """
      @spec version() :: String.t()
      def version, do: unquote(version)
    end
  end

  @spec attr(Macro.Env.t(), atom()) :: [map()]
  defp attr(env, name), do: env.module |> Module.get_attribute(name) |> Enum.reverse()

  @spec validate!(Macro.Env.t(), [map()], [map()], [map()], [map()], [map()], [map()]) :: :ok
  defp validate!(env, events, processes, traces, externals, rules, examples) do
    names = Enum.map(events, & &1.name)

    dupes = names -- Enum.uniq(names)
    dupes == [] || bail!(env, "events declared twice: #{inspect(Enum.uniq(dupes))}")

    # ADR §18, the compile gate: a rule with no example does not compile.
    rules_without_examples =
      rules
      |> Enum.filter(fn rule -> not Enum.any?(examples, &(&1.rule == rule.name)) end)
      |> Enum.map(& &1.name)

    rules_without_examples == [] ||
      bail!(
        env,
        "a rule with no example does not compile (ADR §18): #{inspect(rules_without_examples)}. " <>
          "A rule with no example is a sentence in prose — add at least one `example` that can " <>
          "be read aloud to the process owner."
      )

    orphan_examples =
      examples
      |> Enum.filter(fn ex -> not Enum.any?(rules, &(&1.name == ex.rule)) end)
      |> Enum.map(& &1.description)

    orphan_examples == [] ||
      bail!(env, "examples pointing at a rule that does not exist: #{inspect(orphan_examples)}")

    # `from` and `eventually` are the assertion. Without `eventually` a trace
    # compiles and evaluates to nonsense: nothing can ever satisfy it, so every
    # run is violated once its window passes. Declaring the requirement in the
    # schema and not enforcing it would be the same decoration this project keeps
    # finding elsewhere.
    for t <- traces, key <- PNS.Contract.schema().trace.required, is_nil(Map.get(t, key)) do
      bail!(
        env,
        "trace #{inspect(t.name)}: missing `#{key}`. A trace states \"after X, eventually Y\"; " <>
          "without both halves there is nothing an observed run could satisfy."
      )
    end

    validate_membership!(env, events, processes)

    # A gate matched to what assertion evaluation **can actually compute**.
    # Without it `within: {1, :month}` passed compilation and blew up at run
    # time, which means at the client's — and the single source of truth about
    # units lives in `PNS.Duration` so the gate cannot drift from the arithmetic.
    for t <- traces, not is_nil(t.within) do
      {_n, unit} = t.within

      unit in PNS.Duration.units() ||
        bail!(env, "trace #{inspect(t.name)}: `within` — #{PNS.Duration.message(unit)}")
    end

    for t <- traces, ev <- Enum.reject([t.from, t.eventually, t.or_else], &is_nil/1), ev not in names do
      bail!(env, "trace #{inspect(t.name)} names event #{inspect(ev)}, which the contract does not declare")
    end

    validate_instances!(env, events, processes, traces)

    external_names = Enum.map(externals, & &1.name)

    for e <- events, not is_nil(e.depends_on), e.depends_on not in external_names do
      bail!(
        env,
        "event #{inspect(e.name)} declares `depends_on: #{inspect(e.depends_on)}`, " <>
          "which is not declared as an `external`"
      )
    end

    for e <- events, {field, _policy} <- e.retain, not Map.has_key?(e.payload, field) do
      bail!(
        env,
        "event #{inspect(e.name)}: `retain` names field #{inspect(field)}, " <>
          "which is not in `payload`"
      )
    end

    for e <- events, field <- e.identity || [] do
      Map.has_key?(e.payload, field) ||
        bail!(
          env,
          "event #{inspect(e.name)}: `identity` names field #{inspect(field)}, " <>
            "which is not in `payload`"
        )

      # A field dropped from the payload cannot take part in a fact's identity —
      # the idempotency key would disappear along with it.
      Map.get(e.retain, field) == :drop &&
        bail!(
          env,
          "event #{inspect(e.name)}: field #{inspect(field)} is in `identity` and " <>
            "`retain: :drop` at the same time"
        )
    end

    :ok
  end

  # An event's membership of a process and of a stage. The event declares it, so
  # all that is checked here is whether it points at something that exists, and
  # whether it leaves the process without an answer to "which stage is this".
  @spec validate_membership!(Macro.Env.t(), [map()], [map()]) :: :ok
  defp validate_membership!(env, events, processes) do
    by_process = Map.new(processes, &{&1.name, &1})

    for e <- events do
      cond do
        is_nil(e.process) and not is_nil(e.stage) ->
          bail!(
            env,
            "event #{inspect(e.name)} gives `stage: #{inspect(e.stage)}` with no `process:`. " <>
              "A stage is a stage of some process."
          )

        is_nil(e.process) and e.terminal ->
          bail!(
            env,
            "event #{inspect(e.name)} is `terminal: true` with no `process:`. " <>
              "Terminal means \"the process ends here\", so it has to say which one."
          )

        is_nil(e.process) ->
          :ok

        not Map.has_key?(by_process, e.process) ->
          bail!(
            env,
            "event #{inspect(e.name)} declares `process: #{inspect(e.process)}`, " <>
              "which the contract does not declare"
          )

        true ->
          validate_stage!(env, e, Map.fetch!(by_process, e.process))
      end
    end

    :ok
  end

  @spec validate_stage!(Macro.Env.t(), map(), map()) :: :ok
  defp validate_stage!(env, event, process) do
    cond do
      process.stages == [] and not is_nil(event.stage) ->
        bail!(
          env,
          "event #{inspect(event.name)} gives `stage: #{inspect(event.stage)}`, but process " <>
            "#{inspect(process.name)} declares no stages. A process with no `stages:` is one " <>
            "stage and zero claims about order."
        )

      process.stages != [] and is_nil(event.stage) ->
        bail!(
          env,
          "event #{inspect(event.name)} belongs to process #{inspect(process.name)}, which " <>
            "declares stages #{inspect(process.stages)}, but does not say which one it is in. " <>
            "Backward-edge detection rests on the order of stages, so an event with no stage " <>
            "would be a hole in that check rather than a missing ornament."
        )

      not is_nil(event.stage) and event.stage not in process.stages ->
        bail!(
          env,
          "event #{inspect(event.name)} gives `stage: #{inspect(event.stage)}`, which process " <>
            "#{inspect(process.name)} does not declare. Declared stages: #{inspect(process.stages)}"
        )

      true ->
        :ok
    end
  end

  # Two gates around run identity. Both follow from one property: the
  # `instance_id` computed at emit time has to be unambiguous and reproducible
  # from the log alone, and the log has one column for it.
  #
  # A third gate is no longer here, and that is the result of moving `process:`
  # onto the event: "an event belongs to at most one process" used to be a check
  # and has become something **inexpressible**. That is the stop condition from
  # ADR §15 ("stop if processes nest or one event belongs to two") settled by the
  # shape of the declaration rather than by a check.
  @spec validate_instances!(Macro.Env.t(), [map()], [map()], [map()]) :: :ok
  defp validate_instances!(env, events, processes, traces) do
    by_process = Map.new(processes, &{&1.name, &1})
    process_of = fn ev -> Enum.find_value(events, &(&1.name == ev && &1.process)) end

    # 1. Every event of a process carries the instance fields — and does not lose
    #    them on the way.
    for e <- events, p = e.process && Map.get(by_process, e.process), field <- p.instance do
      Map.has_key?(e.payload, field) ||
        bail!(
          env,
          "process #{inspect(p.name)} declares `instance: #{inspect(p.instance)}`, but event " <>
            "#{inspect(e.name)} has no #{inspect(field)} field in its payload. Without it there " <>
            "is no way to say which run this event belongs to — and then a `trace` assertion " <>
            "will match it against any other run."
        )

      Map.get(e.retain, field) == :drop &&
        bail!(
          env,
          "event #{inspect(e.name)}: field #{inspect(field)} takes part in the run identity of " <>
            "process #{inspect(p.name)} and has `retain: :drop` at the same time. Run identity " <>
            "is computed from the payload after `retain` is applied, so it would disappear along " <>
            "with the field."
        )
    end

    # 2. An assertion is counted within one run, so it cannot span two processes
    #    — each of them has a different run identity.
    for t <- traces do
      trace_events = Enum.reject([t.from, t.eventually, t.or_else], &is_nil/1)
      homeless = Enum.filter(trace_events, &is_nil(process_of.(&1)))

      homeless == [] ||
        bail!(
          env,
          "trace #{inspect(t.name)} names events outside any process: #{inspect(homeless)}. " <>
            "There is no run in which this assertion could be counted."
        )

      case trace_events |> Enum.map(process_of) |> Enum.uniq() do
        [_one] ->
          :ok

        many ->
          bail!(
            env,
            "trace #{inspect(t.name)} spans processes #{inspect(many)}. An assertion is counted " <>
              "within one run, and every process has its own run identity."
          )
      end
    end

    :ok
  end

  @spec bail!(Macro.Env.t(), String.t()) :: no_return()
  defp bail!(env, message) do
    raise CompileError, file: env.file, line: env.line, description: message
  end
end
