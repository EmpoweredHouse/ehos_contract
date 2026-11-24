defmodule EhosContract.Auth.Signing do
  @moduledoc false

  # A credential in EHOS's form signed by a key of this application, and a session written for
  # it as a sign-in through EHOS writes one: what `EhosContract.Auth.Testing` and
  # `EhosContract.Auth.Development` both do, so the two cannot drift apart.

  alias EhosContract.Auth.SignIn
  alias EhosContract.Auth.SignIn.Sessions

  # EHOS's: ten minutes.
  @lifetime 600

  @doc false
  # A credential for `subject` with `capabilities` and `scopes`, the configured `iss` and `aud`,
  # living ten minutes from `now`, signed by `private` under `kid`; and when it expires.
  @spec credential(map(), String.t(), String.t(), [String.t()], map(), DateTime.t()) ::
          {String.t(), DateTime.t()}
  def credential(private, kid, subject, capabilities, scopes, now) do
    config = Application.get_all_env(:ehos_contract_auth)
    now = DateTime.to_unix(now)

    claims =
      %{
        "iss" => Keyword.fetch!(config, :issuer),
        "aud" => Keyword.fetch!(config, :audience),
        "sub" => subject,
        "iat" => now,
        "exp" => now + @lifetime,
        "jti" => Ecto.UUID.generate(),
        "cap" => Enum.sort(capabilities)
      }
      |> then(&if scopes == %{}, do: &1, else: Map.put(&1, "scp", scopes))

    signer = Joken.Signer.create("Ed25519", private, %{"kid" => kid})
    {:ok, token, _claims} = Joken.encode_and_sign(claims, signer)
    {token, DateTime.from_unix!(claims["exp"])}
  end

  @doc false
  # A session of `subject` holding `token`, through the sign-in child `name`; answers the token
  # the browser keeps. EHOS's tokens it has none of are random values marked by `prefix`.
  @spec session(atom(), String.t(), String.t(), DateTime.t(), String.t()) :: {:ok, String.t()}
  def session(name, subject, token, expires_at, prefix) do
    unique = fn -> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false) end

    Sessions.create(name, %{
      subject: subject,
      sid: prefix <> "-sid-" <> unique.(),
      auth_time: EhosContract.Clock.now(),
      refresh_token: prefix <> "-refresh-" <> unique.(),
      id_token: prefix <> "-id-" <> unique.(),
      credential: %{resource: SignIn.config(name).address, token: token, expires_at: expires_at}
    })
  end
end
