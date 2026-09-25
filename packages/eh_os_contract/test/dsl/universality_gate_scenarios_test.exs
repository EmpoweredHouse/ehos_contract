defmodule UniversalityGate.Next.TreatmentEpisodeScenariosTest do
  @moduledoc """
  v2 plan, E5: **the fixture's scenarios run against its decider**,
  `UniversalityGate.Next.Episode` — the successor of v1's examples running against
  `UniversalityGate.Eligibility.decide/1` in `universality_gate_test`.
  """

  use EhOsContract.ScenarioCase, contract: UniversalityGate.Next.TreatmentEpisode
end
