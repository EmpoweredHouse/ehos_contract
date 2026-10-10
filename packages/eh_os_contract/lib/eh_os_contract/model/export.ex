defmodule EhOsContract.Model.Export do
  @moduledoc false

  @doc false
  @spec redact(map(), map()) :: {map(), map()}
  def redact(model, domain) do
    values = Map.new(domain.values, &{&1.name, &1})

    contract =
      model
      |> redact_scenarios(Map.get(domain, :entities, []), values)
      |> redact_service_examples(values)
      |> redact_contract_defaults(values)

    {contract, redact_domain_examples(domain, values)}
  end

  @doc false
  @spec redact_domain(map()) :: map()
  def redact_domain(domain),
    do: redact_domain_examples(domain, Map.new(domain.values, &{&1.name, &1}))

  defp redact_scenarios(model, entities, values) do
    Map.update!(model, :scenarios, fn scenarios ->
      Enum.map(scenarios, &redact_scenario(&1, model, entities, values))
    end)
  end

  defp redact_scenario(scenario, model, entities, values) do
    scenario
    |> redact_given_entities(entities, values)
    |> update_many(:given, &redact_event(&1, :event, model, values))
    |> update_one(:trigger, &redact_trigger(&1, model, values))
    |> update_many(:expect, &redact_event(&1, :event, model, values))
    |> update_many(:issues, &redact_named(&1, :command, model.commands, values))
    |> redact_answers(model, values)
    |> redact_state(model, values)
  end

  # The rows of the entities a scenario's command reads (plan DD, T2a, #240), by the
  # fields the domain's entity declares: a personal one is redacted as an event's is.
  # Kept only where the scenario gives some, so the key is not added to the others.
  defp redact_given_entities(%{given_entities: rows} = scenario, entities, values) do
    rows =
      for row <- rows do
        case Enum.find(entities, &(&1.name == row.entity)) do
          %{fields: fields} -> redact_data(row, fields, values)
          nil -> redact_data(row, :unknown, values)
        end
      end

    %{scenario | given_entities: rows}
  end

  defp redact_given_entities(scenario, _entities, _values), do: scenario

  # A process manager's run, as a scenario expects it (plan EP4): its state's fields,
  # correlation included, say which are personal.
  defp redact_state(%{state: state, target: %{name: name}} = scenario, model, values) do
    fields =
      case Enum.find(model.process_managers, &(&1.name == name)) do
        %{state: %{fields: fields}} -> fields
        nil -> []
      end

    %{scenario | state: redact_fields(state, fields, values)}
  end

  defp redact_state(scenario, _model, _values), do: scenario

  defp redact_trigger(%{kind: :command} = trigger, model, values),
    do: redact_named(trigger, :name, model.commands, values)

  defp redact_trigger(%{kind: :on} = trigger, model, values),
    do: redact_event(trigger, :name, model, values)

  defp redact_trigger(%{kind: :query} = trigger, model, values),
    do: redact_named(trigger, :name, model.queries, values, :params)

  defp redact_trigger(trigger, _model, _values), do: trigger

  defp redact_named(item, name_key, declarations, values, fields_key \\ :fields) do
    fields =
      case Enum.find(declarations, &(&1.name == Map.get(item, name_key))) do
        nil -> :unknown
        declaration -> declaration[fields_key]
      end

    redact_data(item, fields, values)
  end

  # A scenario of a consumer names a sibling's event by its local name, and the
  # sibling declares which of its fields are personal: the contract's own events are
  # not enough to know (a policy on `ClinicalDocumentation`'s closing carries a PESEL).
  defp redact_event(item, name_key, model, values),
    do: redact_data(item, event_fields(model, Map.get(item, name_key)), values)

  defp event_fields(model, name) do
    with nil <- Enum.find(model.events, &(&1.name == name)) do
      case EhOsContract.Model.consumed(model, name) do
        {:contract, from, original} ->
          case Enum.find(EhOsContract.Model.fetch(from).events, &(&1.name == original)) do
            %{fields: fields} -> fields
            nil -> :unknown
          end

        {:published, fields} ->
          fields

        nil ->
          :unknown
      end
    else
      %{fields: fields} -> fields
    end
  end

  # Data whose declaration cannot be found is dropped rather than published: nothing
  # says which of its fields are personal. A timer's trigger carries none.
  defp redact_data(item, :unknown, _values),
    do: Map.update(item, :data, %{}, &drop_values/1)

  defp redact_data(item, fields, values),
    do: Map.update(item, :data, %{}, &redact_fields(&1, fields, values))

  defp redact_answers(%{trigger: %{kind: :query, name: name}} = scenario, model, values) do
    query = Enum.find(model.queries, &(&1.name == name))
    read_model = query && Enum.find(model.read_models, &(&1.name == query.reads))

    if read_model,
      do: Map.update!(scenario, :answers, &redact_rows(&1, read_model.fields, values)),
      else: Map.update!(scenario, :answers, &redact_rows(&1, [], values))
  end

  defp redact_answers(scenario, _model, _values), do: scenario

  defp redact_rows(rows, fields, values) when is_list(rows),
    do: Enum.map(rows, &redact_fields(&1, fields, values))

  defp redact_rows(%{} = row, fields, values), do: redact_fields(row, fields, values)
  defp redact_rows(nil, _fields, _values), do: nil

  # Per key, not per declared field: a key no field declares is dropped, since nothing
  # says it is not personal. The compiler refuses such keys (S3, X9) in a contract it
  # checks, so this only matters for one it never saw.
  defp redact_fields(data, fields, values) when is_map(data) do
    declared = Map.new(fields, &{Atom.to_string(&1.name), &1})

    Map.new(data, fn {key, value} ->
      case Map.get(declared, to_string(key)) do
        nil -> {key, nil}
        %{personal: personal} when not is_nil(personal) -> {key, nil}
        field -> {key, redact_value(field.type, value, values)}
      end
    end)
  end

  defp redact_fields(value, _fields, _values), do: value

  defp drop_values(data) when is_map(data), do: Map.new(data, fn {key, _value} -> {key, nil} end)
  defp drop_values(_data), do: nil

  defp redact_value(_type, nil, _values), do: nil

  defp redact_value({:list, inner}, values_to_redact, values) when is_list(values_to_redact),
    do: Enum.map(values_to_redact, &redact_value(inner, &1, values))

  defp redact_value(type, value, values) when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil, fields: fields} when is_map(value) -> redact_fields(value, fields, values)
      # A structured value written as something else, as an invariant's
      # `violated_by` may be: it could be any of its fields, personal ones included.
      %{type: nil} = structured -> if personal_inside?(structured, values), do: nil, else: value
      %{type: inner} -> redact_value(inner, value, values)
    end
  end

  defp redact_value(_type, value, _values), do: value

  defp personal_inside?(%{fields: fields}, values) do
    Enum.any?(fields, fn field ->
      Map.get(field, :personal) != nil or personal_type?(field.type, values)
    end)
  end

  defp personal_type?({:list, inner}, values), do: personal_type?(inner, values)

  defp personal_type?(type, values) when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil} = structured -> personal_inside?(structured, values)
      %{type: inner} -> personal_type?(inner, values)
    end
  end

  defp personal_type?(_type, _values), do: false

  defp redact_service_examples(model, values) do
    Map.update!(model, :domain_services, fn services ->
      Enum.map(services, fn service ->
        Map.update!(service, :functions, fn functions ->
          Enum.map(functions, &redact_function_examples(&1, values))
        end)
      end)
    end)
  end

  defp redact_function_examples(function, values) do
    Map.update!(function, :rules, fn rules ->
      Enum.map(rules, fn rule ->
        Map.update!(rule, :examples, fn examples ->
          Enum.map(examples, &redact_call(&1, function, values))
        end)
      end)
    end)
  end

  defp redact_call({arguments, result}, function, values) when is_list(arguments) do
    arguments =
      function.arguments
      |> Enum.zip(arguments)
      |> Enum.map(fn {argument, value} -> redact_value(argument.type, value, values) end)

    result = redact_value(function.returns.type, result, values)
    {arguments, result}
  end

  defp redact_call(example, _function, _values), do: example

  defp redact_contract_defaults(model, values) do
    model
    |> update_fields(:commands, :fields, values)
    |> update_fields(:events, :fields, values)
    |> update_fields(:read_models, :fields, values)
    |> update_fields(:queries, :params, values)
    |> update_fields(:consumes, :fields, values)
    |> update_state_fields(:units, values)
    |> update_state_fields(:process_managers, values)
  end

  defp redact_domain_examples(domain, values) do
    domain
    |> Map.update!(:values, fn domain_values ->
      Enum.map(domain_values, fn value ->
        value
        |> Map.update!(:fields, &redact_defaults(&1, values))
        |> Map.update!(:invariants, fn invariants ->
          Enum.map(invariants, fn invariant ->
            invariant
            |> Map.update!(
              :violated_by,
              &Enum.map(&1, fn item -> redact_value(value.name, item, values) end)
            )
            |> Map.update!(
              :satisfied_by,
              &Enum.map(&1, fn item -> redact_value(value.name, item, values) end)
            )
          end)
        end)
      end)
    end)
    |> update_fields(:entities, :fields, values)
  end

  defp update_fields(model, collection, fields_key, values) do
    Map.update!(model, collection, fn declarations ->
      Enum.map(
        declarations,
        &Map.update!(&1, fields_key, fn fields -> redact_defaults(fields, values) end)
      )
    end)
  end

  defp update_state_fields(model, collection, values) do
    Map.update!(model, collection, fn declarations ->
      Enum.map(declarations, fn declaration ->
        Map.update!(declaration, :state, fn state ->
          Map.update!(state, :fields, &redact_defaults(&1, values))
        end)
      end)
    end)
  end

  defp redact_defaults(fields, values) do
    Enum.map(fields, fn field ->
      if Map.has_key?(field, :default) do
        Map.update!(field, :default, fn default ->
          if Map.get(field, :personal), do: nil, else: redact_value(field.type, default, values)
        end)
      else
        field
      end
    end)
  end

  defp update_many(map, key, fun), do: Map.update(map, key, [], &Enum.map(&1, fun))
  defp update_one(map, key, fun), do: Map.update(map, key, nil, &if(&1, do: fun.(&1), else: nil))
end
