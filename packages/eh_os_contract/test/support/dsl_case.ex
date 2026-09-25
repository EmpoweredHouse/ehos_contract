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
