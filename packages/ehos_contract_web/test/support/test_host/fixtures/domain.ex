defmodule EhosContract.Web.TestHost.Fixtures.Domain do
  @moduledoc """
  INVENTED — the vocabulary `EhosContract.Web.TestHost.Fixtures.CaseHandling` names,
  and nothing more: one context and the one person who opens and decides a case.
  """

  use EhosContract.Domain, name: :web_test_host, language: :en

  context :cases, "Cases", subdomain: :core

  actor :case_officer, :human, "Case officer"

  subdomain :core, "Core", type: :core
end
