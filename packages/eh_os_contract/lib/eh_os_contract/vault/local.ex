defmodule EhOsContract.Vault.Local do
  @moduledoc """
  `EhOsContract.Vault` with the master keys in configuration, the default:

      config :eh_os_contract, EhOsContract.Vault,
        keys: [{"2026-09", System.fetch_env!("EH_OS_CONTRACT_KEK")}]

  Each key is 32 bytes, Base64-encoded, under an id of your choosing that is stored
  beside every data key it wraps. The first wraps; the others only unwrap, until
  `mix eh_os_contract.rewrap` has moved every data key off them.

  A data key is wrapped with AES-256-GCM: a 12-byte random IV, the vault's context
  as additional data, stored as `iv <> tag <> ciphertext`.
  """

  @behaviour EhOsContract.Vault

  @impl true
  @spec wrap(binary(), binary()) :: {EhOsContract.Vault.kek_id(), binary()}
  def wrap(key, context) do
    {id, kek} = hd(keys!())
    iv = :crypto.strong_rand_bytes(12)
    {ct, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, kek, iv, key, context, true)
    {id, iv <> tag <> ct}
  end

  @impl true
  @spec unwrap(EhOsContract.Vault.kek_id(), binary(), binary()) :: {:ok, binary()} | :error
  def unwrap(id, <<iv::binary-12, tag::binary-16, ct::binary>>, context) do
    with {^id, kek} <- List.keyfind(keys!(), id, 0),
         key when is_binary(key) <-
           :crypto.crypto_one_time_aead(:aes_256_gcm, kek, iv, ct, context, tag, false) do
      {:ok, key}
    else
      _ -> :error
    end
  end

  def unwrap(_id, _wrapped, _context), do: :error

  @impl true
  @spec current() :: EhOsContract.Vault.kek_id()
  def current, do: keys!() |> hd() |> elem(0)

  @impl true
  @spec check() :: :ok | {:error, String.t()}
  def check do
    case keys() do
      {:ok, _keys} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp keys! do
    case keys() do
      {:ok, keys} -> keys
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # The configured keys, decoded: `{:ok, [{id, key}]}`, or why they cannot be used.
  # Read on every call, as configuration is: a copy kept here would outlive a
  # rotation.
  defp keys do
    configured =
      :eh_os_contract
      |> Application.get_env(EhOsContract.Vault, [])
      |> Keyword.get(:keys, [])

    decoded =
      Enum.map(configured, fn
        {id, encoded} when is_binary(id) and id != "" and is_binary(encoded) ->
          case Base.decode64(encoded) do
            {:ok, <<_::binary-32>> = key} -> {:ok, {id, key}}
            _ -> {:error, "master key #{inspect(id)} is not 32 bytes in Base64"}
          end

        _other ->
          {:error, "a master key is configured as {id, base64}, with a non-empty id"}
      end)

    ids = for {:ok, {id, _}} <- decoded, do: id

    cond do
      configured == [] ->
        {:error, "config :eh_os_contract, EhOsContract.Vault, keys: [...] names no master key"}

      error = Enum.find(decoded, &match?({:error, _}, &1)) ->
        error

      length(Enum.uniq(ids)) != length(ids) ->
        {:error, "two master keys share an id"}

      true ->
        {:ok, for({:ok, pair} <- decoded, do: pair)}
    end
  end
end
