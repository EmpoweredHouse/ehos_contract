defmodule PNS.Command do
  @moduledoc """
  The capability a `command` declaration derives, and the one level of access it
  can decide.

  ## Two levels, and only one of them is mechanical

  **Level 2 — may this *kind* of principal issue this command at all.** Derived
  from `principals:`, decidable with nothing but the contract and the actor, and
  what `permits?/3` answers.

  **Level 3 — may *this* principal issue it *for this subject*.** `actor_company ==
  command.company_id` is the corpus's example, and the contract that carries it
  calls it "the third IAM level, inexpressible in an identity provider's
  configuration". It stays a `rule` with a decision function and no declaration
  replaces it.

  Neither level makes the other redundant, and the corpus shows both directions:
  of the two commands declared today one has a level-3 rule that a derived
  capability cannot stand in for, and the other has no actor field anywhere — so
  for that one this is the only access control there is.

  ## Why the principal type is derived rather than declared on the actor

  `PNS.Auth.Actor` holds a subject, roles and a claims bag, and deliberately knows
  nothing about anybody's business. A principal *type* is not a role: roles are the
  client's words, and `[:human, :system]` is a property of how a request arrives.
  The engine already draws that line in one place — `PNS.Auth.system_actor/0`, the
  explicit stand-in for "no human did this" — so the type reads off that rather
  than asking every client to classify their own roles.
  """

  @doc """
  Whether this actor's kind of principal may issue this command.

  Raises for a command the contract does not declare. **Not `false`:** a denial and
  a name that does not exist are different answers, and returning the former for
  the latter means a renamed command starts denying everybody silently, which is
  the failure mode this whole declaration exists to remove.
  """
  @spec permits?(module(), atom(), PNS.Auth.Actor.t() | nil) :: boolean()
  def permits?(contract, command_name, actor) do
    command =
      contract.command(command_name) ||
        raise ArgumentError,
              "#{inspect(contract)} declares no command #{inspect(command_name)}. Declared: " <>
                "#{inspect(Enum.map(contract.commands(), & &1.name))}"

    principal_type(actor) in command.principals
  end

  @doc """
  The kind of principal an actor is.

  `nil` is `:system` for the same reason `PNS.Emitter` defaults a missing actor to
  the system stand-in: an absent actor is a scheduled job or a backfill, never an
  unidentified person.
  """
  @spec principal_type(PNS.Auth.Actor.t() | nil) :: :human | :system
  def principal_type(nil), do: :system

  def principal_type(%PNS.Auth.Actor{subject: subject}) do
    if subject == PNS.Auth.system_actor(), do: :system, else: :human
  end
end
