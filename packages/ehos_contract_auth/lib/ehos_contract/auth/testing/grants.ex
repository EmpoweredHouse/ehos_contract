defmodule EhosContract.Auth.Testing.Grants do
  @moduledoc """
  The `EhosContract.Auth.Grants.Granter` of a host's tests: what
  `EhosContract.Auth.Testing.stub_grants/1` asked for the test, and every grant made, as
  `EhosContract.Auth.Grants.Local` makes it, when it asked nothing.

      # config/test.exs
      config :ehos_contract_auth, granter: EhosContract.Auth.Testing.Grants
  """

  @behaviour EhosContract.Auth.Grants.Granter

  alias EhosContract.Auth.Grants
  alias EhosContract.Auth.Grants.{Grant, Local}
  alias EhosContract.Auth.Testing

  @impl true
  @doc "The grant, as the test asked."
  @spec grant(Plug.Conn.t() | map(), [Grants.grant_option()]) ::
          {:ok, Grant.t()} | {:error, Grants.reason()}
  def grant(session, grant) do
    case Testing.stubbed!(:grants, :made) do
      :made -> Local.grant(session, grant)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  @doc "The revocation, as the test asked."
  @spec revoke(Plug.Conn.t() | map(), String.t(), String.t()) ::
          {:ok, %{role_binding_id: String.t(), role: String.t()}} | {:error, Grants.reason()}
  def revoke(session, person_id, role) do
    case Testing.stubbed!(:grants, :made) do
      :made -> Local.revoke(session, person_id, role)
      {:error, reason} -> {:error, reason}
    end
  end
end
