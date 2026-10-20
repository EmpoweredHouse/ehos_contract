defmodule EhOsContract.Auth.SignIn.ClientKey do
  @moduledoc false

  # The client's private key, as EHOS gives it: the file at
  # `EHOS_CLIENT_KEY_FILE` holds one Ed25519 JWK with exactly these members, and EHOS
  # checks every client assertion against the public half the deployment's status
  # names, by its `kid`. `oidcc` copies the key's `kid` into each assertion and signs
  # only with a key whose `use` is `sig` or absent, so the key is handed over as it
  # is, `kid` and `use` kept.
  #
  # A file of any other shape is refused at boot, by name and member, never with a
  # value: `d` is the secret, and an error message ends up in logs.

  @members ~w(alg crv d kid kty use x)
  @fixed %{"kty" => "OKP", "crv" => "Ed25519", "use" => "sig", "alg" => "Ed25519"}

  @doc false
  @spec load!(Path.t()) :: JOSE.JWK.t()
  def load!(path) when is_binary(path) do
    contents =
      case File.read(path) do
        {:ok, contents} -> contents
        {:error, reason} -> refuse!(path, "cannot be read: #{:file.format_error(reason)}")
      end

    if String.starts_with?(String.trim_leading(contents), "-----BEGIN") do
      refuse!(
        path,
        "is a PEM; EHOS gives the client key as a JWK, and a PEM is not read"
      )
    end

    map =
      case Jason.decode(contents) do
        {:ok, map} when is_map(map) -> map
        _other -> refuse!(path, "is not a JSON object, the one JWK EHOS says it holds")
      end

    case map |> Map.keys() |> Enum.sort() do
      @members ->
        :ok

      members ->
        refuse!(
          path,
          "must have exactly the members EHOS gives (#{Enum.join(@members, ", ")}), " <>
            "and has #{Enum.join(members, ", ")}"
        )
    end

    for {member, value} <- @fixed, map[member] != value do
      refuse!(
        path,
        "has #{member} #{inspect(map[member])}, and EHOS gives #{inspect(value)}"
      )
    end

    with {:ok, secret} <- decode(map["d"]),
         {:ok, public} <- decode(map["x"]),
         32 <- byte_size(secret),
         {^public, _secret} <- :crypto.generate_key(:eddsa, :ed25519, secret) do
      :ok
    else
      _mismatch -> refuse!(path, "has an x that is not the public half of its d")
    end

    jwk = JOSE.JWK.from_map(map)

    if map["kid"] != JOSE.JWK.thumbprint(jwk) do
      refuse!(
        path,
        "has a kid that is not the RFC 7638 thumbprint of its public half, as EHOS gives it"
      )
    end

    jwk
  end

  defp decode(value) when is_binary(value), do: Base.url_decode64(value, padding: false)
  defp decode(_value), do: :error

  defp refuse!(path, reason) do
    raise ArgumentError, "the client key file #{path} #{reason}"
  end
end
