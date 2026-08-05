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

          process :p, label: "P", events: [:a]
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

          event :a, label: "A", payload: %{sprawa_id: :id}
          event :b, label: "B", payload: %{cos_innego: :id}

          process :p, label: "P", events: [:a, :b], instance: [:sprawa_id]
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

          event :a, label: "A", payload: %{sprawa_id: :id}, retain: %{sprawa_id: :drop}

          process :p, label: "P", events: [:a], instance: [:sprawa_id]
        end
        """,
        "współtworzy tożsamość przebiegu"
      )
    end

    test "zdarzenie należące do dwóch procesów nie kompiluje się (ADR §15)" do
      # Dwa procesy to dwie tożsamości przebiegu, a w logu jest na to jedna
      # kolumna. Cicha wersja tego wybrałaby jedną z nich.
      refute_compiles(
        """
        defmodule Reject.EventInTwoProcesses do
          use PNS.Contract

          event :a, label: "A", payload: %{sprawa_id: :id}

          process :p1, label: "P1", events: [:a], instance: [:sprawa_id]
          process :p2, label: "P2", events: [:a], instance: [:sprawa_id]
        end
        """,
        "należy do dwóch procesów"
      )
    end

    test "trace rozciągnięty na dwa procesy nie kompiluje się" do
      # Assercja liczy się w obrębie jednego przebiegu, a każdy proces ma własną
      # tożsamość przebiegu.
      refute_compiles(
        """
        defmodule Reject.TraceAcrossProcesses do
          use PNS.Contract

          event :a, label: "A", payload: %{sprawa_id: :id}
          event :b, label: "B", payload: %{przesylka_id: :id}

          process :p1, label: "P1", events: [:a], instance: [:sprawa_id]
          process :p2, label: "P2", events: [:b], instance: [:przesylka_id]

          trace :przez_dwa_procesy do
            from :a
            eventually :b, within: {1, :day}
          end
        end
        """,
        "rozciąga się na procesy"
      )
    end

    test "proces z `stages:` i `events:` naraz nie przechodzi" do
      assert_raise ArgumentError, ~r/`stages:` albo `events:`, nie oba/, fn ->
        Code.compile_string("""
        defmodule Reject.ProcessWithBoth do
          use PNS.Contract

          event :a, label: "A", payload: %{id: :id}

          process :p, label: "P", events: [:a], stages: [x: [:a]]
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
