defmodule Lending do
  @moduledoc """
  **An invented case study, not client material**: a public library lending copies
  to its members. It exists so that the library's mechanisms are tested on material
  anyone may read (the publication programme, PB2, #369).

  Like the client trees beside it, this one is contracts and the code they need to
  run: a domain, two contracts, two process modules, the decisions, reactions and
  the one table they need, and stand-ins for the desk's tariff and the card system.
  No screen and no real integration.

  What it is here to show, each with its test in `sandbox/test/lending_*`:

  - holds on a copy as a dynamic consistency boundary, raced on real commits;
  - a member's personal data, sealed in the log, kept in a read model and erased;
  - a membership card read from outside the log, and a late fee the host supplies;
  - an overdue chase with a timer set from the loan's due date;
  - a promise that a late fee is paid, kept the other way when it is waived.
  """

  use Boundary, deps: [EhOsContract], exports: [Supplier, Entities]
end
