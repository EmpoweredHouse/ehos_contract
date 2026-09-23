defmodule EhOsContract.CommandTest do
  @moduledoc """
  Stage 5.6: **a `command` declaration, as a description.**

  A command says how a process is entered from outside and which kinds of
  principal take that way in. The engine records it and decides nothing with it:
  `EhOsContract.Command.permits?/3` derived an access decision from `principals:` until
  23 September 2026, and went with the rest of the identity layer — who may do
  what is the emitting application's question, not the conformance engine's.
  """

  use ExUnit.Case, async: true

  defmodule Contract do
    @moduledoc "INVENTED. One command per principal type, so neither is the default."

    use EhOsContract.Contract

    event :a, label: "A", payload: %{case_id: :id}, process: :p

    command :by_hand, label: "By hand", process: :p, principals: [:human]
    command :by_schedule, label: "By schedule", process: :p, principals: [:system]
    command :by_either, label: "By either", process: :p, principals: [:human, :system]

    command :sourced,
      label: "Sourced",
      process: :p,
      principals: [:human],
      source: "Event model §4, C-99, aktor A-02"

    process :p, label: "P", instance: [:case_id], accountable: "Someone"
  end

  describe "where a command came from" do
    test "a citation is carried on the declaration, not in a comment" do
      # A comment is unreadable by anything. This is part of the declaration, so it
      # is also part of the digest — correcting a citation is a change to the
      # agreement and gets recorded as one.
      assert Contract.command(:sourced).source =~ "C-99"
    end

    test "an absent one is `nil`, and says something true" do
      # Not "untidy": it says nobody has yet found this command in what the client
      # actually said. `Taxvision.Contracts.AccountingMonth`'s `:open_month` is the
      # real instance — the workshop's diagram opens the month with a cron chain and
      # names exactly one command on it, which is not that one.
      assert Contract.command(:by_hand).source == nil
    end
  end
end
