defmodule EhosContract.Auth.EhosYaml.Schema do
  @moduledoc false
  # A version of `ehos.yaml` is its JSON Schema, and EHOS alone writes it. The copy in
  # `priv/schemas/` is EHOS's file byte for byte, a quotation, not a second definition:
  # `ehos.yaml/v1` as read on 1 October 2026, the same bytes EHOS's application template puts in
  # an application's `.ehos/`, `ehos.yaml/v2` (sign-in) as read on 2 October, `ehos.yaml/v3` (the
  # company's people) on 8 October, `ehos.yaml/v4` (a seed and secrets) on 17 October,
  # `ehos.yaml/v5` (the hosts outside the installation it reaches) on 22 October, before EHOS
  # released it, `ehos.yaml/v6` (mail sent through EHOS) on 24 October, as EHOS 0.20.0
  # releases it, `ehos.yaml/v7` (the CPU and memory a workload asks for) on 27 October, as EHOS
  # 0.21.0 released it, and `ehos.yaml/v8` (an application or a utility service, and the services
  # an application calls) on 16 November 2026, before EHOS released it. A test pins each SHA-256;
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
    "ehos.yaml/v4" => "v4.json",
    "ehos.yaml/v5" => "v5.json",
    "ehos.yaml/v6" => "v6.json",
    "ehos.yaml/v7" => "v7.json",
    "ehos.yaml/v8" => "v8.json"
  }
  @dir Path.expand("../../../../priv/schemas/ehos.yaml", __DIR__)

  for {_version, file} <- @versions, do: @external_resource(Path.join(@dir, file))

  @schemas Map.new(@versions, fn {version, file} ->
             {version, @dir |> Path.join(file) |> File.read!() |> Jason.decode!()}
           end)

  # A pattern is an ECMA-262 regular expression, where `$` ends the text, but JSV compiles it with
  # PCRE, where `$` also matches before a final line break, so `^[a-z]+$` would take `"ledger\\n"`.
  # EHOS writes each such `$` as `\\z` before JSV builds the schema, and so does this copy; the
  # file, and the schema a reason quotes, stay as written.
  @built Map.new(@schemas, fn {version, schema} -> {version, __MODULE__.Ecma.schema(schema)} end)

  # What failed inside a value is reported there; these report it again at every value around it.
  @enclosing [:properties, :items, :additionalProperties, :"$ref", :allOf]

  # From v8, what a utility service may not give, and the two keys v8 adds, said as EHOS says them,
  # keyed by where the schema refuses them. No earlier version has a schema at these locations.
  @words %{
    "#/properties/kind" =>
      "must be application, a workload with a contract, or service, a utility service",
    "#/properties/needs/properties/services" => "must list at most 16 utility services",
    "#/then" =>
      "is required for a utility service, which has no contract to take its name from: " <>
        "name the service here",
    "#/then/properties/needs/properties/database" =>
      "is not for a utility service, which keeps no data of its own: remove it",
    "#/then/properties/needs/properties/people" =>
      "is not for a utility service, which does not read the people directory: remove it",
    "#/then/properties/needs/properties/mail" =>
      "is not for a utility service, which sends no mail through EHOS: remove it",
    "#/then/properties/needs/properties/services" =>
      "is not for a utility service, which calls no other utility service: remove it",
    "#/then/properties/sign_in" =>
      "is not for a utility service, which signs nobody in: remove it",
    "#/then/properties/serves/items/properties/public/not" =>
      "must not be true for a utility service: only the applications of its environment " <>
        "reach it, each with a service agreement"
  }

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
  # each read, in under a millisecond, from the schema with its patterns' `$` read as EHOS reads it.
  defp root(version), do: JSV.build!(Map.fetch!(@built, version))

  defp reasons(unit, data, schema) do
    path = from_pointer(unit.instanceLocation, data)
    here = resolve(schema, unit.schemaLocation)

    own = Map.get(@words, unit.schemaLocation)

    Enum.flat_map(unit.errors, fn
      # What a schema's `then` refuses is said by what failed inside it; the `if` that held is
      # listed with it, and failed nothing.
      %{kind: :"if/then", details: details} ->
        details
        |> Enum.reject(& &1.valid)
        |> Enum.flat_map(&reasons(&1, data, schema))

      %{kind: kind, message: message} ->
        cond do
          kind in @enclosing -> []
          kind == :required -> missing(here, value_at(data, path), path, own || "is required")
          # A value of the wrong type is told its type, as EHOS tells it.
          own != nil and kind != :type -> [error(path, own)]
          kind == :boolean_schema -> [error(path, unknown(unit.evaluationPath, schema, message))]
          true -> [error(path, reason(kind, here, message))]
        end
    end)
  end

  # Each missing key is reported where it should be.
  defp missing(%{"required" => required}, %{} = present, path, message) do
    for key <- required, not Map.has_key?(present, key), do: error(path ++ [key], message)
  end

  defp missing(_here, _present, _path, _message), do: []

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
  defp reason(:not, %{"anyOf" => [_ | _] = choices}, message) do
    refused =
      Enum.flat_map(choices, fn
        %{"pattern" => pattern} -> ["match #{pattern}"]
        %{"enum" => values} -> ["be #{Enum.join(values, ", ")}"]
        %{"const" => value} -> ["be #{value}"]
        _other -> []
      end)

    if length(refused) == length(choices),
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
