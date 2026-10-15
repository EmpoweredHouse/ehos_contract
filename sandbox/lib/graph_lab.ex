defmodule GraphLab do
  @moduledoc """
  **A test set for drawing the graph. It is not client material.**

  The graph of the contracts (plan DD, stage G1, #297; the set was first written on #302)
  is drawn and checked on this set: a clinic under a domain of its own, `:"graph-lab"`,
  in which every shape the graph has to draw is at least once.

  - **The map:** core, supporting and generic subdomains; a context with no contract
    (configuration) and one with two (settlement, beside the till), seven contracts in
    all; context relations of several patterns; an external system with an expected
    latency and one whose answer carries a number it gives (`issued_by:`).
  - **Units:** aggregates with a lifecycle (the visit, the till's day, a cash refund) and
    without; two consistency boundaries; a contract with two units (the till); a unit
    that records only, in the core (the visit's note) and outside it (the P1 report);
    fields holding another contract's unit's number (`visit_id`).
  - **Between contracts:** an event three contracts consume (`visit_completed`), one
    consumed under another name (`patient_left`), and one received from another
    application (the patient app's confirmation).
  - **Reactions:** policies, one taking three events and one whose command may be
    refused; process managers with a timer after a wait and a timer at a time its state
    holds, one reacting to an event during its run by cancelling its timer; an effect; a
    read model with its query; a domain service.
  - **Rules:** invariants, a command's constraint, a policy's, a value's (`:pesel`), and
    a command scoped to what the actor is granted (`scope:`).
  - **Processes:** two sharing an event, one over one contract, one with no end; stages
    with labels; promises kept by their event or another way; a deadline.

  **It does not publish.** The sandbox is one application to EHOS, `taxvision`
  (`config :eh_os_contract_auth, audience: "taxvision/sandbox"`), and an application
  publishes only under its own name, so a publication here would stop the host at boot.

  Its contracts change at will for the graph's sake: nothing outside the set depends on
  them. A `source:` saying, in Polish, that it was added for the graph's tests marks what
  is there for the graph alone; the other sources are labels kept as test data, with no material behind them in
  this repository. `mix graph_lab.traffic` fills the development database with runs of
  the set, with drift, and prints how to start the dashboard with this set alone.
  """

  use Boundary, deps: [EhOsContract], exports: []
end
