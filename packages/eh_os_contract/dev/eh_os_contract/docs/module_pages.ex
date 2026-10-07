defmodule EhOsContract.Docs.ModulePages do
  @moduledoc """
  Reference pages written from the package's own modules (#141): the command-line
  tasks a host runs, from their `@shortdoc` and `@moduledoc`, and the behaviours a host
  may implement, from their `@moduledoc`, `@callback` specs and docs.

  Both lists are found, not written down: every `mix` task and every behaviour
  compiled from `lib/`. A new one appears on its page with the next `mix
  eh_os_contract.docs`, and `--check` fails until it does. The tasks under `dev/` are
  this package's own tooling and stay off the page.

  A spec is printed by `Macro.to_string/1`, whose layout can change between Elixir
  versions: generate with the version CI runs.
  """

  import EhOsContract.Docs, only: [shift: 2]

  @doc "The page of the command-line tasks: `docs/cli.md`."
  @spec cli() :: String.t()
  def cli do
    tasks = for module <- shipped(), task?(module), do: module

    """
    #{EhOsContract.Docs.marker("the mix tasks' docs")}

    # Command-line tasks

    The `mix` tasks of `eh_os_contract`, as each one's documentation describes it. Run
    `mix help <task>` for the same text in a terminal.

    #{Enum.map_join(tasks, "\n", &task_section/1)}\
    """
  end

  @doc "The page of the behaviours a host may implement: `docs/behaviours.md`."
  @spec behaviours() :: String.t()
  def behaviours do
    keys = EhOsContract.Config.docs()
    behaviours = for module <- shipped(), behaviour?(module), do: module

    """
    #{EhOsContract.Docs.marker("the behaviours' docs")}

    # Behaviours

    What a host may put in place of the library's own implementation. Each is named in
    the [configuration](configuration.md) under the key after its name.

    #{Enum.map_join(behaviours, "\n", &behaviour_section(&1, keys))}\
    """
  end

  defp task_section(module) do
    """
    ## mix #{Mix.Task.task_name(module)}

    #{Mix.Task.shortdoc(module)}

    #{module |> moduledoc() |> qualify(module) |> shift(1)}
    """
  end

  defp behaviour_section(module, keys) do
    key = module |> Module.split() |> List.last() |> Macro.underscore()

    case Regex.run(~r/^\* `:#{key}` \(([^)]*)\)/mu, keys) do
      [_line, type] ->
        """
        ## #{inspect(module)}

        Configured with `config :eh_os_contract, #{key}: ...`, #{type}.

        #{module |> moduledoc() |> qualify(module) |> shift(1)}

        ### Callbacks

        #{Enum.map_join(callbacks(module), "\n", &callback_section/1)}\
        """

      nil ->
        raise ArgumentError,
              "#{inspect(module)} is a behaviour, but `config :eh_os_contract` has no key " <>
                ":#{key} naming its implementation"
    end
  end

  defp callback_section({specs, optional?, doc}) do
    """
    ```elixir
    #{Enum.map_join(specs, "\n", &"@callback #{&1}")}
    ```

    #{if optional?, do: "Optional. "}#{doc}
    """
  end

  # Each callback's specs and doc, in the order the module declares them; one marked
  # `@doc false` is left out, as ExDoc leaves it out.
  defp callbacks(module) do
    {:ok, specs} = Code.Typespec.fetch_callbacks(module)
    optional = module.behaviour_info(:optional_callbacks)

    for {{:callback, name, arity}, _anno, _signature, doc, _meta} <- doc_entries(module),
        doc != :hidden do
      clauses =
        for {{^name, ^arity}, list} <- specs,
            spec <- list,
            do:
              name
              |> Code.Typespec.spec_to_quoted(spec)
              |> local_types(module)
              |> Macro.to_string()

      {clauses, {name, arity} in optional, doc |> text() |> qualify(module)}
    end
  end

  # A type of the module's own is written bare in its spec (`reason()`); on a page of
  # its own it gets the module's name.
  defp local_types(quoted, module) do
    {:ok, types} = Code.Typespec.fetch_types(module)
    own = for {kind, {name, _, args}} <- types, kind in [:type, :opaque], do: {name, length(args)}

    Macro.prewalk(quoted, fn
      {name, meta, args} = call when is_atom(name) and is_list(args) ->
        if {name, length(args)} in own,
          do: {{:., meta, [module, name]}, meta, args},
          else: call

      other ->
        other
    end)
  end

  # A reference ExDoc resolves on the module's own page (`c:publish/2`, `t:entry/0`,
  # `check!/1`, a callback written without `c:`) names nothing on a page of its own,
  # so it gets the module's name.
  defp qualify(doc, module) do
    name = inspect(module)

    Regex.replace(~r/`([ct]:)?([a-z_][a-zA-Z0-9_]*[!?]?)\/([0-9]+)`/u, doc, fn whole,
                                                                               kind,
                                                                               fun,
                                                                               arity ->
      arity = String.to_integer(arity)

      cond do
        kind == "t:" -> "`t:#{name}.#{fun}/#{arity}`"
        kind == "c:" or callback?(module, fun, arity) -> "`c:#{name}.#{fun}/#{arity}`"
        exported?(module, fun, arity) -> "`#{name}.#{fun}/#{arity}`"
        true -> whole
      end
    end)
  end

  # No atom is made from the docs' text: a name that is no atom is no function either.
  defp exported?(module, fun, arity) do
    function_exported?(module, String.to_existing_atom(fun), arity)
  rescue
    ArgumentError -> false
  end

  defp callback?(module, fun, arity) do
    behaviour?(module) and
      {String.to_existing_atom(fun), arity} in module.behaviour_info(:callbacks)
  rescue
    ArgumentError -> false
  end

  defp text(%{"en" => doc}), do: String.trim(doc)
  defp text(_none), do: ""

  defp shipped do
    {:ok, modules} = :application.get_key(:eh_os_contract, :modules)
    lib = Path.join(File.cwd!(), "lib") <> "/"

    modules
    |> Enum.filter(&from?(&1, lib))
    |> Enum.sort_by(&inspect/1)
  end

  # The task runs in the package's root, so its `lib/` is exactly this one. A module
  # compiled without its source path (`ERL_COMPILER_OPTIONS=deterministic`) cannot be
  # placed, and is refused rather than left off a page.
  defp from?(module, lib) do
    Code.ensure_loaded!(module)

    case module.module_info(:compile)[:source] do
      nil ->
        raise ArgumentError,
              "#{inspect(module)} was compiled without its source path, so its place " <>
                "(lib/ or dev/) is unknown; compile without `deterministic`"

      source ->
        String.starts_with?(to_string(source), lib)
    end
  end

  defp task?(module), do: match?("Elixir.Mix.Tasks." <> _, Atom.to_string(module))

  defp behaviour?(module) do
    function_exported?(module, :behaviour_info, 1) and
      not function_exported?(module, :__protocol__, 1)
  end

  defp doc_entries(module) do
    {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(module)
    Enum.sort_by(entries, fn {_, anno, _, _, _} -> :erl_anno.line(anno) end)
  end

  defp moduledoc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} ->
        doc

      _hidden_or_none ->
        raise ArgumentError,
              "#{inspect(module)} has no @moduledoc, and its reference page would " <>
                "print nothing; write one"
    end
  end
end
