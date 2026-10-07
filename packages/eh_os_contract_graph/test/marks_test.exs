defmodule EhOsContract.GraphRenderer.MarksTest do
  use ExUnit.Case, async: true

  alias EhOsContract.GraphRenderer.Marks

  defp step(changes) do
    Map.merge(
      %{
        "taken" => 3,
        "waiting" => %{"lag" => 0, "timers" => 0, "effects" => 0},
        "failing" => %{"commands" => 0, "effects" => 0, "subscription" => nil},
        "untraversed" => false,
        "pending" => false
      },
      changes
    )
  end

  defp relation(entry), do: Marks.relation(%{"relations" => %{"r" => entry}}, "r")

  test "nothing without an overlay or without an entry" do
    assert Marks.node(nil, "n") == %{count: nil, states: []}
    assert Marks.relation(nil, "r") == %{count: nil, states: []}
    assert Marks.node(%{"nodes" => %{}}, "n") == %{count: nil, states: []}
    assert Marks.relation(%{"relations" => %{}}, "r") == %{count: nil, states: []}
  end

  test "a node's count is its occurrences, runs or aggregates" do
    for {key, n} <- [{"occurrences", 4}, {"runs", 2}, {"aggregates", 7}] do
      assert Marks.node(%{"nodes" => %{"n" => %{key => n}}}, "n") == %{count: n, states: []}
    end
  end

  test "a step: taken, and the states the report gives it" do
    assert relation(step(%{})) == %{count: 3, states: []}
    assert relation(step(%{"taken" => 0, "untraversed" => true})).states == [:untraversed]
    assert relation(step(%{"pending" => true})).states == [:pending]
    assert relation(step(%{"taken" => nil})).count == nil

    assert relation(step(%{"waiting" => %{"lag" => 0, "timers" => 1, "effects" => 0}})).states ==
             [:waiting]

    assert relation(
             step(%{"failing" => %{"commands" => 0, "effects" => 2, "subscription" => nil}})
           ).states ==
             [:failing]

    stopped = %{"stopped_at" => 12, "failure" => "boom"}

    assert relation(
             step(%{"failing" => %{"commands" => 0, "effects" => 0, "subscription" => stopped}})
           ).states ==
             [:failing]
  end

  test "a transition, a move the lifecycle does not allow, and traffic between contracts" do
    assert relation(%{"count" => 2, "pending" => false, "untraversed" => true}) ==
             %{count: 2, states: [:untraversed]}

    assert relation(%{"count" => 1}) == %{count: 1, states: [:undeclared]}

    assert relation(%{"events" => 9, "waiting" => 1, "failing" => true}) ==
             %{count: 9, states: [:waiting, :failing]}
  end

  test "a relation several steps end at is left to the views" do
    assert relation(%{"by_trigger" => %{"a" => step(%{}), "b" => step(%{"untraversed" => true})}}) ==
             %{count: nil, states: []}
  end
end
