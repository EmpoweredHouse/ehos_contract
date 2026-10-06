defmodule DispatchRig.Unfinished do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  **A contract implemented in part**, for `mix eh_os_contract.check`: its unit has a
  decider, its read model and its query have none, so dispatch would refuse to
  project and to answer. Nothing here is dispatched.
  """

  use EhOsContract.Contract,
    domain: DispatchRig.Domain,
    context: :ledger,
    id: "dispatch_rig.unfinished"

  aggregate :note, "Note" do
    identity :note_id
    command :write_note, "Write a note", by: :clerk, emits: :note_written
    event :note_written, "Note written"
  end

  read_model :notes, "Notes", projects: :note_written do
    field :note_id, :id
  end

  query :notes_of, "Notes", reads: :notes, by: :auditor do
    param :note_id, :id
  end
end

defmodule DispatchRig.Note do
  @moduledoc "**Invented.** The one declaration of `DispatchRig.Unfinished` that is implemented."

  use DispatchRig.Unfinished, aggregate: :note

  @impl true
  def write_note(%WriteNote{note_id: id}, _state), do: emit(%NoteWritten{note_id: id})
end
