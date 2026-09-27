defmodule EhOsContract.Next.ContractDomainServicesTest do
  @moduledoc """
  Plan EM2: **what a contract refuses in a domain service** — the names (N1, N2) and
  the types of its arguments and results (F1, F2) — each with a control that
  compiles, and that a contract declaring none keeps the version it had before the
  kind existed.
  """

  use EhOsContract.DslCase, async: false

  @process """
    aggregate :visit, "Wizyta" do
      identity :visit_id
      command :close_visit, "Zamknięcie", by: :reception, emits: :visit_closed
      event :visit_closed, "Zamknięto", terminal: true
    end

    process :visit, "Wizyta" do
      correlate :visit_id
    end
  """

  test "two functions or two rules of one name, a Kernel clash and a repeated argument are refused" do
    message =
      refuse_contract("ServicesNamed", """
        domain_service :pricing, "Cennik" do
          function :price, "Cena" do
            argument :minutes, :integer
            argument :minutes, :integer
            returns :integer
            rule :rounded, "Zaokrąglona"
            rule :rounded, "Zaokrąglona w górę"
          end

          function :price, "Cena druga" do
            returns :integer
          end

          function :send, "Wyślij" do
            argument :to, :string
            argument :what, :string
            returns :boolean
          end
        end

      #{@process}
      """)

    assert message =~
             "N1: domain service :pricing has two functions named :price (services_named.ex:13)"

    assert message =~ "N1: function :price has two rules named :rounded (services_named.ex:10)"
    assert message =~ "N2: function :send would define send/2, which clashes with Kernel.send/2"

    assert message =~
             "F1: domain service :pricing, function :price declares field :minutes twice " <>
               "(services_named.ex:7)"
  end

  test "a malformed argument or result type is refused" do
    message =
      refuse_contract("ServicesTyped", """
        domain_service :pricing, "Cennik" do
          function :price, "Cena" do
            argument :method, {:enum, []}
            returns "integer"
          end
        end

      #{@process}
      """)

    assert message =~
             "F2: domain service :pricing, function :price, field :method: an enum is a " <>
               "non-empty list of members"

    assert message =~
             ~s|F2: domain service :pricing, function :price returns "integer" is not a type| <>
               " (services_typed.ex:5)"
  end

  test "control: a service with functions, arguments of every shape and rules compiles into the model" do
    model =
      compile_contract("ServicesRight", """
        domain_service :pricing, "Cennik", source: "AGG-06" do
          function :price, "Cena usługi" do
            argument :service_id, {:id, :service}
            argument :minutes, :integer, optional: true
            returns :money
            rule :rounded, "Zaokrąglona do pełnych złotych", source: "W1 00:10:00"
          end

          function :free, "Czy bezpłatna" do
            argument :service_id, :id
            returns :boolean
          end
        end

      #{@process}
      """)

    assert [%{name: :pricing, source: "AGG-06", functions: [price, free]}] = model.domain_services

    assert [
             %{name: :service_id, type: :id, refers_to: :service},
             %{name: :minutes, type: :integer, optional: true}
           ] = price.arguments

    assert %{returns: :money, rules: [%{name: :rounded}]} = price
    assert %{name: :free, returns: :boolean} = free
    assert Map.has_key?(model.digests, "domain_service:pricing")

    assert EhOsContract.Model.module_for(model, :domain_service, :pricing) ==
             EhOsContract.Next.Fixtures.ServicesRight.DomainServices.Pricing
  end

  test "a contract without domain services hashes as it did before they existed" do
    with_one =
      compile_contract("ServicesOne", "#{@process}\n  domain_service :pricing, \"Cennik\"\n")

    without = compile_contract("ServicesNone", @process)

    # The service moves the version, and nothing else's digest.
    assert Map.delete(with_one.digests, "domain_service:pricing") == without.digests
    refute with_one.version == without.version

    # The version the invented ledger had before the kind existed, read on the
    # commit before EM2; the sandbox's Rehmed.Contracts.VisitSettlement kept its
    # recorded 2ae1d0074cbc the same way. An empty group hashed in would move both.
    assert EhOsContract.Model.fetch(DispatchRig.Ledger).version == "4e94b8af0057"
  end
end
