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

  @field [:name, :type, :optional, :label, :personal, :subject, :default]

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
             [:actor] => [:name, :kind, :label, :backed_by, :context, :scope],
             [:subject] => [:name, :label],
             [:value] => [:name, :type, :unit, :label, :context],
             [:value, :field] => @field,
             # Plan EM2: ESDM's entity, reference data a context owns.
             [:entity] => [:name, :label, :context, :identified_by, :source],
             [:entity, :field] => @field,
             [:external] => [
               :name,
               :label,
               :direction,
               :unavailable_looks_like,
               :expected_latency
             ],
             [:relation] => [:type, :upstream, :downstream, :between, :terms]
           }
  end
end
