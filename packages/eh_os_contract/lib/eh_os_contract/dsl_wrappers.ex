defmodule EhOsContract.DslWrappers do
  @moduledoc """
  Options beside a `do` block, for the library's Spark DSLs (v2 §16, D13).

  Elixir reads `context :settlement, "Rozliczenia", subdomain: :supporting do … end`
  as four arguments: the two positional ones, the keyword list, and `[do: …]`. A Spark
  entity macro takes its positional arguments and one options list, so that call
  names a macro Spark never defines. For every entity that takes a block, one that
  has entities nested in it, `attach/2` defines that one more arity from the entity's
  definition. It moves the block into the options, `context(name, label, opts, do: b)`
  → `context(name, label, opts ++ [do: b])`, and Spark's own macro reads the block
  from `opts[:do]`. Nothing is written by hand per entity.

  The wrappers are imported where Spark imports the entity macros they stand beside:
  a top-level entity's through the section's `imports`, a nested entity's through
  its parent's. The call they expand to keeps the caller's file and line, so a DSL
  error points at the declaration, never at this module.

  An entity with an optional positional argument needs one more thing. Spark already
  defines the arity the wrapper would take for the shorter form: for
  `value :address, label: "Adres" do … end` it calls `value(name, type, opts)`, with
  the keyword list in `type` and only the block in `opts`. Without a block Spark
  itself reads a keyword list in the last optional argument as options. `attach/2`
  gives such an entity a `transform` that applies the same rule when a block follows,
  so an optional positional argument of an entity that takes a block must never
  accept a keyword list as its value.

  The formatter needs nothing for them: it never adds parentheses to a call with a
  `do` block, so a consumer's `mix format` keeps the four-argument form as written.
  """

  @doc """
  Defines the wrappers for `section`'s entities under `namespace` and returns the
  section with its own and its entities' `imports` pointing at them.

  Called from an extension module's body, before `use Spark.Dsl.Extension`.
  """
  @spec attach(Spark.Dsl.Section.t(), module()) :: Spark.Dsl.Section.t()
  def attach(%Spark.Dsl.Section{} = section, namespace) do
    {entities, imports} = level(section.entities, Module.concat(namespace, Wrappers))
    %{section | entities: entities, imports: section.imports ++ imports}
  end

  # One level of nesting: the wrappers for these entities go into `module`, which is
  # imported wherever these entities are. Their own children get a module of their
  # own, imported in their body.
  defp level(entities, module) do
    blocked = Enum.filter(entities, &takes_block?/1)
    if blocked != [], do: define!(module, blocked)

    entities =
      Enum.map(entities, fn entity ->
        children = Module.concat(module, Macro.camelize(Atom.to_string(entity.name)))

        {nested, imports} =
          Enum.map_reduce(entity.entities, [], fn {key, list}, imports ->
            {list, more} = level(list, children)
            {{key, list}, Enum.uniq(imports ++ more)}
          end)

        %{entity | entities: nested, imports: entity.imports ++ imports}
        |> with_options_transform()
      end)

    {entities, if(blocked == [], do: [], else: [module])}
  end

  defp takes_block?(entity), do: entity.entities != []

  defp define!(module, entities) do
    macros =
      for entity <- entities do
        args = Macro.generate_arguments(length(entity.args), __MODULE__)

        quote do
          @doc false
          defmacro unquote(entity.name)(unquote_splicing(args), opts, block) do
            EhOsContract.DslWrappers.expand(
              unquote(entity.name),
              unquote(args),
              opts,
              block,
              __CALLER__
            )
          end
        end
      end

    Module.create(
      module,
      [quote(do: @moduledoc(false)) | macros],
      Macro.Env.location(__ENV__)
    )
  end

  @doc false
  @spec expand(atom(), [Macro.t()], Macro.t(), Macro.t(), Macro.Env.t()) :: Macro.t()
  def expand(name, args, opts, block, caller) do
    unless is_list(opts) and Keyword.keyword?(opts) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "#{name}: the options beside a do block must be a literal keyword list, " <>
            "got #{Macro.to_string(opts)}"
    end

    unless match?([do: _], block) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "#{name}: expected a do block after the options, got #{Macro.to_string(block)}"
    end

    {name, [line: caller.line], args ++ [opts ++ block]}
  end

  defp with_options_transform(%{transform: nil} = entity) do
    optional = for {:optional, name} <- entity.args, do: name
    optional = optional ++ for {:optional, name, _default} <- entity.args, do: name

    if optional == [] or not takes_block?(entity) do
      entity
    else
      options =
        for {key, spec} <- entity.schema, key not in arg_names(entity), do: {key, loose(spec)}

      %{entity | transform: {__MODULE__, :options_from_optional_argument, [optional, options]}}
    end
  end

  defp with_options_transform(%{name: name}) do
    raise ArgumentError,
          "#{name} has its own transform, which EhOsContract.DslWrappers cannot chain"
  end

  defp arg_names(entity) do
    Enum.map(entity.args, fn
      {:optional, name} -> name
      {:optional, name, _default} -> name
      name -> name
    end)
  end

  # Options given beside a block were not checked against the schema, since Spark took
  # them for an argument. They are checked here, but nothing is required or defaulted:
  # a required option may have been set inside the block.
  defp loose(spec), do: spec |> Keyword.delete(:required) |> Keyword.delete(:default)

  @doc false
  @spec options_from_optional_argument(struct(), [atom()], keyword()) ::
          {:ok, struct()} | {:error, term()}
  def options_from_optional_argument(built, optional, options) do
    last_given = optional |> Enum.reverse() |> Enum.find(&(Map.get(built, &1) != nil))
    value = last_given && Map.get(built, last_given)

    if is_list(value) and value != [] and Keyword.keyword?(value) do
      with {:ok, valid} <- Spark.Options.validate(value, options) do
        {:ok, built |> Map.put(last_given, nil) |> struct(valid)}
      end
    else
      {:ok, built}
    end
  end
end
