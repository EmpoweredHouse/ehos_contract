defmodule EhOsContract.Vault do
  @moduledoc """
  The master keys that wrap the subjects' data keys. A data key is 32
  random bytes per subject, stored in `eh_os_contract_subject_keys` only wrapped:
  the database alone cannot decrypt a personal field.

  **The default is `EhOsContract.Vault.Local`**, which takes the master keys from
  configuration:

      # config/runtime.exs
      config :eh_os_contract, EhOsContract.Vault,
        keys: [
          {"2026-09", System.fetch_env!("EH_OS_CONTRACT_KEK")},
          {"2026-03", System.fetch_env!("EH_OS_CONTRACT_KEK_OLD")}
        ]

  **Another implementation** — a KMS — is named in `config :eh_os_contract, vault:
  MyApp.KmsVault` and implements this behaviour.

  **Rotation.** The first key wraps every new data key; the others only unwrap.
  `mix eh_os_contract.rewrap` rewraps every data key a retired master key still
  wraps, after which that key can leave the list. No event is rewritten.

  **At boot** the engine refuses to start when a contract it runs declares personal
  fields and the vault is not ready: without a master key, the first such command
  would fail rather than the deployment.
  """

  @typedoc "What names a master key, stored beside each data key it wraps."
  @type kek_id :: String.t()

  @doc """
  Wraps `key`, a data key, with the current master key. `context` is bound to the
  result: unwrapping with another context fails, so a wrapped key cannot be moved to
  another subject's row.
  """
  @callback wrap(key :: binary(), context :: binary()) :: {kek_id(), wrapped :: binary()}

  @doc "Unwraps what `wrap/2` returned, with the master key `kek_id` names."
  @callback unwrap(kek_id(), wrapped :: binary(), context :: binary()) :: {:ok, binary()} | :error

  @doc "The master key `wrap/2` wraps with now."
  @callback current() :: kek_id()

  @doc """
  Whether the vault can wrap and unwrap: `:ok`, or why not, in a sentence that
  names no key.
  """
  @callback check() :: :ok | {:error, String.t()}

  @doc "The configured implementation: `config :eh_os_contract, vault:`, `EhOsContract.Vault.Local` by default."
  @spec impl() :: module()
  def impl, do: EhOsContract.Config.get(:vault)

  @doc "Wraps `key` through the configured vault (`c:wrap/2`)."
  @spec wrap(binary(), binary()) :: {kek_id(), binary()}
  def wrap(key, context), do: impl().wrap(key, context)

  @doc "Unwraps through the configured vault (`c:unwrap/3`)."
  @spec unwrap(kek_id(), binary(), binary()) :: {:ok, binary()} | :error
  def unwrap(kek_id, wrapped, context), do: impl().unwrap(kek_id, wrapped, context)

  @doc "The configured vault's current master key (`c:current/0`)."
  @spec current() :: kek_id()
  def current, do: impl().current()

  @doc """
  Raises when `contracts` — v2 models — declare a personal field and the configured
  vault is not ready. What the engine runs at boot.
  """
  @spec check!([map()]) :: :ok
  def check!(models) do
    case Enum.filter(models, &EhOsContract.Personal.declares?/1) do
      [] ->
        :ok

      personal ->
        vault = impl()

        result =
          if Code.ensure_loaded?(vault) and function_exported?(vault, :check, 0),
            do: vault.check(),
            else: {:error, "#{inspect(vault)} does not implement #{inspect(__MODULE__)}"}

        with {:error, reason} <- result do
          raise ArgumentError,
                "#{Enum.map_join(personal, ", ", &inspect(&1.module))} declare personal fields, " <>
                  "and the vault cannot encrypt them: #{reason}"
        end
    end
  end
end
