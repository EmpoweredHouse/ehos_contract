defmodule EhOsContract.Next.Contract.Generate do
  @moduledoc """
  Generates the modules a v2 contract names (v2 §5), after `Build` has made its
  model.

  **Structs.** For a contract `C`:

  | Module | From |
  | --- | --- |
  | `C.Commands.RecordPayment` | a command |
  | `C.Events.PaymentRecorded` | an event of a unit |
  | `C.Received.VisitClosed` | `consumes "<name>", as: :visit_closed`, with the fields declared there |
  | `C.Aggregates.VisitSettlement.State`, `C.Dcbs.*.State`, `C.ProcessManagers.*.State` | a state |
  | `C.ReadModels.DailyTotals.Row` | a read model's fields |
  | `C.Queries.DailyTotalsFor` | a query's parameters |

  A unit's identity comes first in its state, commands and events, as the model
  injects it. A command, an event and a received event enforce their required
  fields and carry `__meta__`, an `EhOsContract.Meta` that dispatch and the store
  set. A state starts from its defaults, and a row and a query's parameters are
  plain structs.

  Each module's `@type t` uses a domain value as a remote type of the domain's
  generated `Values` module, which records no compile dependency (v2 §8). Each is
  created at the file and line of its declaration, so going to its definition
  lands on the DSL. `EhOsContract.Model.module_for/3` names them.

  An event consumed from a sibling contract gets no struct here: the sibling's own
  is the only one (v2 §7, mechanism 1).
  """

  use Spark.Dsl.Transformer

  alias EhOsContract.Domain
  alias EhOsContract.Model
  alias EhOsContract.Next.Contract.{Build, Rules}
  alias Spark.Dsl.Transformer

  @built_in Domain.Rules.built_in_types()

  @impl true
  def after?(Build), do: true
  def after?(_), do: false

  @impl true
  def transform(dsl) do
    model = Transformer.get_persisted(dsl, :eh_os_contract_model)
    anno = locations(Rules.declarations(dsl))
    values = Module.concat(model.domain, Values)

    modules =
      for {module, what, fields, shape, key} <- structs(model) do
        create(module, struct_body(model, what, fields, shape, values), Map.get(anno, key))
      end

    {:ok, Transformer.eval(dsl, [], quote(do: (unquote_splicing(modules))))}
  end

  # `{module, what it is, fields, shape, location key}` for every struct.
  defp structs(model) do
    units =
      for unit <- model.units do
        module = Model.module_for(model, unit.kind, unit.name)

        {Module.concat(module, State), "the state of #{unit.kind} #{inspect(unit.name)}",
         unit.state.fields, :state, {:unit, unit.name}}
      end

    managers =
      for pm <- model.process_managers do
        module = Model.module_for(model, :process_manager, pm.name)

        {Module.concat(module, State), "the state of process manager #{inspect(pm.name)}",
         pm.state.fields, :state, {:process_manager, pm.name}}
      end

    Enum.concat([
      for(
        c <- model.commands,
        do:
          {Model.module_for(model, :command, c.name), "command #{inspect(c.name)}", c.fields,
           :message, {:command, c.name}}
      ),
      for(
        e <- model.events,
        do:
          {Model.module_for(model, :event, e.name), "event #{inspect(e.name)}", e.fields,
           :message, {:event, e.name}}
      ),
      for(
        %{kind: :published, as: as} = c <- model.consumes,
        is_atom(as) and as != nil,
        do:
          {Model.module_for(model, :event, as), "event #{inspect(as)}, received as #{c.from}",
           c.fields, :message, {:received, as}}
      ),
      units,
      managers,
      for(
        r <- model.read_models,
        do:
          {Module.concat(Model.module_for(model, :read_model, r.name), Row),
           "a row of read model #{inspect(r.name)}", r.fields, :plain, {:read_model, r.name}}
      ),
      for(
        q <- model.queries,
        do:
          {Model.module_for(model, :query, q.name), "the parameters of query #{inspect(q.name)}",
           q.params, :plain, {:query, q.name}}
      )
    ])
  end

  defp struct_body(model, what, fields, shape, values) do
    doc =
      "#{String.capitalize(what)} of `#{inspect(model.module)}`, generated from its declaration."

    defaults =
      for f <- fields, do: {f.name, if(shape == :state, do: Map.get(f, :default), else: nil)}

    enforce = if shape == :message, do: for(f <- fields, not f.optional, do: f.name), else: []

    types =
      for f <- fields do
        type = typespec(f.type, values)

        {f.name,
         if(f.optional or shape != :message, do: quote(do: unquote(type) | nil), else: type)}
      end

    {defaults, types} =
      if shape == :message,
        do:
          {defaults ++ [__meta__: nil],
           types ++ [__meta__: quote(do: EhOsContract.Meta.t() | nil)]},
        else: {defaults, types}

    quote do
      @moduledoc unquote(doc)
      @enforce_keys unquote(enforce)
      defstruct unquote(Macro.escape(defaults))
      @type t :: %__MODULE__{unquote_splicing(types)}
    end
  end

  @doc false
  @spec typespec(term(), module()) :: Macro.t()
  def typespec({:list, inner}, values), do: quote(do: [unquote(typespec(inner, values))])
  def typespec({:enum, _} = enum, _values), do: Domain.Build.typespec(enum)
  def typespec(type, _values) when type in @built_in, do: Domain.Build.typespec(type)
  def typespec(value, values) when is_atom(value), do: quote(do: unquote(values).unquote(value)())

  # `Module.create/3` at the declaration's file and line, when Spark recorded one.
  defp create(module, body, anno) do
    location =
      case anno do
        nil -> []
        anno -> [file: anno |> :erl_anno.file() |> to_string(), line: :erl_anno.line(anno)]
      end

    quote do
      Module.create(
        unquote(module),
        unquote(Macro.escape(body)),
        Keyword.merge(Macro.Env.location(__ENV__), unquote(location))
      )
    end
  end

  defp locations(d) do
    pairs =
      Enum.concat([
        for(u <- d.units, do: {{:unit, u.name}, u}),
        for(c <- Rules.commands(d), do: {{:command, c.name}, c}),
        for(e <- Rules.local_events(d), do: {{:event, e.name}, e}),
        for({as, c} <- Rules.consumed(d), is_binary(c.from), do: {{:received, as}, c}),
        for(pm <- d.process_managers, do: {{:process_manager, pm.name}, pm}),
        for(r <- d.read_models, do: {{:read_model, r.name}, r}),
        for(q <- d.queries, do: {{:query, q.name}, q})
      ])

    Map.new(pairs, fn {key, declaration} -> {key, Spark.Dsl.Entity.anno(declaration)} end)
  end
end
