defmodule GraphLab.Processes do
  @moduledoc """
  The test set's process modules (`GraphLab`): the clinical visit and the payer's month;
  the visit's settlement, which shares the patient leaving with the clinical visit; the
  till's day, over one contract; and the contact with the patient, which never ends.
  """

  use Boundary, deps: [EhOsContract, GraphLab.Contracts], exports: []
end
