defmodule ReadRig.Entities do
  @moduledoc """
  **Invented.** The engine suite's `EhOsContract.Entities`. It answers the row the test
  put under `{:read_rig_row, id}` — a row, `:not_found`, or anything else to see what the
  engine does with it — and otherwise a product on sale at 4. It keeps the ids it was
  asked for under `:read_rig_fetched`. Both in the calling process, which is the one
  dispatch runs in.
  """

  @behaviour EhOsContract.Entities

  @impl true
  def fetch(actor, ReadRig.Domain, :product, id) do
    Process.put(:read_rig_actor, actor)
    Process.put(:read_rig_fetched, [id | Process.get(:read_rig_fetched, [])])

    case Process.get({:read_rig_row, id}, :default) do
      :default -> {:ok, %{product_id: id, price: 4, on_sale: true, shelf: "B2"}}
      answer -> answer
    end
  end
end
