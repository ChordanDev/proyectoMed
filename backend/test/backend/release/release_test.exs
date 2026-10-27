defmodule Backend.ReleaseTest do
  @moduledoc """
  Release tasks (#344): `bin/backend eval "Backend.Release.create_admin()"`
  provisions an admin from `ADMIN_EMAIL` and `ADMIN_PASSWORD`, idempotently,
  and never prints the password.
  """

  use Backend.DataCase, async: true

  import ExUnit.CaptureIO
  import Backend.AccountsFixtures

  alias Backend.Accounts
  alias Backend.Release

  @password "a long admin password"

  describe "provision_admin/1" do
    test "creates a confirmed admin from ADMIN_EMAIL and ADMIN_PASSWORD" do
      email = unique_user_email()

      assert {:ok, :created} =
               Release.provision_admin(%{"ADMIN_EMAIL" => email, "ADMIN_PASSWORD" => @password})

      admin = Accounts.get_user_by_email_and_password(email, @password)
      assert admin.role == :admin
      assert admin.confirmed_at
    end

    test "leaves an existing admin unchanged" do
      email = unique_user_email()
      env = %{"ADMIN_EMAIL" => email, "ADMIN_PASSWORD" => @password}
      assert {:ok, :created} = Release.provision_admin(env)

      assert {:ok, :exists} =
               Release.provision_admin(%{env | "ADMIN_PASSWORD" => "another admin password"})

      assert Accounts.get_user_by_email_and_password(email, @password).role == :admin
    end

    test "refuses an email that belongs to a non-admin account, leaving it unchanged" do
      user = user_fixture()

      assert {:error, :not_admin} =
               Release.provision_admin(%{
                 "ADMIN_EMAIL" => user.email,
                 "ADMIN_PASSWORD" => @password
               })

      assert Accounts.get_user_by_email(user.email).role == user.role
      refute Accounts.get_user_by_email_and_password(user.email, @password)
    end

    test "refuses without both variables" do
      assert {:error, :missing_env} = Release.provision_admin(%{})

      assert {:error, :missing_env} =
               Release.provision_admin(%{"ADMIN_EMAIL" => unique_user_email()})

      assert {:error, :missing_env} =
               Release.provision_admin(%{"ADMIN_EMAIL" => " ", "ADMIN_PASSWORD" => @password})
    end

    test "returns the validation errors of an invalid password" do
      assert {:error, {:invalid, errors}} =
               Release.provision_admin(%{
                 "ADMIN_EMAIL" => unique_user_email(),
                 "ADMIN_PASSWORD" => "short"
               })

      assert Map.has_key?(errors, :password)
    end
  end

  describe "create_admin/1" do
    test "reports the outcome by email and never prints the password" do
      email = unique_user_email()
      env = %{"ADMIN_EMAIL" => email, "ADMIN_PASSWORD" => @password}

      created = capture_io(fn -> assert {:ok, :created} = Release.create_admin(env) end)
      assert created =~ "admin #{email} created"
      refute created =~ @password

      exists = capture_io(fn -> assert {:ok, :exists} = Release.create_admin(env) end)
      assert exists =~ "admin #{email} already exists"
      refute exists =~ @password
    end

    test "says an existing non-admin account was not made an admin" do
      user = user_fixture()

      output =
        capture_io(fn ->
          assert {:error, :not_admin} =
                   Release.create_admin(%{
                     "ADMIN_EMAIL" => user.email,
                     "ADMIN_PASSWORD" => @password
                   })
        end)

      assert output =~ "#{user.email} belongs to a non-admin account"
      refute output =~ "already exists"
      refute output =~ @password
    end

    test "never prints a rejected password" do
      output =
        capture_io(fn ->
          assert {:error, {:invalid, _errors}} =
                   Release.create_admin(%{
                     "ADMIN_EMAIL" => unique_user_email(),
                     "ADMIN_PASSWORD" => "tiny-pw"
                   })
        end)

      assert output =~ "not created"
      refute output =~ "tiny-pw"
    end
  end

  describe "exit_code/1" do
    test "is 0 for a created or existing admin and 1 for every error" do
      assert Release.exit_code({:ok, :created}) == 0
      assert Release.exit_code({:ok, :exists}) == 0
      assert Release.exit_code({:error, :missing_env}) == 1
      assert Release.exit_code({:error, :not_admin}) == 1
      assert Release.exit_code({:error, {:invalid, %{}}}) == 1
      assert Release.exit_code({:error, {:repo, :econnrefused}}) == 1
    end

    test "bin/create_admin exits with it, so a failure is never reported as success" do
      script = File.read!(Path.expand("../../../rel/overlays/bin/create_admin", __DIR__))

      assert script =~
               "Backend.Release.create_admin() |> Backend.Release.exit_code() |> System.halt()"
    end
  end
end
