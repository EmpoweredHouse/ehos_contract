defmodule EhOsContract.Form do
  # #474: a form checks what a person typed with the rules dispatch applies, read
  # from the command's declaration, never a second copy of them in the application.
  @moduledoc """
  An `Ecto.Changeset` for a form that issues a command, built from the command's
  declaration: which fields it has, their types, and the invariants of the domain values
  they hold. The form is checked while the person types, with the same rules dispatch
  applies, and the application writes none of them a second time.

      # mount, and phx-change="validate"
      changeset = EhOsContract.Form.changeset(Billing.Contracts.Invoicing, Commands.IssueInvoice, params)
      assign(socket, :form, to_form(changeset, action: :validate))

      # phx-submit="save"
      with {:ok, command} <- EhOsContract.Form.to_command(changeset),
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
  or its error helper), in its client's language. The engine writes none:

    * a field that is missing: `{"can't be blank", validation: :required}`;
    * a value not of its type: `{"is invalid", validation: :type}`;
    * a domain value that breaks one of its invariants:
      `{"is invalid", validation: :invariant, invariant: :positive}`.

  A domain value with fields, or a list of them, is checked whole in this version: a
  problem anywhere inside it is an error at the field that holds it.

  **What it does not take from the params:**

    * a field the host supplies (`supplied_by: :host`), which `EhOsContract.Supplier` gives
      at dispatch;
    * the identity of a unit the command creates, when the unit's identity is
      `generated: :uuid`, which dispatch gives;
    * the identity of the unit the form edits: the page puts it in `data:`, and a value
      the params carry for it is ignored, so a person cannot point the form at another
      unit. When `data:` holds none, as on a form that creates a unit under an identity
      the person types, it is read from the params like any other field.

  What the form has that the command does not, a search box or a picker's query, stays
  the application's: put it in another changeset, or read it from the params yourself.

  **What dispatch refuses comes back to the form** through `refused/3`: a field's problem
  at the field, and a rejection at the field the application names for its rule, or
  above the fields.

  The changeset's data is the command's struct, so `Phoenix.HTML.FormData` names the form
  after the command (`issue_invoice[...]`), unless `to_form/2` is given `as:`.

  The rule behind it, from both sides, and a LiveView page that uses it:
  [Forms](forms.md) (`docs/concepts/forms.md` in the package).
  """

  alias EhOsContract.{Codec, Model, Rejection, Supplier}

  # The key of an error that is the whole form's, not one field's.
  @form_error :base

  @typedoc "A changeset `changeset/4` built, over the command's struct."
  @type t :: Ecto.Changeset.t()

  @doc """
  The changeset of `command`, a command module of `contract`, for the form's `params`.

  `opts`:

    * `data:`, a map of the command's fields the form starts from, the identity of the
      unit an edit form changes among them. Its values are the command's as the engine
      holds them (an atom for an enum's member, a `Date`, a `Decimal`), not as a form
      sends them.

  The changeset is valid when the params hold everything the command needs, in its
  types; it has no `action`, which `Phoenix.Component.to_form/2` is given.

      changeset =
        EhOsContract.Form.changeset(Till, Till.Commands.PayIn, %{"amount" => "0"},
          data: %{till_id: "till-1"}
        )

      changeset.errors
      #=> [amount: {"is invalid", [validation: :invariant, invariant: :positive]}]

  Raises `ArgumentError` when `contract` is not a contract or `command` is not one of its
  commands, and when `data:` names a field the command does not have.
  """
  @spec changeset(module(), module(), map(), keyword()) :: t()
  def changeset(contract, command, params, opts \\ []) when is_map(params) do
    model = contract!(contract)
    declaration = command!(model, command)
    data = data!(command, Keyword.get(opts, :data, %{}))
    values = Codec.values(model.domain)

    excluded = excluded(model, declaration)
    fixed = for field <- identity(model, declaration), Map.get(data, field) != nil, do: field
    cast = Enum.reject(declaration.fields, &(&1.name in excluded or &1.name in fixed))
    types = Map.new(declaration.fields, &{&1.name, ecto_type(&1.type, values)})

    {changes, errors} =
      Enum.reduce(cast, {%{}, []}, fn field, {changes, errors} ->
        case read(field, params, values, model.domain) do
          {:ok, value} -> {Map.put(changes, field.name, value), errors}
          {:error, problem} -> {changes, [{field.name, error(problem)} | errors]}
        end
      end)

    {data, types}
    |> Ecto.Changeset.change(changes)
    |> Map.put(:params, stringified(params))
    |> then(fn changeset ->
      # `add_error/4` puts each in front, so the last field's goes in first.
      Enum.reduce(errors, changeset, fn {field, {message, keys}}, changeset ->
        Ecto.Changeset.add_error(changeset, field, message, keys)
      end)
    end)
  end

  @doc """
  The command a valid changeset holds, `{:ok, struct}`, for `EhOsContract.dispatch/3`; or
  `{:error, changeset}` with the action `:insert`, so the form shows its errors.

  The fields the changeset does not take from the params are as `data:` gave them, or
  nil: dispatch supplies the host's, and gives a generated identity.
  """
  @spec to_command(t()) :: {:ok, struct()} | {:error, t()}
  def to_command(%Ecto.Changeset{valid?: true} = changeset),
    do: {:ok, Ecto.Changeset.apply_changes(changeset)}

  def to_command(%Ecto.Changeset{} = changeset),
    do: {:error, %{changeset | action: :insert}}

  @doc """
  The changeset with what dispatch refused put back on it, for the form to show, with the
  action `:insert`.

    * `{:invalid, problems}`: each problem at its field, as `changeset/4` puts its own,
      and an entity the host does not have (`:unknown`, a company id that names no
      company) as `{"does not exist", validation: :unknown}`;
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
    |> refusal_errors(at)
    |> Enum.reduce(%{changeset | action: :insert}, fn {field, {message, keys}}, changeset ->
      Ecto.Changeset.add_error(changeset, field, message, keys)
    end)
  end

  defp refusal_errors({:invalid, problems}, _at) when is_list(problems),
    do: for({field, problem} <- Enum.reverse(problems), do: {field, error(problem)})

  defp refusal_errors(%Rejection{invariant: name}, at),
    do: [
      {Keyword.get(at, name, @form_error),
       {"was refused", validation: :rejected, invariant: name}}
    ]

  defp refusal_errors(_not_a_field, _at), do: []

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

  defp unit(model, declaration), do: Enum.find(model.units, &(&1.name == declaration.unit))

  # The changeset's types, from the declaration's, for the form to show each value. A domain
  # value with fields is a map until its fields are cast one by one.
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

  defp contract!(contract) do
    case Model.fetch(contract) do
      %{kind: :contract, units: _} = model -> model
      %{module: module} -> raise ArgumentError, "#{inspect(module)} is not a contract"
    end
  end

  defp command!(model, module) do
    Enum.find(model.commands, &(Model.module_for(model, :command, &1.name) == module)) ||
      raise ArgumentError, "#{inspect(module)} is not a command of #{inspect(model.module)}"
  end
end
