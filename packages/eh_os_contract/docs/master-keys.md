# Manage the keys and the backups of personal data

This page tells how to rotate a master key, and how to keep the master keys in a key management
service. It also tells how to restore a backup that is older than an erasure, and how to start the
engine on a backup whose master key you destroyed. It is for a developer or an operator of an application whose contracts declare personal
fields. [The glossary](glossary.md) defines each word in italics.

A *master key* wraps the *data key* of each subject.
[How does the engine keep and erase personal data?](personal-data.md) tells why.

## Before you start

- You can deploy the application two or more times, one deploy after the other.
- You can run a Mix task on the database of the application, or call a function from a release.
- To rotate a key in the configuration, the application uses the vault `EhOsContract.Vault.Local`,
  as [Getting started](getting-started.md) tells.
- To restore a backup that is older than an erasure, you keep a record of each erasure outside the
  database. Write it before you call `erase/3`. It holds the type and the id of the subject, the
  time, and who asked. It holds no value of an erased field. Keep each record as long as the oldest
  backup.
- An id of a subject, or the name of who asked, can still identify a person. Keep the record under
  the same privacy controls as your other records of people.

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

3. When each node runs the configuration of step 2, rewrap each data key with the new key. Run the
   rewrap with the configuration of step 2 too. It wraps with the first key of the list that it
   reads. Give it the id of the new key. If the first key of the list is another key, the rewrap
   stops before it changes a data key.

   ```bash
   mix eh_os_contract.rewrap --expect 2026-09
   ```

   A release has no `mix`. From a release, call
   `EhOsContract.Personal.rewrap!(MyApp.Repo, "2026-09")`.

   **Result:** the task prints how many data keys it rewrapped, and the id of the key that it used.
   Example: `120 data keys rewrapped with 2026-09`. The id must be the id of the new key. The
   task does not rewrite an event.

   The rewrap runs in batches of 500 data keys, each in its own transaction. If it stops, run it
   again. "What can go wrong" below tells what to do when it raises.

   Run the rewrap at a quiet time. An erasure of a subject in the current batch waits for that batch,
   and holds the append lock while it waits. So each other append waits too.

4. Do this step only when step 3 ended without an error, with the id of the new key. After you
   remove the old key, a data key that it still wraps cannot be unwrapped. Check the table of data
   keys just before the deploy. Each row must name the new key, or a key that `destroyed:` names:

   ```sql
   SELECT kek_id, count(*) FROM eh_os_contract_subject_keys GROUP BY kek_id;
   ```

   Then remove the old key from the list, and deploy.

   **Result:** the nodes use only the new key. If a data key still names the old key, the engine
   does not start. "What can go wrong" below tells what to do.

