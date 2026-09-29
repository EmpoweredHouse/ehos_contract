defmodule UniversalityGate.TreatmentEpisodeScenariosTest do
  @moduledoc """
  v2 plan, E5: **the fixture's scenarios run against its decider**,
  `UniversalityGate.Episode` — the successor of v1's examples, which ran against
  v1's decision function.
  """

  use EhOsContract.ScenarioCase, contract: UniversalityGate.TreatmentEpisode
end
