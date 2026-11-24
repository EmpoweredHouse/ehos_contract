defmodule EhosContract.Auth.Grants.Unconfigured do
  @moduledoc """
  The `EhosContract.Auth.Grants.Granter` of a release started without sign-in, and
  `EhosContract.Auth.Grants.granter/0`'s answer there: every call answers
  `{:error, :unavailable}`, so the page never says it invited someone it did not.
  """

  @behaviour EhosContract.Auth.Grants.Granter

  @impl true
  @doc "`{:error, :unavailable}`."
  @spec grant(term(), term()) :: {:error, :unavailable}
  def grant(_session, _grant), do: {:error, :unavailable}

  @impl true
  @doc "`{:error, :unavailable}`."
  @spec revoke(term(), term(), term()) :: {:error, :unavailable}
  def revoke(_session, _person_id, _role), do: {:error, :unavailable}
end
