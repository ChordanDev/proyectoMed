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
    # References that may only point at an admin, never at a learner. Admins are
    # never deleted by `delete_user/1`, so these need not cascade: they nilify
    # (`case_revisions.editor_id` keeps the author in `editor_email`) or
    # restrict, so deleting an admin never erases the content they edited.
    @admin_only_references MapSet.new([
                             "case_revisions.editor_id",
                             "cases.approved_by_id",
                             "station_versions.approved_by_id"
                           ])

    test "every foreign key to users cascades on delete, except admin-only ones" do
      %{rows: rows} =
        Repo.query!("""
        SELECT c.conrelid::regclass::text, a.attname, c.confdeltype
        FROM pg_constraint c
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
        WHERE c.contype = 'f' AND c.confrelid = 'users'::regclass
        """)

      assert rows != []

      for [table, column, on_delete] <- rows,
          not MapSet.member?(@admin_only_references, "#{table}.#{column}") do
        assert on_delete == "c",
               "#{table}.#{column} must reference users with on_delete: :delete_all " <>
                 "so deleting an account erases that data (#336), or be listed as an " <>
                 "admin-only reference in this test"
      end
    end
  end
end
