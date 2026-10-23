# Reads the `mix.exs` of a package as `mix hex.build --unpack` wrote it, the way an
# application that installed it from Hex reads it, and fails if it declares a dependency
# by `path:` or `git:` for an environment a host builds in. Hex refuses such a package at
# publish time only when it is built; a package whose `mix.exs` switches to `path:` once
# installed would pass that and break every application installing it.
#
#     elixir .github/scripts/hex-package-deps.exs <unpacked package directory>
#
# Run it without `EH_OS_CONTRACT_HEX` in the environment: the package has to know it came
# from Hex by the `hex_metadata.config` beside its `mix.exs`.
[dir] = System.argv()
mix_exs = Path.join(dir, "mix.exs")

unless File.exists?(Path.join(dir, "hex_metadata.config")) do
  IO.puts(:stderr, "#{dir} has no hex_metadata.config: not a package unpacked by hex.build")
  System.halt(1)
end

Mix.start()
Code.require_file(mix_exs)

local =
  for dep <- Mix.Project.config()[:deps],
      opts = if(is_list(elem(dep, tuple_size(dep) - 1)), do: elem(dep, tuple_size(dep) - 1), else: []),
      Keyword.has_key?(opts, :path) or Keyword.has_key?(opts, :git) or
        Keyword.has_key?(opts, :github),
      only = List.wrap(Keyword.get(opts, :only, [:prod])),
      :prod in only,
      do: dep

if local == [] do
  IO.puts("#{Path.basename(dir)}: every dependency a host builds is by version")
else
  IO.puts(:stderr, "#{Path.basename(dir)} declares, once installed from Hex:")
  for dep <- local, do: IO.puts(:stderr, "  #{inspect(dep)}")
  System.halt(1)
end
