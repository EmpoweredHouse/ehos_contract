defmodule EhosContract.Check.Finding do
  # One thing `mix ehos_contract.check` says: which rule, how loudly, the sentence,
  # and where the declaration it is about was written.
  #
  # The rule is a stable name from `EhosContract.Check.Catalog`; the sentence is for a
  # person and may change between versions, the name may not. Anything reading the
  # output — a CI step, `--format json` — selects on `rule`. The level is the rule's,
  # fixed in the catalog, so building a finding for a rule the catalog does not have
  # raises: a name printed without a documented rule behind it would be a name
  # nobody can look up.
  @moduledoc false

  alias EhosContract.Check.Catalog

  @enforce_keys [:rule, :level, :message]
  defstruct [:rule, :level, :message, :at]

  @typedoc "How loudly: an error fails `check`, a warning fails it under `--warnings-as-errors`."
  @type level :: :error | :warn | :info

  @type t :: %__MODULE__{
          rule: String.t(),
          level: level(),
          message: String.t(),
          at: :erl_anno.anno() | nil
        }

  @doc """
  A finding of the catalog's rule `rule`, at its level. `at` is where the
  declaration the finding is about was written, when anything says so.
  """
  @spec new(String.t(), String.t(), :erl_anno.anno() | nil) :: t()
  def new(rule, message, at \\ nil) do
    %__MODULE__{rule: rule, level: Catalog.fetch!(rule).level, message: message, at: at}
  end

  @doc """
  A violation of a rule of the compiler, L2 or L3, as an error under the code its
  message starts with (`"X2: …"` is rule `X2`), or `L3` when it names none. The
  catalog does not document these; v2 §6 does.
  """
  @spec compiler({String.t(), :erl_anno.anno() | nil}) :: t()
  def compiler({message, at}) do
    case Regex.run(~r/\A([A-Z]+[0-9]+): (.*)\z/s, message) do
      [_, code, rest] -> %__MODULE__{rule: code, level: :error, message: rest, at: at}
      nil -> %__MODULE__{rule: "L3", level: :error, message: message, at: at}
    end
  end

  @doc "`file:line` relative to the working directory, or `nil` when nothing says where."
  @spec place(t()) :: {String.t(), pos_integer()} | nil
  def place(%__MODULE__{at: nil}), do: nil

  def place(%__MODULE__{at: at}) do
    case :erl_anno.file(at) do
      :undefined -> nil
      file -> {file |> to_string() |> Path.relative_to_cwd(), :erl_anno.line(at)}
    end
  end
end
