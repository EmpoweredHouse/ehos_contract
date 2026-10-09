defmodule EhOsContract.Domain do
  @moduledoc """
  The vocabulary an application's contracts share: one module per application.

      defmodule Rehmed.Domain do
        use EhOsContract.Domain, name: :rehmed, language: :pl

        subdomain :billing, "Rozliczenia z pacjentami", type: :supporting
        context :settlement, "Rozliczenia", subdomain: :billing
        actor :reception, :human, "Recepcja"
        value :money, :integer, unit: :grosze, label: "Kwota"
      end

  A domain module declares subdomains, contexts with their glossary, actors, subjects of
  personal data, value types, external systems and the relations between contexts.

  A value may declare invariants, each with values that break it and keep it:

      value :money, :integer, unit: :grosze do
        invariant :not_negative, "Kwota nie jest ujemna",
          violated_by: [-1],
          satisfied_by: [0, 15_000]
      end

  The domain then generates a behaviour, `Rehmed.Domain.Values.Money`, and a module
  bound with `use Rehmed.Domain, value: :money` defines one function per invariant,
  answering whether a value keeps it. Dispatch holds every value of the type to them,
  once the value fits its type and after the values it is made of: a command, or a
  recorded event, that carries a value breaking one is refused with
  `{field, {:invariant, name}}`, and an event a decision returns with one raises, as
  a defect. Dispatch raises, too, on a value with invariants that no module implements.
  What is read back from the log is never held to them, so an invariant declared
  today does not make yesterday's events unreadable. `use EhOsContract.ScenarioCase,
  domain: Rehmed.Domain` tests each example.
  It compiles to plain data, `__eh_os_contract_model__/0`, which
  `EhOsContract.Model.fetch/1` returns for it. The data carries a `version`: a digest
  that ignores the order declarations are written in.

  `name:` is the domain's name, and `language:` is the language its labels and terms
  are written in, unless a context says otherwise. The name is the application's
  namespace, the first segment of every name its contracts publish and of every
  capability, so it is one such segment: lowercase letters, digits, `_` and `-`,
  starting with a letter and not ending with a dash.
  `code_language:` is the language its identifiers are written in, English unless it
  says otherwise: a term's word in code is its translation into that language, or the
  term itself in a context written in it. `mix eh_os_contract.glossary` shows each
  term's word in code and the declarations named with it, and `mix eh_os_contract.check`
  ranks the words of a context's names no term covers (`word-without-term`) and warns
  where a name uses a term of another context only (`term-of-another-context`).
  `time_zone:` is the zone its days are in, UTC unless it says otherwise: an event's
  `:timestamp` is tagged with its day there when it is appended, so a day is the
  business's, not Greenwich's. A zone the configured time zone database does not
  know does not compile.
  """

  use Spark.Dsl,
    default_extensions: [extensions: [EhOsContract.Domain.Dsl]],
    opt_schema: [
      name: [
        type: :atom,
        required: true,
        doc:
          "The domain's name, the application's namespace: lowercase letters, digits, `_` " <>
            "and `-`, starting with a letter and not ending with a dash, like `:\"my-shop\"`."
      ],
      language: [
        type: :atom,
        required: true,
        doc: "The language labels and terms are written in."
      ],
      # The glossary joined to the code (plan DD, L1).
      code_language: [
        type: :atom,
        default: :en,
        doc:
          "The language identifiers are written in: a term's word in code is its " <>
            "translation into it."
      ],
      # A timestamp's business day (plan W2).
      time_zone: [
        type: :string,
        default: "Etc/UTC",
        doc:
          "The zone the business's days are in, like `\"Europe/Warsaw\"`: a `:timestamp` " <>
            "is tagged with its day there. Read with the time zone database the " <>
            "host configures."
      ]
    ]

  # The words of the DSL: for every entity, by its path from the module body, the keys
  # it takes — positional arguments first, then options, in the order the entity
  # defines them. Derived from the extension, never listed by hand, so a test that
  # pins it notices every word added or removed.
  @doc false
  @spec vocabulary() :: %{[atom()] => [atom()]}
  def vocabulary, do: EhOsContract.DslWrappers.vocabulary(EhOsContract.Domain.Dsl.sections())

  # Whether `zone` is one the time zone database Elixir is configured with knows
  # (plan W2): asked as dispatch asks it, so a database module that is configured but
  # not there — Tz's database without `{:tz, …}` among the deps — answers `false`, as an
  # unknown zone does, rather than raising.
  @doc false
  @spec time_zone_known?(term()) :: boolean()
  def time_zone_known?(zone) when is_binary(zone) do
    match?({:ok, _}, DateTime.shift_zone(~U[2026-01-01 00:00:00Z], zone))
  rescue
    _undefined in UndefinedFunctionError -> false
  end

  def time_zone_known?(_zone), do: false

  @impl Spark.Dsl
  def handle_opts(opts) do
    quote do
      @persist {:eh_os_contract_domain,
                %{
                  name: unquote(opts[:name]),
                  language: unquote(opts[:language]),
                  code_language: unquote(Keyword.get(opts, :code_language, :en)),
                  time_zone: unquote(Keyword.get(opts, :time_zone, "Etc/UTC"))
                }}
      @persist {:eh_os_contract_line, __ENV__.line}
    end
  end
end
