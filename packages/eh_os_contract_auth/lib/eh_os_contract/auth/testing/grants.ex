defmodule EhOsContract.Auth.Testing.Grants do
  @moduledoc """
  The `EhOsContract.Auth.Grants.Granter` of a host's tests: what
  `EhOsContract.Auth.Testing.stub_grants/1` asked for the test, and every grant made, as
  `EhOsContract.Auth.Grants.Local` makes it, when it asked nothing.

      # config/test.exs
      config :eh_os_contract_auth, granter: EhOsContract.Auth.Testing.Grants
  """

  @behaviour EhOsContract.Auth.Grants.Granter

  alias EhOsContract.Auth.Grants
  alias EhOsContract.Auth.Grants.{Grant, Local}
  alias EhOsContract.Auth.Testing

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
