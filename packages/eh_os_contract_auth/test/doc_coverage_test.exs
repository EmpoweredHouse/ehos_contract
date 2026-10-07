defmodule EhOsContract.Auth.DocCoverageTest do
  @moduledoc """
  Every public function and macro of `lib/` says what it does: a `@doc`, or `@doc
  false` when it is public only for another module of the library; and every
  documented function has a `@spec`, so `dialyzer` has something to check (#141).

  `CLAUDE.md` asked for this before anything held it. Left out:

    * a callback implementation, which its behaviour documents (`@impl`);
    * a module with `@moduledoc false`, whose functions are the library's own and
      published nowhere;
    * the `@spec` of a function with `@doc false`, which is the `write-docs` skill's
      to decide.
  """

  use ExUnit.Case, async: true

  @lib Path.join(File.cwd!(), "lib") <> "/"

  defp modules do
    {:ok, modules} = :application.get_key(:eh_os_contract_auth, :modules)

    for module <- modules,
        Code.ensure_loaded?(module),
        String.starts_with?(to_string(module.module_info(:compile)[:source]), @lib),
        {:docs_v1, _, _, _, moduledoc, _, entries} <- [Code.fetch_docs(module)],
        moduledoc != :hidden,
        do: {module, entries}
  end

  # The callbacks of every behaviour `module` declares.
  defp callbacks(module) do
    for behaviour <- Keyword.get_values(module.module_info(:attributes), :behaviour),
        behaviour <- behaviour,
        Code.ensure_loaded?(behaviour),
        function_exported?(behaviour, :behaviour_info, 1),
        callback <- behaviour.behaviour_info(:callbacks),
        do: callback
  end

  # `__struct__/1`, `__schema__/1`: written by a macro, documented by
  # nobody. A name with a single leading underscore is a function someone wrote.
  defp generated?(name), do: Regex.match?(~r/\A__.*__\z/u, Atom.to_string(name))

  defp public(entries, module) do
    implemented = callbacks(module)

    for {{kind, name, arity}, _anno, _signature, doc, _meta} <- entries,
        kind in [:function, :macro],
        not generated?(name),
        {name, arity} not in implemented,
        do: {kind, name, arity, doc}
  end

  # Otherwise a source path spelled differently from the working directory (a
  # symlink, `/tmp` against `/private/tmp`) leaves nothing to check, and both pass.
  test "the modules of lib/ are found" do
    assert EhOsContract.Auth in Enum.map(modules(), &elem(&1, 0))
  end

  test "every public function and macro of lib/ has a @doc or @doc false" do
    undocumented =
      for {module, entries} <- modules(),
          {_kind, name, arity, :none} <- public(entries, module),
          do: "#{inspect(module)}.#{name}/#{arity}"

    assert undocumented == []
  end

  test "every documented public function of lib/ has a @spec" do
    unspecified =
      for {module, entries} <- modules(),
          specs = specs(module),
          {:function, name, arity, doc} <- public(entries, module),
          doc not in [:none, :hidden],
          {name, arity} not in specs,
          do: "#{inspect(module)}.#{name}/#{arity}"

    assert unspecified == []
  end

  defp specs(module) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} -> Enum.map(specs, &elem(&1, 0))
      :error -> []
    end
  end
end
