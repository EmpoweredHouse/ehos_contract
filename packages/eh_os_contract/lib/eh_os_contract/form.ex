defmodule EhOsContract.Form do
  # #474: a form checks what a person typed with the rules dispatch applies, read
  # from the command's declaration, never a second copy of them in the application.
  @moduledoc """
  An `Ecto.Changeset` for a form that issues a command, built from the command's
  declaration: which fields it has, their types, and the invariants of the domain values
  they hold. The form is checked while the person types, with the same rules dispatch
  applies, and the application writes none of them a second time.

  A form that records a fact (an event an actor records, `recorded_by:`) or asks a query
  (a search or a filter over a read model) is built the same way, from the event's fields
  or the query's params, for `EhOsContract.record/3` or `EhOsContract.query/3`. And
  "a form" is any input that arrives as text, a CSV import or a console among them, not
  only an HTML page.

      # mount, and phx-change="validate"
      changeset = EhOsContract.Form.changeset(Billing.Contracts.Invoicing, Commands.IssueInvoice, params)
      assign(socket, :form, to_form(changeset, action: :validate))

      # phx-submit="save"
      with {:ok, command} <- EhOsContract.Form.to_struct(changeset),
           {:ok, _receipt} <- EhOsContract.dispatch(Billing.Contracts.Invoicing, command, actor: actor) do
        ...
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          assign(socket, :form, to_form(changeset))

        {:error, reason} ->
          changeset = EhOsContract.Form.refused(changeset, reason, at: [period_open: :period])
          assign(socket, :form, to_form(changeset))
      end

  **What it reads** is what a form sends: every value as text, a field left blank
  (`""`, or only spaces) as absent, a list as `inputs_for` sends its rows. A select's
  text is found among an enum's members without creating an atom.

  **What it checks** is the shape of the input, and nothing else: that a required field
  is there, that each value is of its declared type, and that a domain value keeps its
  own invariants, a billing period written `YYYY-MM` or an amount that is not negative,
  asked of the domain as dispatch asks them. The invariants of the unit the command
  addresses, and the command's constraints, are not asked here: they need the unit's
  history, and come back as dispatch's refusal.

  **Each problem is an error at its field**, with the engine's reason in its keyword
  list, so the application writes its own words for it (with `Ecto.Changeset.traverse_errors/2`
  or its error helper), in its client's language. The engine writes no words of its own
  beyond Ecto's stock messages:

    * a field that is missing: `{"can't be blank", validation: :required}`;
    * a value not of its type: `{"is invalid", validation: :type}`;
    * a domain value that breaks one of its invariants:
      `{"is invalid", validation: :invariant, invariant: :positive}`.

  **A domain value with fields, or a list of them, is a row each**, which
  `Phoenix.Component.inputs_for/1` renders: each row is a changeset of its own, its
  problems at its fields, and an invariant of the value as a whole, which no single field
  holds, on the row's `:base`. The form is invalid while any row is; the field that holds
  the rows carries no error of theirs. A list that is not rows, or a required value left
  out, is an error at that field.

      <.inputs_for :let={line} field={@form[:items]}>
        <.input field={line[:title]} label="Line" />
        <.input field={line[:quantity]} type="number" label="Quantity" />
      </.inputs_for>

  **What it does not take from the params:**

    * a field the host supplies (`supplied_by: :host`): the page fills it in `data:`, or
      passes `supply: true` to `EhOsContract.dispatch/3`, which then asks the
      `EhOsContract.Supplier`;
    * the identity of a unit the command creates, when the unit's identity is
      `generated: :uuid`, which dispatch gives;
    * the identity of the unit the form edits: the page puts it in `data:`, and a value
      the params carry for it is ignored, so a person cannot point the form at another
      unit through the form. Only the identity is held so: any other field `data:` gives
      is a value the params may change. Holding the form to its unit is not access: who
      may act on which unit is the `EhOsContract.Authorizer`'s and the host's to say. When
      `data:` holds none, as on a form that creates a unit under an identity the person
      types, it is read from the params like any other field.

  What the form has that the command does not, a search box or a picker's query, stays
  the application's: put it in another changeset, or read it from the params yourself.

  **What dispatch refuses comes back to the form** through `refused/3`: a field's problem
  at the field, and a rejection at the field the application names for its rule, or
  above the fields.

  The changeset's data is the command's struct (the event's, the query's), so `Phoenix.HTML.FormData` names the form
  after the command (`issue_invoice[...]`), unless `to_form/2` is given `as:`. An error
  that is the whole form's is at `:base`, which a command with a field named `base` shares.

  The rule behind it, from both sides, and a LiveView page that uses it:
  [Forms](forms.md) (`docs/concepts/forms.md` in the package).
  """

  alias EhOsContract.{Codec, Dispatcher, Model, Rejection, Supplier}

  # The key of an error that is the whole form's, not one field's.
  @form_error :base

  @typedoc "A changeset `changeset/4` built, over the struct of a command, a recorded event or a query."
  @type t :: Ecto.Changeset.t()

  @doc """
  The changeset of the capability EHOS grants by `capability`'s name, for a page that knows
  the name rather than the module, as `EhOsContract.call/3` takes it: `{:command, name}`,
  `{:record, name}` or `{:query, name}`. `opts` are `changeset/4`'s, and `contracts:`, the
  contracts the name is looked up among, every registered one by default, as for `call/3`.

      EhOsContract.Form.changeset({:command, "billing.issue_invoice"}, params, data: %{invoice_id: id})

  Like `changeset/4`, it checks the shape of what was typed, which the contract's published
  documents already state, and asks no `EhOsContract.Authorizer`: whether the person may
  issue it is asked when it is sent, by `dispatch/3`, `record/3` or `query/3`.

  Raises `ArgumentError` when none of the contracts declares a capability of that kind and
  name.
  """
  @spec changeset({:command | :record | :query, String.t()}, map()) :: t()
  def changeset({_kind, _name} = capability, params), do: changeset(capability, params, [])

  @doc """
  `changeset/4` without options, or `changeset/2`'s capability with them: the first
  argument tells which.
  """
  @spec changeset(module(), module(), map()) :: t()
  @spec changeset({:command | :record | :query, String.t()}, map(), keyword()) :: t()
  def changeset(contract, command, params) when is_atom(contract),
    do: changeset(contract, command, params, [])

  def changeset({kind, name}, params, opts)
      when kind in [:command, :record, :query] and is_binary(name) and is_map(params) do
    {contracts, opts} = Keyword.pop_lazy(opts, :contracts, &EhOsContract.Registry.contracts/0)

    case Dispatcher.route(contracts, kind, name) do
      {:ok, model, declaration} ->
        generated = if kind == :record, do: :event, else: kind
        module = Model.module_for(model, generated, declaration.name)
        changeset(model.module, module, params, opts)

      {:error, :not_found} ->
        raise ArgumentError, "no contract among those given declares #{kind} #{inspect(name)}"
    end
  end

  @doc """
  The changeset of `command` for the form's `params`: a command module of `contract`, or
  the module of an event it lets an actor record, or of one of its queries. An event's
  fields and a query's params are read and checked as a command's are; a query has no
  identity.

  `opts`:

    * `data:`, a map of the command's fields the form starts from, the identity of the
      unit an edit form changes among them. Its values are the command's as the engine
      holds them (an atom for an enum's member, a `Date`, a `Decimal`, a map for a domain
      value with fields), not as a form sends them. A field the params leave out keeps
      the value `data:` gives it, so an edit form need not render every field; one the
      params carry, even blank, is read from them.

  The changeset is valid when the params hold everything the command needs, in its
  types; it has no `action`, which `Phoenix.Component.to_form/2` is given.

      changeset =
        EhOsContract.Form.changeset(Till, Till.Commands.PayIn, %{"amount" => "0"},
          data: %{till_id: "till-1"}
        )

      changeset.errors
      #=> [amount: {"is invalid", [validation: :invariant, invariant: :positive]}]

  Raises `ArgumentError` when `contract` is not a contract or `command` is none of its
  commands, recorded events or queries, and when `data:` names a field the command does not have, holds a value not of
  its field's type, holds an identity dispatch generates, or holds part of an identity of
  several fields: the page's mistakes, which dispatch would refuse at a field the person
  never sees.
  """
  @spec changeset(module(), module(), map(), keyword()) :: t()
  def changeset(contract, command, params, opts) when is_atom(contract) and is_map(params) do
    model = contract!(contract)
    declaration = declaration!(model, command)
    given = Keyword.get(opts, :data, %{})
    data = data!(command, given)
    values = Codec.values(model.domain)

    excluded = excluded(model, declaration)
    fixed = for field <- identity(model, declaration), Map.get(data, field) != nil, do: field
    data_fits!(model, declaration, given, values, excluded, fixed)
    cast = Enum.reject(declaration.fields, &(&1.name in excluded or &1.name in fixed))

    # What the form never reads is not kept either: `Phoenix.HTML.FormData` shows a field's
    # params when it has no change, so a tampered identity would be shown for the real one.
    sent = Map.drop(stringified(params), Enum.map(excluded ++ fixed, &to_string/1))

    build(declaration.fields, cast, sent, data, values, model.domain)
  end

  # A changeset over `data` for `fields`, reading those of `cast` from `params`: the form's
  # whole, or one row of a domain value with fields, which is built the same way.
  defp build(fields, cast, params, data, values, domain) do
    types = Map.new(fields, &{&1.name, field_type(&1, values)})

    {changes, rows, errors} =
      Enum.reduce(cast, {%{}, %{}, []}, &read_field(&1, params, data, values, domain, &2))

    changeset = Ecto.Changeset.change({data, types}, changes)

    changeset = %{
      changeset
      | changes: Map.merge(changeset.changes, rows),
        params: params,
        valid?: changeset.valid? and Enum.all?(rows, fn {_name, row} -> valid_rows?(row) end)
    }

    # `add_error/4` puts each in front, so the last field's goes in first.
    Enum.reduce(errors, changeset, fn {field, {message, keys}}, changeset ->
      Ecto.Changeset.add_error(changeset, field, message, keys)
    end)
  end

  # A field the params leave out keeps what `data:` gave it: an edit form need not render
  # every field. A domain value with fields becomes a changeset per row, which
  # `Phoenix.HTML.FormData`'s `inputs_for` shows with its own errors.
  defp read_field(field, params, data, values, domain, {changes, rows, errors}) do
    sent? = Map.has_key?(params, Atom.to_string(field.name))
    held = Map.get(data, field.name)

    case shape(field.type, values) do
      :flat when not sent? and held != nil ->
        {changes, rows, errors}

      :flat ->
        case read(field, params, values, domain) do
          {:ok, value} -> {Map.put(changes, field.name, value), rows, errors}
          {:error, problem} -> {changes, rows, [{field.name, error(problem)} | errors]}
        end

      {cardinality, value} ->
        raw = if sent?, do: Map.get(params, Atom.to_string(field.name)), else: held
        # The rows of what `data:` holds. `inputs_for` builds rows from the data when a field
        # has no change, and cannot from a plain map, so a field always gets rows of its own.
        kept =
          if held in [nil, []], do: nil, else: rows_of(cardinality, value, held, values, domain)

        case {nested(cardinality, value, raw, sent?, values, domain), sent?} do
          {:absent, false} when held != nil ->
            {changes, Map.put(rows, field.name, kept), errors}

          # Cleared on purpose: the form sent it, blank.
          {:absent, true} when field.optional ->
            {changes, Map.put(rows, field.name, if(cardinality == :one, do: nil, else: [])),
             errors}

          {:absent, false} when field.optional ->
            {changes, rows, errors}

          {problem, _sent?} when problem in [:absent, :type] ->
            rows = if kept, do: Map.put(rows, field.name, kept), else: rows

            {changes, rows,
             [{field.name, error(if problem == :absent, do: :required, else: :type)} | errors]}

          {row_or_rows, _sent?} ->
            {changes, Map.put(rows, field.name, row_or_rows), errors}
        end
    end
  end

  defp rows_of(cardinality, value, held, values, domain) do
    case nested(cardinality, value, held, false, values, domain) do
      problem when problem in [:absent, :type] -> nil
      row_or_rows -> row_or_rows
    end
  end

  # A domain value with fields, one or a list, read from what the form sent or from `data:`.
  defp nested(_cardinality, _value, raw, _sent?, _values, _domain)
       when raw in [nil, "", []] or raw == %{},
       do: :absent

  defp nested(:one, value, raw, sent?, values, domain) when is_map(raw),
    do: row(value, raw, sent?, values, domain)

  defp nested(:many, value, raw, sent?, values, domain) do
    case if(sent?, do: Codec.form_rows(raw), else: {:ok, raw}) do
      {:ok, items} when is_list(items) ->
        if Enum.all?(items, &is_map/1),
          do: Enum.map(items, &row(value, &1, sent?, values, domain)),
          else: :type

      _not_rows ->
        :type
    end
  end

  defp nested(_cardinality, _value, _raw, _sent?, _values, _domain), do: :type

  # One row: its fields read as the form's are, and, once they all fit, the value's own
  # invariants, which no single field holds, on the row's `:base`.
  defp row(value, raw, sent?, values, domain) do
    %{fields: fields} = Map.fetch!(values, value)
    {params, data} = if sent?, do: {stringified(raw), %{}}, else: {%{}, plain(raw)}
    data = Map.new(fields, &{&1.name, Map.get(data, &1.name)})
    changeset = build(fields, fields, params, data, values, domain)

    whole = [%{name: :value, type: value}]

    with true <- changeset.valid?,
         [value: problem] <- Codec.problems(whole, %{value: applied(changeset)}, values, domain) do
      {message, keys} = error(problem)
      Ecto.Changeset.add_error(changeset, @form_error, message, keys)
    else
      _fits_or_already_refused -> changeset
    end
  end

  defp valid_rows?(nil), do: true
  defp valid_rows?(%Ecto.Changeset{valid?: valid?}), do: valid?
  defp valid_rows?(rows) when is_list(rows), do: Enum.all?(rows, &valid_rows?/1)

  # What a changeset holds, its rows applied into the maps a command's field carries.
  defp applied(%Ecto.Changeset{data: data, changes: changes}),
    do:
      Enum.reduce(changes, data, fn {name, value}, acc -> Map.put(acc, name, applied(value)) end)

  defp applied(rows) when is_list(rows), do: Enum.map(rows, &applied/1)
  defp applied(value), do: value

  # A row `data:` holds, as a map: an embedded schema's struct, from a read model, too.
  defp plain(%_{} = struct), do: Map.from_struct(struct)
  defp plain(map), do: map

  @doc """
  The struct a valid changeset holds, `{:ok, struct}`: the command for
  `EhOsContract.dispatch/3`, the event for `EhOsContract.record/3`, or the query for
  `EhOsContract.query/3`. Or `{:error, changeset}` with the action `:insert`, so the form
  shows its errors.

  The fields the changeset does not take from the params are as `data:` gave them, or
  nil: dispatch supplies the host's, and gives a generated identity.
  """
  @spec to_struct(t()) :: {:ok, struct()} | {:error, t()}
  def to_struct(%Ecto.Changeset{valid?: true} = changeset),
    do: {:ok, applied(changeset)}

  def to_struct(%Ecto.Changeset{} = changeset),
    do: {:error, %{changeset | action: :insert}}

  @doc """
  The changeset with what dispatch refused put back on it, for the form to show, with the
  action `:insert`.

    * `{:invalid, problems}`: each problem at its field, as `changeset/4` puts its own,
      and an entity the host does not have (`:unknown`, a company id that names no
      company) as `{"does not exist", validation: :unknown}`. A problem at a field the
      form never sent, the identity in `data:` or a field the host supplies, goes on
      `:base` with `field:` naming it, so it is never shown at an input that is not there;
    * an `EhOsContract.Rejection`, a rule of the unit or a constraint of the command that
      refused it: `{"was refused", validation: :rejected, invariant: name}`, at the field
      `at:` names for the rule, or at `:base`, the whole form's, when it names none. A
      rule names no field, and the rejection carries none of the values, so which field
      it is about is the application's to say;
    * anything else, a capability the person lacks, an idempotency key, the host failing
      to supply a field: the changeset unchanged but for its action. None of those is a
      field's, and the page says it in its own words, from the reason it holds.

  `opts`:

    * `at:`, a keyword list from a rule's name to the field a rejection on it is shown
      at: `at: [period_open: :period]`.

  ```elixir
  {:error, %EhOsContract.Rejection{invariant: :period_open}} = EhOsContract.dispatch(...)
  changeset = EhOsContract.Form.refused(changeset, reason, at: [period_open: :period])
  changeset.errors
  #=> [period: {"was refused", [validation: :rejected, invariant: :period_open]}]
  ```

  Raises `ArgumentError` when `at:` names a field the command does not have.
  """
  @spec refused(t(), term(), keyword()) :: t()
  def refused(%Ecto.Changeset{data: %command{}} = changeset, reason, opts \\ []) do
    at = at!(command, Keyword.get(opts, :at, []))

    reason
    |> refusal_errors(at, Map.keys(changeset.params || %{}))
    |> Enum.reduce(%{changeset | action: :insert}, fn {field, {message, keys}}, changeset ->
      Ecto.Changeset.add_error(changeset, field, message, keys)
    end)
  end

  defp refusal_errors({:invalid, problems}, _at, sent) when is_list(problems) do
    for {field, problem} <- Enum.reverse(problems) do
      {message, keys} = error(problem)

      if Atom.to_string(field) in sent,
        do: {field, {message, keys}},
        else: {@form_error, {message, keys ++ [field: field]}}
    end
  end

  defp refusal_errors(%Rejection{invariant: name}, at, _sent),
    do: [
      {Keyword.get(at, name, @form_error),
       {"was refused", validation: :rejected, invariant: name}}
    ]

  defp refusal_errors(_not_a_field, _at, _sent), do: []

  defp at!(command, at) do
    known = command |> struct() |> Map.keys()

    unless Keyword.keyword?(at) and Enum.all?(Keyword.values(at), &(&1 in known)) do
      raise ArgumentError,
            "at: takes a keyword list from a rule's name to a field of #{inspect(command)}, " <>
              "not #{inspect(at)}"
    end

    at
  end

  # One field, read as dispatch reads it: decoded from what the form sent, then held to its
  # domain value's invariants.
  defp read(field, params, values, domain) do
    case Codec.decode([field], params, values, form: true) do
      {:ok, %{} = decoded} ->
        case Codec.problems([field], decoded, values, domain) do
          [] -> {:ok, Map.fetch!(decoded, field.name)}
          [{_name, problem} | _] -> {:error, problem}
        end

      {:error, [{_name, problem} | _]} ->
        {:error, problem}
    end
  end

  defp error(:required), do: {"can't be blank", validation: :required}
  defp error(:type), do: {"is invalid", validation: :type}
  defp error({:invariant, name}), do: {"is invalid", validation: :invariant, invariant: name}
  defp error(:unknown), do: {"does not exist", validation: :unknown}
  # The engine's, never a person's: a field the host supplies or the engine generates sent anyway.
  defp error(problem) when problem in [:generated, :supplied],
    do: {"is invalid", validation: problem}

  # What dispatch gives rather than the caller: the host's supplied fields, and a generated
  # identity of a unit the command creates.
  defp excluded(model, declaration) do
    supplied = declaration.fields |> Supplier.fields() |> Enum.map(& &1.name)

    case unit(model, declaration) do
      %{generated: generated, identity: identity} when generated != nil ->
        if Map.get(declaration, :creates, false), do: identity ++ supplied, else: supplied

      _other ->
        supplied
    end
  end

  defp identity(model, declaration) do
    case unit(model, declaration) do
      %{identity: identity} -> identity
      _boundary -> []
    end
  end

  # A query addresses no unit, and has no identity.
  defp unit(model, declaration),
    do: Enum.find(model.units, &(&1.name == Map.get(declaration, :unit, :none)))

  # Whether a field holds a domain value with fields, one or a list of them, which the form
  # reads row by row, or anything else, which it reads whole.
  defp shape({:list, inner}, values) do
    case shape(inner, values) do
      {:one, value} -> {:many, value}
      _other -> :flat
    end
  end

  defp shape(type, values) when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil} -> {:one, type}
      %{type: inner} -> shape(inner, values)
    end
  end

  defp shape(_type, _values), do: :flat

  # A field's type in the changeset: an embed for a domain value with fields, which is what
  # `inputs_for` asks for, though no schema stands behind it and nothing is cast through it.
  defp field_type(field, values) do
    case shape(field.type, values) do
      {cardinality, _value} ->
        {:embed,
         %Ecto.Embedded{cardinality: cardinality, field: field.name, related: __MODULE__.Row}}

      :flat ->
        ecto_type(field.type, values)
    end
  end

  # The changeset's types, from the declaration's, for the form to show each value.
  defp ecto_type(type, _values) when type in [:string, :id], do: :string
  defp ecto_type({:id, _entity}, _values), do: :string
  defp ecto_type(:timestamp, _values), do: :utc_datetime_usec
  defp ecto_type(type, _values) when type in [:integer, :boolean, :decimal, :date], do: type

  defp ecto_type({:enum, members}, _values),
    do:
      Ecto.ParameterizedType.init(Ecto.Enum,
        values:
          Enum.map(members, fn
            {name, _label} -> name
            name -> name
          end)
      )

  defp ecto_type({:list, inner}, values), do: {:array, ecto_type(inner, values)}

  defp ecto_type(type, values) when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil} -> :map
      %{type: inner} -> ecto_type(inner, values)
    end
  end

  defp ecto_type(_type, _values), do: :any

  # A form keyed by atoms, from a test or the page's own code, as a form's would be.
  defp stringified(params), do: Map.new(params, fn {key, value} -> {to_string(key), value} end)

  defp data!(command, data) when is_map(data) do
    known = command |> struct() |> Map.keys()

    case Map.keys(data) -- known do
      [] ->
        struct(command, data)

      unknown ->
        raise ArgumentError,
              "data: names #{inspect(unknown)}, which #{inspect(command)} does not have"
    end
  end

  # The page's data, held to what dispatch will hold the command to, so its mistakes fail
  # here, by the field's name and never its value, rather than as a refusal at a field the
  # person has no input for.
  defp data_fits!(model, declaration, given, values, excluded, fixed) do
    identity = identity(model, declaration)
    present = for {name, value} <- given, value != nil, do: name

    generated = Enum.filter(identity, &(&1 in excluded and &1 in present))
    if generated != [], do: bad_data!(generated, "an identity dispatch generates")

    if fixed != [] and fixed != identity,
      do: bad_data!(identity -- fixed, "the rest of an identity of several fields")

    fields = Enum.filter(declaration.fields, &(&1.name in present))

    case Codec.problems(fields, Map.new(given), values, model.domain) do
      [] ->
        :ok

      problems ->
        bad_data!(Keyword.keys(problems), "a value its field's type and invariants allow")
    end
  end

  defp bad_data!(fields, what),
    do: raise(ArgumentError, "data: needs #{what}, for #{inspect(fields)}")

  defp contract!(contract) do
    case Model.fetch(contract) do
      %{kind: :contract, units: _} = model -> model
      %{module: module} -> raise ArgumentError, "#{inspect(module)} is not a contract"
    end
  end

  # The declaration whose struct `module` is: a command, an event an actor records, or a
  # query, whose params are its fields here.
  defp declaration!(model, module) do
    Enum.find(model.commands, &(Model.module_for(model, :command, &1.name) == module)) ||
      Enum.find(model.events, fn event ->
        event.recorded_by != [] and Model.module_for(model, :event, event.name) == module
      end) ||
      Enum.find_value(model.queries, fn query ->
        if Model.module_for(model, :query, query.name) == module,
          do: Map.put(query, :fields, query.params)
      end) ||
      raise ArgumentError,
            "#{inspect(module)} is not a command, a recorded event or a query of " <>
              inspect(model.module)
  end
end

defmodule EhOsContract.Form.Row do
  # What `Phoenix.HTML.FormData` builds a row from when a form has none of a value's yet,
  # through `Ecto.Changeset.change/1`, which asks a schema's types of `__changeset__/0`: a
  # row with no fields, so every input of it is empty.
  @moduledoc false
  defstruct []

  @doc false
  @spec __changeset__() :: %{}
  def __changeset__, do: %{}
end
