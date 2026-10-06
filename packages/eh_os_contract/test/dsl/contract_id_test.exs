defmodule EhOsContract.ContractIdTest do
  @moduledoc """
  Plan DD, ID1: **a contract's `id:`**, declared on its `use` and checked — its shape by
  **D11** (L2), its namespace by D11 against the domain's `name:` (L3), and its
  uniqueness by **X7**. It stays out of the version: naming a contract changes nothing
  it decides or records. Each refusal stands at the `use` line, with a control beside it.
  """

  use EhOsContract.DslCase, async: false

  @fixtures EhOsContract.Fixtures
  @domain EhOsContract.Fixtures.IdClinic

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :clinic, language: :pl

        context :settlement, "Rozliczenia", subdomain: :core
        actor :reception, :human, "Recepcja"

        subdomain :core, "Core", type: :core
      end
      """,
      "id_clinic.ex"
    )

    :ok
  end

  # A contract whose `use` is at line 2, naming `id` when given.
  defp source(name, id, process \\ nil) do
    id = if id, do: ", id: #{inspect(id)}", else: ""
    process = process || Macro.underscore(name) |> String.to_atom()

    """
    defmodule #{inspect(Module.concat(@fixtures, name))} do
      use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :settlement#{id}

      aggregate #{inspect(process)}, "Jednostka" do
        identity :case_id
        command #{inspect(:"open_#{process}")}, "Otwórz", by: :reception, emits: #{inspect(:"#{process}_opened")}
        event #{inspect(:"#{process}_opened")}, "Otwarto"
      end

      process #{inspect(process)}, "Proces" do
        correlate :case_id
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
        assert EhOsContract.Model.fetch(Module.concat(@fixtures, name)).id == id
      end
    end
  end

  test "the id is in the model and out of the version; a contract without one has no key" do
    compile(source("IdVersioned", "clinic.versioned", :versioned), "id_versioned_a.ex")
    named = EhOsContract.Model.fetch(Module.concat(@fixtures, "IdVersioned"))

    compile(source("IdUnnamed", nil, :versioned), "id_unnamed.ex")
    unnamed = EhOsContract.Model.fetch(Module.concat(@fixtures, "IdUnnamed"))

    assert named.id == "clinic.versioned"
    refute Map.has_key?(unnamed, :id)
    assert named.version == unnamed.version
    assert named.digests == unnamed.digests

    # The export carries it, so the exported document's own digest moves with it.
    named_export = EhOsContract.Model.to_data(Module.concat(@fixtures, "IdVersioned"))
    unnamed_export = EhOsContract.Model.to_data(Module.concat(@fixtures, "IdUnnamed"))

    assert named_export["contract"]["id"] == "clinic.versioned"
    refute Map.has_key?(unnamed_export["contract"], "id")

    # The id is part of what that digest covers: dropped, the same document hashes otherwise.
    body = Map.delete(named_export, "digest")
    without_id = Map.update!(body, "contract", &Map.delete(&1, "id"))

    assert EhOsContract.Digest.document_hash(body) == named_export["digest"]
    refute EhOsContract.Digest.document_hash(without_id) == named_export["digest"]
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
                 "#{inspect(@fixtures)}.IdTwinA (id_twin_a.ex:2); a contract's id names it " <>
                 "outside the code, so it is unique in the application"

      assert length(violations) == 1
    end

    test "control: two ids, and contracts without one" do
      assert links([
               {"id_one.ex", source("IdOne", "clinic.one")},
               {"id_two.ex", source("IdTwo", "clinic.two")},
               {"id_none_a.ex", source("IdNoneA", nil)},
               {"id_none_b.ex", source("IdNoneB", nil)}
             ]) == []
    end
  end
end
