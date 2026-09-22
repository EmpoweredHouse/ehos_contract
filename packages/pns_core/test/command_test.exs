defmodule PNS.CommandTest do
  @moduledoc """
  Stage 5.6: **the capability derived from a `command` declaration.**

  One level of two, and the file exists partly to keep that boundary visible. What
  is decided here is "may this kind of principal issue this command at all".
  Whether this particular caller may issue it for this particular subject is a
  `rule` with a decision function, and no declaration replaces it.

  The corpus is why both levels are kept: of the two commands declared today, one
  has an authorization rule this cannot stand in for, and the other has no actor
  field anywhere — so for that one this is the only access control there is.
  """

  use ExUnit.Case, async: true

  defmodule Contract do
    @moduledoc "INVENTED. One command per principal type, so neither is the default."

    use PNS.Contract

    event :a, label: "A", payload: %{case_id: :id}, process: :p

    command :by_hand, label: "By hand", process: :p, principals: [:human]
    command :by_schedule, label: "By schedule", process: :p, principals: [:system]
    command :by_either, label: "By either", process: :p, principals: [:human, :system]

    process :p, label: "P", instance: [:case_id], accountable: "Someone"
  end

  defp person, do: %PNS.Auth.Actor{subject: "u-1", roles: ["accounting"], claims: %{}}
  defp system, do: %PNS.Auth.Actor{subject: PNS.Auth.system_actor(), roles: [], claims: %{}}

  describe "level 2 — which kind of principal may issue this" do
    test "a person may issue a command declared for people" do
      assert PNS.Command.permits?(Contract, :by_hand, person())
    end

    test "and may not issue one declared for the system alone" do
      refute PNS.Command.permits?(Contract, :by_schedule, person())
    end

    test "the system stand-in is recognised by its subject, not by a role" do
      # `roles` are the client's words and this set has to be the engine's, so the
      # type reads off the one place the engine already draws the line.
      assert PNS.Command.permits?(Contract, :by_schedule, system())
      refute PNS.Command.permits?(Contract, :by_hand, system())
    end

    test "a command declared for both accepts both" do
      assert PNS.Command.permits?(Contract, :by_either, person())
      assert PNS.Command.permits?(Contract, :by_either, system())
    end

    test "no actor at all is the system, not an unidentified person" do
      # The same reading `PNS.Emitter` already applies to a missing `ctx.actor`: an
      # absent actor is a scheduled job or a backfill, and treating it as a person
      # would let anonymity pass a check meant for people.
      assert PNS.Command.principal_type(nil) == :system
    end
  end

  describe "a command that is not declared" do
    test "raises rather than denying" do
      # **Not `false`.** A denial and a name that does not exist are different
      # answers, and returning the first for the second means a renamed command
      # starts refusing everybody silently — which is the failure this declaration
      # exists to remove, reintroduced one level down.
      assert_raise ArgumentError, ~r/declares no command :no_such/, fn ->
        PNS.Command.permits?(Contract, :no_such, person())
      end
    end
  end
end
