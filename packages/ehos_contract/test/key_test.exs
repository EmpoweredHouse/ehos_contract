defmodule EhosContract.KeyTest do
  @moduledoc """
  Which fields an append tags an event with (v2 §10.4, plan EM1), and since E9c a
  field typed by a domain value whose base type is `:id` among them: a period named
  "2026-07" is an identifier with an invariant of its own.
  """

  use ExUnit.Case, async: true

  alias EhosContract.Key

  # As `EhosContract.Codec.values/1` gives them: a value of `:id`, a value of that
  # value, one of another type, and one made of fields.
  @values %{
    period: %{name: :period, type: :id},
    closing_period: %{name: :closing_period, type: :period},
    money: %{name: :money, type: :integer},
    window: %{name: :window, type: nil}
  }

  defp field(type, opts \\ []),
    do: Map.merge(%{name: :f, type: type, optional: false, personal: nil}, Map.new(opts))

  test "a domain value of :id is a tag, followed through a value of it" do
    assert Key.tag_field?(field(:period), @values)
    assert Key.tag_field?(field(:closing_period), @values)
  end

  test "control: a value of another type, or made of fields, is not" do
    refute Key.tag_field?(field(:money), @values)
    refute Key.tag_field?(field(:window), @values)
  end

  test "control: without the domain's values only the built-in type counts" do
    assert Key.tag_field?(field(:id))
    refute Key.tag_field?(field(:period))
  end

  test "control: optional and personal values of :id are not tags either" do
    refute Key.tag_field?(field(:period, optional: true), @values)
    refute Key.tag_field?(field(:period, personal: :member_id), @values)
  end

  test "base_type follows values to the built-in type, and stops at what it cannot follow" do
    assert Key.base_type(:closing_period, @values) == :id
    assert Key.base_type(:window, @values) == :window
    assert Key.base_type(:undeclared, @values) == :undeclared
    assert Key.base_type({:list, :id}, @values) == {:list, :id}
  end

  describe "the budget (issue #98)" do
    test "counts the bytes of every column of an entry together" do
      assert Key.fits?([String.duplicate("a", 2000), String.duplicate("b", 48)])
      refute Key.fits?([String.duplicate("a", 2000), String.duplicate("b", 49)])
    end

    test "counts bytes, not characters" do
      # "€" is three bytes in UTF-8.
      assert Key.fits?([String.duplicate("€", 682) <> "aa"])
      refute Key.fits?([String.duplicate("€", 682) <> "aaa"])
    end
  end
end
