defmodule EhOsContract.Auth.EhosYaml do
  @moduledoc """
  Reads an application's `ehos.yaml` as EHOS reads it (`eh-os` D-51).

  `ehos.yaml` says what a workload needs in order to run, and EHOS alone defines its
  format. `mix eh_os_contract.manifest` carries every key of it into the manifest
  unchanged, so it must read the file exactly as EHOS's checking page does, or it
  would write a manifest from a file EHOS refuses. Whatever YAML can say and JSON
  cannot is refused before anything else sees the file: an anchor or an alias, a
  tag, a directive, a key given twice in one mapping, a key that is not a string,
  more than one document, and a number such as `.inf`. Plain values are read by
  YAML 1.2's core schema, so `yes` and `on` are strings, not `true`.

  A file that reads is then validated against the JSON Schema of the version its
  `schema` names, EHOS's own file, copied unchanged into this package's
  `priv/schemas/`; `versions/0` lists the versions there. The rules EHOS checks beside
  its schema, such as unique names and ports in `serves`, are left to EHOS, which
  refuses them when the manifest is deployed, but for the two of `ehos.yaml/v2`'s
  `sign_in` (`eh-os` D-69), which adding `sign_in` alone breaks: it needs an entry of
  `serves` named `web` with `public: true`, where sign-in returns, and its
  `applications` never name the `application` the file names.

  A refusal is a list of reasons, each at the path of the value it is about, in
  EHOS's notation (`serves[0].port`, `""` for the file as a whole), with the line
  when it is known.

  It reads the developer's own file, in a Mix task. Nothing bounds the time a file
  takes to read, so it is not for a file that arrives with a request; and its
  dependencies, yamerl and JSV, are `runtime: false`, so a release has neither.
  """

  alias EhOsContract.Auth.EhosYaml.{Reader, Schema}

  @typedoc "One reason a file is refused."
  @type error :: %{path: String.t(), line: pos_integer() | nil, message: String.t()}

  @doc """
  Reads `ehos.yaml` from its text.

  Returns the file in JSON's data model, keys as strings, as it is written: no
  default is filled in. Otherwise every reason it is refused, sorted by line, those
  without one first.
  """
  @spec read(binary()) :: {:ok, map()} | {:error, [error()]}
  def read(text) when is_binary(text) do
    with {:ok, data, lines} <- Reader.decode(text),
         {:ok, data} <- mapping(data, lines),
         :ok <- validate(data, lines),
         :ok <- sign_in(data, lines) do
      {:ok, data}
    else
      {:error, errors} -> refused(errors)
    end
  end

  @doc """
  The versions of `ehos.yaml` this package can read and carry into a manifest.

  Each is EHOS's own JSON Schema, copied unchanged into this package's `priv/schemas/`.
  """
  @spec versions() :: [String.t()]
  def versions, do: Schema.versions()

  defp mapping(%{} = data, _lines), do: {:ok, data}

  defp mapping(_data, lines),
    do: {:error, [%{path: [], line: Map.get(lines, []), message: "must be a mapping"}]}

  # A reason from the schema has no line of its own: it is given the line of the value's key, or,
  # for a key that is missing, of the mapping that should hold it.
  defp validate(data, lines) do
    case Schema.validate(data) do
      :ok ->
        :ok

      {:error, errors} ->
        {:error, Enum.map(errors, &%{&1 | line: line(lines, &1.path)})}
    end
  end

  # `eh-os` D-69, as `Ehos.Applications.EhosYaml.V2` checks it beside the schema: sign-in returns
  # to the host of the public entry `web` (D-68), and the list names the other applications only.
  # `public` is false when it is not written, as the schema's default says.
  defp sign_in(%{"sign_in" => sign_in} = data, lines) do
    public_web =
      data
      |> Map.get("serves", [])
      |> Enum.any?(&(&1["name"] == "web" and &1["public"] == true))

    web =
      if public_web,
        do: [],
        else: [
          error(
            ["sign_in"],
            lines,
            "needs an entry of serves named web with public: true, where sign-in returns"
          )
        ]

    own =
      for {name, index} <- Enum.with_index(Map.get(sign_in, "applications", [])),
          name == data["application"],
          do:
            error(["sign_in", "applications", index], lines, "is the application this file names")

    if web ++ own == [], do: :ok, else: {:error, web ++ own}
  end

  defp sign_in(_data, _lines), do: :ok

  defp error(path, lines, message), do: %{path: path, line: line(lines, path), message: message}

  defp line(_lines, []), do: nil

  defp line(lines, path) do
    case Map.fetch(lines, path) do
      {:ok, line} -> line
      :error -> if length(path) > 1, do: Map.get(lines, Enum.drop(path, -1))
    end
  end

  @doc "The largest file EHOS reads, in bytes: 64 KiB."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: Reader.max_bytes()

  @doc "One reason as a line of text: `line 7: serves[0].port: must be at least 1024`."
  @spec format_error(error()) :: String.t()
  def format_error(%{path: path, line: line, message: message}) do
    at = if line, do: "line #{line}: ", else: ""
    if path == "", do: at <> message, else: "#{at}#{path}: #{message}"
  end

  defp refused(errors) do
    errors =
      errors
      |> Enum.map(&%{&1 | path: path_to_string(&1.path)})
      |> Enum.sort_by(&{&1.line != nil, &1.line || 0, &1.path})

    {:error, errors}
  end

  # The notation of EHOS's reasons: a key that is an identifier after a dot, any other key quoted
  # in brackets, and an index in brackets.
  defp path_to_string(path) do
    Enum.reduce(path, "", fn
      index, written when is_integer(index) ->
        "#{written}[#{index}]"

      key, written ->
        cond do
          not Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_-]*\z/u, key) ->
            "#{written}[#{Jason.encode!(key)}]"

          written == "" ->
            key

          true ->
            "#{written}.#{key}"
        end
    end)
  end
end
