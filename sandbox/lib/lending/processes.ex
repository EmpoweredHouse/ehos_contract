defmodule Lending.Processes do
  @moduledoc """
  **Invented.** The library's runs, each a process module: a loan from lending to
  return, and a late fee from its charge to its payment or waiver.
  """

  use Boundary, deps: [EhosContract, Lending.Contracts], exports: []
end
