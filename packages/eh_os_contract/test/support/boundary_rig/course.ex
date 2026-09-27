defmodule BoundaryRig.Course do
  @moduledoc "**Invented.** The decider of `BoundaryRig.Courses`'s course."

  use BoundaryRig.Courses, aggregate: :course

  @impl true
  def define_course(%DefineCourse{course_id: id, capacity: capacity}, _state),
    do: emit(%CourseDefined{course_id: id, capacity: capacity})
end
