defmodule PNS.Contract do
  @moduledoc """
  Kontrakt jako moduł Elixira (ADR §2, notatki §1).

  Deklaracje akumulują się w atrybutach modułu, a `@before_compile` generuje
  funkcje zapytań wołane w dwóch różnych momentach: w czasie kompilacji przez
  makro handlera i w runtime przez zapytania conformance.

  Brama z ADR §18 jest tutaj: **reguła bez przykładu nie kompiluje się.**
  """

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

  @doc "Zdarzenie: fakt, który zaszedł. Nazwa w czasie przeszłym."
  defmacro event(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      @pns_events PNS.Contract.build_event(name, opts)
    end
  end

  @doc "Proces: jednostka nawigacji dashboardu i jednostka podziału kontraktu."
  defmacro process(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      @pns_processes PNS.Contract.build_process(name, opts)
    end
  end

  @doc "Zależność zewnętrzna, nazwana faktem biznesowym, nie vendorem (ADR §11-12)."
  defmacro external(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      @pns_externals PNS.Contract.build_external(name, opts)
    end
  end

  @doc """
  Reguła wskazuje **jedną czystą funkcję i nic więcej**, przez MFA.

  MFA, nie capture: capture zrobiłby z kontraktu zależność kompilacyjną od
  domeny, a handlery zależą od kontraktu — więc każda zmiana domeny
  rekompilowałaby wszystkie handlery.
  """
  defmacro rule(name, opts) do
    quote bind_quoted: [name: name, opts: opts] do
      @pns_rules PNS.Contract.build_rule(name, opts)
    end
  end

  @doc """
  Przykład przypina regułę przypadkiem, który da się przeczytać na głos
  process ownerowi i wykonać jako test.
  """
  defmacro example(description, opts) do
    quote bind_quoted: [description: description, opts: opts] do
      @pns_examples PNS.Contract.build_example(description, opts)
    end
  end

  @doc """
  Assercja nad zaobserwowanym przebiegiem. Blok jest rozbierany w czasie
  kompilacji, więc `from`/`eventually`/`or_else` nie istnieją w runtime.
  """
  defmacro trace(name, do: block) do
    steps = trace_steps(block)

    quote bind_quoted: [name: name, steps: Macro.escape(steps)] do
      @pns_traces Map.put(steps, :name, name)
    end
  end

  # --- budowanie deklaracji (wołane w czasie kompilacji kontraktu) ---

  @doc false
  def build_event(name, opts) do
    validate_keys!(
      opts,
      [:label, :owner, :payload, :retain, :depends_on, :identity],
      "event #{inspect(name)}"
    )

    %{
      name: name,
      label: fetch!(opts, :label, "event #{inspect(name)}"),
      owner: Keyword.get(opts, :owner),
      payload: Keyword.get(opts, :payload, %{}),
      retain: Keyword.get(opts, :retain, %{}),
      depends_on: Keyword.get(opts, :depends_on),
      # `identity` mówi, **co czyni dwa wystąpienia tego zdarzenia tym samym
      # faktem biznesowym**. Stąd bierze się klucz idempotencji.
      #
      # Siedzi na zdarzeniu, nie na handlerze, i to jest poprawka wobec
      # pierwszej wersji: "dwa rozjazdy w jednym miesiącu to jedno
      # powiadomienie czy dwa" jest pytaniem do process ownera, a nie do
      # programisty piszącego handler. ADR §9-10 mówi wprost, że idempotencja
      # jest własnością kontraktu; notatki §4 mówiły, że handlera. Rację ma ADR.
      #
      # Konsekwencja jest też praktyczna: tożsamość faktu jest jedna, a
      # handlerów tego samego zdarzenia może być wiele. Trzymana na handlerze
      # rozjeżdżałaby się między nimi.
      identity: opts |> Keyword.get(:identity) |> then(&(&1 && List.wrap(&1)))
    }
  end

  @doc false
  def build_process(name, opts) do
    validate_keys!(
      opts,
      [:label, :events, :stages, :terminal, :cadence, :deadline],
      "process #{inspect(name)}"
    )

    where = "process #{inspect(name)}"

    # **Sekwencyjne są bramki, nie zdarzenia.**
    #
    # Pierwsza wersja miała płaską, uporządkowaną listę `events:` i na tej
    # kolejności stało wykrywanie krawędzi wstecznych. Tylko że warsztat mówi
    # wprost: "fazy nie są w pełni sekwencyjne … sekwencyjne są bramki" — KSeF
    # ciągnie ciągle, meczowanie doszywa na bieżąco. Liniowa lista była naszym
    # pomysłem podanym jako model klienta, a check stał na tym pomyśle.
    #
    # `stages:` deklaruje kolejność **między** fazami i nie twierdzi nic o
    # kolejności wewnątrz fazy. `events:` zostaje jako skrót dla procesu bez
    # bramek i znaczy dokładnie tyle: jedna faza, zero twierdzeń o kolejności.
    stages =
      case {Keyword.fetch(opts, :stages), Keyword.fetch(opts, :events)} do
        {{:ok, stages}, :error} -> stages
        {:error, {:ok, events}} -> [all: events]
        {{:ok, _}, {:ok, _}} -> raise ArgumentError, "#{where}: `stages:` albo `events:`, nie oba"
        {:error, :error} -> raise ArgumentError, "#{where}: brakuje `stages:` albo `events:`"
      end

    %{
      name: name,
      label: fetch!(opts, :label, where),
      stages: stages,
      events: Enum.flat_map(stages, fn {_stage, events} -> events end),
      terminal: Keyword.get(opts, :terminal, []),
      # cadence: co jak często instancja jest należna — z tego liczy się okno
      # "never observed". Bez tego miesięczne zamknięcie czyta się jako
      # martwa ścieżka szósty dzień po ostatnim przebiegu (notatki §9).
      cadence: Keyword.get(opts, :cadence),
      deadline: Keyword.get(opts, :deadline)
    }
  end

  @doc false
  def build_external(name, opts) do
    validate_keys!(opts, [:label, :expected_latency, :unavailable_looks_like], "external #{inspect(name)}")

    %{
      name: name,
      label: fetch!(opts, :label, "external #{inspect(name)}"),
      expected_latency: Keyword.get(opts, :expected_latency),
      unavailable_looks_like: Keyword.get(opts, :unavailable_looks_like)
    }
  end

  @doc false
  def build_rule(name, opts) do
    validate_keys!(opts, [:label, :function, :source], "rule #{inspect(name)}")
    mfa = fetch!(opts, :function, "rule #{inspect(name)}")

    case mfa do
      {m, f, a} when is_atom(m) and is_atom(f) and is_integer(a) ->
        :ok

      other ->
        raise ArgumentError,
              "rule #{inspect(name)}: `function:` musi być krotką MFA {Modul, :funkcja, arnosc}, " <>
                "dostałem #{inspect(other)}. Capture (&Mod.fun/1) jest zabroniony — zrobiłby " <>
                "z kontraktu zależność kompilacyjną od domeny."
    end

    %{
      name: name,
      label: fetch!(opts, :label, "rule #{inspect(name)}"),
      function: mfa,
      source: Keyword.get(opts, :source)
    }
  end

  @doc false
  def build_example(description, opts) do
    validate_keys!(opts, [:rule, :given, :command, :then, :rejected_with], "example #{inspect(description)}")

    outcome =
      case {Keyword.fetch(opts, :then), Keyword.fetch(opts, :rejected_with)} do
        {{:ok, events}, :error} -> {:emits, events}
        {:error, {:ok, reason}} -> {:rejected, reason}
        {{:ok, _}, {:ok, _}} -> raise ArgumentError, "example #{inspect(description)}: `then:` albo `rejected_with:`, nie oba"
        {:error, :error} -> raise ArgumentError, "example #{inspect(description)}: brakuje `then:` albo `rejected_with:`"
      end

    %{
      description: description,
      rule: fetch!(opts, :rule, "example #{inspect(description)}"),
      given: Keyword.get(opts, :given, %{}),
      command: fetch!(opts, :command, "example #{inspect(description)}"),
      outcome: outcome
    }
  end

  defp fetch!(opts, key, where) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "#{where}: brakuje wymaganego `#{key}:`"
    end
  end

  defp validate_keys!(opts, allowed, where) do
    case Keyword.keys(opts) -- allowed do
      [] -> :ok
      extra -> raise ArgumentError, "#{where}: nieznane klucze #{inspect(extra)}, dozwolone #{inspect(allowed)}"
    end
  end

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
              "trace: nieznana instrukcja #{Macro.to_string(other)}. Dozwolone: from/1, eventually/1-2, or_else/1"
    end)
  end

  # --- generowanie funkcji zapytań ---

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
      def __pns_contract__, do: true

      def events, do: unquote(Macro.escape(events))
      def event_names, do: unquote(Enum.map(events, & &1.name))
      def event?(name), do: name in unquote(Enum.map(events, & &1.name))

      def event(name) do
        Enum.find(events(), &(&1.name == name)) ||
          raise ArgumentError, "#{inspect(__MODULE__)}: nie ma zdarzenia #{inspect(name)}"
      end

      def processes, do: unquote(Macro.escape(processes))
      def process(name), do: Enum.find(processes(), &(&1.name == name))
      def traces, do: unquote(Macro.escape(traces))
      def externals, do: unquote(Macro.escape(externals))
      def external(name), do: Enum.find(externals(), &(&1.name == name))
      def rules, do: unquote(Macro.escape(rules))
      def rule(name), do: Enum.find(rules(), &(&1.name == name))
      def examples, do: unquote(Macro.escape(examples))
      def examples_for(rule_name), do: Enum.filter(examples(), &(&1.rule == rule_name))

      @doc """
      Hash wszystkich deklaracji, policzony w czasie kompilacji. To jest
      `contract_version` stemplowany na każdym zdarzeniu — nie da się go
      zapomnieć ani utrzymywać ręcznie.
      """
      def version, do: unquote(version)
    end
  end

  defp attr(env, name), do: env.module |> Module.get_attribute(name) |> Enum.reverse()

  defp validate!(env, events, processes, traces, externals, rules, examples) do
    names = Enum.map(events, & &1.name)

    dupes = names -- Enum.uniq(names)
    dupes == [] || bail!(env, "zdarzenia zadeklarowane dwa razy: #{inspect(Enum.uniq(dupes))}")

    # ADR §18, brama kompilacyjna: reguła bez przykładu nie kompiluje się.
    rules_without_examples =
      rules
      |> Enum.filter(fn rule -> not Enum.any?(examples, &(&1.rule == rule.name)) end)
      |> Enum.map(& &1.name)

    rules_without_examples == [] ||
      bail!(
        env,
        "reguła bez przykładu nie kompiluje się (ADR §18): #{inspect(rules_without_examples)}. " <>
          "Reguła bez przykładu to zdanie w prozie — dopisz przynajmniej jeden `example`, " <>
          "który da się przeczytać na głos process ownerowi."
      )

    orphan_examples =
      examples
      |> Enum.filter(fn ex -> not Enum.any?(rules, &(&1.name == ex.rule)) end)
      |> Enum.map(& &1.description)

    orphan_examples == [] ||
      bail!(env, "przykłady wskazujące nieistniejącą regułę: #{inspect(orphan_examples)}")

    for p <- processes, ev <- p.events ++ p.terminal, ev not in names do
      bail!(env, "proces #{inspect(p.name)} wymienia zdarzenie #{inspect(ev)}, którego nie ma w kontrakcie")
    end

    for t <- traces, ev <- Enum.reject([t.from, t.eventually, t.or_else], &is_nil/1), ev not in names do
      bail!(env, "trace #{inspect(t.name)} wymienia zdarzenie #{inspect(ev)}, którego nie ma w kontrakcie")
    end

    external_names = Enum.map(externals, & &1.name)

    for e <- events, not is_nil(e.depends_on), e.depends_on not in external_names do
      bail!(env, "zdarzenie #{inspect(e.name)} deklaruje `depends_on: #{inspect(e.depends_on)}`, którego nie ma w `external`")
    end

    for e <- events, {field, _policy} <- e.retain, not Map.has_key?(e.payload, field) do
      bail!(env, "zdarzenie #{inspect(e.name)}: `retain` wskazuje pole #{inspect(field)}, którego nie ma w `payload`")
    end

    for e <- events, field <- e.identity || [] do
      Map.has_key?(e.payload, field) ||
        bail!(env, "zdarzenie #{inspect(e.name)}: `identity` wskazuje pole #{inspect(field)}, którego nie ma w `payload`")

      # Pole usuwane z payloadu nie może współtworzyć tożsamości faktu — klucz
      # idempotencji zniknąłby razem z nim.
      Map.get(e.retain, field) == :drop &&
        bail!(env, "zdarzenie #{inspect(e.name)}: pole #{inspect(field)} jest w `identity` i jednocześnie `retain: :drop`")
    end

    :ok
  end

  defp bail!(env, message) do
    raise CompileError, file: env.file, line: env.line, description: message
  end
end
