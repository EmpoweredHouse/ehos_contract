defmodule EhOsContract.BootTest do
  @moduledoc """
  `EhOsContract` as a child of the host's supervision tree: the registry scan and the
  deployment record in one step, so a host cannot remember one and forget the other.
  """

  use EhOsContract.DataCase, async: false

  test "the child spec starts the boot step and keeps nothing alive" do
    assert %{id: EhOsContract, start: {EhOsContract, :boot, []}, restart: :temporary} =
             Supervisor.child_spec(EhOsContract, [])
  end

  test "booting loads the registry and records the deployment" do
    assert EhOsContract.TestRepo.all(EhOsContract.Deployment) == []
    assert EhOsContract.boot() == :ignore
    refute EhOsContract.Registry.contracts() == []
    refute EhOsContract.TestRepo.all(EhOsContract.Deployment) == []
  end
end
