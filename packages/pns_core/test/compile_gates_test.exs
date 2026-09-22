defmodule PNS.CompileGatesTest do
  @moduledoc """
  The most convincing artifacts on the whole list: things that **do not compile**.

  Tested through `Code.compile_string/1` with an assertion on the exception. If one
  of these tests ever stops passing, it means the enforcement turned into a
  convention — that is, into nothing.
  """

  use ExUnit.Case, async: true

  defp refute_compiles(source, expected_fragment) do
    error =
      assert_raise CompileError, fn ->
        Code.compile_string(source)
      end

    message = Exception.message(error)

    assert message =~ expected_fragment or
             error.description =~ expected_fragment,
           """
           the code failed to compile, but not for this reason.
           expected fragment: #{inspect(expected_fragment)}
           got: #{message}
           """
  end

  describe "command" do
    test "naming a process the contract does not declare does not compile" do
      refute_compiles(
        """
        defmodule Reject.CommandWithoutProcess do
          use PNS.Contract

          event :a, label: "A", payload: %{case_id: :id}, process: :real
          command :do_it, label: "Do it", process: :imaginary, principals: [:human]
          process :real, label: "Real", instance: [:case_id]
        end
        """,
        "which this contract does not declare"
      )
    end

    test "declared twice does not compile" do
      refute_compiles(
        """
        defmodule Reject.CommandTwice do
          use PNS.Contract

          event :a, label: "A", payload: %{case_id: :id}, process: :p
          command :do_it, label: "Do it", process: :p, principals: [:human]
          command :do_it, label: "Do it again", process: :p, principals: [:human]
          process :p, label: "P", instance: [:case_id]
        end
        """,
        "commands declared twice"
      )
    end

    test "a principal outside the closed set does not compile" do
      # `ArgumentError` rather than `CompileError`, like every other `build_*`
      # refusal: this one is decidable from the declaration alone, without the rest
      # of the module, so it fires where it is written.
      assert_raise ArgumentError, ~r/must be a non-empty list drawn from/, fn ->
        Code.compile_string("""
        defmodule Reject.CommandBadPrincipal do
          use PNS.Contract

          event :a, label: "A", payload: %{case_id: :id}, process: :p
          command :do_it, label: "Do it", process: :p, principals: [:accountant]
          process :p, label: "P", instance: [:case_id]
        end
        """)
      end
    end

    test "an empty principal list does not compile either" do
      # A command nobody may issue is not a narrower permission, it is a command
      # with no way in — and almost certainly a forgotten key rather than an
      # intention.
      assert_raise ArgumentError, ~r/must be a non-empty list drawn from/, fn ->
        Code.compile_string("""
        defmodule Reject.CommandNoPrincipal do
          use PNS.Contract

          event :a, label: "A", payload: %{case_id: :id}, process: :p
          command :do_it, label: "Do it", process: :p, principals: []
          process :p, label: "P", instance: [:case_id]
        end
        """)
      end
    end

    test "a payload type outside the closed set does not compile, as for an event" do
      refute_compiles(
        """
        defmodule Reject.CommandBadPayloadType do
          use PNS.Contract

          event :a, label: "A", payload: %{case_id: :id}, process: :p
          command :do_it,
            label: "Do it",
            process: :p,
            principals: [:human],
            payload: %{case_id: :uuid}
          process :p, label: "P", instance: [:case_id]
        end
        """,
        "command :do_it declares `case_id: :uuid`"
      )
    end
  end

  describe "example pointing at a command" do
    test "an example naming a command the contract does not declare does not compile" do
      # The third pointer gate, beside `example.rule` and `event.depends_on`. Without
      # it a contract could declare one command and write examples for another for
      # ever, which is what would make the declaration decorative.
      refute_compiles(
        """
        defmodule Reject.ExampleUnknownCommand do
          use PNS.Contract

          event :a, label: "A", payload: %{case_id: :id}, process: :p
          rule :r, label: "R", function: {Kernel, :is_map, 1}
          example "x", rule: :r, command: {:no_such, %{case_id: "c"}}, then: [:a]
          process :p, label: "P", instance: [:case_id]
        end
        """,
        "does not declare as a `command`"
      )
    end

    test "supplying a different set of params than the command declares does not compile" do
      # Equality, not a subset: this DSL has no optional fields anywhere, so a
      # mismatch means one of the two is wrong rather than that one is partial.
      refute_compiles(
        """
        defmodule Reject.ExampleParamMismatch do
          use PNS.Contract

          event :a, label: "A", payload: %{case_id: :id}, process: :p
          command :do_it,
            label: "Do it",
            process: :p,
            principals: [:human],
            payload: %{case_id: :id}
          rule :r, label: "R", function: {Kernel, :is_map, 1}
          example "x", rule: :r, command: {:do_it, %{case_id: "c", extra: 1}}, then: [:a]
          process :p, label: "P", instance: [:case_id]
        end
        """,
        "They must match"
      )
    end
  end

  describe "handler" do
    test "on an event that does not exist does not compile" do
      refute_compiles(
        """
        defmodule Reject.HandlerOnUnknownEvent do
          use PNS.Handler,
            contract: ProcessShapes.Rig,
            event: :no_such_event
        end
        """,
        "which contract"
      )
    end

    test "publishing an event outside the contract does not compile" do
      refute_compiles(
        """
        defmodule Reject.HandlerPublishingUnknown do
          use PNS.Handler,
            contract: ProcessShapes.Rig,
            event: :item_received,
            publishes: [:invented_event]
        end
        """,
        "declares `publishes:"
      )
    end

    test "asynchronous on an event without `identity` in the contract does not compile" do
      # The question "what makes two occurrences the same fact" belongs to the
      # process owner, so the message points at the contract, not at the handler.
      refute_compiles(
        """
        defmodule Reject.AsyncOnEventWithoutIdentity do
          use PNS.Handler,
            contract: ProcessShapes.Rig,
            # `case_closed` is the one event in the rig with no `identity`, which
            # is exactly the state this gate refuses to let a queue see.
            event: :case_closed,
            async: true
        end
        """,
        "requires event"
      )
    end
  end

  describe "contract" do
    test "a rule with no example does not compile (ADR §18)" do
      refute_compiles(
        """
        defmodule Reject.RuleWithoutExample do
          use PNS.Contract

          event :something_happened, label: "Something", payload: %{id: :string}

          rule :rule_with_no_example,
            label: "A rule nobody pinned with an example",
            function: {String, :length, 1}
        end
        """,
        "a rule with no example does not compile"
      )
    end

    test "a capture instead of an MFA is refused" do
      assert_raise ArgumentError, ~r/must be an MFA tuple/, fn ->
        Code.compile_string("""
        defmodule Reject.RuleWithCapture do
          use PNS.Contract

          event :something_happened, label: "Something", payload: %{id: :string}

          rule :some_rule,
            label: "A rule with a capture",
            function: &String.length/1

          example "an example", rule: :some_rule, command: {:x, %{}}, then: []
        end
        """)
      end
    end

    test "a trace on an event that does not exist does not compile" do
      refute_compiles(
        """
        defmodule Reject.TraceOnUnknownEvent do
          use PNS.Contract

          event :start, label: "Start", payload: %{id: :string}

          trace :gets_somewhere do
            from :start
            eventually :not_here, within: {1, :day}
          end
        end
        """,
        "which the contract does not declare"
      )
    end

    test "identity on a field outside the payload does not compile" do
      refute_compiles(
        """
        defmodule Reject.IdentityUnknownField do
          use PNS.Contract

          event :something_happened,
            label: "Something",
            payload: %{id: :id},
            identity: [:not_here]
        end
        """,
        "`identity` names field"
      )
    end

    test "identity on a field dropped by retain does not compile" do
      # The idempotency key would disappear along with the field.
      refute_compiles(
        """
        defmodule Reject.IdentityOnDroppedField do
          use PNS.Contract

          event :something_happened,
            label: "Something",
            payload: %{id: :id, note: :string},
            retain: %{note: :drop},
            identity: [:note]
        end
        """,
        "`retain: :drop`"
      )
    end

    test "a process without `instance:` does not compile" do
      assert_raise ArgumentError, ~r/missing required `instance:`/, fn ->
        Code.compile_string("""
        defmodule Reject.ProcessWithoutInstance do
          use PNS.Contract

          event :a, label: "A", payload: %{id: :id}

          process :p, label: "P"
        end
        """)
      end
    end

    test "an event of a process without the instance field in its payload does not compile" do
      # Without that field there is no way to say which run the event belongs to —
      # and then the assertion will match it against any other run.
      refute_compiles(
        """
        defmodule Reject.EventWithoutInstanceField do
          use PNS.Contract

          event :a, label: "A", payload: %{case_id: :id}, process: :p
          event :b, label: "B", payload: %{something_else: :id}, process: :p

          process :p, label: "P", instance: [:case_id]
        end
        """,
        "has no :case_id field in its payload"
      )
    end

    test "an instance field dropped by retain does not compile" do
      # Run identity is computed from the payload after `retain`, so it would
      # disappear along with the field.
      refute_compiles(
        """
        defmodule Reject.InstanceOnDroppedField do
          use PNS.Contract

          event :a, label: "A", payload: %{case_id: :id}, retain: %{case_id: :drop}, process: :p

          process :p, label: "P", instance: [:case_id]
        end
        """,
        "takes part in the run identity"
      )
    end

    # The "an event in two processes" gate **is gone, and that is a result rather
    # than a regression**. Since `process:` is a single key on the event, two
    # processes on one event stopped being something that can be written. The stop
    # condition from ADR §15 is now settled by the shape of the declaration rather
    # than by a check — and something inexpressible cannot be pinned by a test.

    test "an event naming a process that does not exist does not compile" do
      refute_compiles(
        """
        defmodule Reject.EventWithUnknownProcess do
          use PNS.Contract

          event :a, label: "A", payload: %{case_id: :id}, process: :not_here

          process :p, label: "P", instance: [:case_id]
        end
        """,
        "which the contract does not declare"
      )
    end

    test "an event in a staged process with no `stage:` does not compile" do
      # Backward-edge detection rests on the order of stages, so an event with no
      # stage would be a hole in the check rather than a missing ornament.
      refute_compiles(
        """
        defmodule Reject.EventWithoutStage do
          use PNS.Contract

          event :a, label: "A", payload: %{case_id: :id}, process: :p, stage: :first
          event :b, label: "B", payload: %{case_id: :id}, process: :p

          process :p, label: "P", stages: [:first, :second], instance: [:case_id]
        end
        """,
        "does not say which one it is in"
      )
    end

    test "an event in a stage the process does not declare does not compile" do
      refute_compiles(
        """
        defmodule Reject.EventInUnknownStage do
          use PNS.Contract

          event :a, label: "A", payload: %{case_id: :id}, process: :p, stage: :invented

          process :p, label: "P", stages: [:first, :second], instance: [:case_id]
        end
        """,
        "which process"
      )
    end

    test "`stage:` without `process:` does not compile" do
      refute_compiles(
        """
        defmodule Reject.StageWithoutProcess do
          use PNS.Contract

          event :a, label: "A", payload: %{id: :id}, stage: :somewhere
        end
        """,
        "with no `process:`"
      )
    end

    test "a trace with a calendar unit in `within` does not compile" do
      # It used to pass compilation and blow up at run time, during assertion
      # evaluation — that is, at the client's. The gate and the arithmetic share
      # one source of truth about units so they cannot drift apart.
      refute_compiles(
        """
        defmodule Reject.TraceWithCalendarUnit do
          use PNS.Contract

          event :a, label: "A", payload: %{case_id: :id}, process: :p
          event :b, label: "B", payload: %{case_id: :id}, process: :p

          process :p, label: "P", instance: [:case_id]

          trace :within_a_month do
            from :a
            eventually :b, within: {1, :month}
          end
        end
        """,
        "unsupported time unit :month"
      )
    end

    test "a trace spanning two processes does not compile" do
      # An assertion is counted within one run, and every process has its own run
      # identity.
      refute_compiles(
        """
        defmodule Reject.TraceAcrossProcesses do
          use PNS.Contract

          event :a, label: "A", payload: %{case_id: :id}, process: :p1
          event :b, label: "B", payload: %{shipment_id: :id}, process: :p2

          process :p1, label: "P1", instance: [:case_id]
          process :p2, label: "P2", instance: [:shipment_id]

          trace :across_two_processes do
            from :a
            eventually :b, within: {1, :day}
          end
        end
        """,
        "spans processes"
      )
    end

    test "a process no longer accepts `events:` — events declare their own membership" do
      assert_raise ArgumentError, ~r/unknown keys \[:events\]/, fn ->
        Code.compile_string("""
        defmodule Reject.ProcessListingEvents do
          use PNS.Contract

          event :a, label: "A", payload: %{id: :id}

          process :p, label: "P", events: [:a], instance: [:id]
        end
        """)
      end
    end

    test "retain on a field outside the payload does not compile" do
      refute_compiles(
        """
        defmodule Reject.RetainUnknownField do
          use PNS.Contract

          event :something_happened,
            label: "Something",
            payload: %{id: :string},
            retain: %{no_such_field: :hash}
        end
        """,
        "which is not in `payload`"
      )
    end

    test "a payload type outside the closed set does not compile" do
      # `:period` specifically, because it is the one that got in. It looked like a
      # general type, named an accounting month, and no gate existed to stop it —
      # before this one, any atom was a legal type.
      refute_compiles(
        """
        defmodule Reject.DomainSpecificPayloadType do
          use PNS.Contract

          event :month_opened,
            label: "Month opened",
            payload: %{company_id: :id, period: :period}
        end
        """,
        "which is not a payload type"
      )
    end

    test "{:enum, [...]} with a legal set compiles" do
      # Fixed 21 August 2026: the one payload type whose legal shape is a tuple
      # rather than a bare atom, and this is the positive case — nothing here is
      # expected to raise.
      Code.compile_string("""
      defmodule Accept.EnumWithADeclaredSet do
        use PNS.Contract

        event :status_changed,
          label: "Status changed",
          payload: %{id: :id, status: {:enum, [:open, :closed]}}
      end
      """)
    end

    test "{:enum, []} — an empty set is not a set" do
      refute_compiles(
        """
        defmodule Reject.EmptyEnumSet do
          use PNS.Contract

          event :status_changed,
            label: "Status changed",
            payload: %{id: :id, status: {:enum, []}}
        end
        """,
        "an enum with nothing legal in it"
      )
    end

    test "{:enum, [:open, :open]} — the same member twice is not a set" do
      refute_compiles(
        """
        defmodule Reject.DuplicateEnumMember do
          use PNS.Contract

          event :status_changed,
            label: "Status changed",
            payload: %{id: :id, status: {:enum, [:open, :open]}}
        end
        """,
        "the same member twice"
      )
    end

    test "{:enum, [:open, \"open\"]} — the same name twice, one as an atom and one as text, is caught too" do
      # The reason the check compares as strings rather than as terms: once JSON has
      # been through the round trip, `:open` and `"open"` are the same value, so
      # declaring both is the duplicate-member mistake wearing two different
      # Elixir representations.
      refute_compiles(
        """
        defmodule Reject.CrossRepresentationDuplicateEnumMember do
          use PNS.Contract

          event :status_changed,
            label: "Status changed",
            payload: %{id: :id, status: {:enum, [:open, "open"]}}
        end
        """,
        "the same member twice"
      )
    end

    test "{:enum, [1, 2]} — a set of numbers is not a set of names" do
      refute_compiles(
        """
        defmodule Reject.NonNameEnumMember do
          use PNS.Contract

          event :status_changed,
            label: "Status changed",
            payload: %{id: :id, status: {:enum, [1, 2]}}
        end
        """,
        "must be a non-empty list of atoms or strings"
      )
    end

    test "the refusal says what to write instead, because the answer is not obvious" do
      # A type naming a thing collapses to `:id`, and what the thing *is* belongs to
      # the client's application. Without that sentence the error tells somebody their
      # word is wrong and leaves them to guess, which is how a gate gets worked around
      # rather than obeyed.
      error =
        assert_raise CompileError, fn ->
          Code.compile_string("""
          defmodule Reject.UnhelpfulTypeError do
            use PNS.Contract

            event :thing_happened, label: "Thing", payload: %{id: :invoice_number}
          end
          """)
        end

      assert error.description =~ "it is `:id`"
      assert error.description =~ inspect(PNS.Contract.payload_types())
    end
  end
end
