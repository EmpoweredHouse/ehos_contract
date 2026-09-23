defmodule Taxvision.Identity do
  @moduledoc """
  Levels 1 and 2 of `Taxvision.Api`'s three: who is calling, and whether their
  token carries the role for this API at all.

  **The client application's, not the engine's.** This lived in the engine as
  `EhOsContract.Auth` until 23 September 2026, from a scope in which the engine would also
  own the dashboard's login and user management. The conformance engine takes an
  actor as an opaque subject string in `ctx.actor` and needs nothing more, so the
  verifier moved to the one application that has a request edge.

  The verifier is a dev-only HMAC over a JSON payload. What is deliberately **not**
  here: a password table, registration, sessions — identity is bought, and a real
  provider replaces `verify/1` with a JWKS check. `sign/1` exists only so that dev
  and tests have somewhere to get a token from, which is why no domain module may
  call it.
  """

  use Boundary, deps: [], exports: [Actor]

  defmodule Actor do
    @moduledoc """
    Who is performing an operation, reconstructed from the token.

    `claims` is a bag on purpose: what a tenant is — here, a company — is read
    from it by domain code, not written into this struct.
    """
    defstruct [:subject, roles: [], claims: %{}]

    @type t :: %__MODULE__{subject: String.t() | nil, roles: [String.t()], claims: map()}
  end

  @doc "Level 1: who is this."
  @spec verify(String.t() | nil) :: {:ok, Actor.t()} | {:error, :invalid_token | :missing_token}
  def verify(token) when is_binary(token) do
    with [body64, mac64] <- String.split(token, ".", parts: 2),
         {:ok, body} <- Base.url_decode64(body64, padding: false),
         {:ok, mac} <- Base.url_decode64(mac64, padding: false),
         true <- secure_compare(mac, mac(body)),
         {:ok, claims} <- Jason.decode(body) do
      {:ok,
       %Actor{
         subject: claims["sub"],
         # Roles stay strings. `String.to_atom` on data from a token would be a
         # vector for exhausting the atom table — atoms are never reclaimed.
         roles: claims["roles"] || [],
         claims: claims
       }}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def verify(_), do: {:error, :missing_token}

  @doc """
  Level 2: entitlement. One claim from the token, no network, freshness bounded by
  the token's lifetime.
  """
  @spec entitled?(Actor.t(), atom() | String.t()) :: boolean()
  def entitled?(%Actor{roles: roles}, role), do: to_string(role) in roles

  @doc "Dev and tests. Disappears when a real provider takes over."
  @spec sign(map()) :: String.t()
  def sign(claims) do
    body = Jason.encode!(claims)
    Base.url_encode64(body, padding: false) <> "." <> Base.url_encode64(mac(body), padding: false)
  end

  @spec mac(binary()) :: binary()
  defp mac(body), do: :crypto.mac(:hmac, :sha256, secret(), body)

  # A constant-time comparison. `==` on binaries stops at the first differing
  # byte, which leaks how many characters matched.
  @spec secure_compare(binary(), binary()) :: boolean()
  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    :crypto.exor(left, right) |> :binary.bin_to_list() |> Enum.reduce(0, &Bitwise.bor(&1, &2)) ==
      0
  end

  defp secure_compare(_, _), do: false

  @spec secret() :: binary()
  defp secret do
    Application.get_env(:eh_os_contract_host, __MODULE__)[:secret] ||
      raise "no secret configured for #{inspect(__MODULE__)}"
  end
end
