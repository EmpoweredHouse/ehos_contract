defmodule KeyRig.Bins do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A bin stocked, in three keys over its identity: its stream, `"bin:"` in front; its
  run, `KeyRig.Restocking`'s, whose id is in the entry twice; and its watch, a process
  manager whose key starts with this module's name, the longest of the three (issue
  #98). The run was `:replenishment` inside this contract until plan DD, P2g (#228).
  """

  use EhOsContract.Contract, domain: KeyRig.Domain, context: :stock, id: "key_rig.bins"

  aggregate :bin, "Bin" do
    identity [:site_id, :aisle_id, :bin_id]

    command :stock_bin, "Stock a bin", by: :stocker, emits: :restocked do
      field :lot_id, :id
    end

    event :restocked, "Bin restocked" do
      field :lot_id, :id
    end

    command :count_bin, "Count a bin", by: :stocker, emits: :counted

    event :counted, "Bin counted"
  end

  process_manager :watch, "Watch a stocked bin" do
    correlate [:site_id, :aisle_id, :bin_id]
    starts_on :restocked
    on :counted
  end

  scenario "a bin is stocked" do
    command :stock_bin, %{lot_id: "l-1"}
    expect :restocked, %{lot_id: "l-1"}
  end
end

defmodule KeyRig.BinDecider do
  @moduledoc "**Invented.** The decider of `KeyRig.Bins`."

  use KeyRig.Bins, aggregate: :bin

  @impl true
  def stock_bin(%StockBin{} = command, _state),
    do:
      emit(%Restocked{
        site_id: command.site_id,
        aisle_id: command.aisle_id,
        bin_id: command.bin_id,
        lot_id: command.lot_id
      })

  @impl true
  def count_bin(%CountBin{} = command, _state),
    do:
      emit(%Counted{
        site_id: command.site_id,
        aisle_id: command.aisle_id,
        bin_id: command.bin_id
      })
end

defmodule KeyRig.Watch do
  @moduledoc "**Invented.** `KeyRig.Bins`'s process manager `:watch`, which only keeps its run."

  use KeyRig.Bins, process_manager: :watch
end
