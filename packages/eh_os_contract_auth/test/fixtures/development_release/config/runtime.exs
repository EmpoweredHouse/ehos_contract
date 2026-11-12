import Config

# The case `EhOsContract.Auth.DevelopmentReleaseTest` starts the release for: the development
# mode's switch, as config.exs sets it, or `pin_keys: true` in its place, set where a release
# reads it.
if System.get_env("RELEASE_CASE") == "pin_keys" do
  config :eh_os_contract_auth, development: false, pin_keys: true
end
