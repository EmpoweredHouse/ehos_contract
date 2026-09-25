defmodule EhOsContract.Model.V1 do
  @moduledoc """
  Builds `EhOsContract.Model` data from a contract written with
  `use EhOsContract.Contract`.

  **The only module that calls the functions a v1 contract generates.** Everything
  else reads through `EhOsContract.Model`, so when v1 goes (v2 plan, E11) this file
  goes with it and no reader changes.

  Not cached. Every generated function returns a compile-time literal, so building
  the map costs a handful of calls and no copying — and a cache keyed by module
  would have to notice a module being recompiled, which tests do on purpose.
  """

  @doc """
  Whether a module was compiled with `use EhOsContract.Contract`.

  Loads the module first. `function_exported?/3` answers `false` for a module that
  is not loaded yet, which in dev is every module before its first use.
  """
  @spec contract?(module()) :: boolean()
  def contract?(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :__eh_os_contract__, 0)

  @doc """
  The model of a v1 contract module. Raises `ArgumentError` naming the module when
  it is not a contract, rather than failing on whichever generated function
  happens to be called first.
  """
  @spec build(module()) :: EhOsContract.Model.t()
  def build(module) do
    unless contract?(module) do
      raise ArgumentError,
            "#{inspect(module)} is not an EhOsContract contract (no `use EhOsContract.Contract`)"
    end

    %{
      format: 1,
      kind: :contract,
      module: module,
      events: module.events(),
      processes: module.processes(),
      commands: module.commands(),
      traces: module.traces(),
      externals: module.externals(),
      rules: module.rules(),
      examples: module.examples(),
      version: module.version(),
      digests: module.declaration_digests()
    }
  end
end
