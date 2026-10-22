defmodule Backend.Accounts.AdminRoleTest do
  @moduledoc """
  Roles `admin` and `student` (ADR-014 #346) and admin provisioning without a
  public sign-up path (issue #331).
  """

  use Backend.DataCase, async: true

  import Backend.AccountsFixtures

  alias Backend.Accounts

  describe "roles" do
    test "a registered user is a student" do
      user = user_fixture()

      assert user.role == :student
      refute Accounts.admin?(Accounts.Scope.for_user(user))
    end

    test "registration ignores a role in the attributes" do
      {:ok, user} = Accounts.register_user(valid_user_attributes(%{role: "admin"}))

      assert user.role == :student
    end

    test "admin?/1 is false without a user" do
      refute Accounts.admin?(nil)
      refute Accounts.admin?(Accounts.Scope.for_user(nil))
    end
  end

  describe "create_admin/1" do
    test "creates a confirmed admin that logs in with its password" do
      email = unique_user_email()

      assert {:ok, admin} =
               Accounts.create_admin(%{email: email, password: valid_user_password()})

      assert admin.role == :admin
      assert admin.confirmed_at
      assert Accounts.admin?(Accounts.Scope.for_user(admin))

      assert %{id: id} = Accounts.get_user_by_email_and_password(email, valid_user_password())
      assert id == admin.id
    end

    test "requires a valid email and a password of at least 12 characters" do
      assert {:error, changeset} =
               Accounts.create_admin(%{email: "no-at-sign", password: "short"})

      assert %{email: [_ | _], password: [_ | _]} = errors_on(changeset)
    end

    test "refuses an email that is already registered" do
      user = user_fixture()

      assert {:error, changeset} =
               Accounts.create_admin(%{email: user.email, password: valid_user_password()})

      assert %{email: [_ | _]} = errors_on(changeset)
      assert Accounts.get_user_by_email(user.email).role == :student
    end
  end
end
