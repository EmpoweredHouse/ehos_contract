defmodule Rehmed.Settlement do
  @moduledoc """
  The one decision `Rehmed.Contracts.VisitSettlement` pins with examples: whether a
  settlement may be closed, given what was charged and what was paid.

  **This is the only domain code in `lib/rehmed/`, and it exists for the library
  rather than for the clinic.** `rule` points at an MFA and a rule with no example
  does not compile, so without a function neither Rehmed contract could exercise
  the two declarations that turn a contract into executable tests. It is pure: no
  repo, no schema, no process. Everything it knows arrives in one map.

  It encodes `AGG-03` invariant 1 and nothing beyond it — *payment lines sum to the
  settlement total* — because that invariant is stated, and its failure is on
  record: split payments flip sign in the incumbent, so the daily report is wrong
  on exactly the days it matters (W1 02:02:07).

  ## The partial-payment assumption, stated because it is ours

  Zero payments is a legitimate close: `C-30 Zamknij bez płatności` is a real
  transition, and `P-08` exists to notice it. Anything other than zero must match
  the total exactly.

  What nobody described is a **partial** payment — 150 against a total of 200, with
  the rest owed. It is refused here rather than modelled, because a settlement that
  can be short is a receivable, and receivables are `AGG-20`'s subject, which has
  its own lifecycle and is not this. If the clinic does take part payments, this is
  the line that is wrong.
  """

  use Boundary, deps: [PNS], exports: []

  @doc """
  Decides whether the commercial side of a visit may be closed.

  Amounts arrive in **minor units** — grosze — and the reason they are integers at
  all is in the contract's moduledoc. Sums of integers are exact; the same
  arithmetic in floats is not, and money that is added up must never be a float.
  """
  @spec decide(map()) :: [PNS.Event.intention()] | {:error, atom()}
  def decide(%{command: :close_settlement} = input) do
    %{visit_id: visit_id, total_minor: total_minor} = input

    paid_minor = input.payments |> Enum.map(& &1.amount_minor) |> Enum.sum()

    cond do
      paid_minor == 0 ->
        [PNS.event(:visit_closed_without_payment, %{visit_id: visit_id})]

      paid_minor != total_minor ->
        {:error, :payment_lines_do_not_sum_to_total}

      true ->
        [PNS.event(:visit_closed_commercially, %{visit_id: visit_id})]
    end
  end
end
