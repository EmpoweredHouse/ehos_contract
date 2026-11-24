defmodule EhosContract.Docs.ProseTest do
  @moduledoc """
  `EhosContract.Docs.Prose`: what a prose page says it covers is read and checked
  against what exists, and its generated regions are filled from the code (#141).
  """

  use ExUnit.Case, async: true

  alias EhosContract.Docs.Prose

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

    test "ignores a covers comment shown in a code block" do
      page = """
      ```markdown
      <!-- covers: entities contract.made_up -->
      ```
      """

      assert Prose.covers(page) == %{entities: [], keys: [], rules: []}
    end

    test "reads a fence as CommonMark does: a longer fence holds a shorter one, and ~~~ closes no backticks" do
      page = """
      ````markdown
      ```
      <!-- covers: entities contract.made_up -->
      ```
      ````

      ```text
      ~~~
      <!-- covers: entities contract.also_made_up -->
      ```

      <!-- covers: entities contract.policy -->
      """

      assert Prose.covers(page).entities == ["contract.policy"]
    end

    test "a line of backticks with a backtick after them is inline code, not a fence" do
      page = """
      ```inline``` is not a fence
      <!-- covers: entities contract.policy -->
      ~~~ a tilde fence may hold ` in its info
      <!-- covers: entities contract.made_up -->
      ~~~
      """

      assert Prose.covers(page).entities == ["contract.policy"]
    end

    test "refuses a comment that is nearly a covers comment, rather than ignoring it" do
      for page <- ["<!-- Covers: entities contract.policy -->", "<!-- cover: rules x -->"] do
        assert_raise ArgumentError, ~r/is written `<!-- covers: ... -->`/, fn ->
          Prose.covers(page)
        end
      end
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
      # Since plan DD, P2h (#221) no entity of the DSLs is named after another's prefix,
      # so the names are given.
      names = %{entities: ["contract.process", "contract.process_manager"], keys: [], rules: []}
      gaps = Prose.uncovered(["<!-- covers: entities contract.process_manager -->"], names)

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

    test "fills a region whose opener has trailing spaces or a CRLF ending" do
      assert Prose.fill("<!-- generated: config -->  \n<!-- /generated -->\n") =~
               "`:applications`"

      assert Prose.fill("<!-- generated: config -->\r\n<!-- /generated -->\r\n") =~
               "`:applications`"
    end

    test "leaves a region shown in a code block as it is" do
      page = """
      ```markdown
      <!-- generated: config -->
      an example
      <!-- /generated -->
      ```
      """

      assert Prose.fill(page) == page
    end

    # Otherwise a region read to the wrong closer replaces the prose between them.
    test "refuses openers and closers out of order, or sharing a line with text" do
      for page <- [
            "<!-- /generated -->\n<!-- generated: config -->\nprose\n<!-- /generated -->\n",
            "<!-- generated: config -->\n<!-- generated: config -->\n<!-- /generated -->\n",
            "text <!-- generated: config -->\n<!-- /generated -->\n",
            "<!-- generated: config --><!-- /generated -->\n"
          ] do
        assert_raise ArgumentError, ~r/line [0-9]+/, fn -> Prose.fill(page) end
      end
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
