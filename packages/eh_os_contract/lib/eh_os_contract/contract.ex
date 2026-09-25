defmodule EhOsContract.Contract do
  @moduledoc """
  The contract as an Elixir module (ADR §2, notes §1).

  Declarations accumulate in module attributes, and `@before_compile` generates
  the query functions. Inside the engine only `EhOsContract.Model.V1` calls them;
  every reader, the handler macro at compile time included, asks
  `EhOsContract.Model` instead. A new reader should do the same.

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
      optional: [:stages, :cadence, :deadline, :unverified, :accountable],
      defaults: %{stages: [], unverified: []}
    },
    command: %{
      required: [:label, :process, :principals],
      optional: [:payload, :source],
      defaults: %{payload: %{}}
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

  # The payload type vocabulary, closed on purpose.
  #
  # Every one of these says something about the **shape of a value**, and nothing
  # about anybody's business. That is the whole property: a library whose type
  # vocabulary knows what an accounting period is, is a library that knows one
  # client's domain — and the universality gate cannot catch it, because that gate
  # asks whether a word had to be **added** to describe a second domain, never
  # whether one is surplus. `:period` lived here for two days and was found by
  # counting: the medical contract has fourteen payload fields and uses it zero
  # times. It is an accounting month wearing the costume of a general type.
  #
  # The set is closed rather than advisory because the alternative is not a
  # convention, it is nothing: before this gate any atom was a legal type, so
  # removing `:period` would have been undone by the next person who found it
  # convenient. A closed set makes the domain leak a compile error.
  #
  # `:string` means text a human typed, and it is the only member with a second
  # reader: the retention check in `mix eh_os_contract.check` reports a `:string` field with no
  # `retain` policy. That check only produces signal because identifiers are a
  # different type — its first version flagged every `:string` and produced 33
  # notices for 11 events, including every `company_id`.
  @payload_types [:id, :string, :integer, :timestamp, :enum]

  # Who may issue a command. Closed for the reason `@payload_types` is closed: an
  # open set is not a convention, it is nothing.
  #
  # **This one is a proposal, not a reading.** The stage 5.5 census looked for a
  # principal vocabulary in the corpus and did not find one: the engine knows only
  # an opaque actor subject and `EhOsContract.Event.system_actor/0`; the contracts
  # carry `actor_roles: ["accounting"]`, which is a role rather than a kind of
  # principal. Both members describe *who issues* and neither names anybody's
  # business — but they were chosen rather than observed, and that is written here
  # so the next reader does not mistake one for the other.
  @principal_types [:human, :system]

  @event_keys @schema.event.required ++ @schema.event.optional
  @process_keys @schema.process.required ++ @schema.process.optional
  @external_keys @schema.external.required ++ @schema.external.optional
  @rule_keys @schema.rule.required ++ @schema.rule.optional
  @example_keys @schema.example.required ++ @schema.example.optional
  @command_keys @schema.command.required ++ @schema.command.optional

  @typedoc "A declaration kind: the name of one DSL construct."
  @type declaration :: :event | :process | :external | :rule | :example | :trace | :command

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
  The legal payload types, in the order they are documented.

  A closed set, and closed is the point: each member describes the shape of a value
  and none of them knows anything about a business. Public because the reference in
  `docs/contract.md` is generated from it and a test pins it against a literal — a
  domain-specific type added here fails that test the same day rather than at a
  review next quarter.
  """
  @spec payload_types() :: [atom()]
  def payload_types, do: @payload_types

  @doc """
  Who may issue a command. A closed set, and a proposal — the attribute's own
  comment says why this one was chosen rather than read out of the corpus.

  A description of who takes this way into the process, not an access decision:
  the engine enforces nothing with it. Whether a given caller may issue a command
  is the emitting application's to decide, and where that decision is a domain
  rule it stays a `rule` with a decision function.
  """
  @spec principal_types() :: [atom()]
  def principal_types, do: @principal_types

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
      import EhOsContract.Contract,
        only: [event: 2, process: 2, trace: 2, external: 2, rule: 2, example: 2, command: 2]

      Module.register_attribute(__MODULE__, :eh_os_contract_events, accumulate: true)
      Module.register_attribute(__MODULE__, :eh_os_contract_processes, accumulate: true)
      Module.register_attribute(__MODULE__, :eh_os_contract_traces, accumulate: true)
      Module.register_attribute(__MODULE__, :eh_os_contract_externals, accumulate: true)
      Module.register_attribute(__MODULE__, :eh_os_contract_rules, accumulate: true)
      Module.register_attribute(__MODULE__, :eh_os_contract_examples, accumulate: true)
      Module.register_attribute(__MODULE__, :eh_os_contract_commands, accumulate: true)

      @before_compile EhOsContract.Contract
    end
  end

  @doc "An event: a fact that happened. Named in the past tense."
  defmacro event(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      @eh_os_contract_events EhOsContract.Contract.build_event(name, opts)
    end
  end

  @doc "A process: the dashboard's navigation unit and the contract's unit of division."
  defmacro process(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      @eh_os_contract_processes EhOsContract.Contract.build_process(name, opts)
    end
  end

  @doc "An external dependency, named after the business fact rather than the vendor (ADR §11-12)."
  defmacro external(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      @eh_os_contract_externals EhOsContract.Contract.build_external(name, opts)
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
      @eh_os_contract_rules EhOsContract.Contract.build_rule(name, opts)
    end
  end

  @doc """
  An example pins a rule with a case that can be read aloud to the process owner
  and executed as a test.
  """
  defmacro example(description, opts) do
    quote bind_quoted: [description: description, opts: opts] do
      @eh_os_contract_examples EhOsContract.Contract.build_example(description, opts)
    end
  end

  @doc """
  A command: a way into a process from outside, and who may take it.

  Everything else in a contract describes what happened; this describes what can be
  asked for. It carries no list of the events it emits — see `build_command/2`.
  """
  defmacro command(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      @eh_os_contract_commands EhOsContract.Contract.build_command(name, opts)
    end
  end

  @doc """
  An assertion over an observed run. The block is taken apart at compile time, so
  `from`/`eventually`/`or_else` do not exist at run time.
  """
  defmacro trace(name, do: block) do
    steps = trace_steps(block)

    quote bind_quoted: [name: name, steps: Macro.escape(steps)] do
      @eh_os_contract_traces Map.put(steps, :name, name)
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
      # EhOsContract can only describe as "some event of this type happened" — which is
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
      # Who the report is addressed to when this process's rule is broken. A role,
      # not a person and not a module — `owner:` on an event answers a different
      # question, "which module implements this fact", and holds a module. One key
      # meaning two types is the drift this library sells detection of, so the two
      # questions get two words.
      #
      # Optional, and `mix eh_os_contract.check` warns rather than the compiler refusing: a
      # process whose owner has not been agreed yet is an ordinary state mid-rollout,
      # and a gate that fails a build for being early gets removed before it catches
      # the real case.
      accountable: Keyword.get(opts, :accountable),
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

  @doc """
  Builds one `command` declaration.

  **There is no `emits:` key, and that is a deviation from `D-15` as written.** The
  stage 5.5 census measured both readings of "what this command emits" against the
  corpus: the set the examples show and the set reachable through handler edges are
  identical for one of the two commands and differ by three events for the other —
  including the event that command is named after. So the key would have two
  meanings, provably different, and no gate could check either: a gate can refuse an
  event that does not exist, never a set that is incomplete. It would be the first
  key in a contract allowed to be wrong with nothing to notice.

  The reachable set is already held, by `EhOsContract.Registry` and the handlers' own
  `publishes:`, which the engine verifies at run time. A third copy is the drift
  this product detects.
  """
  @spec build_command(atom(), keyword()) :: map()
  def build_command(name, opts) do
    validate_keys!(opts, @command_keys, "command #{inspect(name)}")

    principals = fetch!(opts, :principals, "command #{inspect(name)}")

    unless is_list(principals) and principals != [] and
             Enum.all?(principals, &(&1 in @principal_types)) do
      raise ArgumentError,
            "command #{inspect(name)}: `principals:` must be a non-empty list drawn from " <>
              "#{inspect(@principal_types)}, got #{inspect(principals)}. The set is closed " <>
              "because an open one is not a convention."
    end

    %{
      name: name,
      label: fetch!(opts, :label, "command #{inspect(name)}"),
      process: fetch!(opts, :process, "command #{inspect(name)}"),
      principals: principals,
      payload: Keyword.get(opts, :payload, %{}),
      # Where this command came from, in the same sense `rule` means it: a pointer
      # into the workshop material a person can follow. Optional, and an empty one
      # says something true — that nobody has yet found this command in what the
      # client actually said. Left in a comment it would be unreadable by anything;
      # here it is part of the declaration and therefore part of its digest, so
      # correcting a citation is a change to the agreement and is recorded as one.
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
      [] ->
        :ok

      extra ->
        raise ArgumentError,
              "#{where}: unknown keys #{inspect(extra)}, allowed #{inspect(allowed)}"
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
    events = attr(env, :eh_os_contract_events)
    processes = attr(env, :eh_os_contract_processes)
    traces = attr(env, :eh_os_contract_traces)
    externals = attr(env, :eh_os_contract_externals)
    rules = attr(env, :eh_os_contract_rules)
    examples = attr(env, :eh_os_contract_examples)
    commands = attr(env, :eh_os_contract_commands)

    validate!(env, events, processes, traces, externals, rules, examples, commands)

    # Through `EhOsContract.Digest` rather than `:erlang.term_to_binary/1`: this value is
    # compared against versions written into the log weeks ago, so it must not move
    # for any reason other than the agreement moving. See that module for what is
    # insignificant here and what is not.
    version =
      EhOsContract.Digest.hash_groups(
        events: events,
        processes: processes,
        traces: traces,
        externals: externals,
        rules: rules,
        examples: examples,
        commands: commands
      )

    digests = declaration_digests(events, processes, traces, externals, rules, commands, examples)

    quote do
      @doc false
      def __eh_os_contract__, do: true

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

      @doc "Every declared command, in declaration order."
      @spec commands() :: [map()]
      def commands, do: unquote(Macro.escape(commands))

      @doc "One command by name, or `nil`."
      @spec command(atom()) :: map() | nil
      def command(name), do: Enum.find(commands(), &(&1.name == name))

      @doc "The commands that enter one process."
      @spec commands_of(atom()) :: [map()]
      def commands_of(process_name), do: Enum.filter(commands(), &(&1.process == process_name))

      @doc """
      A hash of every declaration, computed at compile time. This is the
      `contract_version` stamped on every event — it cannot be forgotten or
      maintained by hand.
      """
      @spec version() :: String.t()
      def version, do: unquote(version)

      @doc """
      One digest per declaration, computed at compile time beside `version/0`.

      `version/0` answers "did anything move". This answers "which one", which is
      the question `EhOsContract.Deployment.diff/2` could not ask: it compares the recorded
      event names and handler edges, so a changed `within`, `retain`, `identity`,
      `instance` or payload type moved the contract version and left no finding.

      Keys are `"<kind>:<name>"` — strings rather than atoms because the map is
      stored as jsonb and comes back as strings either way, and an atom-in,
      string-out asymmetry is a bug with a date on it. The name is part of the
      digested declaration, so a rename reads as remove-plus-add rather than as a
      change, which is correct: a renamed declaration is a different declaration.

      Examples get one collective entry, `"example:*"`. Two reasons, and the first
      is enough on its own: an example is keyed by a prose description whose
      uniqueness nothing checks, so per-example keys would silently collapse two
      examples sharing a description — exactly the class of quiet loss this map
      exists to prevent. The second is that no example can reinterpret a run;
      `EhOsContract.Trace`, `EhOsContract.Graph` and `EhOsContract.Conformance` never read one.
      """
      @spec declaration_digests() :: %{String.t() => String.t()}
      def declaration_digests, do: unquote(Macro.escape(digests))
    end
  end

  # Named declarations carry `name`; examples carry `description` and are grouped
  # instead. `EhOsContract.Digest.hash/1` over the whole declaration map, so every key of it
  # is covered without this function having to know which keys exist.
  @spec declaration_digests([map()], [map()], [map()], [map()], [map()], [map()], [map()]) ::
          %{String.t() => String.t()}
  defp declaration_digests(events, processes, traces, externals, rules, commands, examples) do
    named =
      for {kind, declarations} <- [
            event: events,
            process: processes,
            trace: traces,
            external: externals,
            rule: rules,
            command: commands
          ],
          declaration <- declarations,
          into: %{} do
        {"#{kind}:#{declaration.name}", EhOsContract.Digest.hash(declaration)}
      end

    Map.put(named, "example:*", EhOsContract.Digest.hash_groups(example: examples))
  end

  @spec attr(Macro.Env.t(), atom()) :: [map()]
  defp attr(env, name), do: env.module |> Module.get_attribute(name) |> Enum.reverse()

  @spec validate!(
          Macro.Env.t(),
          [map()],
          [map()],
          [map()],
          [map()],
          [map()],
          [map()],
          [map()]
        ) :: :ok
  defp validate!(env, events, processes, traces, externals, rules, examples, commands) do
    names = Enum.map(events, & &1.name)

    dupes = names -- Enum.uniq(names)
    dupes == [] || bail!(env, "events declared twice: #{inspect(Enum.uniq(dupes))}")

    validate_commands!(env, commands, processes, examples)

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
    for t <- traces,
        key <- EhOsContract.Contract.schema().trace.required,
        is_nil(Map.get(t, key)) do
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
    # units lives in `EhOsContract.Duration` so the gate cannot drift from the arithmetic.
    for t <- traces, not is_nil(t.within) do
      {n, unit} = t.within

      unit in EhOsContract.Duration.units() ||
        bail!(env, "trace #{inspect(t.name)}: `within` — #{EhOsContract.Duration.message(unit)}")

      # Zero is a legitimate window: the deadline coincides with the moment `from`
      # occurred, which reads as "must happen in the same instant" — a real, if rare,
      # promise (`test/trace_edges_test.exs`, describe "a window of length zero").
      # Negative has no such reading: the deadline lands *before* the window opened,
      # so every run is violated the instant it starts, and the report says the
      # process is comprehensively broken rather than that the contract is.
      (is_integer(n) and n >= 0) ||
        bail!(
          env,
          "trace #{inspect(t.name)}: `within` count must be a non-negative integer, got #{inspect(n)}"
        )
    end

    for t <- traces,
        ev <- Enum.reject([t.from, t.eventually, t.or_else], &is_nil/1),
        ev not in names do
      bail!(
        env,
        "trace #{inspect(t.name)} names event #{inspect(ev)}, which the contract does not declare"
      )
    end

    validate_instances!(env, events, processes, traces)
    # Commands carry a payload too, and the set is closed for them for exactly the
    # reason it is closed for events. Passed as `{what, payload}` pairs so the
    # message can name a command as a command, rather than as an event that is not
    # one.
    validate_payload_types!(
      env,
      Enum.map(events, &{"event #{inspect(&1.name)}", &1.payload}) ++
        Enum.map(commands, &{"command #{inspect(&1.name)}", &1.payload})
    )

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
  # A payload field must declare one of the types in `payload_types/0`.
  #
  # The gate exists so the vocabulary is a closed set rather than a habit. Before it,
  # any atom compiled — which is why `:period` could be introduced, describe an
  # accounting month, and look exactly like a general type. The universality gate
  # could not catch that: it asks whether describing a second domain forced a **new**
  # word, never whether one of the existing words is surplus.
  #
  # It also caught two nonexistent types that had been sitting in a documented DSL
  # example: `:uuid` and `:decimal`, neither of which any contract ever used.
  @spec validate_payload_types!(Macro.Env.t(), [{String.t(), map()}]) :: :ok
  defp validate_payload_types!(env, declarations) do
    for {what, payload} <- declarations, {field, type} <- payload, not payload_type?(type) do
      bail!(
        env,
        "#{what} declares `#{field}: #{inspect(type)}`, which is not a payload " <>
          "type. Legal types are #{inspect(@payload_types)} and the set is closed on purpose: " <>
          "each one describes the shape of a value, so a type that knows what a business calls " <>
          "something is a library that knows one client's domain. If #{inspect(type)} names a " <>
          "thing rather than a shape, it is `:id` — what the thing *is* belongs to the client's " <>
          "application, not here. `{:enum, [...]}` is the one exception: a non-empty list of " <>
          "atoms or strings naming the fixed set itself, not a new type."
      )
    end

    for {what, payload} <- declarations,
        {field, {:enum, values}} <- payload,
        not legal_enum_set?(values) do
      bail!(
        env,
        "#{what} declares `#{field}: {:enum, #{inspect(values)}}`, and the set " <>
          "must be a non-empty list of atoms or strings with no repeats — an enum with nothing " <>
          "legal in it, or the same member twice, is not a set."
      )
    end

    :ok
  end

  # `:enum` bare, as before, or `{:enum, [...]}` declaring which names are legal —
  # the one payload type whose shape is a tuple rather than an atom, because "one of
  # a fixed set" needs somewhere to put the set.
  #
  # Deliberately checks only the **shape** here (a 2-tuple naming `:enum` and a
  # list), not whether the list is a legal set — `validate_payload_types!/2`'s
  # second pass owns that, with a message specific to what is wrong with the set.
  # If this function rejected an illegal set too, that pass could never run: this
  # one always runs first and would already have raised, on the same declaration,
  # with the wrong message.
  @spec payload_type?(term()) :: boolean()
  defp payload_type?(type) when type in @payload_types, do: true
  defp payload_type?({:enum, values}) when is_list(values), do: true
  defp payload_type?(_), do: false

  @spec legal_enum_set?(term()) :: boolean()
  defp legal_enum_set?(values) when is_list(values) and values != [] do
    every_member_a_name = Enum.all?(values, &(is_atom(&1) or is_binary(&1)))
    # Compared as strings, not as terms: `:open` and `"open"` name the same value
    # once JSON has been through the round trip, so declaring both is the same
    # mistake as declaring `:open` twice — just harder to see at a glance.
    as_strings = Enum.map(values, &to_string/1)

    every_member_a_name and as_strings == Enum.uniq(as_strings)
  end

  defp legal_enum_set?(_), do: false

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

  # Four gates, each mirroring one that already exists for another declaration, so a
  # seventh kind does not arrive with a weaker contract than the six around it.
  @spec validate_commands!(Macro.Env.t(), [map()], [map()], [map()]) :: :ok
  defp validate_commands!(env, commands, processes, examples) do
    names = Enum.map(commands, & &1.name)
    dupes = names -- Enum.uniq(names)
    dupes == [] || bail!(env, "commands declared twice: #{inspect(Enum.uniq(dupes))}")

    # Same shape as `event`'s `process:` gate: a declaration pointing at a process
    # this contract does not declare cannot be read by anything.
    process_names = Enum.map(processes, & &1.name)

    for command <- commands, command.process not in process_names do
      bail!(
        env,
        "command #{inspect(command.name)}: `process:` names #{inspect(command.process)}, which " <>
          "this contract does not declare. Declared: #{inspect(process_names)}."
      )
    end

    # The third pointer gate, beside `example.rule` and `event.depends_on`. Without
    # it a contract can declare one command and write examples for another for ever,
    # which is what would make the declaration decorative.
    for example <- examples do
      {command_name, params} = example.command

      command =
        Enum.find(commands, &(&1.name == command_name)) ||
          bail!(
            env,
            "example #{inspect(example.description)}: `command:` names " <>
              "#{inspect(command_name)}, which this contract does not declare as a `command`. " <>
              "Declared: #{inspect(names)}."
          )

      declared = command.payload |> Map.keys() |> Enum.sort()
      supplied = params |> Map.keys() |> Enum.sort()

      # Equality, not a subset: this DSL has no optionality anywhere — an event's
      # payload field must be present on every emission, and optionality is expressed
      # by declaring another event. A command whose example supplies a different set
      # of keys than the declaration names is one of the two being wrong.
      declared == supplied ||
        bail!(
          env,
          "example #{inspect(example.description)}: command #{inspect(command_name)} declares " <>
            "payload keys #{inspect(declared)} and this example supplies #{inspect(supplied)}. " <>
            "They must match — this DSL has no optional fields."
        )
    end

    :ok
  end

  @spec bail!(Macro.Env.t(), String.t()) :: no_return()
  defp bail!(env, message) do
    raise CompileError, file: env.file, line: env.line, description: message
  end
end
