defmodule EhosContract.ContractIdTest do
  @moduledoc """
  Plan DD, ID1: **a contract's `id:`**, declared on its `use` and checked — its shape by
  **D11** (L2), its namespace by D11 against the domain's `name:` (L3), and its
  uniqueness by **X7**. Since ID3 it is required and types every event the contract records,
  so a contract without one is refused and renaming one moves the version. Each refusal
  stands at the `use` line, with a control beside it.
  """

  use EhosContract.DslCase, async: false

  @fixtures EhosContract.Fixtures
  @domain EhosContract.Fixtures.IdClinic

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhosContract.Domain, name: :clinic, language: :en

        context :settlement, "Settlement", subdomain: :core
        actor :reception, :human, "Reception"

        subdomain :core, "Core", type: :core
      end
      """,
      "id_clinic.ex"
    )

    :ok
  end

  # A contract whose `use` is at line 2, naming `id` when given.
  defp source(name, id, unit \\ nil) do
    id = if id, do: ", id: #{inspect(id)}", else: ""
    unit = unit || Macro.underscore(name) |> String.to_atom()

    """
    defmodule #{inspect(Module.concat(@fixtures, name))} do
      use EhosContract.Contract, domain: #{inspect(@domain)}, context: :settlement#{id}

      aggregate #{inspect(unit)}, "Unit" do
        identity :case_id
        command #{inspect(:"open_#{unit}")}, "Open", by: :reception, emits: #{inspect(:"#{unit}_opened")}
        event #{inspect(:"#{unit}_opened")}, "Opened"
      end
    end
    """
  end

  defp file(name), do: "#{Macro.underscore(name)}.ex"

  describe "D11 (L2): the id's shape" do
    for {id, why} <- [
          {"clinic", "one segment, no name under the namespace"},
          {"clinic.Settlement", "a segment not snake_case"},
          {"Clinic.settlement", "a namespace not lowercase"},
          {"clinic..settlement", "an empty segment"},
          {"clinic.settlement.v1", "versioned, as a publication is"},
          {"clinic.v1.settlement", "a version segment anywhere"},
          {"v1.settlement", "a version as the namespace"},
          {"clinic.settle:ment", "a colon, which separates a key's parts"},
          {"clinic.settle|ment", "a bar, which separates a run's parts"},
          {"clinic." <> String.duplicate("a", 94), "over 100 bytes"}
        ] do
      test "refused: #{why}" do
        name = "IdBad#{System.unique_integer([:positive])}"

        error = compile_error(source(name, unquote(id)), file(name))

        assert Exception.message(error) =~
                 "D11: the contract's id: #{inspect(unquote(id))} is not a contract's name: the " <>
                   "application's namespace, then dotted snake_case segments, unversioned, at " <>
                   "most 100 bytes"

        assert Exception.message(error) =~ "(#{file(name)}:2)"
      end
    end

    test "control: the namespace, then one or more snake_case segments, up to 100 bytes" do
      for {id, n} <- [
            {"clinic.settlement", 1},
            {"clinic.visit_settlement.payers", 2},
            {"clinic." <> String.duplicate("a", 93), 3}
          ] do
        name = "IdGood#{n}"
        compile(source(name, id), file(name))
        assert EhosContract.Model.fetch(Module.concat(@fixtures, name)).id == id
      end
    end
  end

  test "a contract without an id does not compile (plan DD, ID3)" do
    error = compile_error(source("IdUnnamed", nil), "id_unnamed.ex")

    assert Exception.message(error) =~
             "D11: the contract names no id:, which labels every event it records; add one"

    assert Exception.message(error) =~ "(id_unnamed.ex:2)"
  end

  test "the id is in the model and types every event, so the version follows it" do
    compile(source("IdVersioned", "clinic.versioned", :versioned), "id_versioned.ex")
    named = EhosContract.Model.fetch(Module.concat(@fixtures, "IdVersioned"))

    compile(source("IdRenamed", "clinic.renamed", :versioned), "id_renamed.ex")
    renamed = EhosContract.Model.fetch(Module.concat(@fixtures, "IdRenamed"))

    assert named.id == "clinic.versioned"
    assert [%{type: "clinic.versioned.versioned_opened"}] = named.events
    assert [%{type: "clinic.renamed.versioned_opened"}] = renamed.events
    refute named.version == renamed.version

    # The export carries it, and the exported document's digest covers it: dropped, the
    # same document hashes otherwise.
    export = EhosContract.Model.to_data(Module.concat(@fixtures, "IdVersioned"))
    assert export["contract"]["id"] == "clinic.versioned"

    body = Map.delete(export, "digest")
    without_id = Map.update!(body, "contract", &Map.delete(&1, "id"))

    assert EhosContract.Digest.document_hash(body) == export["digest"]
    refute EhosContract.Digest.document_hash(without_id) == export["digest"]
  end

  describe "D11 (L3): the id is under the domain's namespace" do
    test "an id under another namespace" do
      violations = links([{"id_elsewhere.ex", source("IdElsewhere", "dental.settlement")}])

      assert assert_linked(violations, "D11:", "id_elsewhere.ex", 2) =~
               "the contract's id: \"dental.settlement\" is outside the application's namespace " <>
                 "\"clinic.\", the name: of #{inspect(@domain)}"
    end

    test "control: an id under the domain's name" do
      assert links([{"id_home.ex", source("IdHome", "clinic.home")}]) == []
    end
  end

  describe "X7: an id is the application's" do
    test "two contracts with one id" do
      violations =
        links([
          {"id_twin_a.ex", source("IdTwinA", "clinic.twin")},
          {"id_twin_b.ex", source("IdTwinB", "clinic.twin")}
        ])

      assert assert_linked(violations, "X7:", "id_twin_b.ex", 2) =~
               "the id: \"clinic.twin\" of #{inspect(@fixtures)}.IdTwinB is also the id: of " <>
                 "#{inspect(@fixtures)}.IdTwinA (id_twin_a.ex:2); a contract's id prefixes its " <>
                 "event types, so it is unique in the application"

      assert length(violations) == 1
    end

    test "control: two ids" do
      assert links([
               {"id_one.ex", source("IdOne", "clinic.one")},
               {"id_two.ex", source("IdTwo", "clinic.two")}
             ]) == []
    end
  end
end
