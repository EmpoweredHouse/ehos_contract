defmodule EhOsContract.AuthorizerTest do
  @moduledoc """
  The decision a credential's actor is held to (v2 §11, D14), and the rule that an
  implementation can narrow it and never widen it.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.{Actor, Authorizer}
  alias EhOsContract.Authorizer.Request

  @query "rehmed.open_visits_for_clinic"

  defp request(capability, scope \\ nil),
    do: %Request{
      kind: :query,
      capability: capability,
      contract: __MODULE__,
      contract_id: "authorizer_test.contract",
      version: "v",
      scope: scope
    }

  defp anna(scopes \\ %{}),
    do: Actor.credential("u-1", ["rehmed.record_payment", @query], scopes)

  describe "check/2" do
    test "a capability the credential does not grant is refused; one it grants passes" do
      assert Authorizer.check(anna(), request("rehmed.close_settlement")) ==
               {:error, :missing_capability}

      assert Authorizer.check(anna(), request("rehmed.record_payment")) == :ok
    end

    test "a scoped value within the grant passes, and one outside it is refused" do
      actor = anna(%{@query => %{"clinic_id" => ["12", "7"]}})

      assert Authorizer.check(actor, request(@query, {"clinic_id", "7"})) == :ok

      assert Authorizer.check(actor, request(@query, {"clinic_id", "9"})) ==
               {:error, :outside_scope}
    end

    test "a scoped capability with no values is refused: empty is not all" do
      assert Authorizer.check(anna(), request(@query, {"clinic_id", "7"})) ==
               {:error, :unscoped_grant}

      assert Authorizer.check(
               anna(%{@query => %{"clinic_id" => []}}),
               request(@query, {"clinic_id", "7"})
             ) ==
               {:error, :unscoped_grant}

      # Values for another dimension grant nothing along this one.
      assert Authorizer.check(
               anna(%{@query => %{"region" => ["7"]}}),
               request(@query, {"clinic_id", "7"})
             ) ==
               {:error, :unscoped_grant}
    end

    test "a scoped query asked without a value is outside the grant" do
      actor = anna(%{@query => %{"clinic_id" => ["7"]}})

      assert Authorizer.check(actor, request(@query, {"clinic_id", nil})) ==
               {:error, :outside_scope}
    end

    test "values are compared as the credential's strings, so a value of another type never matches" do
      actor = anna(%{@query => %{"clinic_id" => ["07", "seven"]}})

      assert Authorizer.check(actor, request(@query, {"clinic_id", "7"})) ==
               {:error, :outside_scope}
    end
  end

  describe "run/3" do
    defmodule Refuses do
      @behaviour EhOsContract.Authorizer
      @impl true
      def authorize(_actor, _request), do: {:error, :suspended}
    end

    defmodule Widens do
      @behaviour EhOsContract.Authorizer
      @impl true
      def authorize(_actor, _request), do: :ok
    end

    test "an implementation's refusal is the answer, with its own reason" do
      assert Authorizer.run(anna(), request("rehmed.record_payment"), Refuses) ==
               {:error, :suspended}
    end

    test "an implementation that allows what the credential does not grant raises" do
      assert_raise Authorizer.WidenedError, ~r/may narrow a grant, never widen it/, fn ->
        Authorizer.run(anna(), request("rehmed.close_settlement"), Widens)
      end

      assert_raise Authorizer.WidenedError, fn ->
        Authorizer.run(anna(), request(@query, {"clinic_id", "7"}), Widens)
      end
    end

    test "control: the same permissive implementation passes what the credential grants" do
      assert Authorizer.run(anna(), request("rehmed.record_payment"), Widens) == :ok
    end

    test "the default implementation is check/2" do
      assert Authorizer.impl() == Authorizer.Default

      assert Authorizer.run(anna(), request("rehmed.close_settlement")) ==
               {:error, :missing_capability}
    end
  end

  describe "Actor" do
    test "a credential carries its claims as strings, unconverted" do
      actor = Actor.credential("u-1", ["a.b"], %{"a.b" => %{"x" => ["1"]}})
      assert actor.kind == :credential
      assert MapSet.member?(actor.capabilities, "a.b")
      assert Actor.label(actor) == "actor:u-1"

      assert_raise ArgumentError, fn -> Actor.credential("u-1", [:a_b]) end

      assert_raise ArgumentError, fn ->
        Actor.credential("u-1", ["a.b"], %{"a.b" => %{x: [1]}})
      end
    end

    test "the application's own actors are labelled by what they are" do
      assert Actor.label(Actor.system(:referral_intake)) == "system:referral_intake"
      assert Actor.label(Actor.reaction(:policy, :invoice_on_close)) == "policy:invoice_on_close"
    end
  end
end
