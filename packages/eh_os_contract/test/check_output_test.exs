defmodule EhOsContract.CheckOutputTest do
  @moduledoc """
  Plan EL1: **every finding of `mix eh_os_contract.check` names a rule of the
  catalog**, says where its declaration was written, and links to the rule's entry
  in `docs/rules.md`; `--format json` carries the same, and `--warnings-as-errors`
  changes the exit status and nothing else.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check.{Catalog, Finding}
  alias Mix.Tasks.EhOsContract.Check

  describe "the catalog" do
    test "names each rule once, in lower case words joined by hyphens" do
      ids = Enum.map(Catalog.rules(), & &1.id)

      assert ids == Enum.uniq(ids)
      assert Enum.all?(ids, &(&1 =~ ~r/\A[a-z]+(-[a-z0-9]+)*\z/))
    end

    test "says what each rule finds, and why, and which ESDM rule it follows" do
      for rule <- Catalog.rules() do
        assert rule.level in [:error, :warn, :info]
        assert rule.reads in [:v1, :v2, :both]
        assert String.trim(rule.summary) != "", rule.id
        assert String.trim(rule.text) != "", rule.id
        assert rule.esdm == nil or rule.esdm =~ ~r{\Aesdm/[a-z]+/[a-z-]+\z}, rule.id
      end
    end

    test "a finding of a rule it does not have is refused, so no name goes out undocumented" do
      assert_raise ArgumentError, ~r/no rule "orphan-actr"/, fn ->
        Finding.new("orphan-actr", "anything")
      end
    end

    test "a finding takes its rule's level" do
      assert %Finding{level: :info} = Finding.new("promise-without-within", "p")
      assert %Finding{level: :error} = Finding.new("trace-unresolved", "t")
    end
  end

  @at [file: ~c"#{File.cwd!()}/lib/clinic/contract.ex", location: 12]

  describe "the human format" do
    test "a finding is its rule and sentence, then where it was written and its rule's page" do
      text =
        Check.render(
          [Finding.new("process-without-accountable", "process :visit …", @at)],
          :human
        )

      assert text =~
               "WARN  process-without-accountable: process :visit …\n" <>
                 "      lib/clinic/contract.ex:12 · " <>
                 "https://hexdocs.pm/eh_os_contract/rules.html#process-without-accountable\n"

      assert text =~ "eh_os_contract.check: 0 errors, 1 warnings, 0 notices"
    end

    test "control: a finding nothing locates has its rule's page alone" do
      text = Check.render([Finding.new("no-contracts", "no contracts found")], :human)

      assert text =~
               "WARN  no-contracts: no contracts found\n" <>
                 "      https://hexdocs.pm/eh_os_contract/rules.html#no-contracts\n"
    end
  end

  describe "the JSON format" do
    test "one array, a finding an object with its rule, level, sentence, place and page" do
      json =
        Check.render(
          [
            Finding.new("promise-without-within", "promise :paid has no `within`", @at),
            Finding.new("trace-unresolved", "trace :t does not resolve [:x]")
          ],
          :json
        )

      assert [error, notice] = Jason.decode!(json)

      assert error == %{
               "rule" => "trace-unresolved",
               "level" => "error",
               "message" => "trace :t does not resolve [:x]",
               "file" => nil,
               "line" => nil,
               "documentation" => "https://hexdocs.pm/eh_os_contract/rules.html#trace-unresolved"
             }

      assert %{"level" => "notice", "file" => "lib/clinic/contract.ex", "line" => 12} = notice
      refute json =~ "eh_os_contract.check:"
    end
  end

  describe "the exit status" do
    @warning Finding.new("process-without-accountable", "w")
    @notice Finding.new("promise-without-within", "n")
    @error Finding.new("trace-unresolved", "e")

    test "an error fails the task, a warning only under --warnings-as-errors" do
      assert Check.failed?([@error], false)
      refute Check.failed?([@warning, @notice], false)
      assert Check.failed?([@warning], true)
    end

    test "control: a notice never does" do
      refute Check.failed?([@notice], true)
    end
  end

  describe "a v2 finding" do
    test "points at the declaration it is about" do
      compile(
        """
        defmodule EhOsContract.CheckOutputTest.Unaddressed do
          use EhOsContract.Next.Contract, domain: ProcessShapes.Domain, context: :batching

          aggregate :pile, "Pile" do
            identity :pile_id
            command :stack, "Stack", by: :batch_operator, emits: :stacked
            event :stacked, "Stacked"
          end

          process :piling, "Piling" do
            correlate :pile_id
          end
        end
        """,
        "unaddressed.ex"
      )

      assert %Finding{rule: "process-without-accountable"} =
               finding =
               Enum.find(
                 EhOsContract.Check.v2_findings([EhOsContract.CheckOutputTest.Unaddressed]),
                 &(&1.rule == "process-without-accountable")
               )

      assert Finding.place(finding) == {"unaddressed.ex", 10}
    end
  end
end
