defmodule EhosContract.Auth.People.Directory.Unconfigured do
  @moduledoc """
  The `EhosContract.Auth.People.Directory` of a release started without EHOS's
  credentials, and `EhosContract.Auth.People.directory/0`'s answer there: every call
  answers `{:error, :unavailable}`, which a page already says in words, rather than an
  empty list that reads as a company with nobody in it.
  """

  @behaviour EhosContract.Auth.People.Directory

  @impl true
  @doc "`{:error, :unavailable}`."
  @spec list(keyword()) :: {:error, :unavailable}
  def list(_opts \\ []), do: {:error, :unavailable}

  @impl true
  @doc "`{:error, :unavailable}`."
  @spec get(String.t()) :: {:error, :unavailable}
  def get(_id), do: {:error, :unavailable}
end
