defmodule EhOsContract.ContractVocabularyTest do
  @moduledoc """
  v2 plan, E4: **the contract DSL's vocabulary, pinned.** `vocabulary/0` is derived
  from the extension's entity definitions, not from a list kept beside them, so this
  literal is the one place a word is written down twice — on purpose. A word added
  or removed fails this test, and the change it records belongs in the commit that
  makes it.

  The shapes that repeat — a field, an event, a command, a unit's body — are named
  once below; the paths are every place the DSL lets them be written.

  > **Pinned anew 29 September 2026, E11d.** Until the cut this literal was the v2
  > vocabulary beside v1's, and the universality gate's "no word added for it" was
  > measured against v1's keys. v2 did not add to v1's vocabulary; it replaced it
  > wholesale by taking ESDM's, so a comparison with v1 no longer measures anything.
  > From here on the gate counts from this literal: a word added for one domain's
  > sake is a change here, in the commit that adds it, and has to say which domain
  > needed it.
  """

  use ExUnit.Case, async: true

  # Plan EL2: `issued_by`, the external that gives a value; plan T1: `supplied_by`, who
  # gives it instead of the caller.
  @field [
    :name,
    :type,
    :optional,
    :label,
    :personal,
    :subject,
    :default,
    :issued_by,
    :supplied_by
  ]
  @event [:name, :label, :terminal, :depends_on, :recorded_by, :schema_version, :source]
  @command [:name, :label, :by, :emits, :rejects, :creates, :scope, :source]

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
      # Plan LC1 (#99): an aggregate's lifecycle, and the statuses its command may be issued
      # in, with what it is refused on outside; a boundary has none of them.
      |> Map.merge(%{
        [:aggregate, :command] => @command ++ [:from, :or_rejects],
        [:aggregate, :lifecycle] => [],
        [:aggregate, :lifecycle, :status] => [:name, :label, :final, :source],
        [:aggregate, :lifecycle, :initial] => [:status, :on, :source],
        [:aggregate, :lifecycle, :transition] => [:from, :event, :to, :source]
      })
      |> Map.merge(unit(:dcb))
      |> Map.merge(%{
        [:dcb, :consults] => [:event, :match, :where],
        # Plan EP1: `source` on every declaration, the first rung of the ladder.
        [:policy] => [:name, :label, :handles, :issues, :delivery, :idempotency, :source],
        [:effect] => [:name, :label, :handles, :calls, :delivery, :idempotency, :source],
        [:process_manager] => [:name, :label, :correlate, :delivery, :idempotency, :source],
        [:process_manager, :state] => [],
        [:process_manager, :state, :field] => @field,
        [:process_manager, :starts_on] => [:event, :sets, :issues],
        [:process_manager, :on] => [:event, :issues, :sets, :cancels],
        [:process_manager, :timer] => [:name, :label, :wait, :at, :issues, :source],
        [:process_manager, :ends_on] => [:event],
        # Plan EP2: a reaction's rules, which a scenario illustrates.
        [:policy, :constraint] => [:name, :label, :source],
        [:effect, :constraint] => [:name, :label, :source],
        [:process_manager, :constraint] => [:name, :label, :source],
        [:process_manager, :invariant] => [:name, :label, :source],
        [:read_model] => [:name, :label, :projects, :delivery, :source],
        [:read_model, :field] => @field,
        [:query] => [:name, :label, :reads, :by, :returns, :scope, :source],
        [:query, :param] => [:name, :type, :optional, :label],
        [:query, :constraint] => [:name, :label, :source],
        # Plan EM2: ESDM's domain service.
        [:domain_service] => [:name, :label, :source],
        [:domain_service, :function] => [:name, :label],
        [:domain_service, :function, :returns] => [:type, :optional],
        [:domain_service, :function, :argument] => [:name, :type, :optional, :label],
        [:domain_service, :function, :rule] => [:name, :label, :examples, :source],
        [:consumes] => [:from, :events, :as],
        [:consumes, :field] => @field,
        [:subscribe] => [:from, :as],
        [:subscribe, :field] => @field,
        [:publish] => [:name, :as, :from, :fields, :idempotent_on],
        [:process] => [:name, :label, :correlate, :accountable, :source],
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
        [:scenario] => [:description, :target, :actor, :rejected, :illustrates, :ended],
        [:scenario, :given] => [:event, :data],
        [:scenario, :command] => [:name, :data],
        [:scenario, :on] => [:name, :data],
        [:scenario, :query] => [:name, :data],
        [:scenario, :expect] => [:event, :data],
        [:scenario, :issues] => [:command, :data],
        [:scenario, :sets] => [:timer],
        [:scenario, :cancels] => [:timer],
        [:scenario, :answers] => [:rows],
        [:scenario, :state] => [:data]
      })

    assert EhOsContract.Contract.vocabulary() == expected
  end

  test "public: is not a word: an event leaves the application only through publish (D11)" do
    refute :public in EhOsContract.Contract.vocabulary()[[:aggregate, :event]]
  end
end