Then destroy the old key, within the time that you keep backups. After that, a backup that holds a
data key wrapped by the old key cannot unwrap it.
[What does an erasure not reach?](personal-data.md#what-does-an-erasure-not-reach) tells why, and
what it costs.

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
  decrypt. Then a wrapped key that moves to the row of another subject does not unwrap. The engine
  depends on this binding.
- `check/0` returns `:ok`, or `{:error, reason}` in a sentence that names no key. If it returns an
  error and a contract declares personal fields, the engine does not start.

Then name the vault in the configuration:

<!-- not compiled: the host's configuration -->
```elixir
config :eh_os_contract, vault: MyApp.KmsVault
```

**Result:** the application starts, and wraps each new data key in the KMS.

`current/0` names the version of the key that wraps, not only the key. If the KMS rotates the
version behind one name, the rewrap cannot see that the version changed.

To rotate a key in the KMS, make `current/0` return the new version, and deploy. When each node runs
it, rewrap each data key, as step 3 above tells. Disable the old key only after the rewrap ended
without an error, and after the check of step 4: each row of `eh_os_contract_subject_keys` must
name the new version. A node that still returns the old version wraps new data keys with it, also
after the rewrap.

The engine keeps no cache of data keys: a cache on another node would outlive an erasure. So each
read of personal data asks the vault to unwrap the keys of its subjects. With a KMS, each command
and each batch of a read model that touches personal data waits for the KMS, and counts against its
quota. A replay or a rebuild of a read model asks for each subject again. For a smaller rewrap
batch, give the id that `current/0` returns, and the batch size; the Mix task takes no batch size:

<!-- not compiled: the host's repository and key -->
```elixir
EhOsContract.Personal.rewrap!(MyApp.Repo, "projects/my-app/keys/personal-data/versions/2", 50)
```

<a id="restore-a-backup-older-than-an-erasure"></a>

## Restore a backup older than an erasure

A backup that is older than an erasure holds the data key of the subject, and no record of the
erasure. A restored backup can also hold queued effect jobs and subscriptions that are behind. If
they run, they read the personal data of the erased subject and can send it out. So repeat the
erasures before anything reads the log.

1. Start each node of the application without its consumers and without its endpoint. Use
   `config :eh_os_contract, subscriptions: :manual`, `queues: false` for Oban, and
   `server: false` for the endpoint.

   **Result:** no effect job, timer, relay or subscription runs, and no request arrives. Steps 3
   and 4 keep the effect jobs, the timers and the endpoint off.

2. Call `erase/3` for each erasure in your record. Give it an actor for the person who restores.
   Then note the position of the last erasure in the log:

   ```sql
   SELECT max(position) FROM eh_os_contract_events WHERE type = 'eh_os_contract.subject_erased';
   ```

   **Result:** the engine deletes each restored data key, and records the erasure again. For an
   erasure that the backup already holds, `erase/3` returns `{:ok, :already_erased}` and appends
   nothing. Do steps 3 and 4 also then: a read model of the backup can be behind those erasures.

3. Start each node with `subscriptions: :run`. Keep `queues: false` and `server: false`.

   **Result:** the subscriptions run: the read models, the policies, the process managers and the
   relays. If a bus is configured, the inbox also takes events from other applications. The read
   models delivered `:in_transaction` forgot the subjects in step 2, except one that was being
   rebuilt. Each other read model that projects personal data forgets them when it reads those
   events. Until then, its table holds the old copy. No effect runs yet, so no effect can read that
   copy and send it out.

   A relay reads the log, not a read model. It publishes the events that were still waiting at the
   time of the backup, and can publish some again under the same ids. A publication carries no
   personal field, but it can carry the id of a subject.

4. Wait until these read models have read the events of step 2. Their rows in
   `eh_os_contract_subscriptions` have the kind `read_model`:

   ```sql
   SELECT name, status, position FROM eh_os_contract_subscriptions WHERE kind = 'read_model';
   ```

   Check each read model that projects personal data: an event in its `projects:` has a field with
   `personal:`. Only these read models forget, and only they keep personal data.

   - If its status is `running` or `stale` and its position is at or after the position of step 2,
     it is ready.
   - If its status is `rebuilding`, or its position is lower, wait.
   - If its status is `failing`, fix the read model and deploy it with the configuration of step 3.
     Then reset it: `mix eh_os_contract.subscriptions --reset <name>`, with `queues: false` and
     `server: false`. The reset needs `mix`.
   - Do not use `--skip`: a read model moved past an erasure keeps the copy.

   The position of a read model that projects no personal data can stay lower.

   **Result:** each read model that forgets has read the erasures.

5. Start each node with its normal configuration.

   **Result:** the read models of the applications in `config :eh_os_contract, applications:`
   return no personal data of an erased subject. [What does an erasure not
   reach?](personal-data.md#what-does-an-erasure-not-reach) tells the copies that remain.

The erasures of step 2 carry the time of the restore and the actor of step 2. Only your record keeps
the time of the first erasure and who asked for it.

If you have no record of the erasures, the restore makes those subjects readable again.

<a id="start-on-a-backup-whose-master-key-you-destroyed"></a>

## Start on a backup whose master key you destroyed

A backup that is older than a rewrap holds data keys that the old master key wraps. If you
destroyed that key, nothing can unwrap those data keys. The personal data of their subjects is lost.
While a data key names a master key that the vault cannot unwrap with, the engine does not start.

1. Name the destroyed key in the configuration, beside the keys of the vault:

   <!-- not compiled: the host's configuration -->
   ```elixir
   config :eh_os_contract, EhOsContract.Vault,
     keys: [{"2026-09", System.fetch_env!("EH_OS_CONTRACT_KEK")}],
     destroyed: ["2026-03"]
   ```

   Name only a key that you destroyed. If the vault still unwraps a data key of a key that
   `destroyed:` names, the engine does not start.

2. Deploy.

   **Result:** the engine starts. It logs a warning with the count of the data keys that the
   destroyed key wraps. It reads each personal field of their subjects as
   `EhOsContract.Erased`. A command that carries new personal data of such a subject returns
   `{:error, :subject_erased}`. The rewrap leaves those data keys as they are.

3. Find the subjects whose data keys the destroyed key wraps:

   ```sql
   SELECT subject_type, subject_id FROM eh_os_contract_subject_keys WHERE kek_id = '2026-03';
   ```

4. Call `erase/3` for each subject. Give it an actor for the person who restores.

   **Result:** the engine deletes those data keys, records each erasure, and appends the event
   `eh_os_contract.subject_erased`. Each read model that projects personal data forgets the
   subject. At the next boot, the warning does not show.

5. When no data key names the destroyed key, remove it from `destroyed:`, and deploy.

   **Result:** the engine starts without the warning.

If the vault wraps with a key that `destroyed:` names, the engine does not start.

The engine reads a subject of a destroyed key as erased, but its read models keep what they
projected until `erase/3` makes them forget the subject. Do step 4 for each subject.

## What can go wrong

The rewrap raises with one of these messages:

| Message | Cause | What to do |
| --- | --- | --- |
| `the vault wraps with …, not with … that was expected` | The first key of the list is not the key that you gave. The list is not the list of step 2, or you mistyped the id of the new key. No data key changed. | Run the rewrap with the configuration of step 2, and give the id of the new key. |
| `… are still wrapped by another master key than …` | A node still wraps with the old key, or another rewrap holds some rows. | Wait until each node runs the new configuration and the other rewrap ends. Run the rewrap again. |
| `… cannot be unwrapped with master key …; is that key still in the vault?` | The list of keys does not hold the key that wraps a row. | Put that key back in the list, deploy, and run the rewrap again. |
| `the vault wrapped with … and calls … current` | A vault of your own returns from `wrap/2` an id other than `current/0`. | Make `wrap/2` return the id of `current/0`. |

Do not remove the old key while the rewrap raises.

At boot, the engine unwraps one data key of each master key in `eh_os_contract_subject_keys`. If
one does not unwrap, the engine does not start, and raises with this message:

| Message | Cause | What to do |
| --- | --- | --- |
| `… wrapped by master key …. The vault cannot unwrap the data key that the engine tried … Put … back in the vault` | You removed a master key that still wraps data keys, or you changed the bytes of a key that is not the first of the list. | Put that key back in the list, with the bytes that wrapped the data keys, and deploy. Then run the rewrap before you remove the key. If you destroyed the key, do the steps of [Start on a backup whose master key you destroyed](#start-on-a-backup-whose-master-key-you-destroyed). |
| `… wrapped by master key …. The vault cannot unwrap the data key that the engine tried … The vault wraps with …` | You changed the bytes of the first key of the list, and kept its id. A rewrap does not help: it skips the data keys of the first key. | Put the bytes that wrapped that data key back, and deploy. If the vault wrapped data keys with the new bytes too, no list of keys unwraps both sets: choose which set stays readable. The engine cannot repair the other set. |

The engine checks one data key of each master key, not each data key. The count in the message is
the count of data keys that name the master key, not the count that does not unwrap. A master key that you
destroyed cannot come back. If you restore a backup that is older than the rewrap, its data keys
name the destroyed key, and the engine does not start until `destroyed:` names that key.

A destroyed master key cannot unwrap a data key that it wraps, also in a backup. Before you destroy
it, make sure that you do not need to restore such a backup.

## Next steps

- [How does the engine keep and erase personal data?](personal-data.md): the data keys and the
  erasure.
- [The configuration](configuration.md): each key of the engine.
- [The behaviours](behaviours.md): `EhOsContract.Vault` and the other behaviours that an
  application can implement.
