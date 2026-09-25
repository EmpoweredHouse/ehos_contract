defmodule EhOsContract.DomainTest do
  @moduledoc """
  v2 plan, E3: **a domain module compiles to plain data whose version does not see
  declaration order.**

  The fixtures are declared inside this file, as in `digest_test`: modules defined in
  a `.exs` are not in the application's module list, so the registry never sees them.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Model

  defmodule Ordered do
    @moduledoc false
    use EhOsContract.Domain, name: :clinic, language: :pl

    context(:scheduling, "Umawianie", subdomain: :core)

    context :settlement, "Rozliczenia" do
      subdomain(:supporting)

      term "Wizyta" do
        definition("Spotkanie pacjenta ze specjalistą")
        translation(:en, "Visit")
        translation(:de, "Besuch")
        avoid("Seans")
      end

      term "Rozliczenie" do
        definition("Suma należności za wizytę")
      end
    end

    actor(:reception, :human, "Recepcja")
    actor(:payer_gateway, :system, "Bramka płatnika", backed_by: :payer_registry)
    subject(:patient, "Pacjent")
    value(:money, :integer, unit: :grosze, label: "Kwota")

    value :address do
      field(:street, :string)
      field(:city, :string)
    end

    external(:payer_registry, "Rejestr płatnika", direction: :outbound)
    relation(:customer_supplier, upstream: :scheduling, downstream: :settlement)
  end

  defmodule Reordered do
    @moduledoc false
    use EhOsContract.Domain, name: :clinic, language: :pl

    relation(:customer_supplier, upstream: :scheduling, downstream: :settlement)
    external(:payer_registry, "Rejestr płatnika", direction: :outbound)

    value :address do
      field(:city, :string)
      field(:street, :string)
    end

    value(:money, :integer, unit: :grosze, label: "Kwota")
    subject(:patient, "Pacjent")
    actor(:payer_gateway, :system, "Bramka płatnika", backed_by: :payer_registry)
    actor(:reception, :human, "Recepcja")

    context :settlement, "Rozliczenia" do
      subdomain(:supporting)

      term "Rozliczenie" do
        definition("Suma należności za wizytę")
      end

      term "Wizyta" do
        definition("Spotkanie pacjenta ze specjalistą")
        avoid("Seans")
        translation(:de, "Besuch")
        translation(:en, "Visit")
      end
    end

    context(:scheduling, "Umawianie", subdomain: :core)
  end

  defmodule Changed do
    @moduledoc false
    use EhOsContract.Domain, name: :clinic, language: :pl

    context(:scheduling, "Umawianie", subdomain: :core)

    context :settlement, "Rozliczenia" do
      subdomain(:supporting)

      term "Wizyta" do
        definition("Spotkanie pacjenta ze specjalistą")
        translation(:en, "Visit")
        translation(:de, "Besuch")
        avoid("Seans")
      end

      term "Rozliczenie" do
        definition("Suma należności za wizytę")
      end
    end

    actor(:reception, :human, "Recepcja")
    actor(:payer_gateway, :system, "Bramka płatnika", backed_by: :payer_registry)
    subject(:patient, "Pacjent")
    # The only difference from `Ordered`: the unit.
    value(:money, :integer, unit: :zlote, label: "Kwota")

    value :address do
      field(:street, :string)
      field(:city, :string)
    end

    external(:payer_registry, "Rejestr płatnika", direction: :outbound)
    relation(:customer_supplier, upstream: :scheduling, downstream: :settlement)
  end

  describe "the model" do
    test "is plain data, reached through EhOsContract.Model" do
      model = Model.fetch(Ordered)

      assert %{format: 1, kind: :domain, module: Ordered, name: :clinic, language: :pl} = model
      assert Model.fetch(model) == model
      refute Model.contract?(Ordered)

      assert [%{name: :scheduling, subdomain: :core}, %{name: :settlement, terms: [visit, _]}] =
               model.contexts

      assert visit == %{
               text: "Wizyta",
               definition: "Spotkanie pacjenta ze specjalistą",
               source: nil,
               translations: [%{language: :en, text: "Visit"}, %{language: :de, text: "Besuch"}],
               avoid: [%{text: "Seans"}]
             }

      assert [%{name: :money, type: :integer, unit: :grosze}, %{name: :address, fields: fields}] =
               model.values

      assert Enum.map(fields, & &1.name) == [:street, :city]
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

    test "has one digest per declaration, keyed by kind and name" do
      assert Map.keys(Model.fetch(Ordered).digests) |> Enum.sort() == [
               "actor:payer_gateway",
               "actor:reception",
               "context:scheduling",
               "context:settlement",
               "external:payer_registry",
               "relation:customer_supplier:scheduling,settlement",
               "subject:patient",
               "value:address",
               "value:money"
             ]
    end
  end
end
