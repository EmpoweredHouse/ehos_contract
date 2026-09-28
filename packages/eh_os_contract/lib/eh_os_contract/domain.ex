defmodule EhOsContract.Domain do
  @moduledoc """
  The vocabulary an application's contracts share (v2 §4.1): one module per
  application.

      defmodule Rehmed.Domain do
        use EhOsContract.Domain, name: :rehmed, language: :pl

        subdomain :billing, "Rozliczenia z pacjentami", type: :supporting
        context :settlement, "Rozliczenia", subdomain: :billing
        actor :reception, :human, "Recepcja"
        value :money, :integer, unit: :grosze, label: "Kwota"
      end

  A domain module declares subdomains, contexts with their glossary, actors, subjects of
  personal data, value types, external systems and the relations between contexts.

  A value may declare invariants, each with values that break it and keep it
  (plan EL2b):

      value :money, :integer, unit: :grosze do
        invariant :not_negative, "Kwota nie jest ujemna",
          violated_by: [-1],
          satisfied_by: [0, 15_000]
      end

  The domain then generates a behaviour, `Rehmed.Domain.Values.Money`, and a module
  bound with `use Rehmed.Domain, value: :money` defines one function per invariant.
  Dispatch holds every value of the type to them (`EhOsContract.Value`), and
  `use EhOsContract.ScenarioCase, domain: Rehmed.Domain` tests each example.
  It compiles to plain data, `__eh_os_contract_model__/0`, which
  `EhOsContract.Model.fetch/1` returns for it. The data carries a `version`: a digest
  that ignores the order declarations are written in.

  `name:` is the domain's name, and `language:` is the language its labels and terms
  are written in, unless a context says otherwise.
  """

  use Spark.Dsl,
    default_extensions: [extensions: [EhOsContract.Domain.Dsl]],
    opt_schema: [
      name: [type: :atom, required: true, doc: "The domain's name."],
      language: [
        type: :atom,
        required: true,
        doc: "The language labels and terms are written in."
      ]
    ]

  @doc """
  The words of the DSL: for every entity, by its path from the module body, the keys
  it takes — positional arguments first, then options, in the order the entity
  defines them. Derived from the extension, never listed by hand, so a test that
  pins it notices every word added or removed.
  """
  @spec vocabulary() :: %{[atom()] => [atom()]}
  def vocabulary, do: EhOsContract.DslWrappers.vocabulary(EhOsContract.Domain.Dsl.sections())

  @impl Spark.Dsl
  def handle_opts(opts) do
    quote do
      @persist {:eh_os_contract_domain,
                %{name: unquote(opts[:name]), language: unquote(opts[:language])}}
    end
  end
end
