defmodule EhOsContract.ValueRigExamplesTest do
  @moduledoc "The examples of the invented `ValueRig.Domain`'s invariants (plan EL2b)."

  use EhOsContract.ScenarioCase, domain: ValueRig.Domain
end

defmodule EhOsContract.ValueRigRulesTest do
  @moduledoc "The examples of the invented `ValueRig.Till`'s domain service rules (plan EL2b)."

  use EhOsContract.ScenarioCase, contract: ValueRig.Till
end
