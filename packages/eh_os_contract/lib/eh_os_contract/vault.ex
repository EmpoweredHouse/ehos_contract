defmodule EhOsContract.Vault do
  @moduledoc """
  The master keys that protect personal data. A master key wraps the data key of
  each subject.

  The engine encrypts each personal field with the data key of its subject. A data
  key is 32 random bytes. The engine keeps it in the table
  `eh_os_contract_subject_keys`, only in its wrapped form. So the database alone
  cannot decrypt a personal field.

  ## Where are the master keys?

  `EhOsContract.Vault.Local` is the default vault. It reads the master keys from the
  configuration:

      # config/runtime.exs
      config :eh_os_contract, EhOsContract.Vault,
        keys: [
          {"2026-09", System.fetch_env!("EH_OS_CONTRACT_KEK")},
          {"2026-03", System.fetch_env!("EH_OS_CONTRACT_KEK_OLD")}
        ]

  - The first key of the list wraps each new data key.
  - Each key of the list unwraps the data keys that it wrapped.
  - A node whose list does not hold a key cannot unwrap the data keys of that key.

  To keep the master keys in a key management service, write a module that
  implements this behaviour. Then name it in the configuration:

      config :eh_os_contract, vault: MyApp.KmsVault

  [Manage the keys and the backups of personal data](master-keys.md) has an example.

  ## Rotate a master key

  You rotate a master key in four steps, with three deploys.
  [Manage the keys and the backups of personal data](master-keys.md) gives the
  result of each step.

  Do not put the new key first in one deploy. If you do, the nodes with the old list
  cannot read what the nodes with the new list write, until the rollout ends.

  1. Add the new key after the current key, and deploy. Then each node can unwrap
     what the new key will wrap.
  2. Move the new key to the first place, and deploy.
  3. Wait until each node runs the configuration of step 2. Then run
     `mix eh_os_contract.rewrap --expect <id of the new key>` with the configuration
     of step 2. If the first key of its list is another key, the task stops before it
     changes a data key.
  4. Do this step only when step 3 ended without an error. Just before the deploy,
     count the data keys of each master key. Each row must name the new key, or a key
     that `destroyed:` names:

         SELECT kek_id, count(*) FROM eh_os_contract_subject_keys GROUP BY kek_id;

     Then remove the old key from the list, and deploy.

  The check of step 4 is necessary. A node that still runs the configuration of
  step 1 wraps each new data key with the old key, also after the rewrap. After you
  remove the old key, nothing can unwrap those data keys. If you skip the check, the
  engine finds those data keys at the next boot, and does not start.

  A rotation does not rewrite an event.

  ## What does the engine check at boot?

  If a contract declares a personal field, the engine calls `c:check/0` of the vault
  at boot. The engine does not start if it returns an error, or if the vault does not
  export `check/0`. So the default vault with no master key stops the deployment, not
  the first command with a personal field.

  Then the engine unwraps one stored data key of each master key that the table
  `eh_os_contract_subject_keys` names. If one does not unwrap, the engine does not
  start. Its error gives the id of that master key and the count of its data keys.
  This occurs when you remove a master key that still wraps data keys, or when you
  change the bytes of a key and keep its id.

  To start again, put that master key back in the vault, with the bytes that wrapped
  its data keys, and deploy. To remove it, first run
  `mix eh_os_contract.rewrap --expect <id of the current key>`.

  If you changed the bytes of a key and kept its id, its data keys can need two sets
  of bytes: the old bytes for the data keys from before the change, the new bytes for
  the data keys from after it. No list of keys of `EhOsContract.Vault.Local` unwraps
  both, because one id names one set of bytes. The engine tries only one data key
  of each master key, so the check can pass. Then a read of a data key of the other
  set raises an `ArgumentError`.

  The engine does not try a wrap at boot. So a vault whose `c:check/0` returns `:ok`
  starts, even if its wrap fails. The engine unwraps one data key of each master
  key, not each data key.

  ## A master key that you destroyed

  A master key that you destroyed cannot come back. A backup that is older than the
  rewrap can still hold data keys that it wrapped. While a data key names it, the
  engine does not start. To start, name the key in the configuration:

      config :eh_os_contract, EhOsContract.Vault,
        keys: [{"2026-09", System.fetch_env!("EH_OS_CONTRACT_KEK")}],
        destroyed: ["2026-03"]

  - The engine does not unwrap the data keys of a destroyed key when it reads. At
    boot, it tries one of them: if the vault unwraps it, the key is not destroyed,
    and the engine does not start.
  - The engine reads each subject with such a data key as erased: each personal field
    of the subject reads as `EhOsContract.Erased`, and a command that carries new
    personal data of the subject returns `{:error, :subject_erased}`.
  - The rewrap leaves those data keys as they are.
  - At boot, the engine logs a warning with the count of those data keys.
  - `EhOsContract.erase/3` deletes those data keys and records the erasure. Then the
    warning stops.

  The engine does not start if `destroyed:` names the key that the vault wraps with,
  or a key whose data key the vault unwraps at boot.
  [Start on a backup whose master key you destroyed](master-keys.md#start-on-a-backup-whose-master-key-you-destroyed)
  gives the steps.
  """

  @typedoc "What names a master key, stored beside each data key it wraps."
  @type kek_id :: String.t()

  @doc """
  Wraps `key`, a data key, with the current master key. Returns the id of that
  master key and the wrapped key.

  The wrapped key is bound to `context`. An unwrap with another context fails. So a
  wrapped key does not unwrap in the row of another subject.
  """
  @callback wrap(key :: binary(), context :: binary()) :: {kek_id(), wrapped :: binary()}

  @doc """
  Unwraps a key that `wrap/2` returned, with the master key that `kek_id` names and
  the same `context`. Returns `:error` if the vault does not hold that master key, or
  if the context or the wrapped key is not the same.

  If a contract declares a personal field, the engine also calls it at boot, one time
  for each master key that a stored data key names. At boot, `:error` stops the
  engine, with an error that tells the operator to check the master key. For a master
  key that `destroyed:` names, `:error` is the answer that lets the engine start.

  For a master key that the key management service deleted, or holds for deletion,
  return `:error`. Do not raise.

  If the vault cannot answer now, for example because a key management service is
  down, raise. Do not return `:error`. The engine does not start while the service
  is down, so give each call a timeout. Do not put `context` or the wrapped key in
  the exception: the context holds the id of the subject.
  """
  @callback unwrap(kek_id(), wrapped :: binary(), context :: binary()) :: {:ok, binary()} | :error

  @doc "The id of the master key that `wrap/2` uses now."
  @callback current() :: kek_id()

  @doc """
  Tells if the vault can wrap and unwrap. Returns `:ok`, or the reason as a sentence.
  The sentence can name the id of a key, never the key itself.
  """
  @callback check() :: :ok | {:error, String.t()}

  # The configured implementation: `config :eh_os_contract, vault:`, `EhOsContract.Vault.Local` by default.
  @doc false
  @spec impl() :: module()
  def impl, do: EhOsContract.Config.get(:vault)

  # Wraps `key` through the configured vault (`c:wrap/2`).
  # Called by personal.ex.
  @doc false
  @spec wrap(binary(), binary()) :: {kek_id(), binary()}
  def wrap(key, context), do: impl().wrap(key, context)

  # Unwraps through the configured vault (`c:unwrap/3`).
  # Called by personal.ex.
  @doc false
  @spec unwrap(kek_id(), binary(), binary()) :: {:ok, binary()} | :error
  def unwrap(kek_id, wrapped, context), do: impl().unwrap(kek_id, wrapped, context)

  # The configured vault's current master key (`c:current/0`).
  # Called by eh_os_contract.rewrap.ex, personal.ex.
  @doc false
  @spec current() :: kek_id()
  def current, do: impl().current()

  # The master keys that `config :eh_os_contract, EhOsContract.Vault, destroyed:` names.
  # Called by personal.ex.
  @doc false
  @spec destroyed() :: [kek_id()]
  def destroyed, do: __MODULE__ |> EhOsContract.Config.get() |> Keyword.get(:destroyed, [])

  # Raises when `contracts` — v2 models — declare a personal field and the configured
  # vault is not ready. What the engine runs at boot.
  @doc false
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

        case result do
          :ok ->
            check_current!(vault.current())

          {:error, reason} ->
            raise ArgumentError,
                  "#{Enum.map_join(personal, ", ", &inspect(&1.module))} declare personal fields, " <>
                    "and the vault cannot encrypt them: #{reason}"
        end
    end
  end

  # A data key wrapped by a key named destroyed would read as erased as soon as it is
  # stored.
  defp check_current!(current) do
    if current in destroyed() do
      raise ArgumentError,
            "config :eh_os_contract, EhOsContract.Vault, destroyed: names #{inspect(current)}, " <>
              "the master key that the vault wraps with. Name only the master keys that you " <>
              "destroyed"
    end

    :ok
  end
end
