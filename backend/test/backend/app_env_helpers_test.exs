defmodule Backend.AppEnvHelpersTest do
  # Edits the :backend application env: not async.
  use ExUnit.Case, async: false

  alias Backend.AppEnvHelpers

  @key :app_env_helpers_test_key

  setup do
    Application.delete_env(:backend, @key)
    on_exit(fn -> Application.delete_env(:backend, @key) end)
  end

  describe "snapshot/1 and restore/2 (#363)" do
    test "a key that was unset is deleted again, not left as nil" do
      previous = AppEnvHelpers.snapshot(@key)
      Application.put_env(:backend, @key, :temporary)

      assert :ok = AppEnvHelpers.restore(@key, previous)

      assert Application.fetch_env(:backend, @key) == :error
      assert Application.get_env(:backend, @key, :default) == :default
    end

    test "a key that held a value gets that value back" do
      Application.put_env(:backend, @key, :original)
      previous = AppEnvHelpers.snapshot(@key)
      Application.put_env(:backend, @key, :temporary)

      assert :ok = AppEnvHelpers.restore(@key, previous)

      assert Application.fetch_env(:backend, @key) == {:ok, :original}
    end

    test "a key that held an explicit nil keeps the explicit nil" do
      Application.put_env(:backend, @key, nil)
      previous = AppEnvHelpers.snapshot(@key)
      Application.delete_env(:backend, @key)

      assert :ok = AppEnvHelpers.restore(@key, previous)

      assert Application.fetch_env(:backend, @key) == {:ok, nil}
    end

    test "snapshot/2 and restore/3 do the same for another application" do
      app = :app_env_helpers_test_app
      on_exit(fn -> Application.delete_env(app, @key) end)

      previous = AppEnvHelpers.snapshot(app, @key)
      Application.put_env(app, @key, :temporary)

      assert :ok = AppEnvHelpers.restore(app, @key, previous)

      assert Application.fetch_env(app, @key) == :error
    end
  end

  describe "leaked_nils/1 (#363)" do
    test "lists the keys that now hold nil but were absent or non-nil in the snapshot" do
      before = %{was_set: :value, was_nil: nil}

      env = [was_set: nil, was_nil: nil, new_nil: nil, new_value: :value]

      assert AppEnvHelpers.leaked_nils(before, env) == [:new_nil, :was_set]
    end

    test "is empty when no key turned into nil" do
      assert AppEnvHelpers.leaked_nils(%{a: 1}, a: 2, b: :value) == []
    end
  end
end
