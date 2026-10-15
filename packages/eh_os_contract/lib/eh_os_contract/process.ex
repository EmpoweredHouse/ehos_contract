defmodule EhOsContract.Process do
  @moduledoc """
  A process written as a module of its own: one run that crosses the contracts of
  several parts of a business.

      defmodule Rehmed.Processes.ClinicalVisit do
        use EhOsContract.Process,
          id: "rehmed.clinical_visit",
          domain: Rehmed.Domain,
          label: "Wizyta: wykonanie, dokumentacja i zgłoszenie zdarzenia medycznego",
          accountable: :manager

        correlate :visit_id

        stage :departure, include: [{Rehmed.Contracts.Scheduling, :visit_completed}]
        stage :closing, include: [{Rehmed.Contracts.ClinicalDocumentation, :visit_closed_clinically}]

        stage :reporting,
          include: [
            {Rehmed.Contracts.StatutoryReporting,
             [:p1_report_queued, :p1_report_sent, :p1_report_failed, :p1_reporting_not_required]}
          ]

        ends_on [:p1_report_sent, :p1_reporting_not_required]

        promise :medical_event_reported_within_statutory_window do
          from :visit_completed
          eventually :p1_report_sent
          within {2, :day}
          or_else :p1_reporting_not_required
          source "Dz.U. 2025 poz. 866"
        end
      end

  A contract describes a part of the business, the units that decide in it and what
  reacts to them; a process module describes one run through several of them. It
  names the run (`id:`, `label:`), what tells one run from another (`correlate`), its
  stages and the events of the contracts each includes, the events that end a run
  (`ends_on`), the promises it keeps and how long a run may take (`deadline`). An
  included event is named by its name alone everywhere else in the module, so that
  name is unique in it.

  `domain:` names the application's `EhOsContract.Domain`, and a stage's `include:`
  names contract modules; neither records a compile dependency. `id:` is
  `"<domain name>.<segment>…"` (D11).

  What one module can get wrong does not compile. It compiles to plain data,
  `__eh_os_contract_model__/0`, which `EhOsContract.Model.fetch/1` returns, of kind
  `:process`. What it names in other modules — its domain, the contracts and their
  events — is checked by the `:eh_os_contract` compiler, which checks the links
  between modules, and dispatch files each event it includes into its run, under its
  `id:` and keyed by its `correlate`. The conformance report shows those runs, its
  deployment record its version, and the check reads what it includes; the
  conformance wire carries its report too (`EhOsContract.Conformance.as_data/2`). It
  has a page of its own (`mix eh_os_contract.pages`), a `graph.v1` document
  (`EhOsContract.Graph.Document.process/1`), a branch of `mix eh_os_contract.view` and a
  section on the dashboard's status screen.

  Inside the library this module is always written in full, never aliased: `Process`
  is Elixir's.
  """

  use Spark.Dsl,
    default_extensions: [extensions: [EhOsContract.Process.Dsl]],
    opt_schema: [
      id: [
        type: :string,
        required: true,
        doc:
          "The process's name (D11): the domain's `name:`, then dotted snake_case segments, " <>
            "like `\"rehmed.clinical_visit\"`."
      ],
      label: [type: :string, required: true, doc: "What the business calls the process."],
      domain: [type: :atom, required: true, doc: "The application's domain module."],
      accountable: [type: :atom, doc: "The actor a finding about the process is addressed to."],
      source: [type: :string, doc: "Where the process comes from in the material."]
    ]

  # The words of the DSL: for every entity, by its path from the module body, the keys
  # it takes — positional arguments first, then options, in the order the entity
  # defines them. Derived from the extension, never listed by hand.
  @doc false
  @spec vocabulary() :: %{[atom()] => [atom()]}
  def vocabulary,
    do: EhOsContract.DslWrappers.vocabulary(EhOsContract.Process.Dsl.sections())

  @impl Spark.Dsl
  def handle_opts(opts) do
    quote do
      @persist {:eh_os_contract_process,
                %{
                  id: unquote(opts[:id]),
                  label: unquote(opts[:label]),
                  domain: unquote(opts[:domain]),
                  accountable: unquote(opts[:accountable]),
                  source: unquote(opts[:source])
                }}
      @persist {:eh_os_contract_line, __ENV__.line}
    end
  end
end
