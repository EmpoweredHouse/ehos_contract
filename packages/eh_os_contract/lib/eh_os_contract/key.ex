defmodule EhOsContract.Key do
  @moduledoc """
  The one escaping every key the store builds goes through (v2 §10.4): stream ids,
  tags and instance ids.

      Key.stream(:visit_settlement, ["w-1"])   #=> "visit_settlement:w-1"
      Key.tag(:visit_id, "w-1")                #=> "visit_id:w-1"
      Key.join(["visit_settlement", "w-1"])    #=> "visit_settlement|w-1"

  Values are joined with `|`, and a `|` or `%` inside a value is percent-escaped,
  as `EhOsContract.Instance` has escaped since 21 August. Without it `a|b` + `c`
  and `a` + `b|c` would be one key: two runs, or two streams, merged. One copy of
  that rule, not one per kind of key.
  """

  @separator "|"

  # Measured against Postgres 17 (issue #96, 3 October 2026), by sampling, not proved. An
  # entry is compressed only when that saves a quarter of it, so the worst value is not all
  # `|` but printable text with about a quarter of `|` and `%`: each escapes to three bytes
  # and the whole barely compresses. Seven such fields of 255 bytes fail most inserts. Six
  # fail none while the name in front of the key is short: a run's key carries the process's
  # name twice (its column and its prefix), and six fields began to fail behind a process
  # name of about 100 bytes; a manager's key, whose name is once, held at 140. Since #98
  # `budget/0` is what bounds a key; this refuses at compile time the shapes that would
  # mostly be over it.
  @max_fields 6

  @doc """
  How many fields a key is made of at most: a unit's identity, a process's or a process
  manager's `correlate` (F9). Each is an `:id` of at most 255 bytes, and the key is a
  btree entry of `eh_os_contract_events`, `eh_os_contract_event_runs` or
  `eh_os_contract_process_managers`, which Postgres refuses past 2704 bytes.
  """
  @spec max_fields() :: pos_integer()
  def max_fields, do: @max_fields

  # Postgres refuses a btree entry past 2704 bytes, its header, the columns' length words
  # and their padding included: about 2667 bytes of text are left for the key's columns
  # (issue #98). An entry under the budget fits whatever compression does, so the bound
  # is no longer a sample (#96), and the margin leaves room for a column more.
  @budget 2048

  @doc """
  How many bytes the text columns of one key's btree entry hold together at most: a
  stream id, a run's process and instance id, a process manager's name and correlation,
  counted after escaping and without compression. Dispatch refuses a command whose key
  is over it with `:key_too_long`, and a process manager raises
  `EhOsContract.Key.TooLongError`, both in place of Postgres's refusal (issue #98).
  """
  @spec budget() :: pos_integer()
  def budget, do: @budget

  @doc "Whether the columns of one key's entry, their bytes together, are within `budget/0`."
  @spec fits?([String.t()]) :: boolean()
  def fits?(columns) when is_list(columns),
    do: columns |> Enum.map(&byte_size/1) |> Enum.sum() <= @budget

  @doc "Values joined with `|`, each escaped."
  @spec join([term()]) :: String.t()
  def join(values) when is_list(values), do: Enum.map_join(values, @separator, &escape/1)

  @doc "A unit's stream: its name, `:`, then its key values in declared order."
  @spec stream(atom(), [term()]) :: String.t()
  def stream(unit, values) when is_atom(unit), do: "#{unit}:" <> join(values)

  @doc "A tag: the field's name, `:`, then its value."
  @spec tag(atom(), term()) :: String.t()
  def tag(field, value) when is_atom(field), do: "#{field}:" <> escape(value)

  @doc """
  Whether a declared field is a tag of every event that carries it: a required,
  non-personal field of the built-in type `:id` (v2 §10.4). A unit's identity is
  injected as such fields, so it is always among them. A consistency boundary finds
  what it consults by these tags, so its `match:` names only such fields (A4, X6);
  the rule and the append read this one predicate. Since E9c the append also counts
  a field typed by a domain value of `:id`, which A4, at compile time and without
  the domain, cannot see: it refuses a local `match:` on one, conservatively.
  """
  #
  # With the domain's `values` (`EhOsContract.Codec.values/1`), a field typed by a
  # value whose base type is `:id` is one too: "2026-07" is a period's identifier
  # with an invariant of its own, and still an identifier (plan E9c). Without them,
  # at compile time where a contract has no domain, only the built-in type counts.
  @spec tag_field?(map(), map()) :: boolean()
  def tag_field?(field, values \\ %{})
  def tag_field?(%{type: :id, optional: false, personal: nil}, _values), do: true
  # An entity's identifier as declared, before the model makes it an `:id` (plan EM2).
  def tag_field?(%{type: {:id, _entity}, optional: false, personal: nil}, _values), do: true

  def tag_field?(%{type: type, optional: false, personal: nil}, values) when is_atom(type),
    do: base_type(type, values) == :id

  def tag_field?(_field, _values), do: false

  @doc """
  Whether a declared field is tagged with its day when an event carrying it is
  appended (plan W2): a required, non-personal `:date` or `:timestamp`, or a domain
  value resting on one. The log only grows, so a tag added later would never reach
  the events already in it; a boundary that buckets by day (B2) finds every event
  that could fall on it.
  """
  @spec bucket_field?(map(), map()) :: boolean()
  def bucket_field?(field, values \\ %{})

  def bucket_field?(%{type: type, optional: false, personal: nil}, values) when is_atom(type),
    do: base_type(type, values) in [:date, :timestamp]

  def bucket_field?(_field, _values), do: false

  @doc """
  A day tag: the field's name and `.day`, `:`, then the day, `YYYY-MM-DD`. A
  timestamp's day is the one it falls on in `zone`, the domain's `time_zone:`; a date
  is its own day.

      Key.day_tag(:scheduled_at, ~U[2026-10-05 22:30:00Z])                    #=> "scheduled_at.day:2026-10-05"
      Key.day_tag(:scheduled_at, ~U[2026-10-05 22:30:00Z], "Europe/Warsaw")   #=> "scheduled_at.day:2026-10-06"

  A field name is snake_case and has no `.`, so a day tag never reads as a field's tag.
  """
  @spec day_tag(atom(), Date.t() | DateTime.t(), String.t()) :: String.t()
  def day_tag(field, value, zone \\ "Etc/UTC")

  def day_tag(field, %DateTime{} = at, zone) when is_atom(field),
    do: day_tag(field, at |> DateTime.shift_zone!(zone) |> DateTime.to_date(), zone)

  def day_tag(field, %Date{} = day, _zone) when is_atom(field),
    do: tag(:"#{field}.day", Date.to_iso8601(day))

  @doc """
  The built-in type a field's type comes down to: a domain value's type followed to
  the built-in one it rests on, `value :fee, :amount` to `:amount`'s. A value made of
  fields, or a name the domain does not declare, comes down to itself.
  """
  @spec base_type(term(), map()) :: term()
  def base_type(type, values) when is_atom(type) do
    case values do
      %{^type => %{type: base}} when is_atom(base) and base != nil and base != type ->
        base_type(base, Map.delete(values, type))

      _ ->
        type
    end
  end

  def base_type(type, _values), do: type

  @doc "One value, with `%` and `|` percent-escaped."
  @spec escape(term()) :: String.t()
  def escape(nil),
    do: raise(ArgumentError, "a key has no nil segment: it would merge with every other nil")

  def escape(value) do
    value
    |> to_string()
    |> String.replace("%", "%25")
    |> String.replace(@separator, "%7C")
  end

  defmodule TooLongError do
    @moduledoc """
    Raised when a process manager is delivered an event whose run's key is over
    `EhOsContract.Key.budget/0`, in place of Postgres's refusal of the entry. Its
    subscription stops at that event, as at any other failure, until someone skips it
    (issue #98). The message names the manager and the bytes, never a value.
    """

    defexception [:message]
  end
end
