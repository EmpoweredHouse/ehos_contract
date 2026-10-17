defmodule EhOsContract.Auth.EhosYaml.Schema do
  @moduledoc false
  # `eh-os` D-51: a version of `ehos.yaml` is its JSON Schema, and EHOS alone writes it. The copy in
  # `priv/schemas/` is EHOS's file byte for byte, a quotation with its source, not a second
  # definition: `ehos.yaml/v1` from `eh-os` `eeb732a`, read at `f7b2330` (1 October 2026), the
  # same bytes the `ehos-tools` template puts in an application's `.ehos/`, and `ehos.yaml/v2`
  # from `eh-os` `99e036b` (D-69), read at `2cd95cb` (2 October 2026), and `ehos.yaml/v3` from
  # `eh-os` `d758c33` (D-81), read at `8ae669f` (8 October 2026), and `ehos.yaml/v4` from `eh-os`
  # `de370ed9` (D-98, D-99), read at `eadd7112` (17 October 2026). A test pins each SHA-256;
  # EHOS freezes a version once released, and until then the copy is refreshed on purpose, never
  # edited.
  #
  # It is validated with JSV, the validator EHOS uses, and what JSV finds is said again at the
  # path of the value it is about, because JSV's own messages quote the schema and report every
  # enclosing object as well. The rules EHOS checks beside the schema, such as unique names and
  # ports in `serves`, are not repeated here: EHOS refuses them when the manifest is deployed.

  @versions %{
    "ehos.yaml/v1" => "v1.json",
    "ehos.yaml/v2" => "v2.json",
    "ehos.yaml/v3" => "v3.json",
    "ehos.yaml/v4" => "v4.json"
  }
  @dir Path.expand("../../../../priv/schemas/ehos.yaml", __DIR__)

  for {_version, file} <- @versions, do: @external_resource(Path.join(@dir, file))

  @schemas Map.new(@versions, fn {version, file} ->
             {version, @dir |> Path.join(file) |> File.read!() |> Jason.decode!()}
           end)

  # What failed inside a value is reported there; these report it again at every value around it.
  @enclosing [:properties, :items, :additionalProperties, :"$ref", :allOf]

  @type error :: %{path: [String.t() | non_neg_integer()], line: nil, message: String.t()}

  @doc false
  @spec versions() :: [String.t()]
  def versions, do: @versions |> Map.keys() |> Enum.sort()

  @doc false
  @spec file(String.t()) :: Path.t()
  def file(version), do: Path.join(@dir, Map.fetch!(@versions, version))

  # A file without `schema`, or with one no copy here is of, is refused before any schema reads it:
  # its version is never guessed at.
  @doc false
  @spec validate(map()) :: :ok | {:error, [error()]}
  def validate(%{"schema" => version} = data) when is_map_key(@schemas, version) do
    case JSV.validate(data, root(version)) do
      {:ok, _valid} ->
        :ok

      {:error, error} ->
        schema = Map.fetch!(@schemas, version)

        reasons =
          error
          |> JSV.normalize_error()
          |> Map.fetch!(:details)
          |> Enum.flat_map(&reasons(&1, data, schema))
          |> Enum.uniq()

        {:error, reasons}
    end
  end

  def validate(%{"schema" => version}) do
    message =
      "must be a version of ehos.yaml this generator knows: #{Enum.join(versions(), ", ")}" <>
        if is_binary(version), do: "; #{inspect(version)} is not one", else: ""

    {:error, [error(["schema"], message)]}
  end

  def validate(%{}),
    do:
      {:error,
       [error(["schema"], "is required: it names the version of ehos.yaml the file is in")]}

  # JSV's built schema holds compiled patterns, which a module attribute cannot, so it is built at
  # each read, in under a millisecond.
  defp root(version), do: JSV.build!(Map.fetch!(@schemas, version))

  defp reasons(unit, data, schema) do
    path = from_pointer(unit.instanceLocation, data)
    here = resolve(schema, unit.schemaLocation)

    Enum.flat_map(unit.errors, fn %{kind: kind, message: message} ->
      cond do
        kind in @enclosing -> []
        kind == :required -> missing(here, value_at(data, path), path)
        kind == :boolean_schema -> [error(path, unknown(unit.evaluationPath, schema, message))]
        true -> [error(path, reason(kind, here, message))]
      end
    end)
  end

  # Each missing key is reported where it should be.
  defp missing(%{"required" => required}, %{} = present, path) do
    for key <- required, not Map.has_key?(present, key), do: error(path ++ [key], "is required")
  end

  defp missing(_here, _present, _path), do: []

  # `additionalProperties: false` is the one schema of `false` a version has: a key it does not know.
  defp unknown(evaluation_path, schema, message) do
    if String.ends_with?(evaluation_path, "/additionalProperties"),
      do: "is not a field of #{schema["title"]}",
      else: message
  end

  defp reason(:type, %{"type" => type}, _message), do: "must be #{a(type)}"
  defp reason(:const, %{"const" => value}, _message), do: "must be #{value}"
  defp reason(:enum, %{"enum" => values}, _message), do: "must be #{Enum.join(values, " or ")}"
  defp reason(:pattern, %{"pattern" => pattern}, _message), do: "must match #{pattern}"
  defp reason(:not, %{"const" => value}, _message), do: "must not be #{value}"

  # v4's reserved secret names: a `not` of patterns and values, said as what it refuses.
  defp reason(:not, %{"anyOf" => [_ | _] = choices} = here, message) do
    refused =
      Enum.flat_map(choices, fn
        %{"pattern" => pattern} -> ["match #{pattern}"]
        %{"enum" => values} -> ["be #{Enum.join(values, ", ")}"]
        %{"const" => value} -> ["be #{value}"]
        _other -> []
      end)

    if length(refused) == length(here["anyOf"]),
      do: "is a name EHOS reserves: it must not " <> Enum.join(refused, ", or "),
      else: message
  end
  defp reason(:minimum, %{"minimum" => min}, _message), do: "must be at least #{min}"
  defp reason(:maximum, %{"maximum" => max}, _message), do: "must be at most #{max}"

  defp reason(:minLength, %{"minLength" => min}, _message),
    do: "must be at least #{min} #{characters(min)} long"

  defp reason(:maxLength, %{"maxLength" => max}, _message),
    do: "must be at most #{max} #{characters(max)} long"

  defp reason(:minItems, %{"minItems" => min}, _message), do: "must list at least #{min}"
  defp reason(:maxItems, %{"maxItems" => max}, _message), do: "must list at most #{max}"
  defp reason(:uniqueItems, %{"uniqueItems" => true}, _message), do: "must list each value once"
  defp reason(_kind, _here, message), do: message

  defp a("object"), do: "a mapping of keys to values"
  defp a("array"), do: "a list"
  defp a("string"), do: "a string"
  defp a("integer"), do: "an integer"
  defp a("boolean"), do: "true or false"
  defp a(type), do: "of type #{type}"

  defp characters(1), do: "character"
  defp characters(_count), do: "characters"

  # The schema's own locations: `#`, `#/$defs/port`, `#/properties/application/not`.
  defp resolve(schema, "#" <> pointer) do
    pointer
    |> String.split("/", trim: true)
    |> Enum.map(&unescape/1)
    |> Enum.reduce(schema, fn key, here -> if is_map(here), do: Map.get(here, key) end)
  end

  # A JSON pointer into the document, as a path whose indices are integers where the document has
  # a list.
  defp from_pointer("#" <> pointer, data), do: from_pointer(pointer, data)
  defp from_pointer("", _data), do: []

  defp from_pointer("/" <> pointer, data) do
    pointer
    |> String.split("/")
    |> Enum.map(&unescape/1)
    |> Enum.map_reduce(data, fn
      token, list when is_list(list) ->
        case Integer.parse(token) do
          {index, ""} -> {index, Enum.at(list, index)}
          _other -> {token, nil}
        end

      token, %{} = map ->
        {token, Map.get(map, token)}

      token, _other ->
        {token, nil}
    end)
    |> elem(0)
  end

  defp unescape(token), do: token |> String.replace("~1", "/") |> String.replace("~0", "~")

  defp value_at(data, path) do
    Enum.reduce(path, data, fn
      index, list when is_integer(index) and is_list(list) -> Enum.at(list, index)
      key, %{} = map -> Map.get(map, key)
      _key, _other -> nil
    end)
  end

  defp error(path, message), do: %{path: path, line: nil, message: message}
end
