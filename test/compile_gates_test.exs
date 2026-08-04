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

    test "asynchroniczny bez klucza idempotencji nie kompiluje się" do
      refute_compiles(
        """
        defmodule Reject.AsyncWithoutIdempotency do
          use PNS.Handler,
            contract: Taxvision.Contracts.AccountingMonth,
            event: :registry_discrepancy_detected,
            async: true
        end
        """,
        "musi zadeklarować `idempotency_key:`"
      )
    end

    test "klucz idempotencji wskazujący pole spoza payloadu nie kompiluje się" do
      refute_compiles(
        """
        defmodule Reject.BadIdempotencyKey do
          use PNS.Handler,
            contract: Taxvision.Contracts.AccountingMonth,
            event: :registry_discrepancy_detected,
            async: true,
            idempotency_key: [:nie_ma_takiego_pola]
        end
        """,
        "nie jest polem payloadu"
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
