defmodule EhOsContract.ValueRigExamplesTest do
  @moduledoc "The examples of the invented `ValueRig.Domain`'s invariants (plan EL2b)."

  use EhOsContract.ScenarioCase, domain: ValueRig.Domain
end

defmodule EhOsContract.ValueRigRulesTest do
  @moduledoc "The examples of the invented `ValueRig.Till`'s domain service rules (plan EL2b)."

  use EhOsContract.ScenarioCase, contract: ValueRig.Till
end

defmodule EhOsContract.TipRigScenariosTest do
  @moduledoc "The scenarios of the invented `TipRig.Till`, two values' rules of one name (#458)."

  use EhOsContract.ScenarioCase, contract: TipRig.Till
end
