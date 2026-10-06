defmodule EhOsContract.DslCase do
  @moduledoc """
  Compiling a DSL module from source in a test, to see what the compiler refuses.

  Spark records where a declaration was written only when the compiler's
  `:debug_info` option is on (`Spark.Dsl.Extension.macro_env_anno/2`). `mix compile`
  turns it on for a project's `.ex` files, so a consumer's errors carry their file
  and line. Code compiled from a string in a test gets the option as it happens to
  be, which is off. So `compile_error/2` turns it on for the one compilation and
  puts it back.

  Compiler options are global to the VM, which is why a case using this is
  `async: false`: two tests switching the option at once could take the location
  away from each other.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import EhOsContract.DslCase
    end
  end

  @doc """
  Compiles `source` as if it were the file `file` and returns the `Spark.Error.DslError`
  it raises. Fails the test when it compiles, or raises anything else.
  """
  @spec compile_error(String.t(), String.t()) :: Spark.Error.DslError.t()
  def compile_error(source, file) do
    compile(source, file)
    ExUnit.Assertions.flunk("expected #{file} not to compile, and it compiled")
  rescue
    error in Spark.Error.DslError -> error
  end

  @doc """
  The source of a v2 contract `EhOsContract.Fixtures.<name>` whose `body` starts
  at line 4 of the file. Its domain is named and does not exist, which a contract
  may do (v2 §8).
  """
  @spec contract(String.t(), String.t()) :: String.t()
  def contract(name, body) do
    """
    defmodule EhOsContract.Fixtures.#{name} do
      use EhOsContract.Contract, domain: Clinic, context: :settlement, id: "clinic.#{Macro.underscore(name)}"

    #{body}
    end
    """
  end

  @doc """
  Compiles the contract `contract/2` writes, as the file `<name, underscored>.ex`, and
  returns the message of the error it raises.
  """
  @spec refuse_contract(String.t(), String.t()) :: String.t()
  def refuse_contract(name, body) do
    name |> contract(body) |> compile_error("#{Macro.underscore(name)}.ex") |> Exception.message()
  end

  @doc "Compiles the contract `contract/2` writes and returns its model."
  @spec compile_contract(String.t(), String.t()) :: map()
  def compile_contract(name, body) do
    compile(contract(name, body), "#{Macro.underscore(name)}.ex")
    EhOsContract.Model.fetch(Module.concat(EhOsContract.Fixtures, name))
  end

  @doc """
  Compiles `source` as the file `file` and returns why it did not compile:
  `%{message:, file:, line:}`. Fails the test when it compiles.

  A refusal comes in one of three shapes, and each is taken: a `Spark.Error.DslError`
  from a DSL rule (L1–L2), a `CompileError` a macro raises at its call site (L4), and
  an error diagnostic from the compiler itself — an unknown key in a struct pattern,
  an undefined function — which it logs before raising a `CompileError` of its own
  that names no cause. The first diagnostic of level error wins over that exception.
  """
  @spec refusal(String.t(), String.t()) :: %{
          message: String.t(),
          file: String.t() | nil,
          line: non_neg_integer() | nil
        }
  def refusal(source, file) do
    {result, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          compile(source, file)
          :compiled
        rescue
          error -> {:raised, error}
        end
      end)

    case {result, Enum.filter(diagnostics, &(&1.severity == :error))} do
      {:compiled, []} ->
        ExUnit.Assertions.flunk("expected #{file} not to compile, and it compiled")

      {_, [diagnostic | _]} ->
        %{message: diagnostic.message, file: diagnostic.file, line: line(diagnostic.position)}

      {{:raised, %Spark.Error.DslError{location: anno} = error}, []} ->
        %{
          message: Exception.message(error),
          file: anno && anno |> :erl_anno.file() |> to_string(),
          line: anno && :erl_anno.line(anno)
        }

      {{:raised, %CompileError{} = error}, []} ->
        %{message: error.description, file: error.file, line: error.line}

      {{:raised, error}, []} ->
        ExUnit.Assertions.flunk(
          "expected #{file} to be refused, and compiling it raised #{inspect(error)}"
        )
    end
  end

  @doc """
  Asserts that `source`, compiled as the file `file`, is refused with a message
  containing `fragment`, **and that the refusal points at `file`** — at the user's
  code, not at the library's. `line`, when given, is checked too. Returns the
  message.
  """
  @spec assert_refused(String.t(), String.t(), String.t() | Regex.t(), pos_integer() | nil) ::
          String.t()
  def assert_refused(source, file, fragment, line \\ nil) do
    refusal = refusal(source, file)

    ExUnit.Assertions.assert(
      refusal.message =~ fragment,
      "#{file} was refused, but not for this reason.\nexpected: #{inspect(fragment)}\n" <>
        "got: #{refusal.message}"
    )

    ExUnit.Assertions.assert(
      refusal.file == file,
      "the refusal points at #{inspect(refusal.file)}, not at #{file}: #{refusal.message}"
    )

    if line, do: ExUnit.Assertions.assert(refusal.line == line, "#{inspect(refusal)}")

    refusal.message
  end

  defp line({line, _column}), do: line
  defp line(line), do: line

  @doc """
  Compiles each `{file, source}` and returns what the rules between modules (L3,
  `EhOsContract.Contract.Links`) find among the modules they define, as
  `%{message:, file:, line:}`. The sources have to compile: L3 reads compiled
  modules.
  """
  @spec links([{String.t(), String.t()}]) :: [
          %{message: String.t(), file: String.t() | nil, line: non_neg_integer() | nil}
        ]
  def links(sources) do
    modules =
      for {file, source} <- sources, {module, _binary} <- compile(source, file), do: module

    for {message, anno} <- EhOsContract.Contract.Links.check(modules) do
      %{
        message: message,
        file: anno && anno |> :erl_anno.file() |> to_string() |> Path.relative_to_cwd(),
        line: anno && :erl_anno.line(anno)
      }
    end
  end

  @doc """
  Asserts that one of `violations` (from `links/1`) has a message containing
  `fragment` **and points at `file`**, at `line` when given. Returns the message.
  """
  @spec assert_linked([map()], String.t() | Regex.t(), String.t(), pos_integer() | nil) ::
          String.t()
  def assert_linked(violations, fragment, file, line \\ nil) do
    found =
      Enum.find(violations, &(&1.message =~ fragment)) ||
        ExUnit.Assertions.flunk(
          "no violation says #{inspect(fragment)}; found:\n" <>
            Enum.map_join(violations, "\n", &"  #{&1.message}")
        )

    ExUnit.Assertions.assert(
      found.file == file,
      "the violation points at #{inspect(found.file)}, not at #{file}: #{found.message}"
    )

    if line, do: ExUnit.Assertions.assert(found.line == line, "#{inspect(found)}")

    found.message
  end

  @doc """
  Compiles `source` as the file `file` with `:debug_info` on, and returns what
  `Code.compile_string/2` returns. The binaries then carry their debug chunk, which
  is also where typespecs are read from.
  """
  @spec compile(String.t(), String.t()) :: [{module(), binary()}]
  def compile(source, file \\ "nofile") do
    previous = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)

    try do
      Code.compile_string(source, file)
    after
      Code.put_compiler_option(:debug_info, previous)
    end
  end
end
