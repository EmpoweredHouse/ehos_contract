defmodule EhOsContract.DomainVocabularyTest do
  @moduledoc """
  Plan EL1, the gap EM2's review found: **the domain DSL's vocabulary, pinned**, as
  the contract's is (`contract_vocabulary_test.exs`). `entity` came into the domain
  in EM2 without any pinned list changing, since there was none. `vocabulary/0` is
  derived from the extension's entity definitions, so this literal is the one place
  a word is written down twice, on purpose: a word added or removed fails this
  test, and the change it records belongs in the commit that makes it.
  """

  use ExUnit.Case, async: true

  # Plan EL2: `issued_by`, the external that gives a value.
  @field [:name, :type, :optional, :label, :personal, :subject, :default, :issued_by]

  test "the words did not change without this test changing with them" do
    assert EhOsContract.Domain.vocabulary() == %{
             # Plan EL2: a named subdomain, which a context names.
             [:subdomain] => [:name, :label, :type, :source],
             [:context] => [:name, :label, :subdomain, :language, :source],
             [:context, :term] => [:text, :definition, :source],
             # Plan EL2: a translation means something, and says what to avoid, and why.
             [:context, :term, :translation] => [:language, :text, :definition],
             [:context, :term, :translation, :avoid] => [:text, :reason],
             [:context, :term, :avoid] => [:text, :reason],
             # Plan EP1: `source` on every declaration, the first rung of the ladder.
             [:actor] => [:name, :kind, :label, :backed_by, :context, :scope, :may_grant, :source],
             # Plan EP5b: what an actor answers for, named prose.
             [:actor, :responsibility] => [:name, :label, :source],
             [:subject] => [:name, :label, :source],
             [:value] => [:name, :type, :unit, :label, :context, :source],
             [:value, :field] => @field,
             [:value, :invariant] => [:name, :label, :violated_by, :satisfied_by, :source],
             # Plan EM2: ESDM's entity; plan N1: its identity, injected, and who issues it.
             [:entity] => [:name, :label, :context, :identity, :issued_by, :source],
             [:entity, :field] => @field,
             [:external] => [
               :name,
               :label,
               :direction,
               :unavailable_looks_like,
               :expected_latency,
               :source
             ],
             # Plan EP5a: what a system does when an effect calls it.
             [:external, :operation] => [:name, :label, :source],
             [:relation] => [:type, :upstream, :downstream, :between, :terms, :source]
           }
  end
end
