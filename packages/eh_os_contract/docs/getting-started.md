# Getting started

This page goes from an installed package to a contract whose scenarios run as tests, a command dispatched through it,
and the first check and report.

<!-- covers: rules no-contracts -->

## 1. Install and configure

The dependency, the migration, the compiler and the place in the supervision tree are in
[the README](../README.md). The 2 settings every application needs:

<!-- not compiled: the host's configuration -->
```elixir
config :eh_os_contract,
  applications: [:my_app],
  repo: MyApp.Repo
```

`applications:` names the OTP applications whose modules hold your domain and contracts. The library
cannot tell whose binary it runs in, and a scan of the wrong application finds nothing and reports
nothing wrong; `mix eh_os_contract.check` warns when it finds no contract at all (`no-contracts`), which
is how a misconfigured scan shows. Every other setting, and what it does, is in
[the configuration](configuration.md); the engine refuses to start with a key it does not know.

## 2. Write a domain and a contract

```elixir
defmodule GettingStarted.Domain do
  use EhOsContract.Domain, name: :getting_started, language: :en

  subdomain :core, "Core", type: :core

  context :lending, "Lending", subdomain: :core

  actor :librarian, :human, "Librarian"
end

defmodule GettingStarted.Contracts.Loans do
  use EhOsContract.Contract,
    domain: GettingStarted.Domain,
    context: :lending,
    id: "getting_started.loans"

  aggregate :loan, "Loan" do
    identity :copy_id

    state do
      field :lent, :boolean, default: false
    end

    command :lend_copy, "Lend a copy",
      by: :librarian,
      emits: :copy_lent,
      rejects: :lent_once do
      field :member_id, :string
    end

    event :copy_lent, "Copy lent" do
      field :member_id, :string
    end

    invariant :lent_once, "A copy is lent to one member at a time"
  end

  scenario "a copy is lent" do
    command :lend_copy, %{copy_id: "c-1", member_id: "m-1"}
    expect :copy_lent
  end

  scenario "a lent copy is not lent again" do
    given :copy_lent, %{copy_id: "c-1", member_id: "m-1"}
    command :lend_copy, %{copy_id: "c-1", member_id: "m-2"}
    rejected :lent_once
  end
end
```

The domain says where the contract lives and who acts in it; the contract says what is decided (an
aggregate, identified by `copy_id`), what it refuses (an invariant), and 2 scenarios a librarian can
read and confirm. [Write a domain, a contract and a process module](contract.md) explains each part, and
[the compile refusals](refusals.md) list every refusal of the compiler; the [concepts](concepts/domain.md) go through each kind of declaration.

## 3. Implement what it decides

```elixir
defmodule GettingStarted.Loan do
  use GettingStarted.Contracts.Loans, aggregate: :loan

  @impl true
  def lend_copy(%LendCopy{}, %State{lent: true}), do: reject(:lent_once)

  def lend_copy(%LendCopy{copy_id: id, member_id: member}, _state),
    do: emit(%CopyLent{copy_id: id, member_id: member})

  @impl true
  def evolve(state, %CopyLent{}), do: %{state | lent: true}
end
```

The implementation points at its contract and gets the command, event and `State` structs the
contract generates. It decides with `emit/1` and `reject/1`; because the unit keeps a state beyond its
identity, `evolve/2` folds its events into it. A callback left out, or an event the command does not
declare, does not compile.
[Units that decide](concepts/units.md) says more.

## 4. Run the scenarios as tests

One test module runs every scenario of a contract against its implementation:

```
defmodule GettingStarted.LoansScenariosTest do
  use EhOsContract.ScenarioCase, contract: GettingStarted.Contracts.Loans
end
```

A scenario that the implementation does not satisfy fails as a test, with the scenario's own words as
its name. [Scenarios](concepts/scenarios.md) says what each part of one asserts.

## 5. Dispatch a command

From the application's own code, with the actor it authenticated:

<!-- not compiled: a call in the host's code -->
```elixir
alias GettingStarted.Contracts.Loans

EhOsContract.dispatch(Loans, %Loans.Commands.LendCopy{copy_id: "c-1", member_id: "m-1"},
  actor: actor
)
```

Dispatch asks whether the actor may issue the command, checks its fields, folds the unit's events,
lets the implementation decide, and appends what it emits to the log, all in one transaction. A
credential from outside enters through `EhOsContract.call/3` instead, and over HTTP through
`EhOsContract.Plug` ([authorization](authorization.md)).

Every command belongs to a piece of work, named by its correlation: `correlation_id:` in dispatch's
options, `x-correlation-id` over HTTP, or a new one. While the engine runs the command, or reacts to
an event, a timer or a message of that work, the Logger's metadata holds it as `correlation_id`, and
what was there before is back afterwards. It is written in lower case, as the log keeps it. An
erasure belongs to no piece of work and sets none, nor does an identifier that is not a UUID's text,
from another application's message for instance: the metadata stays as it was. Name it in the formatter's metadata to write it on each
line, so one piece of work can be read across applications:

<!-- not compiled: the host's configuration -->
```elixir
config :logger, :default_formatter, metadata: [:request_id, :correlation_id]
```

## 6. Check, draw and report

```
mix eh_os_contract.check            # what the model may say, but you should hear about
mix eh_os_contract.graph --contract getting_started.loans --output loans.json
mix eh_os_contract.view             # the domain as a tree
mix eh_os_contract.report --since 2026-07-01T00:00:00Z
```

`mix eh_os_contract.check` is the one for CI; `--warnings-as-errors` fails the build on a warning. Each
finding names a rule, listed with its reason in [the rules](rules.md). The report answers the 4
questions for each contract once there is something in the log. Every task, and its options, is in
[the command-line tasks](cli.md).

## Next

- [Introduction](introduction.md): what the library is for, and what it is not.
- The concepts: [the domain](concepts/domain.md), [actors, personal data and values](concepts/domain-data.md),
  [units that decide](concepts/units.md), [reactions](concepts/reactions.md), [reading](concepts/reading.md),
  [forms](concepts/forms.md), [between contracts](concepts/between-contracts.md), [processes](concepts/process.md) and
  [scenarios](concepts/scenarios.md).
- With an assistant: the `eh-os-contract` Claude Code plugin, from this repository's marketplace, gives
  an application the skills for deciding where a feature lives, distilling a process into a domain and
  contracts, writing an event, a decider and a reaction, and changing a contract that has history
  (`/eh-os-contract:change-contract`). An application enables it in its `.claude/settings.json`: the
  marketplace `EmpoweredHouse/eh-os-contract` at the tag of the plugin's release,
  `eh-os-contract-plugin-vX.Y.Z`, and the plugin `eh-os-contract@eh-os-contract`; `ehos_app`'s template
  is to write both into the projects it generates. The repository is private, so Claude Code fetches
  it with the machine's git credentials: without a GitHub SSH key, set
  `CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1` and run `gh auth setup-git`.
