# Manage the master keys

This page tells how to rotate a master key, and how to keep the master keys in a key management
service. It is for a developer or an operator of an application whose contracts declare personal
fields. [The glossary](../glossary.md) defines each word in italics.

A *master key* wraps the *data key* of each subject.
[How does the engine keep and erase personal data?](personal-data.md) tells why.

## Before you start

- The application runs the engine with the vault `EhOsContract.Vault.Local`, as
  [Getting started](../getting-started.md) tells.
- You can deploy the application two or more times, one deploy after the other.
- You can run a Mix task on the database of the application, or call a function from a release.

## Rotate a master key

The vault wraps each new data key with the first key of its list. It unwraps a data key with the
key that wrapped it. A node whose list does not hold that key cannot unwrap the data key. So you
rotate a key in three deploys.

1. Add the new key after the current key, and deploy:

   <!-- not compiled: the host's configuration -->
   ```elixir
   config :eh_os_contract, EhOsContract.Vault,
     keys: [
       {"2026-03", System.fetch_env!("EH_OS_CONTRACT_KEK")},
       {"2026-09", System.fetch_env!("EH_OS_CONTRACT_KEK_NEW")}
     ]
   ```

   **Result:** each node can unwrap what the new key will wrap. The old key still wraps each new data
   key.

2. Move the new key to the first place, and deploy.

   **Result:** the new key wraps each new data key.

3. Rewrap each data key with the new key:

   ```bash
   mix eh_os_contract.rewrap
   ```

   A release has no `mix`. From a release, call `EhOsContract.Personal.rewrap!(MyApp.Repo)`.

   **Result:** the task prints how many data keys it rewrapped. No data key needs the old key now.
   The task does not rewrite an event.

4. Remove the old key from the list, and deploy.

Do not put the new key first in one deploy. If you do, the nodes that still run the old list cannot
read what the new nodes write, until the rollout ends.

The rewrap runs in batches of 500 data keys, each in its own transaction. You can stop it and run
it again. If a data key is still on another master key at the end, the rewrap raises.

## Keep the master keys in a key management service

To keep the master keys in a key management service (KMS), write a vault of your own. It
implements the behaviour `EhOsContract.Vault`:

```elixir
defmodule MyApp.KmsVault do
  @behaviour EhOsContract.Vault

  # Wraps a data key with the current master key of the KMS.
  @impl true
  def wrap(data_key, context), do: MyApp.Kms.encrypt(current(), data_key, context)

  # Unwraps a data key with the master key that wrapped it.
  @impl true
  def unwrap(key_id, wrapped, context), do: MyApp.Kms.decrypt(key_id, wrapped, context)

  @impl true
  def current, do: "projects/my-app/keys/personal-data/versions/2"

  # Tells if the vault can wrap and unwrap, in a sentence that names no key.
  @impl true
  def check, do: MyApp.Kms.check()
end
```

- `wrap/2` returns `{key_id, wrapped}`. The engine stores the id of the master key beside the
  wrapped data key.
- `unwrap/3` returns `{:ok, data_key}`, or `:error`.
- `context` binds the wrapped key to its subject. If a wrapped key moves to another subject, its
  unwrap fails.

Then name the vault in the configuration:

<!-- not compiled: the host's configuration -->
```elixir
config :eh_os_contract, vault: MyApp.KmsVault
```

**Result:** the application starts. If `check/0` returns an error and a contract declares personal
fields, the engine does not start.

## What can go wrong

- **A backup outlives an erasure.** A backup still holds the wrapped data keys. Rotate and destroy
  the master keys at an interval that is not longer than the time that you keep backups.
  [What does an erasure not reach?](personal-data.md#what-does-an-erasure-not-reach) tells the
  choices and their costs.
- **A destroyed master key cannot unwrap.** A backup that is older than a destroyed master key
  cannot unwrap the data of a subject.

## Next steps

- [How does the engine keep and erase personal data?](personal-data.md): the data keys and the
  erasure.
- [The configuration](../configuration.md): each key of the engine.
- [The behaviours](../behaviours.md): `EhOsContract.Vault` and the other behaviours that an
  application can implement.
