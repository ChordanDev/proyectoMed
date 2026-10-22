defmodule Backend.Accounts.AdminSeedTest do
  @moduledoc """
  `priv/repo/seeds.exs` provisions the admin named by `ADMIN_EMAIL` and
  `ADMIN_PASSWORD` (issue #331). It is the only way to create an admin.
  """

  # Not async: the seed reads process-wide environment variables.
  use Backend.DataCase, async: false

  import ExUnit.CaptureIO

  alias Backend.Accounts

  @seeds Path.expand("../../../priv/repo/seeds.exs", __DIR__)

  setup do
    on_exit(fn ->
      System.delete_env("ADMIN_EMAIL")
      System.delete_env("ADMIN_PASSWORD")
    end)
  end

  test "creates the admin once and is idempotent" do
    System.put_env("ADMIN_EMAIL", "medica@example.com")
    System.put_env("ADMIN_PASSWORD", "senha segura de teste")

    output = capture_io(fn -> Code.eval_file(@seeds) end)
    assert output =~ "admin medica@example.com created"

    admin = Accounts.get_user_by_email_and_password("medica@example.com", "senha segura de teste")
    assert admin.role == :admin

    output = capture_io(fn -> Code.eval_file(@seeds) end)
    assert output =~ "admin medica@example.com already exists"
  end

  test "skips without ADMIN_EMAIL and ADMIN_PASSWORD" do
    output = capture_io(fn -> Code.eval_file(@seeds) end)

    assert output =~ "ADMIN_EMAIL and ADMIN_PASSWORD not set"
    assert Backend.Repo.aggregate(Backend.Accounts.User, :count) == 0
  end

  test "never prints the password" do
    System.put_env("ADMIN_EMAIL", "medica@example.com")
    System.put_env("ADMIN_PASSWORD", "senha segura de teste")

    output = capture_io(fn -> Code.eval_file(@seeds) end)

    refute output =~ "senha segura de teste"
  end
end
