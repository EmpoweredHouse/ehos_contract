defmodule EhOsContract.Next.ContractVocabularyTest do
  @moduledoc """
  v2 plan, E4: **the contract DSL's vocabulary, pinned.** `vocabulary/0` is derived
  from the extension's entity definitions, not from a list kept beside them, so this
  literal is the one place a word is written down twice — on purpose. A word added
  or removed fails this test, and the change it records belongs in the commit that
  makes it, like v1's universality gate (`universality_gate_test.exs`).

  The shapes that repeat — a field, an event, a command, a unit's body — are named
  once below; the paths are every place the DSL lets them be written.
  """

  use ExUnit.Case, async: true

  # Plan EL2: `issued_by`, the external that gives a value.
  @field [:name, :type, :optional, :label, :personal, :subject, :default, :issued_by]
  @event [:name, :label, :terminal, :depends_on, :recorded_by, :schema_version, :source]
  @command [:name, :label, :by, :emits, :rejects, :creates, :source]

  defp unit(kind) do
    %{
      [kind] => [:name, :label, :identity, :source],
      [kind, :state] => [],
      [kind, :state, :field] => @field,
      [kind, :invariant] => [:name, :label, :source],
      [kind, :command] => @command,
      [kind, :command, :field] => @field,
      # Plan EL2: ESDM's constraint, checked as an invariant is.
      [kind, :command, :constraint] => [:name, :label, :source],
      [kind, :event] => @event,
      [kind, :event, :field] => @field,
      [kind, :stage] => [:name],
      [kind, :stage, :event] => @event,
      [kind, :stage, :event, :field] => @field
    }
  end

  test "the words did not change without this test changing with them" do
    expected =
      unit(:aggregate)
      # Plan EM3: a new aggregate's identity may be the library's to give.
      |> Map.put([:aggregate], [:name, :label, :identity, :generated, :source])
      |> Map.merge(unit(:dcb))
      |> Map.merge(%{
        [:dcb, :consults] => [:event, :match, :where],
        [:policy] => [:name, :label, :handles, :issues, :delivery, :idempotency],
        [:effect] => [:name, :label, :handles, :calls, :delivery, :idempotency],
        [:process_manager] => [:name, :label, :correlate, :delivery, :idempotency],
        [:process_manager, :state] => [],
        [:process_manager, :state, :field] => @field,
        [:process_manager, :starts_on] => [:event, :sets, :issues],
        [:process_manager, :on] => [:event, :issues, :sets, :cancels],
        [:process_manager, :timer] => [:name, :wait, :at, :issues],
        [:process_manager, :ends_on] => [:event],
        [:read_model] => [:name, :label, :projects, :delivery],
        [:read_model, :field] => @field,
        [:query] => [:name, :label, :reads, :by, :returns, :scope],
        [:query, :param] => [:name, :type, :optional, :label],
        [:query, :constraint] => [:name, :label, :source],
        # Plan EM2: ESDM's domain service.
        [:domain_service] => [:name, :label, :source],
        [:domain_service, :function] => [:name, :label],
        [:domain_service, :function, :returns] => [:type, :optional],
        [:domain_service, :function, :argument] => [:name, :type, :optional, :label],
        [:domain_service, :function, :rule] => [:name, :label, :source],
        [:consumes] => [:from, :events, :as],
        [:consumes, :field] => @field,
        [:publish] => [:name, :as, :from, :fields, :idempotent_on],
        [:process] => [:name, :label, :correlate, :accountable],
        [:process, :stage] => [:name, :label],
        [:process, :stage, :include] => [:event, :terminal],
        [:process, :include] => [:event, :terminal],
        [:process, :cadence] => [:every, :unverified],
        [:process, :deadline] => [:within, :unverified],
        [:process, :promise] => [
          :name,
          :from,
          :eventually,
          :within,
          :or_else,
          :unverified,
          :source
        ],
        [:scenario] => [:description, :scope, :actor, :rejected, :ended],
        [:scenario, :given] => [:event, :data],
        [:scenario, :command] => [:name, :data],
        [:scenario, :on] => [:name, :data],
        [:scenario, :query] => [:name, :data],
        [:scenario, :expect] => [:event, :data],
        [:scenario, :issues] => [:command, :data],
        [:scenario, :sets] => [:timer],
        [:scenario, :cancels] => [:timer],
        [:scenario, :answers] => [:rows]
      })

    assert EhOsContract.Next.Contract.vocabulary() == expected
  end

  test "public: is not a word: an event leaves the application only through publish (D11)" do
    refute :public in EhOsContract.Next.Contract.vocabulary()[[:aggregate, :event]]
  end
end
