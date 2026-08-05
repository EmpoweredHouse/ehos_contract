defmodule PNS.CompileGatesTest do
  @moduledoc """
  Najbardziej przekonujące artefakty z całej listy: rzeczy, które **nie
  kompilują się**.

  Test przez `Code.compile_string/1` z asercją na wyjątek. Jeśli któryś z tych
  testów kiedyś przestanie przechodzić, znaczy, że wymuszenie zamieniło się w
  konwencję — czyli w nic.
  """

  use ExUnit.Case, async: true

  defp refute_compiles(source, expected_fragment) do
    error =
      assert_raise CompileError, fn ->
        Code.compile_string(source)
      end

    message = Exception.message(error) <> collected_diagnostics()

    assert message =~ expected_fragment or
             error.description =~ expected_fragment,
           """
           kod się nie skompilował, ale nie z tego powodu.
           oczekiwany fragment: #{inspect(expected_fragment)}
           dostałem: #{message}
           """
  end

  defp collected_diagnostics, do: ""

  describe "handler" do
    test "na nieistniejące zdarzenie nie kompiluje się" do
      refute_compiles(
        """
        defmodule Reject.HandlerOnUnknownEvent do
          use PNS.Handler,
            contract: Taxvision.Contracts.AccountingMonth,
            event: :zdarzenie_ktorego_nie_ma
        end
        """,
        "którego nie ma w kontrakcie"
      )
    end

    test "publikujący zdarzenie spoza kontraktu nie kompiluje się" do
      refute_compiles(
        """
        defmodule Reject.HandlerPublishingUnknown do
          use PNS.Handler,
            contract: Taxvision.Contracts.AccountingMonth,
            event: :registry_data_consistent,
            publishes: [:wymyslone_zdarzenie]
        end
        """,
        "czego nie ma w kontrakcie"
      )
    end

    test "asynchroniczny na zdarzeniu bez `identity` w kontrakcie nie kompiluje się" do
      # Pytanie "co czyni dwa wystąpienia tym samym faktem" należy do process
      # ownera, więc komunikat odsyła do kontraktu, nie do handlera.
      refute_compiles(
        """
        defmodule Reject.AsyncOnEventWithoutIdentity do
          use PNS.Handler,
            contract: Taxvision.Contracts.AccountingMonth,
            event: :registry_data_consistent,
            async: true
        end
        """,
        "wymaga, żeby zdarzenie"
      )
    end
  end

  describe "kontrakt" do
    test "reguła bez przykładu nie kompiluje się (ADR §18)" do
      refute_compiles(
        """
        defmodule Reject.RuleWithoutExample do
          use PNS.Contract

          event :cos_sie_stalo, label: "Coś", payload: %{id: :string}

          rule :regula_bez_przykladu,
            label: "Reguła, której nikt nie przypiął przykładem",
            function: {String, :length, 1}
        end
        """,
        "reguła bez przykładu nie kompiluje się"
      )
    end

    test "capture zamiast MFA nie przechodzi" do
      assert_raise ArgumentError, ~r/musi być krotką MFA/, fn ->
        Code.compile_string("""
        defmodule Reject.RuleWithCapture do
          use PNS.Contract

          event :cos_sie_stalo, label: "Coś", payload: %{id: :string}

          rule :regula,
            label: "Reguła z capture",
            function: &String.length/1

          example "przykład", rule: :regula, command: {:x, %{}}, then: []
        end
        """)
      end
    end

    test "trace na nieistniejące zdarzenie nie kompiluje się" do
      refute_compiles(
        """
        defmodule Reject.TraceOnUnknownEvent do
          use PNS.Contract

          event :start, label: "Start", payload: %{id: :string}

          trace :gdzies_dojdzie do
            from :start
            eventually :nie_ma_mnie, within: {1, :day}
          end
        end
        """,
        "którego nie ma w kontrakcie"
      )
    end

    test "identity na pole spoza payloadu nie kompiluje się" do
      refute_compiles(
        """
        defmodule Reject.IdentityUnknownField do
          use PNS.Contract

          event :cos_sie_stalo,
            label: "Coś",
            payload: %{id: :id},
            identity: [:nie_ma_mnie]
        end
        """,
        "`identity` wskazuje pole"
      )
    end

    test "identity na polu usuwanym przez retain nie kompiluje się" do
      # Klucz idempotencji zniknąłby razem z polem.
      refute_compiles(
        """
        defmodule Reject.IdentityOnDroppedField do
          use PNS.Contract

          event :cos_sie_stalo,
            label: "Coś",
            payload: %{id: :id, tekst: :string},
            retain: %{tekst: :drop},
            identity: [:tekst]
        end
        """,
        "`retain: :drop`"
      )
    end

    test "proces bez `instance:` nie kompiluje się" do
      assert_raise ArgumentError, ~r/brakuje wymaganego `instance:`/, fn ->
        Code.compile_string("""
        defmodule Reject.ProcessWithoutInstance do
          use PNS.Contract

          event :a, label: "A", payload: %{id: :id}

          process :p, label: "P"
        end
        """)
      end
    end

    test "zdarzenie procesu bez pola instancji w payloadzie nie kompiluje się" do
      # Bez tego pola nie da się powiedzieć, do którego przebiegu zdarzenie
      # należy — a wtedy assercja dopasuje je do dowolnego innego przebiegu.
      refute_compiles(
        """
        defmodule Reject.EventWithoutInstanceField do
          use PNS.Contract

          event :a, label: "A", payload: %{sprawa_id: :id}, process: :p
          event :b, label: "B", payload: %{cos_innego: :id}, process: :p

          process :p, label: "P", instance: [:sprawa_id]
        end
        """,
        "nie ma w payloadzie pola :sprawa_id"
      )
    end

    test "pole instancji usuwane przez retain nie kompiluje się" do
      # Tożsamość przebiegu jest liczona z payloadu po `retain`, więc zniknęłaby
      # razem z polem.
      refute_compiles(
        """
        defmodule Reject.InstanceOnDroppedField do
          use PNS.Contract

          event :a, label: "A", payload: %{sprawa_id: :id}, retain: %{sprawa_id: :drop}, process: :p

          process :p, label: "P", instance: [:sprawa_id]
        end
        """,
        "współtworzy tożsamość przebiegu"
      )
    end

    # Brama „zdarzenie w dwóch procesach" **zniknęła i to jest wynik, nie regres**.
    # Odkąd `process:` jest pojedynczym kluczem na zdarzeniu, dwa procesy na
    # jednym zdarzeniu przestały być czymś, co da się napisać. Warunek stopu z
    # ADR §15 jest teraz załatwiony kształtem deklaracji, a nie sprawdzeniem —
    # a rzeczy niewyrażalnej nie da się przypiąć testem.

    test "zdarzenie wskazujące nieistniejący proces nie kompiluje się" do
      refute_compiles(
        """
        defmodule Reject.EventWithUnknownProcess do
          use PNS.Contract

          event :a, label: "A", payload: %{sprawa_id: :id}, process: :nie_ma_mnie

          process :p, label: "P", instance: [:sprawa_id]
        end
        """,
        "którego nie ma w kontrakcie"
      )
    end

    test "zdarzenie w procesie z fazami, ale bez `stage:`, nie kompiluje się" do
      # Na kolejności faz stoi wykrywanie krawędzi wstecznych, więc zdarzenie
      # bez fazy byłoby dziurą w checku, a nie brakiem ozdobnika.
      refute_compiles(
        """
        defmodule Reject.EventWithoutStage do
          use PNS.Contract

          event :a, label: "A", payload: %{sprawa_id: :id}, process: :p, stage: :pierwsza
          event :b, label: "B", payload: %{sprawa_id: :id}, process: :p

          process :p, label: "P", stages: [:pierwsza, :druga], instance: [:sprawa_id]
        end
        """,
        "nie mówi, w której z nich jest"
      )
    end

    test "zdarzenie w fazie, której proces nie deklaruje, nie kompiluje się" do
      refute_compiles(
        """
        defmodule Reject.EventInUnknownStage do
          use PNS.Contract

          event :a, label: "A", payload: %{sprawa_id: :id}, process: :p, stage: :wymyslona

          process :p, label: "P", stages: [:pierwsza, :druga], instance: [:sprawa_id]
        end
        """,
        "której proces"
      )
    end

    test "`stage:` bez `process:` nie kompiluje się" do
      refute_compiles(
        """
        defmodule Reject.StageWithoutProcess do
          use PNS.Contract

          event :a, label: "A", payload: %{id: :id}, stage: :gdzies
        end
        """,
        "bez `process:`"
      )
    end

    test "trace z jednostką kalendarzową w `within` nie kompiluje się" do
      # Wcześniej przechodziło kompilację i wywalało się w runtime, przy ocenie
      # assercji — czyli u klienta. Brama i arytmetyka mają jedno źródło prawdy
      # o jednostkach, żeby nie mogły się rozjechać.
      refute_compiles(
        """
        defmodule Reject.TraceWithCalendarUnit do
          use PNS.Contract

          event :a, label: "A", payload: %{sprawa_id: :id}, process: :p
          event :b, label: "B", payload: %{sprawa_id: :id}, process: :p

          process :p, label: "P", instance: [:sprawa_id]

          trace :w_miesiac do
            from :a
            eventually :b, within: {1, :month}
          end
        end
        """,
        "nieobsługiwana jednostka czasu :month"
      )
    end

    test "trace rozciągnięty na dwa procesy nie kompiluje się" do
      # Assercja liczy się w obrębie jednego przebiegu, a każdy proces ma własną
      # tożsamość przebiegu.
      refute_compiles(
        """
        defmodule Reject.TraceAcrossProcesses do
          use PNS.Contract

          event :a, label: "A", payload: %{sprawa_id: :id}, process: :p1
          event :b, label: "B", payload: %{przesylka_id: :id}, process: :p2

          process :p1, label: "P1", instance: [:sprawa_id]
          process :p2, label: "P2", instance: [:przesylka_id]

          trace :przez_dwa_procesy do
            from :a
            eventually :b, within: {1, :day}
          end
        end
        """,
        "rozciąga się na procesy"
      )
    end

    test "proces nie przyjmuje już `events:` — zdarzenia deklarują przynależność same" do
      assert_raise ArgumentError, ~r/nieznane klucze \[:events\]/, fn ->
        Code.compile_string("""
        defmodule Reject.ProcessListingEvents do
          use PNS.Contract

          event :a, label: "A", payload: %{id: :id}

          process :p, label: "P", events: [:a], instance: [:id]
        end
        """)
      end
    end

    test "retain na pole spoza payloadu nie kompiluje się" do
      refute_compiles(
        """
        defmodule Reject.RetainUnknownField do
          use PNS.Contract

          event :cos_sie_stalo,
            label: "Coś",
            payload: %{id: :string},
            retain: %{nieistniejace: :hash}
        end
        """,
        "którego nie ma w `payload`"
      )
    end
  end
end
