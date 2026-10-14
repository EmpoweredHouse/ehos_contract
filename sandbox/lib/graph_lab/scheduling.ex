defmodule GraphLab.Scheduling do
  @moduledoc """
  The implementation of `GraphLab.Contracts.Scheduling`: the visit's decision and the
  confirmation from the patient app.
  """

  use Boundary, deps: [EhOsContract, GraphLab.Contracts], exports: [Visit, ConfirmFromApp]
end
