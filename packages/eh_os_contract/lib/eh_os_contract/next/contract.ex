defmodule EhOsContract.Next.Contract do
  @moduledoc """
  One process, written down (v2 §4.1): the v2 contract DSL, growing beside v1's
  `EhOsContract.Contract` until the cut renames it (v2 plan, E11).

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

  Nothing runs a v2 contract yet. It compiles, it refuses what v2 §6 refuses, and
  its model is data; generated structs and behaviours come in E5, dispatch in E6.
  """

  use Spark.Dsl,
    default_extensions: [extensions: [EhOsContract.Next.Contract.Dsl]],
    opt_schema: [
      domain: [type: :atom, required: true, doc: "The application's domain module."],
      context: [type: :atom, required: true, doc: "The domain context the process belongs to."]
    ]

  @impl Spark.Dsl
  def handle_opts(opts) do
    quote do
      @persist {:eh_os_contract_contract,
                %{domain: unquote(opts[:domain]), context: unquote(opts[:context])}}
    end
  end
end
