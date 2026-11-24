defmodule Lending.Traffic do
  @moduledoc """
  **Invented.** The library's part of `mix sandbox.traffic`: about six weeks of members,
  loans and holds, drift included. Each step is how many hours ago it happened, what
  happened, and a function giving the operations to run then, which the task runs and
  checks (`Mix.Tasks.Sandbox.Traffic`).

  - Ada's copy comes back late and its fee is never settled: past thirty days, the fee's
    promise is broken. Her second copy is still out after three weeks, chased weekly: the
    loan's promise is broken, and the next reminder waits.
  - Cy's late fee is waived, and Dora's paid. Cy's second copy comes back on time.
  - Dora's last copy went out three days ago, its reminder still waiting.
  - Bob's card is suspended, so his loan is refused, and Dora's hold on the copy Cy holds
    is refused. Nobody asks to hold the withdrawn copy.
  """

  alias Lending.Contracts.{Circulation, Membership}

  alias Lending.Contracts.Circulation.Commands.{
    LendCopy,
    PayLateFee,
    PlaceHold,
    ReturnCopy,
    WaiveLateFee,
    WithdrawCopy
  }

  alias Lending.Contracts.Membership.Commands.{ChangeEmail, RegisterMember}

  alias EhosContract.{Actor, Clock}

  @librarian Actor.credential(
               "librarian-una",
               ~w(lending.register_member lending.change_email lending.lend_copy
                  lending.return_copy lending.pay_late_fee lending.waive_late_fee
                  lending.withdraw_copy)
             )

  @doc "The steps, as `{hours_ago, what, operations}`."
  @spec steps() :: [{number(), String.t(), (-> [tuple()])}]
  def steps, do: members() ++ loans() ++ holds()

  defp members do
    [
      {1070, "Ada registered", fn -> register("ada", "Ada Lovelace", "ada@example.org") end},
      {1069, "Bob registered", fn -> register("bob", "Bob Byte", "bob@example.org") end},
      {1068, "Cy registered", fn -> register("cy", "Cy Cipher", "cy@example.org") end},
      {1067, "Dora registered", fn -> register("dora", "Dora Data", "dora@example.org") end},
      {600, "Ada's e-mail changed",
       fn ->
         [
           {:ok, Membership,
            %ChangeEmail{
              membership_id: "membership-ada",
              member_id: "member-ada",
              email: "ada@example.net"
            }, @librarian}
         ]
       end}
    ]
  end

  # A loan's due date is `due` hours after it is lent.
  defp loans do
    [
      {864, "Ada borrows copy-1, due in two days", fn -> lend("loan-1", "ada", 48) end},
      {804, "Ada returns copy-1 late, charged 1.50", fn -> return("loan-1", 150) end},
      {720, "Cy borrows copy-2, due in a week", fn -> lend("loan-2", "cy", 7 * 24) end},
      {480, "Cy returns copy-2 three days late, charged 3.00", fn -> return("loan-2", 300) end},
      {456, "Cy's fee waived",
       fn -> [{:ok, Circulation, %WaiveLateFee{loan_id: "loan-2"}, @librarian}] end},
      {360, "Dora borrows copy-3, due in three days", fn -> lend("loan-3", "dora", 72) end},
      {264, "Dora returns copy-3 late, charged 1.00", fn -> return("loan-3", 100) end},
      {200, "Dora pays her fee",
       fn -> [{:ok, Circulation, %PayLateFee{loan_id: "loan-3"}, @librarian}] end},
      {600, "Ada borrows copy-4, due in two weeks", fn -> lend("loan-4", "ada", 14 * 24) end},
      {300, "Cy borrows copy-5, due in two weeks", fn -> lend("loan-5", "cy", 14 * 24) end},
      {100, "Cy returns copy-5 on time", fn -> return("loan-5", 0) end},
      {72, "Dora borrows copy-6, due in two weeks", fn -> lend("loan-6", "dora", 14 * 24) end},
      {500, "Bob's loan of copy-7 is refused: his card is suspended",
       fn ->
         [
           {:refused, Circulation, lending("loan-7", "bob", 14 * 24), @librarian,
            :suspended_card_borrows_nothing}
         ]
       end}
    ]
  end

  defp holds do
    [
      {400, "Cy places a hold on copy-8",
       fn -> [{:ok, Circulation, hold("copy-8", "cy"), patron("cy")}] end},
      {399, "Dora's hold on copy-8 is refused: Cy holds it",
       fn ->
         [{:refused, Circulation, hold("copy-8", "dora"), patron("dora"), :one_hold_per_copy}]
       end},
      {380, "copy-9 withdrawn from circulation",
       fn -> [{:ok, Circulation, %WithdrawCopy{copy_id: "copy-9"}, @librarian}] end}
    ]
  end

  defp register(name, full_name, email) do
    [
      {:ok, Membership,
       %RegisterMember{
         membership_id: "membership-#{name}",
         member_id: "member-#{name}",
         name: full_name,
         email: email
       }, @librarian}
    ]
  end

  defp lend(loan, name, due), do: [{:ok, Circulation, lending(loan, name, due), @librarian}]

  defp lending(loan, name, due) do
    %LendCopy{
      loan_id: loan,
      copy_id: "copy-" <> String.trim_leading(loan, "loan-"),
      member_id: "member-#{name}",
      card_id: "card-#{name}",
      due_at: DateTime.add(Clock.now(), due * 3600)
    }
  end

  # The application's own dispatch gives the fee the desk's tariff would.
  defp return(loan, fee),
    do: [{:ok, Circulation, %ReturnCopy{loan_id: loan, late_fee: fee}, @librarian}]

  defp hold(copy, name), do: %PlaceHold{copy_id: copy, member_id: "member-#{name}"}

  defp patron(name), do: Actor.credential("member-#{name}", ["lending.place_hold"])
end
