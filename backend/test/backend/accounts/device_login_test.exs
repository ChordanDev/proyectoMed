defmodule Backend.Accounts.DeviceLoginTest do
  @moduledoc """
  Device login (#337, RFC 8628 shape): the Unreal client starts a login, the
  learner approves its user code in the browser, and the client's poll
  receives a short-lived access token and a rotating refresh token. Only
  hashes are stored, and every token is revocable.
  """

  use Backend.DataCase, async: true

  import Backend.AccountsFixtures

  alias Backend.Accounts
  alias Backend.Accounts.{DeviceAuthorization, DeviceToken}

  defp approved_tokens(user) do
    {:ok, start} = Accounts.start_device_authorization()
    :ok = Accounts.approve_device_authorization(user, start.user_code)
    {:ok, tokens} = Accounts.poll_device_authorization(start.device_code)
    tokens
  end

  defp age_authorization!(start, seconds) do
    hash = :crypto.hash(:sha256, start.device_code)
    authorization = Repo.get_by!(DeviceAuthorization, device_code_hash: hash)

    authorization
    |> Ecto.Changeset.change(expires_at: DateTime.add(authorization.expires_at, -seconds))
    |> Repo.update!()
  end

  describe "start_device_authorization/0" do
    test "returns a device code, a short user code, the polling interval and the lifetime" do
      assert {:ok, start} = Accounts.start_device_authorization()

      assert byte_size(start.device_code) >= 43
      assert start.user_code =~ ~r/^[BCDFGHJKLMNPQRSTVWXZ]{4}-[BCDFGHJKLMNPQRSTVWXZ]{4}$/
      assert start.interval == 5
      assert start.expires_in == 600
    end

    test "stores only hashes of the codes" do
      {:ok, start} = Accounts.start_device_authorization()
      [authorization] = Repo.all(DeviceAuthorization)

      refute authorization.device_code_hash == start.device_code
      refute authorization.user_code_hash =~ String.replace(start.user_code, "-", "")
      assert authorization.device_code_hash == :crypto.hash(:sha256, start.device_code)
    end
  end

  describe "pending_device_authorization?/1" do
    test "accepts the user code typed in any case and without the dash" do
      {:ok, start} = Accounts.start_device_authorization()
      typed = start.user_code |> String.replace("-", "") |> String.downcase()

      assert Accounts.pending_device_authorization?(typed)
      refute Accounts.pending_device_authorization?("BBBB-BBBB")
      refute Accounts.pending_device_authorization?(nil)
    end

    test "is false once the code expired" do
      {:ok, start} = Accounts.start_device_authorization()
      age_authorization!(start, 601)

      refute Accounts.pending_device_authorization?(start.user_code)
    end
  end

  describe "poll_device_authorization/1" do
    test "is authorization_pending until the learner approves, then returns the tokens once" do
      user = user_fixture()
      {:ok, start} = Accounts.start_device_authorization()

      assert {:error, :authorization_pending} =
               Accounts.poll_device_authorization(start.device_code)

      assert :ok = Accounts.approve_device_authorization(user, start.user_code)

      # The approval is consumed by the first poll after it, whatever the interval.
      assert {:ok, tokens} = Accounts.poll_device_authorization(start.device_code)
      assert tokens.token_type == "Bearer"
      assert tokens.expires_in == 900
      assert tokens.refresh_expires_in == 30 * 24 * 3600
      assert Accounts.get_user_by_device_access_token(tokens.access_token).id == user.id

      assert {:error, :invalid_grant} = Accounts.poll_device_authorization(start.device_code)
    end

    test "answers slow_down when polled faster than the interval, and widens it" do
      {:ok, start} = Accounts.start_device_authorization()

      assert {:error, :authorization_pending} =
               Accounts.poll_device_authorization(start.device_code)

      assert {:error, :slow_down} = Accounts.poll_device_authorization(start.device_code)

      hash = :crypto.hash(:sha256, start.device_code)
      assert Repo.get_by!(DeviceAuthorization, device_code_hash: hash).interval == 10
    end

    test "answers access_denied after the learner denies, then invalid_grant" do
      user = user_fixture()
      {:ok, start} = Accounts.start_device_authorization()

      assert :ok = Accounts.deny_device_authorization(user, start.user_code)
      assert {:error, :access_denied} = Accounts.poll_device_authorization(start.device_code)
      assert {:error, :invalid_grant} = Accounts.poll_device_authorization(start.device_code)
    end

    test "answers expired_token after the code expired, and the code can no longer be approved" do
      user = user_fixture()
      {:ok, start} = Accounts.start_device_authorization()
      age_authorization!(start, 601)

      assert {:error, :expired_token} = Accounts.poll_device_authorization(start.device_code)

      assert {:error, :invalid_code} =
               Accounts.approve_device_authorization(user, start.user_code)
    end

    test "answers expired_token for an approved code polled after it expired" do
      user = user_fixture()
      {:ok, start} = Accounts.start_device_authorization()
      :ok = Accounts.approve_device_authorization(user, start.user_code)
      age_authorization!(start, 3600)

      assert {:error, :expired_token} = Accounts.poll_device_authorization(start.device_code)
      assert Repo.all(DeviceToken) == []
    end

    test "answers invalid_grant for an unknown device code" do
      assert {:error, :invalid_grant} = Accounts.poll_device_authorization("unknown")
      assert {:error, :invalid_grant} = Accounts.poll_device_authorization(nil)
    end
  end

  describe "approve_device_authorization/2" do
    test "refuses an admin account" do
      admin = admin_fixture()
      {:ok, start} = Accounts.start_device_authorization()

      assert {:error, :admin_account} =
               Accounts.approve_device_authorization(admin, start.user_code)

      assert {:error, :authorization_pending} =
               Accounts.poll_device_authorization(start.device_code)
    end

    test "refuses an unknown or already decided code" do
      user = user_fixture()
      {:ok, start} = Accounts.start_device_authorization()

      assert {:error, :invalid_code} = Accounts.approve_device_authorization(user, "BBBB-BBBB")
      assert :ok = Accounts.approve_device_authorization(user, start.user_code)

      assert {:error, :invalid_code} =
               Accounts.approve_device_authorization(user, start.user_code)

      assert {:error, :invalid_code} = Accounts.deny_device_authorization(user, start.user_code)
    end
  end

  describe "device tokens" do
    test "stores only hashes of the access and refresh tokens" do
      user = user_fixture()
      tokens = approved_tokens(user)
      [row] = Repo.all_by(DeviceToken, user_id: user.id)

      assert row.access_token_hash == :crypto.hash(:sha256, tokens.access_token)
      assert row.refresh_token_hash == :crypto.hash(:sha256, tokens.refresh_token)
    end

    test "an expired access token authenticates nobody" do
      user = user_fixture()
      tokens = approved_tokens(user)

      Repo.update_all(DeviceToken,
        set: [access_expires_at: DateTime.add(DateTime.utc_now(:second), -1)]
      )

      refute Accounts.get_user_by_device_access_token(tokens.access_token)
      refute Accounts.get_user_by_device_access_token("unknown")
      refute Accounts.get_user_by_device_access_token(nil)
    end

    test "refresh rotates both tokens and the old ones stop working" do
      user = user_fixture()
      tokens = approved_tokens(user)

      assert {:ok, refreshed} = Accounts.refresh_device_token(tokens.refresh_token)
      refute refreshed.access_token == tokens.access_token
      refute refreshed.refresh_token == tokens.refresh_token

      assert Accounts.get_user_by_device_access_token(refreshed.access_token).id == user.id
      refute Accounts.get_user_by_device_access_token(tokens.access_token)
    end

    test "reusing a rotated refresh token revokes the whole device login" do
      user = user_fixture()
      tokens = approved_tokens(user)
      {:ok, refreshed} = Accounts.refresh_device_token(tokens.refresh_token)

      assert {:error, :invalid_grant} = Accounts.refresh_device_token(tokens.refresh_token)
      refute Accounts.get_user_by_device_access_token(refreshed.access_token)
      assert {:error, :invalid_grant} = Accounts.refresh_device_token(refreshed.refresh_token)
    end

    test "reusing a refresh token rotated more than once still revokes the whole login" do
      user = user_fixture()
      tokens = approved_tokens(user)
      {:ok, second} = Accounts.refresh_device_token(tokens.refresh_token)
      {:ok, third} = Accounts.refresh_device_token(second.refresh_token)

      assert {:error, :invalid_grant} = Accounts.refresh_device_token(tokens.refresh_token)
      refute Accounts.get_user_by_device_access_token(third.access_token)
      assert {:error, :invalid_grant} = Accounts.refresh_device_token(third.refresh_token)
    end

    test "reusing a rotated refresh token leaves the learner's other logins alone" do
      user = user_fixture()
      tokens = approved_tokens(user)
      other = approved_tokens(user)
      {:ok, _} = Accounts.refresh_device_token(tokens.refresh_token)
      {:ok, _} = Accounts.refresh_device_token(other.refresh_token)

      assert {:error, :invalid_grant} = Accounts.refresh_device_token(tokens.refresh_token)
      assert [%DeviceToken{}] = Repo.all(DeviceToken)
    end

    test "an expired refresh token is refused" do
      user = user_fixture()
      tokens = approved_tokens(user)

      Repo.update_all(DeviceToken,
        set: [refresh_expires_at: DateTime.add(DateTime.utc_now(:second), -1)]
      )

      assert {:error, :invalid_grant} = Accounts.refresh_device_token(tokens.refresh_token)
      assert {:error, :invalid_grant} = Accounts.refresh_device_token(nil)
    end

    test "logout revokes only this device login" do
      user = user_fixture()
      tokens = approved_tokens(user)
      other = approved_tokens(user)

      assert :ok = Accounts.revoke_device_token(tokens.access_token)

      refute Accounts.get_user_by_device_access_token(tokens.access_token)
      assert {:error, :invalid_grant} = Accounts.refresh_device_token(tokens.refresh_token)
      assert Accounts.get_user_by_device_access_token(other.access_token)
    end

    test "logout everywhere revokes every device login of the learner only" do
      user = user_fixture()
      tokens = approved_tokens(user)
      other = approved_tokens(user)
      someone_else = approved_tokens(user_fixture())

      assert :ok = Accounts.revoke_all_device_tokens(user)

      refute Accounts.get_user_by_device_access_token(tokens.access_token)
      refute Accounts.get_user_by_device_access_token(other.access_token)
      assert Accounts.get_user_by_device_access_token(someone_else.access_token)
    end
  end

  describe "revocation on account changes" do
    test "changing the password revokes every device token" do
      user = user_fixture()
      tokens = approved_tokens(user)

      {:ok, _} = Accounts.update_user_password(user, %{password: "a brand new password"})

      refute Accounts.get_user_by_device_access_token(tokens.access_token)
      assert {:error, :invalid_grant} = Accounts.refresh_device_token(tokens.refresh_token)
    end

    test "changing the password revokes an approved login the device has not polled yet" do
      user = user_fixture()
      {:ok, start} = Accounts.start_device_authorization()
      :ok = Accounts.approve_device_authorization(user, start.user_code)

      {:ok, _} = Accounts.update_user_password(user, %{password: "a brand new password"})

      assert {:error, :invalid_grant} = Accounts.poll_device_authorization(start.device_code)
      assert Repo.all(DeviceToken) == []
    end

    test "resetting the password revokes an approved login the device has not polled yet" do
      user = user_fixture()
      {:ok, start} = Accounts.start_device_authorization()
      :ok = Accounts.approve_device_authorization(user, start.user_code)

      {:ok, _} = Accounts.reset_user_password(user, %{password: "a brand new password"})

      assert {:error, :invalid_grant} = Accounts.poll_device_authorization(start.device_code)
    end

    test "logout everywhere revokes an approved login the device has not polled yet" do
      user = user_fixture()
      {:ok, start} = Accounts.start_device_authorization()
      :ok = Accounts.approve_device_authorization(user, start.user_code)

      assert :ok = Accounts.revoke_all_device_tokens(user)

      assert {:error, :invalid_grant} = Accounts.poll_device_authorization(start.device_code)
    end

    test "resetting the password revokes every device token" do
      user = user_fixture()
      tokens = approved_tokens(user)

      {:ok, _} = Accounts.reset_user_password(user, %{password: "a brand new password"})

      refute Accounts.get_user_by_device_access_token(tokens.access_token)
    end

    test "deleting the account revokes every device token" do
      user = user_fixture()
      tokens = approved_tokens(user)
      {:ok, start} = Accounts.start_device_authorization()
      :ok = Accounts.approve_device_authorization(user, start.user_code)

      {:ok, _} = Accounts.delete_user(user)

      refute Accounts.get_user_by_device_access_token(tokens.access_token)
      assert Repo.all(DeviceToken) == []
      assert {:error, :invalid_grant} = Accounts.poll_device_authorization(start.device_code)
    end
  end
end
