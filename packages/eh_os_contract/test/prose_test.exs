defmodule EhOsContract.Docs.ProseTest do
  @moduledoc """
  `EhOsContract.Docs.Prose`: what a prose page says it covers is read and checked
  against what exists, and its generated regions are filled from the code (#141).
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Docs.Prose

  describe "covers/1" do
    test "reads every covers comment of a page, each group by its kind" do
      page = """
      <!-- covers: entities contract.policy, contract.effect; rules backward-edge -->
      Some prose.
      <!--
        covers: keys contract.policy.delivery
      -->
      """

      assert Prose.covers(page) == %{
               entities: ["contract.policy", "contract.effect"],
               keys: ["contract.policy.delivery"],
               rules: ["backward-edge"]
             }
    end

    test "refuses a group it cannot read, naming it" do
      assert_raise ArgumentError, ~r/"policies contract.policy"/, fn ->
        Prose.covers("<!-- covers: policies contract.policy -->")
      end
    end
  end

  describe "unknown/1" do
    test "names what a page covers that does not exist" do
      page = """
      <!-- covers: entities contract.policy, contract.polcy; keys contract.policy.delivery,
      contract.policy.deliver; rules backward-edge, backwards-edge -->
      """

      assert Prose.unknown(page) == [
               "entity contract.polcy",
               "key contract.policy.deliver",
               "rule backwards-edge"
             ]
    end

    test "knows the entities of all three DSLs, nested ones included" do
      page = """
      <!-- covers: entities domain.value, contract.aggregate.command.field, process.promise -->
      """

      assert Prose.unknown(page) == []
    end
  end

  describe "uncovered/1" do
    test "a top-level entity is covered by itself, a nested entity or one of its keys" do
      gaps =
        Prose.uncovered([
          "<!-- covers: entities contract.aggregate.command; keys contract.policy.delivery -->"
        ])

      refute "entity contract.aggregate" in gaps
      refute "entity contract.policy" in gaps
      assert "entity contract.effect" in gaps
      assert "rule backward-edge" in gaps
    end

    test "a prefix of a name is not the name: contract.process is not covered by contract.process_manager" do
      gaps = Prose.uncovered(["<!-- covers: entities contract.process_manager -->"])

      refute "entity contract.process_manager" in gaps
      assert "entity contract.process" in gaps
    end
  end

  describe "fill/1" do
    test "rewrites a region from the code, and keeps the prose around it" do
      page = """
      Before.

      <!-- generated: dsl-keys contract.policy -->
      stale text
      <!-- /generated -->

      After.
      """

      filled = Prose.fill(page)

      assert filled =~ "Before.\n\n<!-- generated: dsl-keys contract.policy -->\n"
      assert filled =~ "| `delivery` |"
      refute filled =~ "stale text"
      assert filled =~ "<!-- /generated -->\n\nAfter.\n"
      assert Prose.fill(filled) == filled
    end

    test "fills the configuration's keys" do
      filled = Prose.fill("<!-- generated: config -->\n<!-- /generated -->\n")
      assert filled =~ "`:applications`"
    end

    test "refuses a region it does not know, an entity no DSL has, and one left open" do
      assert_raise ArgumentError, ~r/"rules"/, fn ->
        Prose.fill("<!-- generated: rules -->\n<!-- /generated -->\n")
      end

      assert_raise ArgumentError, ~r/contract\.polcy/, fn ->
        Prose.fill("<!-- generated: dsl-keys contract.polcy -->\n<!-- /generated -->\n")
      end

      assert_raise ArgumentError, ~r/not closed/, fn ->
        Prose.fill("<!-- generated: config -->\nno end\n")
      end
    end
  end
end
