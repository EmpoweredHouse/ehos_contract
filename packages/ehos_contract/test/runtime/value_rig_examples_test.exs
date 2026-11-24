defmodule EhosContract.ValueRigExamplesTest do
  @moduledoc "The examples of the invented `ValueRig.Domain`'s invariants (plan EL2b)."

  use EhosContract.ScenarioCase, domain: ValueRig.Domain
end

defmodule EhosContract.ValueRigRulesTest do
  @moduledoc "The examples of the invented `ValueRig.Till`'s domain service rules (plan EL2b)."

  use EhosContract.ScenarioCase, contract: ValueRig.Till
end

defmodule EhosContract.TipRigScenariosTest do
  @moduledoc "The scenarios of the invented `TipRig.Till`, two values' rules of one name (#458)."

  use EhosContract.ScenarioCase, contract: TipRig.Till
end
