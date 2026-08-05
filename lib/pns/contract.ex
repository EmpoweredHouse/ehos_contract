defmodule PNS.Contract do
  @moduledoc """
  Kontrakt jako moduł Elixira (ADR §2, notatki §1).

  Deklaracje akumulują się w atrybutach modułu, a `@before_compile` generuje
  funkcje zapytań wołane w dwóch różnych momentach: w czasie kompilacji przez
  makro handlera i w runtime przez zapytania conformance.

  Brama z ADR §18 jest tutaj: **reguła bez przykładu nie kompiluje się.**
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

  @doc """
  The DSL surface as data: keys per declaration, which are required, and the
  fallback for each omitted optional key.

  Exists so the reference in `docs/contract.md` can be generated rather than
  written by hand. A hand-written key table is a second source of truth, and
  every one of those in this project has eventually disagreed with the code.
  """
  @spec schema() :: map()
  def schema, do: @schema

  @doc """
  Cały słownik DSL, maszynowo — wyprowadzony z `schema/0`.

  Istnieje po to, żeby **brama uniwersalności dała się przypiąć testem**.
  Kryterium etapu 1.2 brzmi „zero nowych słów, żeby opisać inną domenę", a
  kryterium, którego nikt nie sprawdza, jest zdaniem w prozie. Test pinuje tę
  mapę; dopisanie do DSL słowa specyficznego dla domeny wywala go tego samego
  dnia, a nie przy przeglądzie za kwartał.

  Stąd też bierze się zapis, dlaczego **nie ma `population`** — jedyne słowo,
  które ten test oblało, i jedyne, które ma tendencję do powrotu.
  """
  @spec vocabulary() :: %{atom() => [atom()]}
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
    validate_keys!(opts, @event_keys, "event #{inspect(name)}")

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
      identity: opts |> Keyword.get(:identity) |> then(&(&1 && List.wrap(&1))),
      # **Gdzie to zdarzenie siedzi w procesie — na zdarzeniu, nie na procesie.**
      #
      # Pierwsza wersja miała odwrotnie: proces wymieniał swoje zdarzenia w
      # `stages:`, więc każda nazwa zdarzenia była w kontrakcie napisana dwa
      # razy, a dodanie zdarzenia wymagało dwóch edycji w miejscach oddalonych
      # o sto linii. Reguła jest ta sama, co przy `identity` i `instance`:
      # deklaracja idzie tam, gdzie jest jedna. Faza jest jedna na zdarzenie.
      #
      # Efekt uboczny jest lepszy niż sama czytelność: „zdarzenie należy do co
      # najwyżej jednego procesu" przestaje być bramą kompilacyjną, a staje się
      # rzeczą niewyrażalną. To był warunek stopu z ADR §15.
      process: Keyword.get(opts, :process),
      stage: Keyword.get(opts, :stage),
      # `terminal: true` — na tym zdarzeniu proces się kończy. Też własność
      # zdarzenia, a nie listy trzymanej gdzie indziej.
      terminal: Keyword.get(opts, :terminal, false)
    }
  end

  @doc false
  def build_process(name, opts) do
    validate_keys!(opts, @process_keys, "process #{inspect(name)}")

    where = "process #{inspect(name)}"

    %{
      name: name,
      label: fetch!(opts, :label, where),
      # **Sekwencyjne są bramki, nie zdarzenia** — i to jest jedyna rzecz, którą
      # `stages:` deklaruje: kolejność **między** fazami. O kolejności wewnątrz
      # fazy kontrakt nie twierdzi nic.
      #
      # Warsztat mówi wprost: "fazy nie są w pełni sekwencyjne … sekwencyjne są
      # bramki" — KSeF ciągnie ciągle, meczowanie doszywa na bieżąco. Pierwsza
      # wersja miała płaską, uporządkowaną listę zdarzeń i na tej kolejności
      # stało wykrywanie krawędzi wstecznych, czyli check egzekwował nasz pomysł
      # podany jako model klienta.
      #
      # Które zdarzenie jest w której fazie, mówi samo zdarzenie. Tutaj zostaje
      # wyłącznie porządek faz, bo to jest jedyna rzecz, której zdarzenie o
      # sobie powiedzieć nie może.
      #
      # Brak `stages:` znaczy dokładnie tyle: jedna faza, zero twierdzeń o
      # kolejności. Wtedy zdarzenia tego procesu nie podają `stage:`.
      stages: Keyword.get(opts, :stages, []),
      # `instance` nazywa pola payloadu, które mówią, **do którego przebiegu**
      # należy zdarzenie. Jest wymagane, bo obie rzeczy, które czynią z tego
      # produkt, liczą się w obrębie przebiegu: assercja `trace` i nakładka
      # declared vs observed. Proces bez tożsamości przebiegu jest procesem, o
      # którym PNS umie powiedzieć tylko „jakieś zdarzenie tego typu zaszło" —
      # czyli dokładnie ten stan, który etap 1.1 naprawia.
      #
      # Siedzi na procesie, nie na zdarzeniu, i to jest inne pytanie niż
      # `identity`: tożsamość faktu należy do faktu, tożsamość przebiegu do
      # procesu. Powtórzona na każdym zdarzeniu rozjeżdżałaby się między nimi.
      instance: opts |> fetch!(:instance, where) |> List.wrap(),
      # cadence: co jak często instancja jest należna — z tego liczy się okno
      # "never observed". Bez tego miesięczne zamknięcie czyta się jako
      # martwa ścieżka szósty dzień po ostatnim przebiegu (notatki §9).
      cadence: Keyword.get(opts, :cadence),
      deadline: Keyword.get(opts, :deadline),
      # Deklaracje, których **nie potwierdził process owner**. Zostają w
      # kontrakcie, bo bez nich mechanizm nie ma czego pilnować, ale nie mogą
      # liczyć się do raportu dowodowego: fałszywa metryka jest gorsza niż jej
      # brak, bo to metryka, którą produkt sprzedaje.
      unverified: Keyword.get(opts, :unverified, [])
    }
  end

  @doc false
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
  def build_rule(name, opts) do
    validate_keys!(opts, @rule_keys, "rule #{inspect(name)}")
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
    validate_keys!(opts, @example_keys, "example #{inspect(description)}")

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

      @doc """
      Proces, do którego należy zdarzenie — czyli to, z czego bierze się jego
      tożsamość przebiegu. Zdarzenie wskazuje **jeden** proces, więc odpowiedź
      jest jednoznaczna z konstrukcji, a nie dzięki sprawdzeniu.
      """
      def process_of(event_name) do
        case Enum.find(events(), &(&1.name == event_name)) do
          %{process: nil} -> nil
          %{process: name} -> process(name)
          nil -> nil
        end
      end

      @doc "Zdarzenia należące do procesu. Odwrotność `process_of/1`."
      def events_of(process_name), do: Enum.filter(events(), &(&1.process == process_name))

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

    # Brama dopasowana do tego, co ocena assercji **umie policzyć**. Bez niej
    # `within: {1, :month}` przechodziło kompilację i wywalało się w runtime,
    # czyli u klienta — a jedno źródło prawdy o jednostkach siedzi w
    # `PNS.Duration`, żeby brama nie mogła się rozjechać z arytmetyką.
    for t <- traces, not is_nil(t.within) do
      {_n, unit} = t.within

      unit in PNS.Duration.units() ||
        bail!(env, "trace #{inspect(t.name)}: `within` — #{PNS.Duration.message(unit)}")
    end

    for t <- traces, ev <- Enum.reject([t.from, t.eventually, t.or_else], &is_nil/1), ev not in names do
      bail!(env, "trace #{inspect(t.name)} wymienia zdarzenie #{inspect(ev)}, którego nie ma w kontrakcie")
    end

    validate_instances!(env, events, processes, traces)

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

  # Przynależność zdarzenia do procesu i do fazy. Deklaruje ją samo zdarzenie,
  # więc tutaj sprawdzamy tylko, czy wskazuje na coś, co istnieje, i czy nie
  # zostawia procesu bez odpowiedzi na pytanie „w której to fazie".
  defp validate_membership!(env, events, processes) do
    by_process = Map.new(processes, &{&1.name, &1})

    for e <- events do
      cond do
        is_nil(e.process) and not is_nil(e.stage) ->
          bail!(
            env,
            "zdarzenie #{inspect(e.name)} podaje `stage: #{inspect(e.stage)}` bez `process:`. " <>
              "Faza jest fazą jakiegoś procesu."
          )

        is_nil(e.process) and e.terminal ->
          bail!(
            env,
            "zdarzenie #{inspect(e.name)} jest `terminal: true` bez `process:`. " <>
              "Terminalne znaczy „tu kończy się proces”, więc trzeba powiedzieć który."
          )

        is_nil(e.process) ->
          :ok

        not Map.has_key?(by_process, e.process) ->
          bail!(
            env,
            "zdarzenie #{inspect(e.name)} deklaruje `process: #{inspect(e.process)}`, " <>
              "którego nie ma w kontrakcie"
          )

        true ->
          validate_stage!(env, e, Map.fetch!(by_process, e.process))
      end
    end

    :ok
  end

  defp validate_stage!(env, event, process) do
    cond do
      process.stages == [] and not is_nil(event.stage) ->
        bail!(
          env,
          "zdarzenie #{inspect(event.name)} podaje `stage: #{inspect(event.stage)}`, ale proces " <>
            "#{inspect(process.name)} nie deklaruje żadnych faz. Proces bez `stages:` to jedna " <>
            "faza i zero twierdzeń o kolejności."
        )

      process.stages != [] and is_nil(event.stage) ->
        bail!(
          env,
          "zdarzenie #{inspect(event.name)} należy do procesu #{inspect(process.name)}, który " <>
            "deklaruje fazy #{inspect(process.stages)}, ale nie mówi, w której z nich jest. " <>
            "Na kolejności faz stoi wykrywanie krawędzi wstecznych, więc zdarzenie bez fazy " <>
            "byłoby dziurą w tym checku, a nie brakiem ozdobnika."
        )

      not is_nil(event.stage) and event.stage not in process.stages ->
        bail!(
          env,
          "zdarzenie #{inspect(event.name)} podaje `stage: #{inspect(event.stage)}`, której proces " <>
            "#{inspect(process.name)} nie deklaruje. Zadeklarowane fazy: #{inspect(process.stages)}"
        )

      true ->
        :ok
    end
  end

  # Dwie bramy wokół tożsamości przebiegu. Obie z jednej własności:
  # `instance_id` liczony przy emisji ma być jednoznaczny i odtwarzalny z
  # samego logu, a w logu jest na niego jedna kolumna.
  #
  # Trzeciej bramy tu już nie ma i to jest wynik przeniesienia `process:` na
  # zdarzenie: „zdarzenie należy do co najwyżej jednego procesu" było
  # sprawdzeniem, a stało się rzeczą **niewyrażalną**. To warunek stopu z
  # ADR §15 („stop if processes nest or one event belongs to two") załatwiony
  # kształtem deklaracji, a nie checkiem.
  defp validate_instances!(env, events, processes, traces) do
    by_process = Map.new(processes, &{&1.name, &1})
    process_of = fn ev -> Enum.find_value(events, &(&1.name == ev && &1.process)) end

    # 1. Każde zdarzenie procesu niesie pola instancji — i nie gubi ich po drodze.
    for e <- events, p = e.process && Map.get(by_process, e.process), field <- p.instance do
      Map.has_key?(e.payload, field) ||
        bail!(
          env,
          "proces #{inspect(p.name)} deklaruje `instance: #{inspect(p.instance)}`, ale zdarzenie " <>
            "#{inspect(e.name)} nie ma w payloadzie pola #{inspect(field)}. Bez niego nie da się " <>
            "powiedzieć, do którego przebiegu to zdarzenie należy — a wtedy assercja `trace` " <>
            "dopasuje je do dowolnego innego przebiegu."
        )

      Map.get(e.retain, field) == :drop &&
        bail!(
          env,
          "zdarzenie #{inspect(e.name)}: pole #{inspect(field)} współtworzy tożsamość przebiegu " <>
            "procesu #{inspect(p.name)} i jednocześnie ma `retain: :drop`. Tożsamość przebiegu " <>
            "jest liczona z payloadu po zastosowaniu `retain`, więc zniknęłaby razem z polem."
        )
    end

    # 2. Assercja liczy się w jednym przebiegu, więc nie może rozciągać się na
    # dwa procesy — bo każdy z nich ma inną tożsamość przebiegu.
    for t <- traces do
      trace_events = Enum.reject([t.from, t.eventually, t.or_else], &is_nil/1)
      homeless = Enum.filter(trace_events, &is_nil(process_of.(&1)))

      homeless == [] ||
        bail!(
          env,
          "trace #{inspect(t.name)} wymienia zdarzenia spoza jakiegokolwiek procesu: " <>
            "#{inspect(homeless)}. Nie ma przebiegu, w którym dałoby się tę assercję policzyć."
        )

      case trace_events |> Enum.map(process_of) |> Enum.uniq() do
        [_one] ->
          :ok

        many ->
          bail!(
            env,
            "trace #{inspect(t.name)} rozciąga się na procesy #{inspect(many)}. Assercja liczy się " <>
              "w obrębie jednego przebiegu, a każdy proces ma własną tożsamość przebiegu."
          )
      end
    end

    :ok
  end

  defp bail!(env, message) do
    raise CompileError, file: env.file, line: env.line, description: message
  end
end
