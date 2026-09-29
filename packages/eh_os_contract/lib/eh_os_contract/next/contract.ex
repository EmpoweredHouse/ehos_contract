defmodule EhOsContract.Next.Contract do
  @moduledoc """
  One process, written down (v2 §4.1): the contract DSL, named `Next` until the
  rename that follows v1's removal (v2 plan, E11).

      defmodule Rehmed.Contracts.VisitSettlement do
        use EhOsContract.Next.Contract, domain: Rehmed.Domain, context: :settlement

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

        process :visit_settlement, "Rozliczenie wizyty" do
          correlate :visit_id
        end
      end

  Everything born in the process is declared here: the units that decide, with
  their state, invariants, commands and events; what reacts to events; what is read;
  what enters from elsewhere and what leaves; the process with its stages and
  promises; scenarios. The module compiles to plain data,
  `__eh_os_contract_model__/0`, which `EhOsContract.Model.fetch/1` returns.

  `domain:` names the application's `EhOsContract.Domain` and `context:` one of its
  contexts. Neither records a compile dependency (v2 §8): the domain is checked
  against the contract by a Mix compiler, not by recompiling every contract when the
  domain changes.

  It compiles, it refuses what v2 §6 refuses, its model is data, and it generates a
  struct for every command, event, state, row and query and a behaviour for
  everything code implements (`EhOsContract.Next.Contract.Generate`). Code binds to
  it with `use Contract, aggregate: :name` (`EhOsContract.Implementation`), and
  `EhOsContract.dispatch/3` runs a command through it (`EhOsContract.Dispatcher`).
  """

  use Spark.Dsl,
    default_extensions: [extensions: [EhOsContract.Next.Contract.Dsl]],
    opt_schema: [
      domain: [type: :atom, required: true, doc: "The application's domain module."],
      context: [type: :atom, required: true, doc: "The domain context the process belongs to."]
    ]

  @doc """
  The words of the DSL: for every entity, by its path from the module body, the keys
  it takes — positional arguments first, then options, in the order the entity
  defines them. Derived from the extension, never listed by hand, so a test that
  pins it notices every word added or removed.
  """
  @spec vocabulary() :: %{[atom()] => [atom()]}
  def vocabulary,
    do: EhOsContract.DslWrappers.vocabulary(EhOsContract.Next.Contract.Dsl.sections())

  @impl Spark.Dsl
  def handle_opts(opts) do
    quote do
      @persist {:eh_os_contract_contract,
                %{domain: unquote(opts[:domain]), context: unquote(opts[:context])}}
      @persist {:eh_os_contract_line, __ENV__.line}
    end
  end
end
