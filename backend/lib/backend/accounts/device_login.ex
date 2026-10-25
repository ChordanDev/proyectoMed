defmodule Backend.Accounts.DeviceLogin do
  @moduledoc """
  The device login of the Unreal client (#337), shaped after the OAuth 2.0
  Device Authorization Grant (RFC 8628).

  The client starts a login and gets a secret device code plus a short user
  code. The learner types the user code in the browser and approves it; the
  client polls with the device code and receives a 15-minute access token and
  a 30-day refresh token. A refresh rotates both tokens; presenting any rotated
  refresh token again, however many rotations ago, revokes that login. An
  approved code past its 10 minutes issues nothing, and revoking a learner's
  logins also drops the approvals no device has redeemed yet. Only SHA-256 hashes of codes and
  tokens are stored, and none of them is ever logged.

  Called only through `Backend.Accounts`.
  """

  import Ecto.Query

  alias Backend.Accounts.{DeviceAuthorization, DeviceRetiredRefreshToken, DeviceToken, User}
  alias Backend.Repo

  @device_code_lifetime_s 600
  @poll_interval_s 5
  @slow_down_step_s 5
  @access_lifetime_s 15 * 60
  @refresh_lifetime_s 30 * 24 * 3600
  # RFC 8628 §6.1: consonants only, no vowels or look-alike characters.
  @user_code_alphabet ~c"BCDFGHJKLMNPQRSTVWXZ"
  @user_code_length 8

  @type start :: %{
          device_code: String.t(),
          user_code: String.t(),
          interval: pos_integer(),
          expires_in: pos_integer()
        }

  @type tokens :: %{
          access_token: String.t(),
          refresh_token: String.t(),
          token_type: String.t(),
          expires_in: pos_integer(),
          refresh_expires_in: pos_integer()
        }

  @type poll_error ::
          :authorization_pending | :slow_down | :expired_token | :access_denied | :invalid_grant

  ## Authorization

  @spec start() :: {:ok, start()}
  def start do
    now = DateTime.utc_now(:second)
    Repo.delete_all(from(d in DeviceAuthorization, where: d.expires_at <= ^now))
    insert_authorization(now, 3)
  end

  defp insert_authorization(now, attempts) do
    device_code = random_token()
    user_code = random_user_code()

    authorization = %DeviceAuthorization{
      device_code_hash: hash(device_code),
      user_code_hash: hash(user_code),
      interval: @poll_interval_s,
      expires_at: DateTime.add(now, @device_code_lifetime_s)
    }

    changeset =
      authorization
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint(:user_code_hash)

    case Repo.insert(changeset) do
      {:ok, _authorization} ->
        {:ok,
         %{
           device_code: device_code,
           user_code: format_user_code(user_code),
           interval: @poll_interval_s,
           expires_in: @device_code_lifetime_s
         }}

      {:error, _changeset} when attempts > 1 ->
        insert_authorization(now, attempts - 1)
    end
  end

  @spec pending?(term()) :: boolean()
  def pending?(user_code), do: pending_query(user_code) |> Repo.exists?()

  @spec decide(User.t(), term(), :approved | :denied) ::
          :ok | {:error, :invalid_code | :admin_account}
  def decide(%User{role: :admin}, _user_code, :approved), do: {:error, :admin_account}

  def decide(%User{id: user_id}, user_code, status) do
    case Repo.update_all(pending_query(user_code), set: [status: status, user_id: user_id]) do
      {1, _} -> :ok
      {0, _} -> {:error, :invalid_code}
    end
  end

  defp pending_query(user_code) do
    case normalize_user_code(user_code) do
      nil ->
        from(d in DeviceAuthorization, where: false)

      code ->
        now = DateTime.utc_now(:second)

        from(d in DeviceAuthorization,
          where: d.user_code_hash == ^hash(code) and d.status == :pending and d.expires_at > ^now
        )
    end
  end

  @spec poll(term()) :: {:ok, tokens()} | {:error, poll_error()}
  def poll(device_code) when is_binary(device_code) do
    # The transaction always commits: an answer such as slow_down keeps its
    # recorded poll time, and access_denied keeps the deletion.
    {:ok, result} =
      Repo.transact(fn ->
        query =
          from(d in DeviceAuthorization,
            where: d.device_code_hash == ^hash(device_code),
            lock: "FOR UPDATE",
            preload: :user
          )

        {:ok, query |> Repo.one() |> poll_authorization(DateTime.utc_now())}
      end)

    result
  end

  def poll(_device_code), do: {:error, :invalid_grant}

  defp poll_authorization(nil, _now), do: {:error, :invalid_grant}

  # Past its lifetime an approved code issues nothing.
  defp poll_authorization(%DeviceAuthorization{status: :approved, user: %User{}} = auth, now) do
    Repo.delete!(auth)

    if DateTime.compare(auth.expires_at, now) == :gt,
      do: {:ok, issue_tokens(auth.user, DateTime.truncate(now, :second))},
      else: {:error, :expired_token}
  end

  defp poll_authorization(%DeviceAuthorization{status: :denied} = auth, _now) do
    Repo.delete!(auth)
    {:error, :access_denied}
  end

  defp poll_authorization(%DeviceAuthorization{} = auth, now) do
    cond do
      DateTime.compare(auth.expires_at, now) != :gt ->
        {:error, :expired_token}

      polled_too_soon?(auth, now) ->
        update_poll!(auth, now, auth.interval + @slow_down_step_s)
        {:error, :slow_down}

      true ->
        update_poll!(auth, now, auth.interval)
        {:error, :authorization_pending}
    end
  end

  defp polled_too_soon?(%DeviceAuthorization{last_polled_at: nil}, _now), do: false

  defp polled_too_soon?(%DeviceAuthorization{last_polled_at: last, interval: interval}, now),
    do: DateTime.diff(now, last, :millisecond) < interval * 1000

  defp update_poll!(auth, now, interval) do
    auth
    |> Ecto.Changeset.change(last_polled_at: now, interval: interval)
    |> Repo.update!()
  end

  ## Tokens

  defp issue_tokens(%User{} = user, now) do
    {access, refresh, attrs} = token_attrs(now)
    Repo.insert!(struct(DeviceToken, Map.put(attrs, :user_id, user.id)))
    tokens(access, refresh)
  end

  defp token_attrs(now) do
    access = random_token()
    refresh = random_token()

    {access, refresh,
     %{
       access_token_hash: hash(access),
       access_expires_at: DateTime.add(now, @access_lifetime_s),
       refresh_token_hash: hash(refresh),
       refresh_expires_at: DateTime.add(now, @refresh_lifetime_s)
     }}
  end

  defp tokens(access, refresh) do
    %{
      access_token: access,
      refresh_token: refresh,
      token_type: "Bearer",
      expires_in: @access_lifetime_s,
      refresh_expires_in: @refresh_lifetime_s
    }
  end

  @spec user_by_access_token(term()) :: User.t() | nil
  def user_by_access_token(token) when is_binary(token) do
    now = DateTime.utc_now(:second)

    Repo.one(
      from(t in DeviceToken,
        join: u in assoc(t, :user),
        where: t.access_token_hash == ^hash(token) and t.access_expires_at > ^now,
        select: u
      )
    )
  end

  def user_by_access_token(_token), do: nil

  @spec refresh(term()) :: {:ok, tokens()} | {:error, :invalid_grant}
  def refresh(refresh_token) when is_binary(refresh_token) do
    token_hash = hash(refresh_token)

    # Commits even on invalid_grant, so a detected reuse keeps its revocation.
    {:ok, result} =
      Repo.transact(fn ->
        current =
          Repo.one(
            from(t in DeviceToken, where: t.refresh_token_hash == ^token_hash, lock: "FOR UPDATE")
          )

        {:ok, rotate(current, token_hash, DateTime.utc_now(:second))}
      end)

    result
  end

  def refresh(_refresh_token), do: {:error, :invalid_grant}

  defp rotate(nil, token_hash, _now) do
    # A rotated refresh token presented again: the login may be stolen.
    Repo.delete_all(
      from(t in DeviceToken,
        join: r in DeviceRetiredRefreshToken,
        on: r.device_token_id == t.id,
        where: r.refresh_token_hash == ^token_hash
      )
    )

    {:error, :invalid_grant}
  end

  defp rotate(%DeviceToken{} = current, token_hash, now) do
    if DateTime.compare(current.refresh_expires_at, now) == :gt do
      {access, refresh, attrs} = token_attrs(now)

      Repo.insert!(%DeviceRetiredRefreshToken{
        device_token_id: current.id,
        refresh_token_hash: token_hash
      })

      current
      |> Ecto.Changeset.change(attrs)
      |> Repo.update!()

      {:ok, tokens(access, refresh)}
    else
      Repo.delete!(current)
      {:error, :invalid_grant}
    end
  end

  @spec revoke(term()) :: :ok
  def revoke(access_token) when is_binary(access_token) do
    Repo.delete_all(from(t in DeviceToken, where: t.access_token_hash == ^hash(access_token)))
    :ok
  end

  def revoke(_access_token), do: :ok

  @doc """
  Deletes every device token of the user and every login they approved that no
  device has redeemed yet. Callers inside a transaction use it to revoke device
  logins together with another change.
  """
  @spec revoke_all(User.t() | integer()) :: :ok
  def revoke_all(%User{id: user_id}), do: revoke_all(user_id)

  def revoke_all(user_id) when is_integer(user_id) do
    Repo.delete_all(from(t in DeviceToken, where: t.user_id == ^user_id))
    Repo.delete_all(from(d in DeviceAuthorization, where: d.user_id == ^user_id))
    :ok
  end

  ## Codes

  defp random_token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  # Rejection sampling over cryptographic bytes keeps every letter equally likely.
  defp random_user_code(acc \\ "")

  defp random_user_code(acc) when byte_size(acc) == @user_code_length, do: acc

  defp random_user_code(acc) do
    <<byte>> = :crypto.strong_rand_bytes(1)
    size = length(@user_code_alphabet)

    if byte < div(256, size) * size,
      do: random_user_code(acc <> <<Enum.at(@user_code_alphabet, rem(byte, size))>>),
      else: random_user_code(acc)
  end

  defp format_user_code(<<first::binary-size(4), second::binary-size(4)>>),
    do: first <> "-" <> second

  defp normalize_user_code(code) when is_binary(code) do
    normalized = code |> String.upcase() |> String.replace(~r/[^A-Z]/, "")
    if byte_size(normalized) == @user_code_length, do: normalized
  end

  defp normalize_user_code(_code), do: nil

  defp hash(value), do: :crypto.hash(:sha256, value)
end
