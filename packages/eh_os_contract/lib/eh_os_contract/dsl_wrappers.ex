defmodule EhOsContract.DslWrappers do
  @moduledoc """
  Options beside a `do` block, for the library's Spark DSLs (v2 §16, D13).

  Elixir reads `context :settlement, "Rozliczenia", subdomain: :supporting do … end`
  as four arguments: the two positional ones, the keyword list, and `[do: …]`. A Spark
  entity macro takes its positional arguments and one options list, so that call
  names a macro Spark never defines. For every entity that takes a block, one that
  has entities nested in it and options of its own, `attach/2` defines that one more
  arity from the entity's definition. It moves the block into the options, `context(name, label, opts, do: b)`
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
  gives such an entity a `transform` that applies the same rule when a block follows.
  Spark checks the argument's type before a transform runs, so the argument's type
  is widened to accept a keyword list as well, which the transform moves into the
  options before anything reads it. An optional positional argument of an entity
  that takes a block must therefore never take a keyword list as a legal value.

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
    module = Module.concat(namespace, Wrappers)
    imports = define(module, section.entities)
    entities = Enum.map(section.entities, &nest(&1, child_module(module, &1)))
    %{section | entities: entities, imports: section.imports ++ imports}
  end

  # The wrappers for an entity's children go into one module, whatever key each child
  # is nested under, and that module is imported in the entity's body. Each child's
  # own children get a module of their own, one level down.
  defp nest(entity, module) do
    children = Enum.flat_map(entity.entities, fn {_key, list} -> list end)
    imports = define(module, children)

    nested =
      for {key, list} <- entity.entities do
        {key, Enum.map(list, &nest(&1, child_module(module, &1)))}
      end

    with_options_transform(%{entity | entities: nested, imports: entity.imports ++ imports})
  end

  defp child_module(module, entity),
    do: Module.concat(module, Macro.camelize(Atom.to_string(entity.name)))

  # Returns the modules to import: the one defined, or none when no entity at this
  # level takes a block.
  defp define(module, entities) do
    case entities |> Enum.filter(&takes_block?/1) |> Enum.uniq_by(& &1.name) do
      [] ->
        []

      blocked ->
        define!(module, blocked)
        [module]
    end
  end

  # An entity with nothing nested takes no block, and one whose every key is a
  # positional argument has no options to put beside one (`state do … end`).
  defp takes_block?(entity),
    do: entity.entities != [] and Keyword.drop(entity.schema, arg_names(entity)) != []

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

  defp with_options_transform(entity) do
    optional = for {:optional, name} <- entity.args, do: name
    optional = optional ++ for {:optional, name, _default} <- entity.args, do: name

    cond do
      optional == [] or not takes_block?(entity) ->
        entity

      entity.transform != nil ->
        raise ArgumentError,
              "#{entity.name} takes a block and an optional argument, and has its own " <>
                "transform, which EhOsContract.DslWrappers cannot chain"

      true ->
        with_transform(entity, optional)
    end
  end

  defp with_transform(entity, optional) do
    options =
      for {key, spec} <- entity.schema, key not in arg_names(entity), do: {key, loose(spec)}

    defaults = for name <- optional, do: {name, entity.schema[name][:default]}

    %{
      entity
      | schema: Enum.map(entity.schema, &widen(&1, optional)),
        transform: {__MODULE__, :options_from_optional_argument, [defaults, options]}
    }
  end

  # Spark checks the argument's type before any transform runs, so an optional
  # argument's type also accepts the keyword list the transform then moves out.
  defp widen({key, spec}, optional) do
    if key in optional,
      do: {key, Keyword.update!(spec, :type, &{:or, [&1, :keyword_list]})},
      else: {key, spec}
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
  @spec options_from_optional_argument(struct(), keyword(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def options_from_optional_argument(built, defaults, options) do
    last_given =
      defaults
      |> Enum.reverse()
      |> Enum.find(fn {name, default} -> Map.get(built, name) not in [nil, default] end)

    value = last_given && Map.get(built, elem(last_given, 0))

    if is_list(value) and value != [] and Keyword.keyword?(value) do
      {name, default} = last_given

      with {:ok, valid} <- Spark.Options.validate(value, options) do
        {:ok, built |> Map.put(name, default) |> struct(valid)}
      end
    else
      {:ok, built}
    end
  end
end
