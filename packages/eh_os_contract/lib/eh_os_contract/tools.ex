defmodule EhOsContract.Tools do
  @moduledoc false
  # What the tasks that read a domain share (plan EL2): which domain, which context,
  # and a name from the command line as an atom that already exists, so a typo is an
  # error that names the choices rather than a new atom.

  @doc false
  @spec domain!([module()], String.t() | nil) :: module()
  def domain!([], _name),
    do: Mix.raise("no EhOsContract.Domain in `config :eh_os_contract, applications:`")

  def domain!([domain], nil), do: domain

  def domain!(domains, nil),
    do: Mix.raise("#{length(domains)} domains; name one with --domain: #{names(domains)}")

  def domain!(domains, name) do
    Enum.find(domains, &(Atom.to_string(&1.__eh_os_contract_model__().name) == name)) ||
      Mix.raise("no domain #{inspect(name)}; the domains are #{names(domains)}")
  end

  @doc false
  @spec context!(module(), String.t() | nil) :: atom() | nil
  def context!(_domain, nil), do: nil

  def context!(domain, name) do
    contexts = Enum.map(domain.__eh_os_contract_model__().contexts, & &1.name)

    Enum.find(contexts, &(Atom.to_string(&1) == name)) ||
      Mix.raise("no context #{inspect(name)}; the contexts are #{Enum.join(contexts, ", ")}")
  end

  @doc false
  @spec existing_atom(String.t() | nil, String.t()) :: atom() | nil
  def existing_atom(nil, _option), do: nil

  def existing_atom(value, option) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> Mix.raise("#{option} #{inspect(value)} names nothing in the model")
  end

  defp names(domains),
    do: Enum.map_join(domains, ", ", &Atom.to_string(&1.__eh_os_contract_model__().name))
end
