defmodule EhosContract.SchemaLock.PublicationsTest do
  @moduledoc """
  #697: the fields each publication carries, by its name and version, and a change a
  subscriber would no longer read refused at the same version.
  """

  use ExUnit.Case, async: true

  alias EhosContract.SchemaLock.Publications

  @name "shop.order_placed"
  @fields [order_id: [type: :id], total: [type: :integer]]

  defp lock(fields \\ @fields, version \\ 1), do: %{@name => %{version => fields}}

  describe "declared/1" do
    test "each publication by its name without the version, with the fields it carries" do
      assert Publications.declared([BusRig.Orders]) == %{
               "bus_rig_shop.order_placed" => %{
                 1 => [order_id: [type: :id], total: [type: :integer]]
               }
             }
    end
  end

  describe "merge/2" do
    test "records a new publication, and a field added at the same version" do
      assert Publications.merge(%{}, lock()) == {:ok, lock()}

      added = @fields ++ [note: [type: :string, optional: true]]
      assert Publications.merge(lock(), lock(added)) == {:ok, lock(added)}
    end

    test "refuses a field removed, retyped or made optional at the same version" do
      changed = [order_id: [type: :string], total: [type: :integer, optional: true]]

      assert Publications.merge(lock(), lock(changed)) ==
               {:error,
                [
                  "shop.order_placed.v1: order_id changed from [type: :id] to [type: :string], " <>
                    "and a subscriber of shop.order_placed.v1 may read it. Raise version: to 2, " <>
                    "which publishes shop.order_placed.v2, or keep the field as it was",
                  "shop.order_placed.v1: total changed from [type: :integer] to [type: :integer, " <>
                    "optional: true], and a subscriber of shop.order_placed.v1 may read it. Raise " <>
                    "version: to 2, which publishes shop.order_placed.v2, or keep the field as it was"
                ]}

      assert {:error, [removed]} = Publications.merge(lock(), lock(order_id: [type: :id]))
      assert removed =~ "shop.order_placed.v1: total was removed"
    end

    test "takes the fields of a higher version, and refuses a lower one" do
      raised = lock([order_id: [type: :id]], 2)
      assert Publications.merge(lock(), raised) == {:ok, raised}

      assert Publications.merge(raised, lock()) ==
               {:error,
                [
                  "shop.order_placed.v1: the lock records version 2, and its subscribers would " <>
                    "receive nothing under a lower one. Declare version: 2 or higher"
                ]}
    end

    test "refuses a publication no contract declares, until it is forgotten" do
      assert {:error, [gone]} = Publications.merge(lock(), %{})

      assert gone =~
               "shop.order_placed.v1: the lock records it as published, and no contract of the " <>
                 "applications read"

      assert gone =~ "run `mix ehos_contract.schema --forget shop.order_placed`"
      assert Publications.merge(Publications.forget(lock(), @name), %{}) == {:ok, %{}}
    end
  end
end
