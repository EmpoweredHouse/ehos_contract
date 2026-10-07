defmodule EhOsContract.Docs.ModulePages do
  @moduledoc """
  Reference pages written from the package's own modules (#141): the command-line
  tasks a host runs, from their `@shortdoc` and `@moduledoc`, and the behaviours a host
  may implement, from their `@moduledoc`, `@callback` specs and docs.

  Both lists are found, not written down: every `mix` task and every behaviour
  compiled from `lib/`. A new one appears on its page with the next `mix
  eh_os_contract.docs`, and `--check` fails until it does. The tasks under `dev/` are
  this package's own tooling and stay off the page.
  """

  import EhOsContract.Docs, only: [shift: 1]

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
    behaviours = for module <- shipped(), behaviour?(module), do: module

    """
    #{EhOsContract.Docs.marker("the behaviours' docs")}

    # Behaviours

    What a host may put in place of the library's own implementation. Each is named in
    the [configuration](configuration.md) under the key after its name.

    #{Enum.map_join(behaviours, "\n", &behaviour_section/1)}\
    """
  end

  defp task_section(module) do
    """
    ## mix #{Mix.Task.task_name(module)}

    #{Mix.Task.shortdoc(module)}

    #{module |> moduledoc() |> qualify(module) |> shift()}
    """
  end

  defp behaviour_section(module) do
    key = module |> Module.split() |> List.last() |> Macro.underscore()

    unless EhOsContract.Config.docs() =~ "`:#{key}`" do
      raise ArgumentError,
            "#{inspect(module)} is a behaviour, but `config :eh_os_contract` has no key " <>
              ":#{key} naming its implementation"
    end

    """
    ## #{inspect(module)}

    Configured with `config :eh_os_contract, #{key}: MyModule`.

    #{module |> moduledoc() |> qualify(module) |> shift()}

    ### Callbacks

    #{Enum.map_join(callbacks(module), "\n", &callback_section/1)}\
    """
  end

  defp callback_section({spec, doc}) do
    """
    ```elixir
    @callback #{spec}
    ```

    #{doc}
    """
  end

  # Each callback's spec and doc, in the order the module declares them.
  defp callbacks(module) do
    {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(module)
    {:ok, specs} = Code.Typespec.fetch_callbacks(module)

    for {{:callback, name, arity}, anno, _signature, doc, _meta} <-
          Enum.sort_by(entries, fn {_, anno, _, _, _} -> :erl_anno.line(anno) end),
        {{^name, ^arity}, [spec | _]} <- specs do
      quoted = Code.Typespec.spec_to_quoted(name, spec)
      {Macro.to_string(quoted), doc |> text(anno) |> qualify(module)}
    end
  end

  # A reference ExDoc resolves on the module's own page (`c:publish/2`, `check!/1`)
  # names nothing on a page of its own, so it gets the module's name.
  defp qualify(doc, module) do
    name = inspect(module)

    Regex.replace(~r/`(c:)?([a-z_][a-zA-Z0-9_]*[!?]?)\/([0-9]+)`/u, doc, fn whole, c, fun, arity ->
      if c != "" or function_exported?(module, String.to_atom(fun), String.to_integer(arity)),
        do: "`#{c}#{name}.#{fun}/#{arity}`",
        else: whole
    end)
  end

  defp text(%{"en" => doc}, _anno), do: String.trim(doc)

  defp text(_none, _anno), do: ""

  defp shipped do
    {:ok, modules} = :application.get_key(:eh_os_contract, :modules)

    modules
    |> Enum.filter(&from_lib?/1)
    |> Enum.sort_by(&inspect/1)
  end

  defp from_lib?(module) do
    source = to_string(module.module_info(:compile)[:source])
    String.contains?(source, "/eh_os_contract/lib/")
  end

  defp task?(module), do: match?("Elixir.Mix.Tasks." <> _, Atom.to_string(module))

  defp behaviour?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :behaviour_info, 1)
  end

  defp moduledoc(module) do
    {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(module)
    doc
  end
end
