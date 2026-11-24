defmodule Fulfilment do
  @moduledoc """
  **An invented case study, not client material**: a shop fulfilling its orders across
  three departments, the order desk, the warehouse and shipping. It exists so that the
  library's mechanisms are tested on material anyone may read (the publication
  programme, PB2, #369).

  Like the other case studies beside it, this one is contracts and the code they need to
  run: a domain, three contracts, a process module, and the decisions and reactions.
  No screen and no real integration.

  What it is here to show, each with its test in `sandbox/test/fulfilment_*`:

  - warehouse staff granted per warehouse (`scope:`), and a pick list confirmed only by
    the picker it is assigned to (`actor_is`), over HTTP: 401, 403 `missing_capability`,
    403 `outside_scope` and the business's own refusal;
  - a field another context consumes, renamed by its publisher, breaking the
    subscriber's contract and its implementation;
  - a promise counted from an event in the middle of the run, across three contexts.
  """

  use Boundary, deps: [EhosContract], exports: [Traffic]
end
