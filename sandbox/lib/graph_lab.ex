defmodule GraphLab do
  @moduledoc """
  **A copy of Rehmed changed to test the graph on. It is not client material.**

  The one explorable graph of the contracts (`graph-explorer-plan.md`, section 11) is
  drawn and checked on this set alone. It is `lib/rehmed/` copied under a domain of its
  own, `:"graph-lab"`, with what the clients' material lacks added, so that every shape
  the graph has to draw is here at least once:

  - a context with two contracts: settlement's visit settlement beside the till
    (`GraphLab.Contracts.Till`), and so seven contracts in all;
  - aggregates with a lifecycle: the visit, the till's day, a cash refund;
  - a contract with two units, the till;
  - an event three contracts consume, scheduling's `visit_completed`, and one consumed
    under another name, `patient_left` in patient messaging;
  - an event received from another application, the patient app's confirmation;
  - a policy that takes three events, patient messaging's;
  - two processes sharing an event, a process over one contract, and one with no end;
  - a deadline, beside Rehmed's promises.

  **It does not publish.** The sandbox's credential verifier lets only TaxVision publish
  (`config :eh_os_contract_auth, audience: "taxvision/sandbox"`), so a publication here
  would stop the host at boot; the host's configuration is not changed for this set.

  Rehmed's own reasons — what the material says, and why a declaration is shaped as it
  is — stay in `lib/rehmed/`: the copy points there rather than repeating them. What it
  adds is labelled in Polish like the rest, and its `source:` says
  „dodane do testów grafu”, so a reader of the graph can tell it from Rehmed's. It needs
  no migration: its read model writes Rehmed's table (`GraphLab.Settlement.DailyTotals`).
  `mix graph_lab.traffic` fills the development database with runs of it, with drift,
  and prints how to start the dashboard with this set alone.
  """

  use Boundary, deps: [EhOsContract], exports: []
end
