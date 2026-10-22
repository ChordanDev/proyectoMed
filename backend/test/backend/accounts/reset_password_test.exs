defmodule Backend.Accounts.ResetPasswordTest do
  @moduledoc """
  Password recovery by email (#336).
  """

  use Backend.DataCase, async: true

  import Backend.AccountsFixtures

  alias Backend.Accounts
  alias Backend.Accounts.UserToken

  defp reset_token(user) do
    extract_user_token(fn url ->
      Accounts.deliver_user_reset_password_instructions(user, url)
    end)
  end

  describe "deliver_user_reset_password_instructions/2" do
    test "emails a reset link and stores only the hashed token" do
      user = user_fixture()

      token = reset_token(user)

      {:ok, decoded} = Base.url_decode64(token, padding: false)
      stored = Repo.get_by!(UserToken, token: :crypto.hash(:sha256, decoded))
      assert stored.user_id == user.id
      assert stored.sent_to == user.email
      assert stored.context == "reset_password"
    end

    test "the email is in pt-BR" do
      user = user_fixture()

      {:ok, email} = Accounts.deliver_user_reset_password_instructions(user, &"/r/#{&1}")

      assert email.subject == "Redefina a sua senha"
      assert email.text_body =~ "Para redefinir a sua senha"
    end
  end

  describe "get_user_by_reset_password_token/1" do
    test "returns the user for a valid token" do
      user = user_fixture()
      token = reset_token(user)

      assert %{id: id} = Accounts.get_user_by_reset_password_token(token)
      assert id == user.id
    end

    test "returns nil for an invalid, expired or other-context token" do
      user = user_fixture()

      refute Accounts.get_user_by_reset_password_token("oops")
      refute Accounts.get_user_by_reset_password_token(Base.url_encode64("x", padding: false))

      {login_token, _hashed} = generate_user_magic_link_token(user)
      refute Accounts.get_user_by_reset_password_token(login_token)

      token = reset_token(user)
      {:ok, decoded} = Base.url_decode64(token, padding: false)
      offset_user_token(:crypto.hash(:sha256, decoded), -2, :day)
      refute Accounts.get_user_by_reset_password_token(token)
    end

    test "returns nil once the email changed" do
      user = user_fixture()
      token = reset_token(user)

      Repo.update!(Ecto.Changeset.change(user, email: unique_user_email()))

      refute Accounts.get_user_by_reset_password_token(token)
    end
  end

  describe "reset_user_password/2" do
    test "sets the password and expires every token" do
      user = user_fixture()
      _session = Accounts.generate_user_session_token(user)
      _token = reset_token(user)

      assert {:ok, {updated, expired}} =
               Accounts.reset_user_password(user, %{
                 password: "a brand new password",
                 password_confirmation: "a brand new password"
               })

      assert length(expired) == 2
      assert Repo.all_by(UserToken, user_id: user.id) == []
      assert updated.password == nil
      assert Accounts.get_user_by_email_and_password(user.email, "a brand new password")
    end

    test "confirms an unconfirmed account, since the link proved the email" do
      user = unconfirmed_user_fixture()

      assert {:ok, {updated, _expired}} =
               Accounts.reset_user_password(user, %{password: "a brand new password"})

      assert updated.confirmed_at
    end

    test "validates the password" do
      user = user_fixture()

      assert {:error, changeset} =
               Accounts.reset_user_password(user, %{
                 password: "short",
                 password_confirmation: "different"
               })

      assert %{
               password: ["deve ter entre 12 e 72 caracteres"],
               password_confirmation: ["não confere com a senha"]
             } = errors_on(changeset)
    end
  end
end
