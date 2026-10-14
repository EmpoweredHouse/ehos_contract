defmodule EhOsContract.GraphRenderer.MarksTest do
  use ExUnit.Case, async: true

  alias EhOsContract.GraphRenderer.Marks

  defp step(changes) do
    Map.merge(
      %{
        "taken" => 3,
        "waiting" => %{"lag" => 0, "timers" => 0, "effects" => 0},
        "failing" => %{"commands" => 0, "effects" => 0, "subscription" => nil},
        "waits" => false,
        "fails" => false,
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

    waiting = %{"waiting" => %{"lag" => 0, "timers" => 1, "effects" => 0}, "waits" => true}
    assert relation(step(waiting)).states == [:waiting]

    failing = %{"failing" => %{"commands" => 0, "effects" => 2, "subscription" => nil}}
    assert relation(step(Map.put(failing, "fails", true))).states == [:failing]
  end

  test "a step's states are the overlay's reading of it, not a sum of its numbers" do
    # The overlay says whether the report lists a step as waiting or failing; the numbers
    # beside it are for the panel's sentences, and nothing here adds them up again.
    numbers = %{
      "waiting" => %{"lag" => 4, "timers" => 0, "effects" => 0},
      "failing" => %{"commands" => 2, "effects" => 0, "subscription" => nil}
    }

    assert relation(step(numbers)).states == []
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

  # Plan DD, P2e (#220).
  test "a promise's verdicts in words, broken in the error state, and none for one unconfirmed" do
    promise = fn entry -> Marks.promise(%{"nodes" => %{"p" => entry}}, %{"id" => "p"}) end

    zero = %{
      "instances" => 0,
      "satisfied" => 0,
      "violated" => 0,
      "pending" => 0,
      "suspended" => 0
    }

    assert promise.(zero) == %{count: nil, states: [], verdict: "none opened"}

    assert promise.(%{
             zero
             | "instances" => 5,
               "satisfied" => 2,
               "violated" => 1,
               "suspended" => 2
           }) ==
             %{count: nil, states: [:failing], verdict: "2 kept, 1 broken, 2 suspended"}

    # Unconfirmed is the document's word, overlay or not; a promise the overlay merely does
    # not list — of a stale overlay, say — is claimed to be nothing.
    unverified = %{"id" => "p", "unverified" => true}
    unconfirmed = %{count: nil, states: [], verdict: "unconfirmed"}
    assert Marks.promise(%{"nodes" => %{}}, unverified) == unconfirmed
    assert Marks.promise(nil, unverified) == unconfirmed
    assert Marks.promise(%{"nodes" => %{}}, %{"id" => "p"}) == %{count: nil, states: []}
    assert Marks.promise(nil, %{"id" => "p"}) == %{count: nil, states: []}
  end
end
