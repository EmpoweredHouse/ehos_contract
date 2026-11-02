# Repair or replay a subscription

This page tells how to move a subscription past an event that fails, and how to rebuild a read
model. It also tells how to make a consumer read the log again. It is for a developer or an
operator of an application that runs on the engine. [The glossary](glossary.md) defines each word
in italics.

A *subscription* is the position of one consumer that reads the log in order. These consumers have
one:

- a read model delivered `:at_least_once`, or `:in_transaction`: dispatch writes this one, and its
  subscription reads the log only when it is rebuilt;
- a policy delivered `:at_least_once`;
- a process manager;
- a relay, which sends the events of a publication to the bus.

An effect has no subscription: it is an Oban job. [What is a reaction?](reactions.md) tells what
a failure of each consumer leaves.

## Before you start

- The host runs its subscriptions. With `config :eh_os_contract, subscriptions: :manual`, as in
  tests, the host starts no subscription, and this page does not apply.
- You know the key of the subscription: `<contract id>:<kind>:<name>`. The kind is `read_model`,
  `policy`, `process_manager` or `relay`. The name of a relay is the name of its `publish`.
  Example: `subscriptions_example.loans:read_model:copies_out`.
- You can run `mix` with the code that is deployed, and with the configuration and the database of
  the host. A release has no `mix`.

> **The task starts the whole application.**
> Run it only with the code that is deployed. The task boots the host: it records a deployment,
> and registers each subscription with the code that you run. It also starts the subscriptions,
> the relays and Oban, so effects can call external systems from where you run it. Your code can
> differ from the deployed code. Then the engine at once rebuilds each changed process manager,
> and each changed read model that has `reset/0`. A rebuilt process manager forgets its runs.

This page uses this contract. Its read model keeps the copies that are out on loan:

```elixir
defmodule Concepts.Subscriptions.Domain do
  use EhOsContract.Domain, name: :subscriptions_example, language: :en

  subdomain :core, "Core", type: :core
  context :lending, "Lending", subdomain: :core
  actor :librarian, :human, "Librarian"
end

defmodule Concepts.Subscriptions.Contracts.Loans do
  use EhOsContract.Contract,
    domain: Concepts.Subscriptions.Domain,
    context: :lending,
    id: "subscriptions_example.loans"

  aggregate :loan, "Loan of a copy" do
    identity :loan_id

    command :lend_copy, "Lend a copy", by: :librarian, emits: :copy_lent do
      field :copy_id, :id
    end

    event :copy_lent, "Copy lent" do
      field :copy_id, :id
    end
  end

  read_model :copies_out, "Copies out on loan",
    projects: [:copy_lent],
    table: "subscriptions_example_copies_out",
    key: :loan_id,
    delivery: :at_least_once do
    field :loan_id, :id
    field :copy_id, :id
  end
end
```

## See where each subscription stands

Run the task:

```bash
mix eh_os_contract.subscriptions
```

The task prints one line for each subscription: its key, its status and its position in the log.
A subscription that failed also shows the position of the event, the module of the exception and
the number of attempts:

```text
subscriptions_example.loans:read_model:copies_out  failing at 41, fails at 42 (KeyError, 3 attempts)
```

| Status | What it means |
| --- | --- |
| `running` | It reads the log. After a reset, it reads from position 0 again. |
| `stale` | Its declaration changed, and it was not rebuilt. It reads new events over its old rows. |
| `rebuilding` | A process manager or a read model delivered `:in_transaction` reads the log again from the start. |
| `failing` | It failed 3 times on one event, and stopped there. The task adds "while it replays the log" if it is a read model delivered `:in_transaction` or a process manager, and it failed in its replay. |

<a id="move-a-subscription-past-an-event-that-fails"></a>

## Move a subscription past an event that fails

A `failing` subscription does not try again by itself. A restart of the host does not start it,
unless the declaration of a read model or a process manager changed. You decide what occurs to the
event.

