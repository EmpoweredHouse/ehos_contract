defmodule EhOsContract.Auth.Grants.Granter do
  # Issue #475: TaxVision wrote this seam with the same two callbacks.
  @moduledoc """
  Who grants and revokes a role for the signed-in person: EHOS in a release that signs
  people in, someone else in development, in a release started without EHOS, and in
  tests.

  `EhOsContract.Auth.Grants.granter/0` names the one configured, and a page asks it:

      case EhOsContract.Auth.Grants.granter().grant(conn, email: email, role: "clinic.client") do
        {:ok, %EhOsContract.Auth.Grants.Grant{person_id: id}} -> # keep the id
        {:error, reason} -> # say it in words
      end

  The package ships four:

    * `EhOsContract.Auth.Grants`, EHOS's grant routes;
    * `EhOsContract.Auth.Grants.Local`, which answers every grant as made and mailed, for
      development;
    * `EhOsContract.Auth.Grants.Unconfigured`, which answers `:unavailable`, so a release
      without sign-in never says it invited;
    * `EhOsContract.Auth.Testing.Grants`, which answers as a test asked.

  An implementation of its own takes the arguments and answers the reasons
  `EhOsContract.Auth.Grants` documents.
  """

  alias EhOsContract.Auth.Grants
  alias EhOsContract.Auth.Grants.Grant

  @doc "Grants a role, as `EhOsContract.Auth.Grants.grant/3` does."
  @callback grant(Plug.Conn.t() | map(), [Grants.grant_option()]) ::
              {:ok, Grant.t()} | {:error, Grants.reason()}

  @doc "Takes a role back, as `EhOsContract.Auth.Grants.revoke/4` does."
  @callback revoke(Plug.Conn.t() | map(), String.t(), String.t()) ::
              {:ok, %{role_binding_id: String.t(), role: String.t()}}
              | {:error, Grants.reason()}
end
