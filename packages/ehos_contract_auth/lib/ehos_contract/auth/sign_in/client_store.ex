defmodule EhosContract.Auth.SignIn.ClientStore do
  @moduledoc false

  # What `oidcc_plug` asks for the client context (`client_store:`), S1 as amended: the context is
  # built from what the sign-in child holds, for this one call, by `SignIn.client_context/1`. The
  # router puts the child's name in the connection's private map.
  #
  # No `refresh_jwks/1`: it is handed the context alone, which does not say which child it came
  # from, and the child refetches EHOS's keys every five minutes on its own.

  @behaviour Oidcc.Plug.ClientStore

  alias EhosContract.Auth.SignIn

  @doc false
  @impl Oidcc.Plug.ClientStore
  @spec get_client_context(Plug.Conn.t()) ::
          {:ok, Oidcc.ClientContext.t()} | {:error, SignIn.unavailable()}
  def get_client_context(conn) do
    conn.private
    |> Map.get(:ehos_contract_auth_sign_in, SignIn)
    |> SignIn.client_context()
  end
end
