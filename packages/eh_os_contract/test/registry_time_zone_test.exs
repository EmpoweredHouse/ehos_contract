defmodule EhOsContract.RegistryTimeZoneTest do
  @moduledoc """
  Plan W2: D13 asks the time zone database configured when a domain compiles, and a
  release may run with another, or with none. The boot's scan asks again, so a node
  that could not tag a timestamp's day refuses to start, naming the domain and the
  zone, rather than raising on every append. The invented `DispatchRig.Domain` keeps
  the days of Warsaw.

  The scan is cached in `:persistent_term` and the database is global configuration,
  so `on_exit` restores both before another test can observe either.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Domain, Registry}

  setup do
    database = Calendar.get_time_zone_database()

    on_exit(fn ->
      Calendar.put_time_zone_database(database)
      Registry.load!()
    end)

    :ok
  end

  test "a node whose database does not know a domain's zone refuses to start" do
    Calendar.put_time_zone_database(Calendar.UTCOnlyTimeZoneDatabase)

    error = assert_raise ArgumentError, fn -> Registry.load!() end

    assert error.message =~
             ~s|DispatchRig.Domain keeps its days in "Europe/Warsaw", which the time zone | <>
               "database this node runs with (Calendar.UTCOnlyTimeZoneDatabase) does not know"
  end

  test "a database configured but absent knows no zone, rather than raising" do
    Calendar.put_time_zone_database(EhOsContract.NoSuchTimeZoneDatabase)

    refute Domain.time_zone_known?("Europe/Warsaw")
  end

  test "control: the database the domain compiled with knows its zone, and UTC is always known" do
    assert Domain.time_zone_known?("Europe/Warsaw")
    Calendar.put_time_zone_database(Calendar.UTCOnlyTimeZoneDatabase)
    assert Domain.time_zone_known?("Etc/UTC")
    refute Domain.time_zone_known?(nil)
  end
end
