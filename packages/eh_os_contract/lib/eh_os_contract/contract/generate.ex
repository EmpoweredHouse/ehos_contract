defmodule EhOsContract.Contract.Generate do
  # Generates the modules a v2 contract names (v2 §5), structs and behaviours, after
  # `Build` has made its model.
  #
  # **Structs.** For a contract `C`:
  #
  # | Module | From |
  # | --- | --- |
  # | `C.Commands.PayLateFee` | a command |
  # | `C.Events.LateFeePaid` | an event of a unit |
  # | `C.Received.InvoiceIssued` | `subscribe "<name>", as: :invoice_issued`, with the fields declared there |
  # | `C.Aggregates.Loan.State`, `C.Dcbs.*.State`, `C.ProcessManagers.*.State` | a state |
  # | `C.ReadModels.MemberDirectory.Row` | a read model's fields, an Ecto schema |
  # | `C.Queries.MemberContact` | a query's parameters |
  #
  # A unit's identity comes first in its state, commands and events, as the model
  # injects it. A command, an event and a received event enforce their required
  # fields and carry `__meta__`, an `EhOsContract.Meta` that dispatch and the store
  # set. A state starts from its defaults, and a query's parameters are a plain
  # struct. A read model's row is an Ecto schema (#472): of its `table:`, with its
  # `key:` as the primary key, or embedded when it names no table, so a query reads
  # `from r in Row` and a projection writes through it, with the contract's types.
  #
  # Each module's `@type t` uses a domain value as a remote type of the domain's
  # generated `Values` module, which records no compile dependency (v2 §8). Each is
  # created at the file and line of its declaration, so going to its definition
  # lands on the DSL. `EhOsContract.Model.module_for/3` names them.
  #
  # An event consumed from a sibling contract gets no struct here: the sibling's own
  # is the only one (v2 §7, mechanism 1).
  #
  # **Behaviours.** `C.Aggregates.*`, `C.Dcbs.*`, `C.Policies.*`, `C.Effects.*`,
  # `C.ProcessManagers.*`, `C.ReadModels.*` and `C.DomainServices.*` each declare the
  # callbacks an implementation of that declaration defines; a query's one callback
  # sits in `C.Queries.*`, beside its parameters. A domain service's module also
  # defines each of its functions, which a decision calls: it checks the arguments,
  # calls the implementation, and checks the result (`EhOsContract.DomainService`). Which callbacks, with which types, is
  # `EhOsContract.Contract.Callbacks`: the same list the implementation macros
  # check against.
  #
  # Each behaviour's `@moduledoc` and each callback's `@doc` say what the contract says
  # of it, rules and scenarios included (plan EP3): `EhOsContract.Contract.Doc`.
  @moduledoc false

  use Spark.Dsl.Transformer

  alias EhOsContract.Domain
  alias EhOsContract.Model
  alias EhOsContract.Contract.{Build, Callbacks, Rules}
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

    queries = MapSet.new(model.queries, &Model.module_for(model, :query, &1.name))

    structs =
      for {module, what, fields, shape, key} <- structs(model) do
        body =
          case key do
            {:read_model, name} -> row_body(model, name, what, values)
            _other -> struct_body(model, what, fields, shape, values, key)
          end

        # A query's parameters and its callback are one module: `use C, query: :q`
        # binds to it, and the implementation matches on the struct.
        body =
          if MapSet.member?(queries, module),
            do:
              quote(
                do:
                  (
                    unquote(body)
                    unquote(callbacks(model, :query, elem(key, 1)))
                  )
              ),
            else: body

        create(module, body, Map.get(anno, key))
      end

    behaviours =
      for {kind, name, key} <- behaviours(model) do
        module = Model.module_for(model, kind, name)
        create(module, behaviour_body(model, kind, name), Map.get(anno, key))
      end

    # `use C, aggregate: :name` in an implementation (v2 §5).
    binding =
      quote do
        @doc "Binds an implementation to one declaration: `EhOsContract.Implementation`."
        defmacro __using__(opts),
          do: EhOsContract.Implementation.bind(__MODULE__, opts, __CALLER__)
      end

    modules = structs ++ behaviours ++ [binding]

    {:ok, Transformer.eval(dsl, [], quote(do: (unquote_splicing(modules))))}
  end

  # Plan LC2: an aggregate with a lifecycle has its status in its state, which the
  # engine computes from the stream and puts there; it is not a field of the model's
  # state, so declaring a lifecycle moves no field and `evolve/2` never sets it.
  defp status(%{lifecycle: lifecycle}) do
    [
      %{
        name: :status,
        type: {:enum, Enum.map(lifecycle.statuses, & &1.name)},
        optional: true,
        default: nil
      }
    ]
  end

  defp status(_unit), do: []

  # `{module, what it is, fields, shape, location key}` for every struct.
  defp structs(model) do
    units =
      for unit <- model.units do
        module = Model.module_for(model, unit.kind, unit.name)

        {Module.concat(module, State), "the state of #{unit.kind} #{inspect(unit.name)}",
         unit.state.fields ++ status(unit), :state, {:unit, unit.name}}
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

  # `{kind, name, location key}` for every declaration an implementation binds to,
  # except a query, whose callback sits with its parameters.
  defp behaviours(model) do
    Enum.concat([
      for(u <- model.units, do: {u.kind, u.name, {:unit, u.name}}),
      for(p <- model.policies, do: {:policy, p.name, {:policy, p.name}}),
      for(e <- model.effects, do: {:effect, e.name, {:effect, e.name}}),
      for(
        pm <- model.process_managers,
        do: {:process_manager, pm.name, {:process_manager, pm.name}}
      ),
      for(r <- model.read_models, do: {:read_model, r.name, {:read_model, r.name}}),
      for(
        s <- model.domain_services,
        do: {:domain_service, s.name, {:domain_service, s.name}}
      )
    ])
  end

  defp behaviour_body(model, kind, name) do
    doc =
      "What an implementation of #{String.replace(Atom.to_string(kind), "_", " ")} " <>
        "`#{inspect(name)}` of `#{inspect(model.module)}` defines, generated from its declaration. " <>
        "Bound with `use #{inspect(model.module)}, #{kind}: #{inspect(name)}`."

    # Plan EP3: the declaration's label, source and rules follow the sentence.
    doc = EhOsContract.Contract.Doc.moduledoc(model, kind, name, doc)

    quote do
      @moduledoc unquote(doc)
      unquote(callbacks(model, kind, name))
      unquote(if kind == :read_model, do: reset())
      unquote(if kind == :domain_service, do: calls(model, name))
    end
  end

  # A domain service is called through its behaviour's module, which holds each call
  # to the declaration: the arguments before the implementation runs, its result
  # after (plan EM2, the user's choice of 27 September 2026).
  defp calls(model, name) do
    service = Enum.find(model.domain_services, &(&1.name == name))
    %{callbacks: callbacks} = Callbacks.of(model, :domain_service, name)

    by_name = Map.new(callbacks, &{&1.name, &1})

    functions =
      for f <- service.functions, c = Map.fetch!(by_name, f.name) do
        args = Macro.generate_arguments(length(f.arguments), __MODULE__)

        quote do
          @doc unquote(
                 "#{f.label}. Calls the implementation of `#{inspect(name)}` and holds the " <>
                   "arguments and the result to their declared types."
               )
          @spec unquote(f.name)(unquote_splicing(c.args)) :: unquote(c.returns)
          def unquote(f.name)(unquote_splicing(args)) do
            EhOsContract.DomainService.call(
              unquote(model.module),
              unquote(name),
              unquote(f.name),
              unquote(args)
            )
          end
        end
      end

    quote(do: (unquote_splicing(functions)))
  end

  # A read model writes the host's tables, which the library does not know, so only
  # the implementation can empty them before a rebuild (v2 §12; the user's choice of
  # 26 September 2026). Optional: a read model without it is never rebuilt.
  defp reset do
    quote do
      @doc """
      Deletes every row this read model wrote, before it is rebuilt from the log.
      Optional: without it the read model cannot be rebuilt, and a changed declaration
      leaves its subscription `stale`.
      """
      @callback reset() :: :ok

      @doc """
      Deletes, or blanks, what this read model keeps of an erased subject's personal
      data. Required of a read model that projects personal data: without
      it, the host does not boot. A read model delivered in the transaction forgets
      inside the erasure's, under the append lock, so keep it fast: index the column
      that holds the subject's id.
      """
      @callback forget(subject_type :: atom(), subject_id :: String.t()) :: :ok
      @optional_callbacks reset: 0, forget: 2
    end
  end

  defp callbacks(model, kind, name) do
    %{callbacks: callbacks, evolve: evolve} = Callbacks.of(model, kind, name)

    # Plan EP3: each callback carries what the contract says of it, so whoever writes
    # the implementation reads the rules where the code goes.
    docs =
      Enum.map(callbacks, &{&1, EhOsContract.Contract.Doc.callback(model, kind, name, &1.name)}) ++
        if(evolve,
          do: [{evolve.callback, EhOsContract.Contract.Doc.evolve(kind, evolve.events)}],
          else: []
        )

    specs =
      for {c, doc} <- docs do
        quote do
          @doc unquote(doc)
          @callback unquote(c.name)(unquote_splicing(c.args)) :: unquote(c.returns)
        end
      end

    quote(do: (unquote_splicing(specs)))
  end

  defp struct_body(model, what, fields, shape, values, key) do
    doc =
      "#{String.capitalize(what)} of `#{inspect(model.module)}`, generated from its declaration."

    # A query's module is also its behaviour (its callback sits here), so its
    # moduledoc says what the contract says of the query, as a behaviour's does (EP3).
    doc =
      case key do
        {:query, name} -> EhOsContract.Contract.Doc.moduledoc(model, :query, name, doc)
        _ -> doc
      end

    defaults =
      for f <- fields, do: {f.name, if(shape == :state, do: Map.get(f, :default), else: nil)}

    enforce = if shape == :message, do: for(f <- fields, not f.optional, do: f.name), else: []

    types =
      for f <- fields do
        type = typespec(f.type, values)

        # What a personal field reads back as once its subject is erased (v2 §14).
        type =
          if Map.get(f, :personal),
            do: quote(do: unquote(type) | EhOsContract.Erased.t()),
            else: type

        {f.name,
         if(f.optional or shape != :message, do: quote(do: unquote(type) | nil), else: type)}
      end

    {defaults, types} =
      if shape == :message,
        do:
          {defaults ++ [__meta__: nil],
           types ++ [__meta__: quote(do: EhOsContract.Meta.t() | nil)]},
        else: {defaults, types}

    # A person's data stays out of a command, an event or a state printed in a log, a
    # crash report or a failed scenario's message, as a value's struct keeps its own.
    personal = for f <- fields, Map.get(f, :personal), do: f.name

    quote do
      @moduledoc unquote(doc)
      unquote(if personal != [], do: quote(do: @derive({Inspect, except: unquote(personal)})))
      @enforce_keys unquote(enforce)
      defstruct unquote(Macro.escape(defaults))
      @type t :: %__MODULE__{unquote_splicing(types)}
    end
  end

  # A read model's row (#472): an Ecto schema whose fields are the declaration's, in
  # its order, each of the Ecto type `EhOsContract.EctoTypes` gives the declared one.
  # A domain value's type is read from the domain when it is first used, since the
  # contract does not depend on its domain at compile time.
  defp row_body(model, name, what, values) do
    read_model = Enum.find(model.read_models, &(&1.name == name))
    table = Map.get(read_model, :table)
    key = Map.get(read_model, :key, [])

    doc =
      "#{String.capitalize(what)} of `#{inspect(model.module)}`, generated from its " <>
        "declaration: an Ecto schema" <>
        if(table,
          do: " of table `#{table}`, keyed by #{Enum.map_join(key, ", ", &"`#{&1}`")}.",
          else: ", embedded, since the read model names no table."
        )

    fields =
      for f <- read_model.fields do
        {type, opts} = ecto_field(f.type, model.domain)
        opts = if f.name in key, do: [primary_key: true] ++ opts, else: opts
        # A person's data stays out of a row printed in a log or a failed test.
        opts = if Map.get(f, :personal), do: [redact: true] ++ opts, else: opts
        quote(do: field(unquote(f.name), unquote(Macro.escape(type)), unquote(opts)))
      end

    schema =
      if table,
        do: quote(do: schema(unquote(table), do: (unquote_splicing(fields)))),
        else: quote(do: embedded_schema(do: (unquote_splicing(fields))))

    types =
      for f <- read_model.fields do
        type = typespec(f.type, values)

        # A row an implementation builds may carry what an erased field reads back as;
        # one loaded from a table holds `nil` there, since a column cannot hold it.
        type =
          if Map.get(f, :personal) && table == nil,
            do: quote(do: unquote(type) | EhOsContract.Erased.t()),
            else: type

        {f.name, quote(do: unquote(type) | nil)}
      end

    types = if table, do: [__meta__: quote(do: Ecto.Schema.Metadata.t())] ++ types, else: types

    quote do
      @moduledoc unquote(doc)
      use Ecto.Schema
      @primary_key false
      unquote(schema)
      @type t :: %__MODULE__{unquote_splicing(types)}
    end
  end

  # `{type, options}` of a row's `field/3`: an enum is an `Ecto.Enum` of its members,
  # a domain value, or a list of one, the type its domain gives it, anything else
  # `EctoTypes.of/2`'s. Not `of/2` itself: `field/3` takes a type's module and options,
  # never an initialised `{:parameterized, …}`, and a domain value is not known here.
  defp ecto_field({:list, value}, domain)
       when is_atom(value) and value not in @built_in,
       do: {EhOsContract.EctoTypes.Value, domain: domain, value: value, list: true}

  defp ecto_field({:enum, members}, _domain),
    do: {Ecto.Enum, values: EhOsContract.EctoTypes.members(members)}

  defp ecto_field({:list, inner}, domain) do
    {type, opts} = ecto_field(inner, domain)
    {{:array, type}, opts}
  end

  defp ecto_field({:id, _entity} = type, _domain), do: {EhOsContract.EctoTypes.of(type, %{}), []}

  defp ecto_field(type, _domain) when type in @built_in,
    do: {EhOsContract.EctoTypes.of(type, %{}), []}

  defp ecto_field(value, domain) when is_atom(value),
    do: {EhOsContract.EctoTypes.Value, domain: domain, value: value}

  @doc false
  @spec typespec(term(), module()) :: Macro.t()
  def typespec({:list, inner}, values), do: quote(do: [unquote(typespec(inner, values))])
  def typespec({:id, _entity}, _values), do: Domain.Build.typespec(:id)
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
        for(p <- d.policies, do: {{:policy, p.name}, p}),
        for(e <- d.effects, do: {{:effect, e.name}, e}),
        for(r <- d.read_models, do: {{:read_model, r.name}, r}),
        for(q <- d.queries, do: {{:query, q.name}, q}),
        for(s <- d.domain_services, do: {{:domain_service, s.name}, s})
      ])

    Map.new(pairs, fn {key, declaration} -> {key, Spark.Dsl.Entity.anno(declaration)} end)
  end
end
