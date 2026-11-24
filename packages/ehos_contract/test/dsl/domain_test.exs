defmodule EhosContract.DomainTest do
  @moduledoc """
  v2 plan, E3: **a domain module compiles to plain data whose version does not see
  declaration order.**

  The fixtures are declared inside this file on purpose: modules defined in a `.exs`
  are not in the application's module list, so the registry never sees them.
  """

  use ExUnit.Case, async: true

  alias EhosContract.Model

  defmodule Ordered do
    @moduledoc false
    use EhosContract.Domain, name: :clinic, language: :pl

    context(:scheduling, "Scheduling", subdomain: :core)

    context :settlement, "Settlement" do
      subdomain(:supporting)

      term "Wizyta" do
        definition("Spotkanie pacjenta ze specjalistą")
        translation(:en, "Visit", definition: "A patient's appointment with a specialist")
        translation(:de, "Besuch", definition: "Termin eines Patienten bei einem Spezialisten")
        avoid("Seans")
      end

      term "Bill" do
        definition("The sum owed for a visit")
      end
    end

    actor(:reception, :human, "Reception")
    actor(:payer_gateway, :system, "Payer gateway", backed_by: :payer_registry)
    subject(:patient, "Patient")
    value(:money, :integer, unit: :cents, label: "Amount")

    value :address do
      field(:street, :string)
      field(:city, :string)
    end

    external(:payer_registry, "Payer registry", direction: :outbound)
    relation(:customer_supplier, upstream: :scheduling, downstream: :settlement)

    subdomain :core, "Core", type: :core
    subdomain :supporting, "Supporting", type: :supporting
  end

  defmodule Reordered do
    @moduledoc false
    use EhosContract.Domain, name: :clinic, language: :pl

    relation(:customer_supplier, upstream: :scheduling, downstream: :settlement)
    external(:payer_registry, "Payer registry", direction: :outbound)

    value :address do
      field(:city, :string)
      field(:street, :string)
    end

    value(:money, :integer, unit: :cents, label: "Amount")
    subject(:patient, "Patient")
    actor(:payer_gateway, :system, "Payer gateway", backed_by: :payer_registry)
    actor(:reception, :human, "Reception")

    context :settlement, "Settlement" do
      subdomain(:supporting)

      term "Bill" do
        definition("The sum owed for a visit")
      end

      term "Wizyta" do
        definition("Spotkanie pacjenta ze specjalistą")
        avoid("Seans")
        translation(:de, "Besuch", definition: "Termin eines Patienten bei einem Spezialisten")
        translation(:en, "Visit", definition: "A patient's appointment with a specialist")
      end
    end

    context(:scheduling, "Scheduling", subdomain: :core)

    subdomain :core, "Core", type: :core
    subdomain :supporting, "Supporting", type: :supporting
  end

  defmodule Changed do
    @moduledoc false
    use EhosContract.Domain, name: :clinic, language: :pl

    context(:scheduling, "Scheduling", subdomain: :core)

    context :settlement, "Settlement" do
      subdomain(:supporting)

      term "Wizyta" do
        definition("Spotkanie pacjenta ze specjalistą")
        translation(:en, "Visit", definition: "A patient's appointment with a specialist")
        translation(:de, "Besuch", definition: "Termin eines Patienten bei einem Spezialisten")
        avoid("Seans")
      end

      term "Bill" do
        definition("The sum owed for a visit")
      end
    end

    actor(:reception, :human, "Reception")
    actor(:payer_gateway, :system, "Payer gateway", backed_by: :payer_registry)
    subject(:patient, "Patient")
    # The only difference from `Ordered`: the unit.
    value(:money, :integer, unit: :dollars, label: "Amount")

    value :address do
      field(:street, :string)
      field(:city, :string)
    end

    external(:payer_registry, "Payer registry", direction: :outbound)
    relation(:customer_supplier, upstream: :scheduling, downstream: :settlement)

    subdomain :core, "Core", type: :core
    subdomain :supporting, "Supporting", type: :supporting
  end

  describe "the model" do
    test "is plain data, reached through EhosContract.Model" do
      model = Model.fetch(Ordered)

      assert %{format: 1, kind: :domain, module: Ordered, name: :clinic, language: :pl} = model
      assert Model.fetch(model) == model

      assert [%{name: :scheduling, subdomain: :core}, %{name: :settlement, terms: [visit, _]}] =
               model.contexts

      assert visit == %{
               text: "Wizyta",
               definition: "Spotkanie pacjenta ze specjalistą",
               source: nil,
               translations: [
                 %{
                   language: :en,
                   text: "Visit",
                   definition: "A patient's appointment with a specialist",
                   avoid: []
                 },
                 %{
                   language: :de,
                   text: "Besuch",
                   definition: "Termin eines Patienten bei einem Spezialisten",
                   avoid: []
                 }
               ],
               avoid: [%{text: "Seans", reason: nil}]
             }

      assert [%{name: :money, type: :integer, unit: :cents}, %{name: :address, fields: fields}] =
               model.values

      assert Enum.map(fields, & &1.name) == [:street, :city]
    end

    test "a contract accessor refuses a domain by name" do
      error = assert_raise ArgumentError, fn -> Model.version(Ordered) end
      assert error.message =~ "EhosContract.DomainTest.Ordered is a domain, not a contract"
    end

    test "holds no Spark struct and no source annotation" do
      refute inspect(Model.fetch(Ordered), limit: :infinity) =~
               ~r/__spark_metadata__|__struct__|Spark\./
    end
  end

  describe "the version" do
    test "does not move when declarations are written in another order, nested ones included" do
      assert Model.fetch(Ordered).version == Model.fetch(Reordered).version
      assert Model.fetch(Ordered).digests == Model.fetch(Reordered).digests
    end

    test "moves when one declaration changes, and only that declaration's digest moves with it" do
      ordered = Model.fetch(Ordered)
      changed = Model.fetch(Changed)

      assert ordered.version != changed.version

      moved = for {key, digest} <- ordered.digests, changed.digests[key] != digest, do: key
      assert moved == ["value:money"]
    end

    test "moves when the domain's language changes, and only the domain's own digest moves" do
      Code.compile_string("""
      defmodule EhosContract.DomainTest.English do
        use EhosContract.Domain, name: :clinic, language: :en
        context :scheduling, "Scheduling", subdomain: :core

        subdomain :core, "Core", type: :core
      end
      """)

      Code.compile_string("""
      defmodule EhosContract.DomainTest.Polish do
        use EhosContract.Domain, name: :clinic, language: :pl
        context :scheduling, "Scheduling", subdomain: :core

        subdomain :core, "Core", type: :core
      end
      """)

      english = Model.fetch(EhosContract.DomainTest.English)
      polish = Model.fetch(EhosContract.DomainTest.Polish)

      assert english.version != polish.version
      moved = for {key, digest} <- english.digests, polish.digests[key] != digest, do: key
      assert moved == ["domain:clinic"]
    end

    # Plan DD, V5 (#322): a label is a word, and so is the glossary.
    test "does not move when a label or a term changes, and the words' digest does" do
      Code.compile_string("""
      defmodule EhosContract.DomainTest.Worded do
        use EhosContract.Domain, name: :clinic, language: :pl
        context :scheduling, "Scheduling", subdomain: :core do
          term "visit", definition: "A patient's meeting with a doctor."
        end

        subdomain :core, "Core", type: :core
      end
      """)

      Code.compile_string("""
      defmodule EhosContract.DomainTest.Reworded do
        use EhosContract.Domain, name: :clinic, language: :pl
        context :scheduling, "Visit schedule", subdomain: :core do
          term "visit", definition: "A patient's meeting with a doctor in the surgery."
        end

        subdomain :core, "Core", type: :core
      end
      """)

      worded = Model.fetch(EhosContract.DomainTest.Worded)
      reworded = Model.fetch(EhosContract.DomainTest.Reworded)

      assert worded.version == reworded.version
      assert worded.digests == reworded.digests

      moved =
        for {key, digest} <- worded.text_digests, reworded.text_digests[key] != digest, do: key

      assert moved == ["context:scheduling"]
    end

    test "has one digest per declaration, keyed by kind and name" do
      assert Map.keys(Model.fetch(Ordered).digests) |> Enum.sort() == [
               "actor:payer_gateway",
               "actor:reception",
               "context:scheduling",
               "context:settlement",
               "domain:clinic",
               "external:payer_registry",
               "relation:customer_supplier:scheduling,settlement",
               "subdomain:core",
               "subdomain:supporting",
               "subject:patient",
               "value:address",
               "value:money"
             ]
    end
  end
end
