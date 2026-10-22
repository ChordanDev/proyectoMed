defmodule Backend.Accounts.AccountDeletionTest do
  @moduledoc """
  Account deletion (#336): deleting a learner removes the user and all their
  data. Every table holding a user's data references `users` with
  `ON DELETE CASCADE`, which is the hook later contexts (results #338, billing
  #339) use; the last test enforces it for every future migration.
  """

  use Backend.DataCase, async: true

  import Backend.AccountsFixtures

  alias Backend.Accounts
  alias Backend.Accounts.{User, UserToken}

  describe "delete_user/1" do
    test "removes the learner and every token, returning the tokens to disconnect" do
      user = user_fixture()
      _session = Accounts.generate_user_session_token(user)

      Accounts.deliver_user_reset_password_instructions(user, &"/r/#{&1}")

      assert {:ok, expired} = Accounts.delete_user(user)

      assert length(expired) == 2
      refute Repo.get(User, user.id)
      assert Repo.all_by(UserToken, user_id: user.id) == []
      refute Accounts.get_user_by_email(user.email)
    end

    test "the email can sign up again afterwards" do
      user = user_fixture()
      {:ok, _expired} = Accounts.delete_user(user)

      assert {:ok, _user} = Accounts.register_user(valid_user_attributes(%{email: user.email}))
    end

    test "refuses to delete an admin account" do
      admin = admin_fixture()

      assert {:error, :admin_account} = Accounts.delete_user(admin)
      assert Repo.get(User, admin.id)
    end

    test "leaves the other accounts untouched" do
      user = user_fixture()
      other = user_fixture()

      {:ok, _expired} = Accounts.delete_user(user)

      assert Repo.get(User, other.id)
    end
  end

  describe "deletion hook" do
    test "every foreign key to users cascades on delete" do
      %{rows: rows} =
        Repo.query!("""
        SELECT conrelid::regclass::text, conname, confdeltype
        FROM pg_constraint
        WHERE contype = 'f' AND confrelid = 'users'::regclass
        """)

      assert rows != []

      for [table, constraint, on_delete] <- rows do
        assert on_delete == "c",
               "#{table}.#{constraint} must reference users with on_delete: :delete_all " <>
                 "so deleting an account erases that data (#336)"
      end
    end
  end
end
