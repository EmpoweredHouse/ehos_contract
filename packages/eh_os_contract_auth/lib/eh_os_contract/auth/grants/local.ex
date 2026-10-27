defmodule EhOsContract.Auth.Grants.Local do
  @moduledoc """
  Every grant answered as made, for development: an `EhOsContract.Auth.Grants.Granter`
  that never calls EHOS and keeps nothing.

      # config/dev.exs
      config :eh_os_contract_auth, granter: EhOsContract.Auth.Grants.Local

  A grant answers an `EhOsContract.Auth.Grants.Grant` of a person invited, the role
  bound now and a link mailed. The person's id is a UUID derived from the email, the
  same for the same address in either case, and never the email itself, so an
  application that keeps it keeps what it would keep from EHOS. A revocation answers the
  binding it would have removed.

  It takes the arguments `EhOsContract.Auth.Grants` takes, and raises `ArgumentError` for
  the ones EHOS's would raise for, so development fails where a release would.
  """

  @behaviour EhOsContract.Auth.Grants.Granter

  alias EhOsContract.Auth.Grants
  alias EhOsContract.Auth.Grants.Grant

  @impl true
  @doc "A grant of `role` to the person `email:` names, answered as made."
  @spec grant(Plug.Conn.t() | map(), [Grants.grant_option()]) :: {:ok, Grant.t()}
  def grant(_session, grant) do
    %{"email" => email, "role" => role} = Grants.grant!(grant)
    person_id = person_id(email)

    {:ok,
     %Grant{
       person_id: person_id,
       email: email,
       state: :invited,
       role: role,
       role_binding_id: uuid([person_id, role]),
       bound: :now,
       delivery: :mailed
     }}
  end

  @impl true
  @doc "The binding of `role` to `person_id`, answered as removed."
  @spec revoke(Plug.Conn.t() | map(), String.t(), String.t()) ::
          {:ok, %{role_binding_id: String.t(), role: String.t()}}
  def revoke(_session, person_id, role)
      when is_binary(person_id) and is_binary(role) and role != "" do
    person_id = String.downcase(person_id)
    {:ok, %{role_binding_id: uuid([person_id, role]), role: role}}
  end

  def revoke(_session, _person_id, _role),
    do: raise(ArgumentError, "revoke/3 takes the person's id and the role, each a string")

  @doc """
  The id `grant/2` answers for `email`: the same for the same address in either case.

      iex> EhOsContract.Auth.Grants.Local.person_id("Ada@Example.com") ==
      ...>   EhOsContract.Auth.Grants.Local.person_id("ada@example.com")
      true
  """
  @spec person_id(String.t()) :: String.t()
  def person_id(email) when is_binary(email), do: uuid([String.downcase(email)])

  # A version 8 UUID, as EHOS's ids are UUIDs, of a hash that carries nothing readable.
  defp uuid(parts) do
    <<a::48, _::4, b::12, _::2, c::62, _::binary>> =
      :crypto.hash(:sha256, Enum.join([inspect(__MODULE__) | parts], <<0>>))

    <<a::48, 8::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> then(fn <<p1::binary-8, p2::binary-4, p3::binary-4, p4::binary-4, p5::binary-12>> ->
      Enum.join([p1, p2, p3, p4, p5], "-")
    end)
  end
end
