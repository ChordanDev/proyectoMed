defmodule Backend.ApplicationTest do
  @moduledoc """
  Only a release, which sets `RELEASE_NAME`, migrates on boot (issue #329).
  """

  # Mutates an operating system environment variable.
  use ExUnit.Case, async: false

  setup do
    original = System.get_env("RELEASE_NAME")

    on_exit(fn ->
      if original,
        do: System.put_env("RELEASE_NAME", original),
        else: System.delete_env("RELEASE_NAME")
    end)

    :ok
  end

  test "skips boot migrations outside a release" do
    System.delete_env("RELEASE_NAME")
    assert Backend.Application.skip_migrations?()
  end

  test "runs boot migrations in a release" do
    System.put_env("RELEASE_NAME", "backend")
    refute Backend.Application.skip_migrations?()
  end
end
