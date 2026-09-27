defmodule EhOsContract.Codec do
  @moduledoc """
  Field values against their declared types, and their form in the log (v2 §5,
  §11): what the compiler cannot check, since a struct can be built with any value
  in any field.

  **Types.** `:id` and `:string` are binaries, `:integer` and `:boolean` what they
  say, `:decimal` a `Decimal`, `:date` a `Date`, `:timestamp` a `DateTime` in UTC,
  `{:enum, members}` one of the member atoms, `{:list, type}` a list of them. A
  domain value is its own type: an alias of a type (`value :money, :integer`), or a
  map of its fields.

  **The log's form is JSON's.** A decimal is written as a string of digits, so no
  float ever stands between two sums; a date and a timestamp as ISO 8601; an enum
  member as its name. Reading back never creates an atom: a member is found among
  the declared ones, and a name the contract no longer declares does not fit.

  **Problems name the field and what is wrong, never the value** (v2 §17): they
  travel to logs, telemetry and HTTP callers, and a value may be personal data.

  **Personal fields** (v2 §14) — `personal: :patient_id`, at any depth of a domain
  value — are where the codec hands a value to someone else: `encode/4` to a
  function that seals it, `decode/4` to one that opens it, both given by
  `EhOsContract.Personal`. The codec only knows where they are and whose they are:
  the subject is the one the named sibling field identifies. A personal field may
  hold `EhOsContract.Erased`, which is what a sealed one reads back as once its
  subject's key is gone.
  """

  alias EhOsContract.Erased

  @typedoc "A declared field, as a model carries it."
  @type field :: %{
          required(:name) => atom(),
          required(:type) => term(),
          optional(atom()) => term()
        }

  @typedoc "A domain's values, by name: `values/1`."
  @type values :: %{atom() => map()}

  @typedoc "What is wrong with one field: missing, or not of its type."
  @type problem :: {atom(), :required | :type}

  @typedoc "A subject whose personal data a value carries: its type and its id."
  @type subject :: {atom(), String.t()}

  @typedoc """
  Seals a personal field's value, in the log's form: given the field's path
  (`"contact.phone"`) and its subject, returns what the log stores instead.
  """
  @type seal :: (String.t(), subject(), term() -> term())

  @typedoc """
  Opens what `t:seal/0` stored: the value in the log's form, `:erased` when the
  subject's key is gone, `:error` when it does not open.
  """
  @type open :: (String.t(), subject(), term() -> {:ok, term()} | :erased | :error)

  @doc """
  The values a domain declares, by name. `%{}` when the domain is not a compiled
  `EhOsContract.Domain`, and then a field of a domain value fits nothing.
  """
  @spec values(module()) :: values()
  def values(domain) do
    if Code.ensure_loaded?(domain) and function_exported?(domain, :__eh_os_contract_model__, 0),
      do: Map.new(domain.__eh_os_contract_model__().values, &{&1.name, &1}),
      else: %{}
  end

  @doc """
  What is wrong with `data`, a struct or a map with atom keys, against `fields`: a
  required field that is `nil`, or a value not of its type. `[]` when nothing is.
  """
  @spec problems([field()], map(), values()) :: [problem()]
  def problems(fields, data, values) do
    for field <- fields,
        problem <- field_problems(field, Map.get(data, field.name), values),
        do: {field.name, problem}
  end

  defp field_problems(field, nil, _values),
    do: if(Map.get(field, :optional, false), do: [], else: [:required])

  # What a personal field reads back as once its subject is erased, and nothing else.
  defp field_problems(field, %Erased{}, _values),
    do: if(Map.get(field, :personal), do: [], else: [:type])

  defp field_problems(field, value, values),
    do: if(fits?(field.type, value, values), do: [], else: [:type])

  defp fits?(type, value, _values) when type in [:id, :string], do: is_binary(value)
  defp fits?(:integer, value, _values), do: is_integer(value)
  defp fits?(:boolean, value, _values), do: is_boolean(value)
  defp fits?(:decimal, value, _values), do: is_struct(value, Decimal)
  defp fits?(:date, value, _values), do: is_struct(value, Date)

  defp fits?(:timestamp, value, _values),
    do: is_struct(value, DateTime) and value.time_zone == "Etc/UTC"

  defp fits?({:enum, members}, value, _values), do: is_atom(value) and value in names(members)

  defp fits?({:list, inner}, value, values),
    do: is_list(value) and Enum.all?(value, &fits?(inner, &1, values))

  defp fits?(type, value, values) when is_atom(type) do
    case Map.fetch(values, type) do
      {:ok, %{type: nil, fields: fields}} ->
        is_map(value) and problems(fields, value, values) == []

      {:ok, %{type: inner}} ->
        fits?(inner, value, values)

      :error ->
        false
    end
  end

  defp fits?(_type, _value, _values), do: false

  @doc """
  `data`'s fields in the log's form: a map with string keys, JSON-encodable. Every
  declared field is written, `nil` included, so a payload says a field was absent
  rather than leaving it to be guessed. Assumes `problems/3` found nothing.

  With `seal`, a personal field that holds a value is stored as `seal` returns it,
  and `EhOsContract.Erased` cannot be written. Without — a query's rows over HTTP — a
  personal field is written as it is, and `EhOsContract.Erased` as `nil`.
  """
  @spec encode([field()], map(), values(), seal() | nil) :: %{String.t() => term()}
  def encode(fields, data, values, seal \\ nil), do: encode_fields(fields, data, values, seal, [])

  defp encode_fields(fields, data, values, seal, path) do
    Map.new(fields, fn field ->
      value = Map.get(data, field.name)
      here = path ++ [Atom.to_string(field.name)]
      target = Map.get(field, :personal)

      encoded =
        cond do
          is_struct(value, Erased) and seal != nil ->
            raise ArgumentError,
                  "field #{Enum.join(here, ".")} holds EhOsContract.Erased, and an erased value " <>
                    "cannot be written"

          # Out of the log — a query's row over HTTP — what was erased is absent.
          is_struct(value, Erased) ->
            nil

          target != nil and seal != nil and value != nil ->
            seal.(
              Enum.join(here, "."),
              subject!(fields, data, target),
              encode_value(field.type, value, values, nil, here)
            )

          true ->
            encode_value(field.type, value, values, seal, here)
        end

      {Atom.to_string(field.name), encoded}
    end)
  end

  @doc "One value in the log's form. What a scoped query compares, as a string."
  @spec encode_value(term(), term(), values()) :: term()
  def encode_value(type, value, values), do: encode_value(type, value, values, nil, [])

  defp encode_value(_type, nil, _values, _seal, _path), do: nil
  defp encode_value(:decimal, value, _values, _seal, _path), do: Decimal.to_string(value, :normal)
  defp encode_value(:date, value, _values, _seal, _path), do: Date.to_iso8601(value)
  defp encode_value(:timestamp, value, _values, _seal, _path), do: DateTime.to_iso8601(value)
  defp encode_value({:enum, _members}, value, _values, _seal, _path), do: Atom.to_string(value)

  defp encode_value({:list, inner}, value, values, seal, path),
    do: Enum.map(value, &encode_value(inner, &1, values, seal, path))

  defp encode_value(type, value, values, seal, path)
       when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil, fields: fields} -> encode_fields(fields, value, values, seal, path)
      %{type: inner} -> encode_value(inner, value, values, seal, path)
    end
  end

  defp encode_value(_type, value, _values, _seal, _path), do: value

  # The subject a personal field belongs to: the one its sibling identifies. F5
  # makes the sibling a required `:id` field declaring `subject:`.
  defp subject!(fields, data, target) do
    %{subject: subject} = Enum.find(fields, &(&1.name == target))

    case fetch(data, target) do
      id when is_binary(id) -> {subject, id}
      _ -> raise ArgumentError, "field #{target}, whose personal data this is, holds no id"
    end
  end

  # A field of a struct, a map with atom keys, or the log's map with string keys.
  defp fetch(data, name), do: Map.get(data, name, Map.get(data, Atom.to_string(name)))

  @doc """
  Whether `fields` declare a personal field, directly or in a domain value, at any
  depth.
  """
  @spec personal?([field()], values()) :: boolean()
  def personal?(fields, values), do: personal?(fields, values, MapSet.new())

  defp personal?(fields, values, seen) do
    Enum.any?(fields, fn field ->
      Map.get(field, :personal) != nil or personal_type?(field.type, values, seen)
    end)
  end

  defp personal_type?({:list, inner}, values, seen), do: personal_type?(inner, values, seen)

  defp personal_type?(type, values, seen) when is_atom(type) and is_map_key(values, type) do
    if MapSet.member?(seen, type) do
      false
    else
      case Map.fetch!(values, type) do
        %{type: nil, fields: fields} -> personal?(fields, values, MapSet.put(seen, type))
        %{type: inner} -> personal_type?(inner, values, MapSet.put(seen, type))
      end
    end
  end

  defp personal_type?(_type, _values, _seen), do: false

  @doc """
  The subjects whose personal data `data` carries, each once. `:value` reads a
  struct's values, and counts every personal field that is not `nil`; `:stored` reads
  the log's form, and counts only the fields `seal` stored, which are the ones
  whose keys a reader needs.
  """
  @spec subjects([field()], map(), values(), :value | :stored) :: [subject()]
  def subjects(fields, data, values, form) do
    fields |> field_subjects(data, values, form) |> Enum.uniq()
  end

  defp field_subjects(fields, data, values, form) do
    Enum.flat_map(fields, fn field ->
      value = fetch(data, field.name)

      case Map.get(field, :personal) do
        nil ->
          value_subjects(field.type, value, values, form)

        target ->
          sealed = form == :value or sealed?(value)

          case fetch(data, target) do
            id when is_binary(id) and value != nil and sealed ->
              [{Enum.find(fields, &(&1.name == target)).subject, id}]

            _ ->
              []
          end
      end
    end)
  end

  defp value_subjects(_type, nil, _values, _form), do: []

  defp value_subjects({:list, inner}, value, values, form) when is_list(value),
    do: Enum.flat_map(value, &value_subjects(inner, &1, values, form))

  defp value_subjects(type, value, values, form)
       when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil, fields: fields} when is_map(value) ->
        field_subjects(fields, value, values, form)

      %{type: nil} ->
        []

      %{type: inner} ->
        value_subjects(inner, value, values, form)
    end
  end

  defp value_subjects(_type, _value, _values, _form), do: []

  # What `EhOsContract.Personal` stores for a sealed field.
  defp sealed?(%{"$eh" => _}), do: true
  defp sealed?(_value), do: false

  @doc """
  Fields from their external form — the log's, or JSON a caller sent — to the values
  a struct holds. Keys are read as strings, or as atoms when the map has those.
  Fails with the fields that do not fit, and never creates an atom.

  `open:` opens the personal fields `encode/4` sealed (`t:open/0`): a field whose
  subject is erased decodes to `EhOsContract.Erased`. Without it, a sealed field
  does not fit.
  """
  #
  # `strings: true` also reads an integer or a boolean written as text, as a query
  # string carries every value, and only at the top level, where a query's
  # parameters are.
  @spec decode([field()], map(), values(), keyword()) :: {:ok, map()} | {:error, [problem()]}
  def decode(fields, external, values, opts \\ []) when is_map(external) do
    strings = Keyword.get(opts, :strings, false)
    open = Keyword.get(opts, :open)

    {decoded, problems} =
      Enum.reduce(fields, {%{}, []}, fn field, {decoded, problems} ->
        raw = Map.get(external, Atom.to_string(field.name), Map.get(external, field.name))
        raw = if strings, do: from_text(field.type, raw, values), else: raw

        case decode_field(field, raw, fields, external, values, open, []) do
          {:ok, nil} ->
            if Map.get(field, :optional, false),
              do: {Map.put(decoded, field.name, nil), problems},
              else: {decoded, [{field.name, :required} | problems]}

          {:ok, value} ->
            {Map.put(decoded, field.name, value), problems}

          :error ->
            {decoded, [{field.name, :type} | problems]}
        end
      end)

    if problems == [], do: {:ok, decoded}, else: {:error, Enum.reverse(problems)}
  end

  # A sealed personal field is opened first; its value is then decoded as any other,
  # and nothing inside it was sealed again.
  defp decode_field(field, raw, fields, external, values, open, path) do
    here = path ++ [Atom.to_string(field.name)]
    target = Map.get(field, :personal)

    if target != nil and open != nil and sealed?(raw) do
      %{subject: subject} = Enum.find(fields, &(&1.name == target))

      with id when is_binary(id) <- fetch(external, target),
           {:ok, opened} <- open.(Enum.join(here, "."), {subject, id}, raw) do
        decode_value(field.type, opened, values, nil, here)
      else
        :erased -> {:ok, %Erased{subject: subject, id: fetch(external, target)}}
        _ -> :error
      end
    else
      decode_value(field.type, raw, values, open, here)
    end
  end

  defp decode_fields(fields, external, values, open, path) do
    Enum.reduce_while(fields, {:ok, %{}}, fn field, {:ok, decoded} ->
      raw = fetch(external, field.name)

      case decode_field(field, raw, fields, external, values, open, path) do
        {:ok, nil} ->
          if Map.get(field, :optional, false),
            do: {:cont, {:ok, Map.put(decoded, field.name, nil)}},
            else: {:halt, :error}

        {:ok, value} ->
          {:cont, {:ok, Map.put(decoded, field.name, value)}}

        :error ->
          {:halt, :error}
      end
    end)
  end

  defp from_text(type, value, values) when is_binary(value) do
    case base(type, values) do
      :integer ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _ -> value
        end

      :boolean ->
        %{"true" => true, "false" => false} |> Map.get(value, value)

      _ ->
        value
    end
  end

  defp from_text(_type, value, _values), do: value

  # The built-in type a domain value aliases, through as many aliases as there are.
  defp base(type, values) when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil} -> nil
      %{type: inner} -> base(inner, values)
    end
  end

  defp base(type, _values), do: type

  defp decode_value(_type, nil, _values, _open, _path), do: {:ok, nil}

  defp decode_value(type, value, _values, _open, _path)
       when type in [:id, :string] and is_binary(value),
       do: {:ok, value}

  defp decode_value(:integer, value, _values, _open, _path) when is_integer(value),
    do: {:ok, value}

  defp decode_value(:boolean, value, _values, _open, _path) when is_boolean(value),
    do: {:ok, value}

  defp decode_value(:decimal, value, _values, _open, _path)
       when is_binary(value) or is_integer(value) do
    case Decimal.cast(value) do
      {:ok, decimal} -> {:ok, decimal}
      :error -> :error
    end
  end

  defp decode_value(:date, value, _values, _open, _path) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> :error
    end
  end

  defp decode_value(:timestamp, value, _values, _open, _path) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at}
      {:error, _} -> :error
    end
  end

  defp decode_value({:enum, members}, value, _values, _open, _path)
       when is_binary(value) or is_atom(value) do
    name = to_string(value)

    case Enum.find(names(members), &(Atom.to_string(&1) == name)) do
      nil -> :error
      member -> {:ok, member}
    end
  end

  defp decode_value({:list, inner}, value, values, open, path) when is_list(value) do
    Enum.reduce_while(value, {:ok, []}, fn item, {:ok, acc} ->
      case decode_value(inner, item, values, open, path) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      :error -> :error
    end
  end

  defp decode_value(type, value, values, open, path)
       when is_atom(type) and is_map_key(values, type) do
    case Map.fetch!(values, type) do
      %{type: nil, fields: fields} when is_map(value) ->
        decode_fields(fields, value, values, open, path)

      %{type: nil} ->
        :error

      %{type: inner} ->
        decode_value(inner, value, values, open, path)
    end
  end

  defp decode_value(_type, _value, _values, _open, _path), do: :error

  # An enum's members: atoms, or `atom: label` pairs.
  defp names(members),
    do:
      Enum.map(members, fn
        {name, _label} -> name
        name -> name
      end)
end
