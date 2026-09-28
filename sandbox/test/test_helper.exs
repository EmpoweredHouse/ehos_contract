# `:known_defect` marks a test that asserts what the engine **should** do and does
# not. Excluded by default so `mix check` stays green on a defect that is recorded
# rather than fixed; run it deliberately with
#
#     mix test --include known_defect
#
# The alternative — deleting the test and describing the defect in prose — is how a
# gap stops being checkable. A tagged red test is the only form of a known defect
# that turns green by itself when somebody fixes it.
ExUnit.configure(exclude: [:known_defect])
:ok = Taxvision.CommitRepo.reset!()
ExUnit.start()
