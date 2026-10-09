defmodule EhOsContract.PersonRigScenariosTest do
  @moduledoc """
  Plan DD, A1 (#247): `PersonRig.Desk`'s scenarios, run against its implementation. A
  scenario names the person issuing the command with `as:`, and is refused for anyone
  but the one the ticket is assigned to, as dispatch refuses them.
  """

  use EhOsContract.ScenarioCase, contract: PersonRig.Desk
end
