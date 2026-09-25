defmodule EhOsContract.Domain do
  @moduledoc """
  The vocabulary an application's contracts share (v2 §4.1): one module per
  application.

      defmodule Rehmed.Domain do
        use EhOsContract.Domain, name: :rehmed, language: :pl

        context :settlement, "Rozliczenia", subdomain: :supporting
        actor :reception, :human, "Recepcja"
        value :money, :integer, unit: :grosze, label: "Kwota"
      end

  A domain module declares contexts with their glossary, actors, subjects of
  personal data, value types, external systems and the relations between contexts.
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

  @impl Spark.Dsl
  def handle_opts(opts) do
    quote do
      @persist {:eh_os_contract_domain,
                %{name: unquote(opts[:name]), language: unquote(opts[:language])}}
    end
  end
end
