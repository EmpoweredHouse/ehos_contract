defmodule QueryRig do
  @moduledoc """
  **An engine fixture, and invented.** A desk whose one query takes a param of every
  shape the compiler accepts for a query, so that a test can send each through the query
  string the OpenAPI document describes and through `EhosContract.call/3` (#618). No
  workshop stands behind it, and no name in it comes from one.
  """

  use Boundary, deps: [EhosContract], exports: [Domain, Desk]
end
