defmodule EhOsContract.Auth.EhosYaml.Reader do
  @moduledoc false
  # `eh-os` D-51: `ehos.yaml` is read into JSON's data model before its schema sees it, and
  # whatever JSON cannot say is refused, as EHOS's own reader refuses it: an anchor or an alias, a
  # tag, a directive, a key given twice, a key that is not a string, a second document, and a
  # number JSON cannot hold. Plain values are resolved by YAML 1.2's core schema, so `yes` is a
  # string. A reader that took the last of two keys, or expanded an alias, would write a manifest
  # from a file EHOS's checking page refuses.
  #
  # yamerl reads twice, as in EHOS: its parser's tokens show anchors, aliases, tags and
  # directives, which its tree no longer does, and its detailed tree keeps every key of a mapping
  # with its line. The rules and their words follow EHOS's reader,
  # `lib/ehos/applications/ehos_yaml/yaml.ex` in `eh-os` at `f7b2330`; a change there is a change
  # to carry here.
  #
  # EHOS's bounds are kept but its budgets: at most 64 KiB, at most 256 of `[` and `{` anywhere in
  # the text, quoted strings included, nesting at most 16 levels, and no list of more than 256
  # entries. The first two are rules a valid file can break; the other two keep the reader's own
  # work small, before the schema refuses what they refuse. EHOS's budgets of time and memory are
  # not carried over: they guard a server against files from anyone, and this reads the
  # developer's own file in their CI.

  @type path :: [String.t() | non_neg_integer()]
  @type error :: %{path: path(), line: pos_integer() | nil, message: String.t()}
  @typedoc "The line each value is on, by its path: for a mapping's value, the line of its key."
  @type lines :: %{path() => pos_integer()}

  @construction [:detailed_constr, {:schema, :core}, {:keep_duplicate_keys, true}]
  # yamerl adds the node modules `config :yamerl, node_mods:` names to the core schema's, in every
  # read in the VM, and one of those reads `yes` as `true` or `512M` as a number. A node only these
  # build is read.
  @core_nodes [
    :yamerl_node_map,
    :yamerl_node_seq,
    :yamerl_node_str,
    :yamerl_node_null,
    :yamerl_node_bool,
    :yamerl_node_int,
    :yamerl_node_float
  ]
  @directives [:yamerl_yaml_directive, :yamerl_tag_directive, :yamerl_reserved_directive]
  @only_json "ehos.yaml holds only what JSON can"
  @max_bytes 65_536
  @max_flow 256
  # The schema nests four levels deep, and the reader's work grows with the square of how deep a
  # file nests: 8000 levels of `- `, 16 KB with no bracket, took it seconds. A deeper file is
  # refused as the parser reaches the limit, as EHOS refuses it.
  @max_depth 16
  # The longest list the schema allows has 32 entries; a reason about an entry finds it by index.
  @max_items 256

  @spec decode(binary()) :: {:ok, term(), lines()} | {:error, [error()]}
  def decode(text) when is_binary(text) do
    # yamerl reads its options from its application's environment, so it is loaded, though it is
    # never started (`runtime: false`).
    :ok = ensure_loaded()

    with :ok <- readable(text),
         :ok <- plain(text),
         {:ok, root} <- construct(text) do
      data(root)
    end
  end

  defp ensure_loaded do
    case Application.load(:yamerl) do
      :ok ->
        :ok

      {:error, {:already_loaded, :yamerl}} ->
        :ok

      {:error, reason} ->
        raise "yamerl cannot be loaded (#{inspect(reason)}): ehos.yaml is read in a Mix task " <>
                "with the package's dependencies fetched; a release does not carry yamerl"
    end
  end

  # yamerl stops at a raw NUL with a function clause error, and reads bytes that are not UTF-8 as
  # Latin-1; both are refused before it reads anything, as are EHOS's two bounds above.
  defp readable(text) do
    cond do
      byte_size(text) > @max_bytes ->
        refuse(nil, "the file is #{byte_size(text)} bytes; EHOS reads at most #{@max_bytes}")

      not String.valid?(text) ->
        refuse(nil, "the file is not UTF-8 text")

      String.contains?(text, <<0>>) ->
        refuse(nil, nul())

      length(:binary.matches(text, ["[", "{"])) > @max_flow ->
        refuse(nil, "the file holds more than #{@max_flow} of [ and {, which EHOS does not read")

      true ->
        :ok
    end
  end

  defp plain(text) do
    _ = :yamerl_parser.string(text, [{:token_fun, token_fun(0, 0)}])
    :ok
  rescue
    exception -> unreadable(exception)
  catch
    {__MODULE__, error} -> {:error, [error]}
    {:yamerl_exception, errors} -> {:error, Enum.map(errors, &parsing_error/1)}
  end

  # yamerl raises on some text it cannot read, such as a file that starts with `:`. Only the two
  # calls into yamerl are rescued, not the conversion of its tree, so a defect there is not taken
  # for a file that is not YAML; the token function yamerl calls back is inside the first one.
  defp unreadable(exception),
    do: refuse(nil, "the file is not YAML that can be read: #{Exception.message(exception)}")

  # The token function carries how deep the parser is and how many documents it has begun, so a
  # second document, or a collection past the limit, is refused as soon as the parser reaches it.
  defp token_fun(depth, documents), do: &{:ok, next(&1, depth, documents)}

  defp next({:yamerl_doc_start, line, _column, _version, _tags}, _depth, 1),
    do: throw_refusal(line, "the file holds more than one YAML document")

  defp next({:yamerl_doc_start, _line, _column, _version, _tags}, depth, documents),
    do: token_fun(depth, documents + 1)

  defp next({:yamerl_collection_start, line, _column, tag, _style, _kind}, depth, documents) do
    untagged(tag)

    if depth == @max_depth,
      do: throw_refusal(line, "nests deeper than #{@max_depth} levels"),
      else: token_fun(depth + 1, documents)
  end

  defp next({:yamerl_collection_end, _line, _column, _style, _kind}, depth, documents),
    do: token_fun(depth - 1, documents)

  defp next(token, depth, documents) do
    plain_token(token)
    token_fun(depth, documents)
  end

  defp plain_token({:yamerl_anchor, line, _column, name}),
    do: throw_refusal(line, "an anchor (&#{name}) is refused: #{@only_json}")

  defp plain_token({:yamerl_alias, line, _column, name}),
    do: throw_refusal(line, "an alias (*#{name}) is refused: #{@only_json}")

  defp plain_token(token) when elem(token, 0) in @directives,
    do: throw_refusal(elem(token, 1), "a directive is refused: ehos.yaml is YAML 1.2 as it is")

  defp plain_token({:yamerl_scalar, _line, _column, tag, _style, _substyle, _text}),
    do: untagged(tag)

  defp plain_token(_token), do: :ok

  # A node written without a tag has a non-specific one: `?` when plain, `!` when quoted.
  defp untagged({:yamerl_tag, _line, _column, {:non_specific, _}}), do: :ok

  defp untagged({:yamerl_tag, line, _column, uri}),
    do: throw_refusal(line, "a tag (#{uri}) is refused: #{@only_json}")

  # yamerl calls the token function for each token as it parses; throwing is how it stops.
  @spec throw_refusal(term(), String.t()) :: no_return()
  defp throw_refusal(line, message), do: throw({__MODULE__, error([], position(line), message)})

  defp parsing_error({:yamerl_parsing_error, _type, text, line, _column, _name, _token, _extra}),
    do: error([], position(line), "the file is not YAML: #{text}")

  defp construct(text) do
    case :yamerl_constr.string(text, @construction) do
      [] -> refuse(nil, "the file holds no YAML document")
      # A second document has been refused by the token function.
      [{:yamerl_doc, root}] -> {:ok, root}
    end
  rescue
    exception -> unreadable(exception)
  catch
    {:yamerl_exception, errors} -> {:error, Enum.map(errors, &parsing_error/1)}
  end

  defp data(root) do
    {data, {lines, errors}} = node(root, [], at({%{}, []}, [], line(root)))

    case errors do
      [] -> {:ok, data, lines}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  defp node(node, path, acc) when elem(node, 1) not in @core_nodes do
    message =
      "is read by #{inspect(elem(node, 1))}, not by YAML 1.2's core schema: remove it from " <>
        "config :yamerl, node_mods"

    {nil, add(acc, error(path, line(node), message))}
  end

  defp node({:yamerl_map, _module, _tag, _position, pairs}, path, acc) do
    {entries, _seen, acc} =
      Enum.reduce(pairs, {[], %{}, acc}, fn {key, value}, state ->
        pair(key, value, path, state)
      end)

    {Map.new(entries), acc}
  end

  # The line of the list's key, where there is one, as for every other reason.
  defp node({:yamerl_seq, _module, _tag, _position, _items, count} = seq, path, acc)
       when count > @max_items do
    {lines, _errors} = acc
    line = Map.get(lines, path, line(seq))
    {[], add(acc, error(path, line, "lists more than #{@max_items} entries"))}
  end

  defp node({:yamerl_seq, _module, _tag, _position, items, _count}, path, acc) do
    items
    |> Enum.with_index()
    |> Enum.map_reduce(acc, fn {item, index}, acc ->
      node(item, path ++ [index], at(acc, path ++ [index], line(item)))
    end)
  end

  # A NUL written as an escape, `"\0"`, reaches the string; EHOS refuses it as well.
  defp node({:yamerl_str, _module, _tag, _position, chars} = str, path, acc) do
    string = List.to_string(chars)

    if String.contains?(string, <<0>>),
      do: {string, add(acc, error(path, line(str), "holds a NUL character"))},
      else: {string, acc}
  end

  defp node({:yamerl_null, _module, _tag, _position}, _path, acc), do: {nil, acc}

  defp node({kind, _module, _tag, _position, value}, _path, acc)
       when (kind == :yamerl_int and is_integer(value)) or
              (kind == :yamerl_float and is_float(value)) or
              (kind == :yamerl_bool and is_boolean(value)),
       do: {value, acc}

  # `.inf` and `.nan` are floats to YAML and nothing to JSON.
  defp node(other, path, acc),
    do: {nil, add(acc, error(path, line(other), "is a number JSON cannot hold"))}

  defp pair({:yamerl_str, _module, _tag, _position, chars} = key, value, path, state) do
    {entries, seen, acc} = state
    name = List.to_string(chars)
    child = path ++ [name]

    cond do
      String.contains?(name, <<0>>) ->
        {entries, seen, add(acc, error(path, line(key), "has a key that holds a NUL character"))}

      Map.has_key?(seen, name) ->
        message = "is given twice in one mapping; the first is on line #{seen[name]}"
        {entries, seen, add(acc, error(child, line(key), message))}

      true ->
        {data, acc} = node(value, child, at(acc, child, line(key)))
        {[{name, data} | entries], Map.put(seen, name, line(key)), acc}
    end
  end

  defp pair(key, _value, path, {entries, seen, acc}),
    do: {entries, seen, add(acc, error(path, line(key), "has a key that is not a string"))}

  defp at(acc, _path, nil), do: acc
  defp at({lines, errors}, path, line), do: {Map.put(lines, path, line), errors}

  defp add({lines, errors}, error), do: {lines, [error | errors]}

  defp line(node) do
    case elem(node, 3) do
      position when is_list(position) -> position(Keyword.get(position, :line))
      _other -> nil
    end
  end

  defp position(line) when is_integer(line) and line > 0, do: line
  defp position(_line), do: nil

  defp nul, do: "the file holds a NUL character"

  defp refuse(line, message), do: {:error, [error([], line, message)]}

  defp error(path, line, message), do: %{path: path, line: line, message: message}
end
