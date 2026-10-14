defmodule GraphLab do
  @moduledoc """
  **A test set for drawing the graph. It is not client material.**

  The one explorable graph of the contracts (`graph-explorer-plan.md`, section 11) is
  drawn and checked on this set alone: a clinic under a domain of its own,
  `:"graph-lab"`, in which every shape the graph has to draw is at least once:

  - a context with two contracts: settlement's visit settlement beside the till
    (`GraphLab.Contracts.Till`), and so seven contracts in all;
  - aggregates with a lifecycle: the visit, the till's day, a cash refund;
  - a contract with two units, the till;
  - an event three contracts consume, scheduling's `visit_completed`, and one consumed
    under another name, `patient_left` in patient messaging;
  - an event received from another application, the patient app's confirmation;
  - a policy that takes three events, patient messaging's;
  - two processes sharing an event, a process over one contract, and one with no end;
  - promises, one with a way of keeping it other than its event, and a deadline.

  **It does not publish.** The sandbox is one application to EHOS, `taxvision`
  (`config :eh_os_contract_auth, audience: "taxvision/sandbox"`), and an application
  publishes only under its own name, so a publication here would stop the host at boot.

  Its contracts change at will for the graph's sake: nothing outside the set depends on
  them. A declaration whose `source:` says „dodane do testów grafu” is there for the
  graph alone, with no workshop material behind it. `mix graph_lab.traffic` fills the
  development database with runs of the set, with drift, and prints how to start the
  dashboard with this set alone.
  """

  use Boundary, deps: [EhOsContract], exports: []
end
