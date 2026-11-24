defmodule Billing do
  @moduledoc """
  **An invented case study, not client material**: a company that bills its
  subscriptions monthly and collects through a payment gateway. It exists so that the
  library's mechanisms are tested on material anyone may read (the publication
  programme, PB2, #369).

  Like the other case studies beside it, this one is contracts and the code they need to
  run: a domain, two contracts, a process module, the decisions and reactions, and a
  fake payment gateway. No screen and no real integration.

  What it is here to show, each with its test in `sandbox/test/billing_*`:

  - a monthly process manager that never ends: it keeps the next run's date in its
    state, catches up after a late run, and is not reset by a retry;
  - one invoice line per usage record, issued in the transaction that closes the period;
  - a payment collected through a gateway that may be down, with the outage observed
    and a later attempt that succeeds;
  - a process module over two contracts with no end and no deadline;
  - a publication, which the AsyncAPI document, the manifest and the credential
    verifier's audience are tested on.
  """

  use Boundary, deps: [EhosContract], exports: [Traffic, Traffic.Gateway]
end
