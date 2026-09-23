defmodule Taxvision.Authorization do
  @moduledoc """
  **The third IAM level: the domain rule. Ours, not bought.**

  The identity provider answers who this is (level 1) and whether that person can
  reach the accounting API at all (level 2, a role grant as a claim). It cannot
  express what is below in any configuration, because it does not know what an
  accounting month is or whose company this is.

  So the rule sits in the contract as a `rule` with examples, exactly like any
  other business rule — and is tested the same way. If it could be written as a
  policy in the provider's console, the seam would be in the wrong place.

  A pure function: no database access, no knowledge of tokens.
  """

  use Boundary, deps: [], exports: []

  @doc "The month is opened by the accountant assigned to that company."
  @spec authorize_open_month(map()) :: :ok | {:error, atom()}
  def authorize_open_month(%{command: :open_month} = input) do
    roles = input[:actor_roles] || []

    cond do
      "accounting" not in roles -> {:error, :not_accounting}
      input[:actor_company] != input[:company_id] -> {:error, :not_this_company}
      true -> :ok
    end
  end
end
