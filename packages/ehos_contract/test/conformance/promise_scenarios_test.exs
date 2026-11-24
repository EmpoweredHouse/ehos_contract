defmodule ProcessShapes.HandlingScenariosTest do
  @moduledoc """
  Plan DD, S2 (#251): **a process module's scenarios run as tests**, each judging its
  promise from the givens at the trigger's moment, as the report would.
  """

  use EhosContract.ScenarioCase, process: ProcessShapes.Handling
end
