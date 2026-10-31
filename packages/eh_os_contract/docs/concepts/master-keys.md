# Manage the master keys

This page tells how to rotate a master key, and how to keep the master keys in a key management
service. It is for a developer or an operator of an application whose contracts declare personal
fields. [The glossary](../glossary.md) defines each word in italics.

A *master key* wraps the *data key* of each subject.
[How does the engine keep and erase personal data?](personal-data.md) tells why.

## Before you start

- You can deploy the application two or more times, one deploy after the other.
- You can run a Mix task on the database of the application, or call a function from a release.
- To rotate a key in the configuration, the application uses the vault `EhOsContract.Vault.Local`,
  as [Getting started](../getting-started.md) tells.

## Rotate a master key

The vault wraps each new data key with the first key of its list. It unwraps a data key with the
key that wrapped it. A node whose list does not hold that key cannot unwrap the data key. So you
rotate a key in four steps, with three deploys.

Do not put the new key first in one deploy. If you do, the nodes that still run the old list cannot
read what the new nodes write, until the rollout ends.

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

3. When each node runs the configuration of step 2, rewrap each data key with the new key:

   ```bash
   mix eh_os_contract.rewrap
   ```

   A release has no `mix`. From a release, call `EhOsContract.Personal.rewrap!(MyApp.Repo)`.

   **Result:** the task prints how many data keys it rewrapped, and does not raise. The task does
   not rewrite an event.

   The rewrap runs in batches of 500 data keys, each in its own transaction. If it stops or raises,
   run it again. If a data key is still on another master key at the end, the rewrap raises: a node
   still wrapped with the old key.

   Run the rewrap at a quiet time. An erasure of a subject in the current batch waits for that batch,
   and holds the append lock while it waits. So each other append waits too.

4. Do this step only when step 3 ended without an error. After you remove the old key, a data key
   that it still wraps cannot be unwrapped. Remove the old key from the list, and deploy.

   **Result:** the nodes use only the new key.

Then destroy the old key, when no backup that you can restore needs it.
[What does an erasure not reach?](personal-data.md#what-does-an-erasure-not-reach) tells the choices
and their costs.

## Keep the master keys in a key management service

To keep the master keys in a key management service (KMS), write a vault of your own. It
implements the behaviour `EhOsContract.Vault`:

```elixir
defmodule MyApp.KmsVault do
  @behaviour EhOsContract.Vault

  @impl true
  def wrap(data_key, context) do
    # The id must be the one `current/0` returns: the rewrap checks it.
    {current(), MyApp.Kms.encrypt!(current(), data_key, aad: context)}
  end

  @impl true
  def unwrap(key_id, wrapped, context) do
    case MyApp.Kms.decrypt(key_id, wrapped, aad: context) do
      {:ok, data_key} -> {:ok, data_key}
      {:error, _reason} -> :error
    end
  end

  @impl true
  def current, do: "projects/my-app/keys/personal-data/versions/2"

  @impl true
  def check, do: MyApp.Kms.check()
end
```

- `wrap/2` returns `{key_id, wrapped}`. The `key_id` is the id that `current/0` returns. The engine
  stores it beside the wrapped data key.
- `unwrap/3` returns `{:ok, data_key}`, or `:error`.
- Give `context` to the KMS as additional authenticated data, when you encrypt and when you
  decrypt. Then a wrapped key that moves to another subject does not unwrap. The engine depends on
  this binding: without it, a person who can write to the database can make an erased subject
  readable again.
- `check/0` returns `:ok`, or `{:error, reason}` in a sentence that names no key. If it returns an
  error and a contract declares personal fields, the engine does not start.

Then name the vault in the configuration:

<!-- not compiled: the host's configuration -->
```elixir
config :eh_os_contract, vault: MyApp.KmsVault
```

**Result:** the application starts, and wraps each new data key in the KMS.

To rotate a key in the KMS, make `current/0` return the new key, and deploy. When each node runs
it, rewrap each data key, as step 3 above tells. Disable the old key only after the rewrap ended
without an error.

The engine keeps no cache of data keys: a cache on another node would outlive an erasure. So each
read of personal data asks the vault to unwrap the keys of its subjects. With a KMS, each command
and each batch of a read model that touches personal data waits for the KMS, and counts against its
quota. A replay or a rebuild of a read model asks for each subject again. For a smaller rewrap
batch, call `EhOsContract.Personal.rewrap!(MyApp.Repo, 50)`; the Mix task takes no argument.

## What can go wrong

- **The rewrap raises.** A node still wraps with the old key. Wait until each node runs the new
  configuration, and run the rewrap again. Do not remove the old key.
- **A backup outlives an erasure.** A backup still holds the wrapped data keys. Rotate and destroy
  the master keys at an interval that is not longer than the time that you keep backups.
- **A destroyed master key cannot unwrap.** A backup that is older than a destroyed master key
  cannot unwrap the data of any subject.

## Next steps

- [How does the engine keep and erase personal data?](personal-data.md): the data keys and the
  erasure.
- [The configuration](../configuration.md): each key of the engine.
- [The behaviours](../behaviours.md): `EhOsContract.Vault` and the other behaviours that an
  application can implement.