1. Find the cause. The engine logs only the position and the module of the exception, not its
   message, because a message can hold personal data. Do not add a log of the event or of the
   message: an erasure does not reach a log.

   > **A changed declaration rebuilds the subscription at boot.**
   > A correction can change the declaration of a failing process manager. Then the next boot
   > resets it, with the losses in [React to history](#react-to-history-or-publish-it-again). A
   > failing read model with `reset/0` is rebuilt the same way. A read model without `reset/0` is
   > `stale`, and tries the event again. To keep a process manager, correct only its module.

2. Correct the cause, and deploy the correction.
3. Run the task without options. If the subscription is not `failing` now, stop here.
4. Choose what to do for the kind of the subscription. Read the consequence before you run the
   command:

   | Kind | Do this | What it leaves |
   | --- | --- | --- |
   | read model | `--reset`, if it has `reset/0` | It empties the rows and reads the whole log again, with the event. Until it ends, queries read part of the rows: [Rebuild a read model](#rebuild-a-read-model). |
   | read model delivered `:at_least_once` | `--skip` | The rows never get the event. |
   | read model delivered `:in_transaction` | `--skip` | It fails only while it is rebuilt. The rows never get the event. The rebuild continues after the event, also with the events that dispatch appended while it was `failing`. Then dispatch writes the rows again. |
   | policy | `--skip`, then issue the command of that event yourself if it is necessary | The policy never takes the event. A reset reacts to the whole log again: [React to history](#react-to-history-or-publish-it-again). |
   | process manager | `--skip`, then issue the command of that event yourself if it is necessary | The process manager never takes the event. Do not reset it: a reset forgets each run, and replays the log with its reactions turned off. An event appended before the replay ends never gets a reaction, and a timer due by then is dropped. If it failed during such a replay, the replay continues after the event, with its reactions turned off. The events appended while it was `failing` get no reaction either, and a timer due in that time is dropped. |
   | relay | `--skip` | The event never leaves the application. A reset publishes the whole log again to each subscriber, with the identities of erased subjects: [React to history](#react-to-history-or-publish-it-again). |

   > **A reset of a process manager does not undo a skip.**
   > A reset of the other kinds applies the event again. A skip moves the subscription past the
   > event. If the event erased a subject, a read model keeps its copy of the subject until you
   > reset it. A read model delivered `:in_transaction` that is `failing` forgets a subject at the
   > erasure. If its `forget/2` raises, the engine logs a warning and undoes what `forget/2` wrote.
   > The read model then keeps its copy until you skip the event or reset it. If the skipped
   > event is an `ends_on` event, the run of a process manager stays open, and its timers still
   > fire.

5. Run the command:

   ```bash
   mix eh_os_contract.subscriptions --skip subscriptions_example.loans:read_model:copies_out
   ```

The result: after a skip, the task prints the subscription after the event, in the status that it
had before it failed: `running`, `stale` or `rebuilding`. After a reset, it is `running` at position
0, or `rebuilding`.

<a id="rebuild-a-read-model"></a>

## Rebuild a read model

The version of a read model is a digest of its declaration and of each event that it takes. If
the version changes, the engine marks the read model `stale` at the next boot. If the read model
has `reset/0`, the engine then rebuilds it.

> **A rebuild empties the rows first.**
> Until the rebuild ends, a query reads only part of the rows. For a read model delivered
> `:in_transaction`, `reset/0` runs while the engine holds the append lock. Each append waits until
> the delete ends.

1. Give the module of the read model a `reset/0`. It deletes all the rows that the read model
   wrote:

   ```elixir
   defmodule Concepts.Subscriptions.CopiesOut do
     use Concepts.Subscriptions.Contracts.Loans, read_model: :copies_out

     @impl true
     def copy_lent(%CopyLent{} = event) do
       row = %{loan_id: event.loan_id, copy_id: event.copy_id}
       repo().insert_all(Row, [row], on_conflict: :nothing, conflict_target: [:loan_id])
       :ok
     end

     @impl true
     def reset do
       repo().delete_all(Row)
       :ok
     end

     defp repo, do: EhOsContract.Config.fetch!(:repo)
   end
   ```

2. Deploy the change. The engine rebuilds the read model at boot if its version changed, or if it
   was `stale` before. Adding `reset/0` to a read model that is not `stale` does not rebuild it.
3. Run the task. If the read model is still `stale`, or you want to rebuild it at another time,
   reset it:

   ```bash
   mix eh_os_contract.subscriptions --reset subscriptions_example.loans:read_model:copies_out
   ```

The result: the task prints `emptied, and replayed from the beginning of the log`.

> **A read model without `reset/0` stays stale.**
> It reads new events over its old rows. The task cannot reset it, and stops with an error. Add
> `reset/0` first.

While the rebuild runs:

- **A read model delivered `:at_least_once`** is `running`, from position 0. A query without
  `min_position:` answers from the part that it has read. A query with a recent `min_position:`
  waits, and can return `{:error, :not_caught_up}`.
- **A read model delivered `:in_transaction`** is `rebuilding`. Dispatch stops writing to it, and a
  subscription reads the log into it. A query with `min_position:` waits for up to `wait:`, and
  then returns `{:error, :not_caught_up}`.

Rebuild a new read model by hand in one case: it is delivered `:in_transaction`, and the log
already holds its events. A new read model delivered `:at_least_once` reads the whole log by
itself.

<a id="react-to-history-or-publish-it-again"></a>

## React to history, or publish it again

A new policy or relay starts at the head of the log. The events before it are history. A reset
makes a consumer read the whole log, from position 0. Read what it does before you run it:

| Kind | What `--reset` does |
| --- | --- |
| policy | It reacts to each event from the start of the log. The keys stop a second accepted command. The unit decides again each command that it rejected before. A command that it accepts now runs its consumers, and its effects run. Each step holds the append lock, so the reset slows every append until it ends. You cannot undo it. If the policy now issues another command for an event, the reset stops with `:idempotency_key_reused`, and the policy is `failing`. |
| relay | It publishes the whole log again, under the same ids. An inbox drops each message that it already took. An application that subscribed later takes the history as new events. Identities go out in clear text, also those of subjects erased since. |
| process manager | It forgets each run, and reads the log to the head with its reactions turned off. No event gets a reaction until the replay ends, also an event appended during it. A timer that was due in that time is dropped, unless its job is still in the queue. |
| read model | It calls `reset/0`, and reads the whole log again. Until it ends, queries read part of the rows, and for `:in_transaction` each append waits for the delete: [Rebuild a read model](#rebuild-a-read-model). |

```bash
mix eh_os_contract.subscriptions --reset <contract id>:policy:<name>
```

## What can go wrong

**`<key> is not failing, so there is nothing to skip`.** The subscription is not `failing`. Run the
task without options to see the status of each subscription. A subscription that is not `failing`
needs no skip. If a read model is `stale`, rebuild it:
[Rebuild a read model](#rebuild-a-read-model).

**`<key> defines no reset/0, so its rows cannot be emptied and it cannot be reset`.** Add `reset/0`
to the module, and deploy it.

**`<key> is not a subscription of this application`.** The key of `--skip` or `--reset` is wrong,
or the contract is not in `config :eh_os_contract, applications:`. Run the task without options to
see the keys.

**A subscription waits at a position, and counts no attempt.** A newer version of the code wrote
the event at that position. The subscription waits until this node runs the newer code.

## Next steps

- [What is a reaction?](reactions.md): the delivery of each reaction, and what a failure leaves.
- [What are read models and queries?](reading.md): what a read model keeps.
- [How does an event reach another contract?](between-contracts.md): the relay and the inbox.
- [The tasks](cli.md): each option of `mix eh_os_contract.subscriptions`.
