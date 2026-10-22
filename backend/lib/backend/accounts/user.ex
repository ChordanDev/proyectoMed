defmodule Backend.Accounts.User do
  @moduledoc """
  An account. `role` is `:admin` (reviews cases) or `:student` (practises
  stations); it is never cast from user input, so only `admin_changeset/2`
  (used by `Backend.Accounts.create_admin/1`) creates an admin.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "users" do
    field :email, :string
    field :role, Ecto.Enum, values: [:admin, :student], default: :student
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true
    field :terms_accepted, :boolean, virtual: true
    field :privacy_accepted, :boolean, virtual: true
    field :terms_version, :string
    field :terms_accepted_at, :utc_datetime
    field :privacy_version, :string
    field :privacy_accepted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for a learner signing up (#336): the email and the acceptance of
  the terms of use and of the privacy policy. Only `email`, `terms_accepted` and
  `privacy_accepted` are cast; the accepted versions (`:terms_version` and
  `:privacy_version` options, required) and the acceptance time are set here,
  never taken from the attributes, and the role stays `:student`.

  Takes the `:validate_unique` option of `email_changeset/3`.
  """
  def registration_changeset(user, attrs, opts) do
    terms_version = Keyword.fetch!(opts, :terms_version)
    privacy_version = Keyword.fetch!(opts, :privacy_version)

    user
    |> cast(attrs, [:email, :terms_accepted, :privacy_accepted])
    |> validate_email(opts)
    |> validate_acceptance(:terms_accepted, message: "você precisa aceitar os Termos de Uso")
    |> validate_acceptance(:privacy_accepted,
      message: "você precisa aceitar a Política de Privacidade"
    )
    |> put_acceptance(terms_version, privacy_version)
  end

  defp put_acceptance(%{valid?: true} = changeset, terms_version, privacy_version) do
    now = DateTime.utc_now(:second)

    change(changeset,
      terms_version: terms_version,
      terms_accepted_at: now,
      privacy_version: privacy_version,
      privacy_accepted_at: now
    )
  end

  defp put_acceptance(changeset, _terms_version, _privacy_version), do: changeset

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email], message: "não pode ficar em branco")
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "precisa ter o sinal @ e nenhum espaço"
      )
      |> validate_length(:email, max: 160, message: "pode ter no máximo 160 caracteres")

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Backend.Repo, message: "já está em uso")
      |> unique_constraint(:email, message: "já está em uso")
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "não foi alterado")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "não confere com a senha")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password], message: "não pode ficar em branco")
    |> validate_length(:password,
      min: 12,
      max: 72,
      message: "deve ter entre 12 e 72 caracteres"
    )
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password,
        max: 72,
        count: :bytes,
        message: "deve ter no máximo 72 bytes"
      )
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  A changeset for a new, already confirmed admin with an email and a password.
  Admins are provisioned by an operator (`priv/repo/seeds.exs`), never by a
  public sign-up path.
  """
  def admin_changeset(attrs) do
    %__MODULE__{}
    |> email_changeset(attrs)
    |> password_changeset(attrs)
    |> put_change(:role, :admin)
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Backend.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
