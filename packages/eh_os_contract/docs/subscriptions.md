# Repair or replay a subscription

This page tells how to move a subscription past an event that fails, and how to rebuild a read
model. It also tells how to make a consumer read the log again. It is for a developer or an operator of an
application that runs on the engine. [The glossary](glossary.md) defines each word in italics.

A *subscription* is the position of one consumer that reads the log in order, after the commit.
These consumers have one:

- a read model delivered `:at_least_once` or `:in_transaction`;
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
- You run the commands with the configuration of the host that you repair, such as
  `MIX_ENV=prod`.

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

  query :copies_out, "Copies out on loan", reads: :copies_out, by: :librarian

  scenario "a lent copy is out" do
    given :copy_lent, %{loan_id: "loan-1", copy_id: "copy-1"}
    query :copies_out, %{}
    answers [%{copy_id: "copy-1"}]
  end
end
```

## See where each subscription stands

1. Run the task:

   ```bash
   mix eh_os_contract.subscriptions
   ```

   The task prints one line for each subscription: its key, its status and its position in the
   log. A subscription that failed also shows the position of the event, the module of the
   exception and the number of attempts:

   ```text
   subscriptions_example.loans:read_model:copies_out  failing at 41, fails at 42 (KeyError, 3 attempts)
   ```

| Status | What it means |
| --- | --- |
| `running` | It reads the log. |
| `stale` | Its declaration changed, and it was not rebuilt. It reads new events over its old rows. |
| `rebuilding` | It reads the log again from the start. |
| `failing` | It failed 3 times on one event, and stopped there. |

## Move a subscription past an event that fails

A `failing` subscription does not try again by itself. A restart of the host does not start it
either. You decide what occurs to the event.

1. Read the exception in the logs of the host, at the position that the task shows.
2. Correct the cause, and deploy the correction.
3. Choose one of these:
   - To apply the event with the corrected code, reset the subscription:

     ```bash
     mix eh_os_contract.subscriptions --reset subscriptions_example.loans:read_model:copies_out
     ```

     The consumer reads the whole log again. The sections below tell what a reset does to each
     kind.
   - To leave the event out, skip it:

     ```bash
     mix eh_os_contract.subscriptions --skip subscriptions_example.loans:read_model:copies_out
     ```

     The consumer never applies that event. You cannot undo this. If the event erased a subject,
     the read model keeps its copy of the subject until you reset it. If the subscription is a
     relay, the event never leaves the application.

The result: the task prints the subscription as `running`, at a later position.

> **A changed declaration clears the failure.**
> The next boot rebuilds a failing read model or process manager whose declaration changed. A failing policy or relay stays failing.

<a id="rebuild-a-read-model"></a>

## Rebuild a read model

The version of a read model is a digest of its declaration and of each event that it takes.
If the version changes, the engine marks the read model `stale` at the next boot.

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

2. Deploy the change. At boot, the engine calls `reset/0` and reads the log again into the read
   model.
3. To rebuild it at another time, reset it:

   ```bash
   mix eh_os_contract.subscriptions --reset subscriptions_example.loans:read_model:copies_out
   ```

The result: the task prints `emptied, and replayed from the beginning of the log`. The status is
`rebuilding`, then `running`.

> **A read model without `reset/0` stays stale.**
> It reads new events over its old rows. The task cannot reset it, and stops with an error. Add
> `reset/0` first.

A read model delivered `:in_transaction` can also be rebuilt. While it is `rebuilding`, dispatch
does not write to it, and a subscription reads the log into it. A query without `min_position:`
can then read part of the rows. A query with `min_position:` waits.

Rebuild a new read model by hand in one case: it is delivered `:in_transaction`, and the log
already holds its events. A new read model delivered `:at_least_once` reads the whole log by
itself.

## React to history, or publish it again

A new policy, process manager or relay starts at the head of the log. The events before it are
history. To make it read the history, reset it with its key:

```bash
mix eh_os_contract.subscriptions --reset <contract id>:policy:<name>
```

| Kind | What `--reset` does |
| --- | --- |
| policy | It goes back to the start of the log and reacts to each event. The keys of the commands stop a second accepted command. The unit decides a command that it rejected before again. |
| process manager | It forgets each run, and reads the log again with its reactions turned off. It learns the runs again, and issues nothing for them. |
| relay | It publishes the whole log again, under the same ids. An inbox drops each message that it already took. |
| read model | It calls `reset/0`, and reads the whole log again. |

A reset of a process manager does not apply the event that it failed on. If a run needs the
command of that event, issue the command yourself.

## What can go wrong

**`<key> is not failing, so there is nothing to skip`.** You can skip only a `failing`
subscription. Use `--reset`.

**`<key> defines no reset/0, so its rows cannot be emptied and it cannot be reset`.** Add `reset/0`
to the module, and deploy it.

**`<key> is not a subscription of this application`.** The key is wrong, or the contract is not in
`config :eh_os_contract, applications:`. Run the task without options to see the keys.

**A subscription waits at a position, and counts no attempt.** A newer version of the code wrote
the event at that position. The subscription waits until this node runs the newer code.

## Next steps

- [What is a reaction?](reactions.md): the delivery of each reaction, and what a failure leaves.
- [What are read models and queries?](reading.md): what a read model keeps.
- [How does an event reach another contract?](between-contracts.md): the relay and the inbox.
- [The tasks](cli.md): each option of `mix eh_os_contract.subscriptions`.
