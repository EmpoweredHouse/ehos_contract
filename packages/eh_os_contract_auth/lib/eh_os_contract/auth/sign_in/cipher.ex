defmodule EhOsContract.Auth.SignIn.Cipher do
  @moduledoc false

  # S3 in docs/adr/browser-session.md: what a session row holds of EHOS's tokens is encrypted
  # with a key derived from the host's `SECRET_KEY_BASE`, so a backup, a replica, a dump or an SQL
  # injection elsewhere reads nothing it can present. `plug_crypto` 2.x encrypts with
  # XChaCha20-Poly1305, and the associated data binds each ciphertext to its row and column: one
  # copied to another row, or to another column of the same row, does not decrypt.

  alias Plug.Crypto.{KeyGenerator, MessageEncryptor}

  # The package's own, so the key is not one the host derives for anything else from the same
  # secret, such as its cookie session's.
  @salt "eh_os_contract_auth sign-in session tokens"

  @doc false
  @spec key(String.t()) :: binary()
  def key(secret_key_base), do: KeyGenerator.generate(secret_key_base, @salt, length: 32)

  @doc false
  @spec encrypt(String.t(), binary(), binary()) :: String.t()
  def encrypt(value, key, bound_to), do: MessageEncryptor.encrypt(value, bound_to, key, key)

  @doc false
  @spec decrypt(String.t(), binary(), binary()) :: {:ok, String.t()} | :error
  def decrypt(ciphertext, key, bound_to) do
    case MessageEncryptor.decrypt(ciphertext, bound_to, key, key) do
      {:ok, value} -> {:ok, value}
      :error -> :error
    end
  end

  @doc "What a value of `column` in the row of `token_hash` is bound to."
  @spec bound_to(binary(), String.t()) :: binary()
  def bound_to(token_hash, column), do: token_hash <> "/" <> column
end
