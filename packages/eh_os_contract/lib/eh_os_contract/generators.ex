if Code.ensure_loaded?(StreamData) do
  defmodule EhOsContract.Generators do
    # Plan DD, PC1 (#264). Compiled only where StreamData is, as `EhOsContract.Plug` is
    # only where Plug is: a host without it gets neither the module nor the dependency.
    @moduledoc """
    Valid examples of a contract's data, as StreamData generators: its commands, its
    events, a row of a domain entity, and a unit's history in an order its lifecycle
    allows.

        use ExUnitProperties

        property "a visit's history folds without raising" do
          check all events <- EhOsContract.Generators.history(Clinic.Contracts.Visits, :visit) do
            assert Enum.reduce(events, %Clinic.Visit.State{}, &Clinic.Visit.evolve(&2, &1))
          end
        end

    Every value fits what the engine stores:

    - `:id`: printable text of 1 to 64 bytes;
    - `:string`: UTF-8 without NUL, up to 64 characters;
    - `:integer`: the 64-bit range, weighted toward small numbers;
    - `:decimal`: at most 15 digits, at most 6 after the point;
    - `:date` and `:timestamp`: between the years 1 and 9999, a timestamp in UTC;
    - an enum: one of its members; a list: up to 5 items;
    - an optional field: `nil` or a value.

    **A domain value with invariants is one of its `satisfied_by:` examples.** An
    invariant is code, and a generator cannot invert it; the domain already lists
    values that keep it. A value without invariants is generated from its type or its
    fields.

    `fields:` fixes or narrows a field, by a constant or a generator:
    `command(Visits, :close_visit, fields: [visit_id: "visit-1"])`. Naming a field the
    declaration does not have raises `ArgumentError`, as does naming a command, event,
    entity or unit the contract or domain does not declare.

    What it generates is what a host's own code hands the engine: a command for
    `EhOsContract.dispatch/3`, which trusts its struct, so a field the host supplies
    (`supplied_by: :host`) is filled in too; a command that creates its aggregate has
    no identity, which the engine generates. An event is what the log gives back: now
    and then a personal field of it is `%EhOsContract.Erased{}`, as after its subject
    was erased, and its `__meta__` is left unset.

    The module exists only when StreamData is a dependency of the application:
    `{:stream_data, "~> 1.1"}`, usually `only: :test`.
    """

    import StreamData

    alias EhOsContract.{Codec, Lifecycle, Model}
    alias EhOsContract.Contract.Data

    @max_text 64
    @max_list 5
    @max_history 20

    # Days from 0001-01-01 to 9999-12-31, and seconds a day inside the same years: a
    # timestamp at either end, shifted into a domain's time zone for its day tag, would
    # fall in the year 0 or 10000.
    @days Date.diff(~D[9999-12-31], ~D[0001-01-01])
    @first_second DateTime.to_unix(~U[0001-01-02 00:00:00Z])
    @last_second DateTime.to_unix(~U[9999-12-30 23:59:59Z])

    @doc """
    A generator of the command `name` of `contract`, as its struct.

    `fields:` fixes or narrows its fields (see the moduledoc).
    """
    @spec command(module(), atom(), keyword()) :: StreamData.t(struct())
    def command(contract, name, opts \\ []) do
      options!(opts, [:fields])
      model = Model.fetch(contract)

      declaration =
        Enum.find(model.commands, &(&1.name == name)) ||
          raise ArgumentError, unknown("command", name, contract, model.commands)

      # A command that creates its aggregate arrives without the identity, which the
      # engine generates and refuses from the caller.
      opts =
        if Map.get(declaration, :creates) do
          identity = Enum.find(model.units, &(&1.name == declaration.unit)).identity
          absent = for field <- identity, do: {field, nil}
          Keyword.update(opts, :fields, absent, &Keyword.merge(absent, &1))
        else
          opts
        end

      struct_of(model, Model.module_for(model, :command, name), declaration.fields, opts)
    end

    @doc """
    A generator of the event `name` that `contract` declares itself, as its struct.

    An event it consumes from a sibling, or receives from another application, is the
    other side's: generate it from that contract.
    """
    @spec event(module(), atom(), keyword()) :: StreamData.t(struct())
    def event(contract, name, opts \\ []) do
      options!(opts, [:fields])
      model = Model.fetch(contract)

      declaration =
        Enum.find(model.events, &(&1.name == name)) ||
          raise ArgumentError, unknown("event", name, contract, model.events)

      struct_of(
        model,
        Model.module_for(model, :event, name),
        declaration.fields,
        Keyword.put(opts, :erased, true)
      )
    end

    @doc """
    A generator of a row of the domain's entity `name`, as a map of its fields: what an
    `EhOsContract.Entities` host returns for a command that reads the entity.
    """
    @spec entity_row(module(), atom(), keyword()) :: StreamData.t(map())
    def entity_row(domain, name, opts \\ []) do
      options!(opts, [:fields])
      model = Model.fetch(domain)

      declaration =
        Enum.find(model.entities, &(&1.name == name)) ||
          raise ArgumentError, unknown("entity", name, domain, model.entities)

      fields_of(declaration.fields, Codec.values(domain), opts)
    end

    @doc """
    A generator of a legal history of the unit `name` of `contract`: a list of its
    events, oldest first, all of one identity.

    For a unit with a lifecycle, each next event is one the lifecycle allows in the
    status the history has reached, and the history
    stops at a final status, by chance, or at `max_length:` (default #{@max_history}).
    For a unit without one, any of its events in any order. `fields:` applies to every
    event that has the field; a unit's identity is the same in all of them unless
    `fields:` fixes it.
    """
    @spec history(module(), atom(), keyword()) :: StreamData.t([struct()])
    def history(contract, name, opts \\ []) do
      options!(opts, [:fields, :max_length])
      model = Model.fetch(contract)

      unit =
        Enum.find(model.units, &(&1.name == name)) ||
          raise ArgumentError, unknown("unit", name, contract, model.units)

      events = for e <- model.events, e.unit == name, do: e
      names = Enum.map(events, & &1.name)
      max = Keyword.get(opts, :max_length, @max_history)
      {fixed, other} = Keyword.pop(opts, :fields, [])
      values = Codec.values(model.domain)
      known = Enum.uniq(unit.identity ++ for(e <- events, f <- e.fields, do: f.name))

      for {field, _} <- fixed, field not in known do
        raise ArgumentError,
              "fields: names #{inspect(field)}, which no event of unit #{inspect(name)} has; " <>
                "they have #{inspect(known)}"
      end

      # Drawn by the identity's type, as the state declares it: a key typed by a domain
      # value (#435) is one of the value's examples, as any field of it is.
      identity =
        fixed_map(
          for field <- unit.identity do
            declared = Enum.find(unit.state.fields, &(&1.name == field))

            {field,
             Keyword.get_lazy(fixed, field, fn -> field(declared, values) end) |> generator()}
          end
        )

      bind(identity, fn identity ->
        bind(names_of(Lifecycle.of(unit), names, max), fn walked ->
          walked
          |> Enum.map(fn event_name ->
            declaration = Enum.find(events, &(&1.name == event_name))

            # The identity was drawn once for the history, so a generator in `fields:`
            # narrows it and is never drawn again per event.
            own =
              Enum.filter(fixed, fn {field, _} ->
                field not in unit.identity and has_field?(declaration, field)
              end)

            struct_of(
              model,
              Model.module_for(model, :event, event_name),
              declaration.fields,
              other
              |> Keyword.put(:fields, own ++ Map.to_list(identity))
              |> Keyword.put(:erased, true),
              values
            )
          end)
          |> fixed_list()
        end)
      end)
    end

    # --- a history's order ------------------------------------------------------------

    defp names_of(nil, [], _max), do: constant([])
    defp names_of(nil, names, max), do: list_of(member_of(names), max_length: max)
    defp names_of(lifecycle, names, max), do: walk(lifecycle, nil, names, max)

    defp walk(_lifecycle, _status, _names, 0), do: constant([])

    defp walk(lifecycle, status, names, left) do
      case Lifecycle.moves(lifecycle, status, names) do
        [] ->
          constant([])

        moves ->
          frequency([
            {1, constant([])},
            {4,
             bind(member_of(moves), fn {event, next} ->
               map(walk(lifecycle, next, names, left - 1), &[event | &1])
             end)}
          ])
      end
    end

    # --- structs and maps of fields ---------------------------------------------------

    defp struct_of(model, module, fields, opts, values \\ nil) do
      values = values || Codec.values(model.domain)
      map(fields_of(fields, values, opts), &struct!(module, &1))
    end

    defp fields_of(fields, values, opts) do
      fixed = Keyword.get(opts, :fields, [])
      names = Enum.map(fields, & &1.name)

      for {field, _} <- fixed, field not in names do
        raise ArgumentError,
              "fields: names #{inspect(field)}, which is not a field here; the fields are " <>
                inspect(names)
      end

      generated =
        fixed_map(
          for field <- fields do
            case Keyword.fetch(fixed, field.name) do
              {:ok, value} -> {field.name, generator(value)}
              :error -> {field.name, field(field, values)}
            end
          end
        )

      if Keyword.get(opts, :erased, false),
        do: erasable(generated, fields, fixed),
        else: generated
    end

    # A stored event's personal field reads back erased once its subject is shredded,
    # and a unit's `evolve/2` folds it so: now and then, a personal field the caller did
    # not fix is `%EhOsContract.Erased{}`, naming the subject its sibling field holds.
    defp erasable(generated, fields, fixed) do
      personal =
        for %{personal: sibling} = field <- fields,
            is_atom(sibling) and sibling != nil,
            not Keyword.has_key?(fixed, field.name),
            subject = Enum.find(fields, &(&1.name == sibling)),
            subject != nil,
            do: {field.name, sibling, subject.subject}

      if personal == [] do
        generated
      else
        bind(generated, fn data ->
          personal
          |> Enum.map(fn {name, sibling, subject} ->
            case data[sibling] do
              id when is_binary(id) ->
                map(
                  frequency([{4, constant(false)}, {1, constant(true)}]),
                  &if(&1, do: {name, %EhOsContract.Erased{subject: subject, id: id}}, else: nil)
                )

              _ ->
                constant(nil)
            end
          end)
          |> fixed_list()
          |> map(fn erased -> Map.merge(data, Map.new(Enum.reject(erased, &is_nil/1))) end)
        end)
      end
    end

    defp options!(opts, allowed) do
      for {key, _} <- opts, key not in allowed do
        raise ArgumentError, "no option #{inspect(key)}; it takes #{inspect(allowed)}"
      end

      case Keyword.fetch(opts, :max_length) do
        {:ok, n} when not (is_integer(n) and n >= 0) ->
          raise ArgumentError, "max_length: is a non-negative integer, not #{inspect(n)}"

        _ ->
          :ok
      end
    end

    # A value of a declared field, by its type: `EhOsContract.PropertyCase` draws a unit's
    # identity typed by a domain value (#435) with it.
    @doc false
    @spec value_of(map(), map()) :: StreamData.t(term())
    def value_of(field, values), do: field(field, values)

    defp has_field?(declaration, field), do: Enum.any?(declaration.fields, &(&1.name == field))

    defp generator(%StreamData{} = generator), do: generator
    defp generator(value), do: constant(value)

    defp field(%{optional: true} = field, values),
      do: one_of([constant(nil), type(field.type, values)])

    defp field(field, values), do: type(field.type, values)

    # --- values within the codec's bounds ---------------------------------------------

    defp type(:id, _values), do: id()
    defp type({:id, _entity}, _values), do: id()

    defp type(:string, _values),
      do: map(string(:utf8, max_length: @max_text), &String.replace(&1, <<0>>, ""))

    defp type(:integer, _values),
      do: one_of([integer(), integer(-9_223_372_036_854_775_808..9_223_372_036_854_775_807)])

    defp type(:boolean, _values), do: boolean()

    defp type(:decimal, _values) do
      map({integer(-999_999_999_999_999..999_999_999_999_999), integer(0..6)}, fn {n, places} ->
        Decimal.new(if(n < 0, do: -1, else: 1), abs(n), -places)
      end)
    end

    defp type(:date, _values), do: map(integer(0..@days), &Date.add(~D[0001-01-01], &1))

    defp type(:timestamp, _values) do
      map({integer(@first_second..@last_second), integer(0..999_999)}, fn {second, micro} ->
        DateTime.from_unix!(second * 1_000_000 + micro, :microsecond)
      end)
    end

    defp type({:enum, members}, _values) do
      member_of(
        Enum.map(members, fn
          {name, _label} -> name
          name -> name
        end)
      )
    end

    defp type({:list, inner}, values), do: list_of(type(inner, values), max_length: @max_list)

    defp type(name, values) when is_atom(name) do
      case Map.fetch(values, name) do
        {:ok, value} -> domain_value(name, value, values)
        :error -> raise ArgumentError, "no generator for the type #{inspect(name)}"
      end
    end

    # A value with invariants is one of its examples, cast as a scenario's data is.
    defp domain_value(name, %{invariants: [_ | _] = invariants}, values) do
      invariants
      |> Enum.flat_map(& &1.satisfied_by)
      |> Enum.uniq()
      |> Enum.map(fn example ->
        {:ok, cast} = Data.cast(name, example, values)
        cast
      end)
      |> member_of()
    end

    defp domain_value(_name, %{type: nil, fields: fields} = declared, values),
      do: map(fields_of(fields, values, []), &Codec.built(declared, &1))

    defp domain_value(_name, %{type: type}, values), do: type(type, values)

    defp id, do: string(:alphanumeric, min_length: 1, max_length: @max_text)

    defp unknown(kind, name, module, declared) do
      "#{inspect(module)} declares no #{kind} #{inspect(name)}; it declares " <>
        inspect(Enum.map(declared, & &1.name))
    end
  end
end
