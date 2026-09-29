defmodule BoundaryRig.Courses do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A course and how many seats it has: what `BoundaryRig.Enrolment`'s boundary
  consults from a sibling contract.
  """

  use EhOsContract.Contract, domain: BoundaryRig.Domain, context: :enrolment

  aggregate :course, "Course" do
    identity :course_id

    command :define_course, "Define a course", by: :registrar, emits: :course_defined do
      field :capacity, :integer
    end

    event :course_defined, "Course defined" do
      field :capacity, :integer
    end
  end

  process :course, "Course" do
    correlate :course_id
  end
end
