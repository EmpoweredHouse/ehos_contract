defmodule EhOsContract.Contract do
  @moduledoc """
  One context of a business written down: the contract DSL.

      defmodule Rehmed.Contracts.VisitSettlement do
        use EhOsContract.Contract,
          domain: Rehmed.Domain,
          context: :settlement,
          id: "rehmed.visit_settlement"

        aggregate :visit_settlement, "Rozliczenie wizyty" do
          identity :visit_id

          command :record_payment, "Przyjęcie płatności za wizytę",
            by: :reception, emits: :payment_recorded do
            field :amount, :money
          end

          event :payment_recorded, "Pacjent opłacił wizytę" do
            field :amount, :money
          end
        end
      end

  Everything decided in the context is declared here: the units that decide, with
  their state, invariants, commands and events; what reacts to events; what is read;
  what enters from elsewhere and what leaves; scenarios. The run those events make,
  with its stages and promises, is an `EhOsContract.Process` of its own; a contract's
  own `process` is an older form that is being removed. The module compiles to plain data,
  `__eh_os_contract_model__/0`, which `EhOsContract.Model.fetch/1` returns.

  `domain:` names the application's `EhOsContract.Domain` and `context:` one of its
  contexts. Neither records a compile dependency: the domain is checked
  against the contract by a Mix compiler, not by recompiling every contract when the
  domain changes. `id:`, required, names the contract,
  `"<domain name>.<segment>…"` (D11), unique in the application (X7), and types every
  event it records, `"<id>.<event>"`.

  It compiles, refusing what cannot be right with a code and a message; its model is
  data; and it generates a struct for every command, event, state, row and query and
  a behaviour for everything code implements. Code binds to
  it with `use Contract, aggregate: :name` (`EhOsContract.Implementation`), and
  `EhOsContract.dispatch/3` runs a command through it (`EhOsContract.Dispatcher`).
  """

  use Spark.Dsl,
    default_extensions: [extensions: [EhOsContract.Contract.Dsl]],
    opt_schema: [
      domain: [type: :atom, required: true, doc: "The application's domain module."],
      context: [type: :atom, required: true, doc: "The domain context the contract belongs to."],
      id: [
        type: :string,
        doc:
          "The contract's name, required (D11): the domain's `name:`, " <>
            "then dotted snake_case segments, like `\"rehmed.settlement\"`; it types every " <>
            "event the contract records, `\"rehmed.settlement.payment_recorded\"`."
      ]
    ]

  # The words of the DSL: for every entity, by its path from the module body, the keys
  # it takes — positional arguments first, then options, in the order the entity
  # defines them. Derived from the extension, never listed by hand, so a test that
  # pins it notices every word added or removed.
  @doc false
  @spec vocabulary() :: %{[atom()] => [atom()]}
  def vocabulary,
    do: EhOsContract.DslWrappers.vocabulary(EhOsContract.Contract.Dsl.sections())

  @impl Spark.Dsl
  def handle_opts(opts) do
    quote do
      @persist {:eh_os_contract_contract,
                %{
                  domain: unquote(opts[:domain]),
                  context: unquote(opts[:context]),
                  id: unquote(opts[:id])
                }}
      @persist {:eh_os_contract_line, __ENV__.line}
    end
  end
end
