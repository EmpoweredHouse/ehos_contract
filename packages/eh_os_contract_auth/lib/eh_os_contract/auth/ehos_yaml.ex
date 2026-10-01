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

  A refusal is a list of reasons, each at the path of the value it is about, in
  EHOS's notation (`serves[0].port`, `""` for the file as a whole), with the line
  when it is known.
  """

  alias EhOsContract.Auth.EhosYaml.Reader

  @typedoc "One reason a file is refused."
  @type error :: %{path: String.t(), line: pos_integer() | nil, message: String.t()}

  @doc """
  Reads `ehos.yaml` from its text.

  Returns the file in JSON's data model, keys as strings, or every reason it is
  refused, sorted by line, those without one first.
  """
  @spec read(binary()) :: {:ok, map()} | {:error, [error()]}
  def read(text) when is_binary(text) do
    case Reader.decode(text) do
      {:ok, %{} = data, _lines} -> {:ok, data}
      {:ok, _data, _lines} -> refused([%{path: [], line: 1, message: "must be a mapping"}])
      {:error, errors} -> refused(errors)
    end
  end

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
