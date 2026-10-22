defmodule Backend.Accounts.RegistrationTest do
  @moduledoc """
  Learner sign-up (#336): the terms of use and the privacy policy must be
  accepted, and the acceptance date and document version of each are stored.
  """

  use Backend.DataCase, async: true

  import Backend.AccountsFixtures

  alias Backend.Accounts

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{email: unique_user_email(), terms_accepted: "true", privacy_accepted: "true"},
      overrides
    )
  end

  describe "register_user/1" do
    test "creates an unconfirmed student with the acceptance date and versions" do
      before = DateTime.utc_now(:second)

      assert {:ok, user} = Accounts.register_user(attrs())

      assert user.role == :student
      assert user.confirmed_at == nil
      assert user.hashed_password == nil
      assert user.terms_version == Accounts.legal_document(:terms).version
      assert user.privacy_version == Accounts.legal_document(:privacy).version
      assert DateTime.compare(user.terms_accepted_at, before) in [:gt, :eq]
      assert DateTime.compare(user.privacy_accepted_at, before) in [:gt, :eq]

      stored = Accounts.get_user!(user.id)
      assert stored.terms_version == user.terms_version
      assert stored.terms_accepted_at == user.terms_accepted_at
      assert stored.privacy_version == user.privacy_version
      assert stored.privacy_accepted_at == user.privacy_accepted_at
    end

    test "requires accepting the terms of use" do
      assert {:error, changeset} = Accounts.register_user(attrs(%{terms_accepted: "false"}))
      assert %{terms_accepted: ["você precisa aceitar os Termos de Uso"]} = errors_on(changeset)

      assert {:error, changeset} = Accounts.register_user(Map.delete(attrs(), :terms_accepted))
      assert %{terms_accepted: [_]} = errors_on(changeset)
    end

    test "requires accepting the privacy policy" do
      assert {:error, changeset} = Accounts.register_user(attrs(%{privacy_accepted: "false"}))

      assert %{privacy_accepted: ["você precisa aceitar a Política de Privacidade"]} =
               errors_on(changeset)
    end

    test "never takes the role, the versions or the dates from the attributes" do
      forged =
        attrs(%{
          role: "admin",
          confirmed_at: ~U[2020-01-01 00:00:00Z],
          terms_version: "forged",
          terms_accepted_at: ~U[2020-01-01 00:00:00Z],
          privacy_version: "forged",
          privacy_accepted_at: ~U[2020-01-01 00:00:00Z]
        })

      assert {:ok, user} = Accounts.register_user(forged)

      assert user.role == :student
      assert user.confirmed_at == nil
      assert user.terms_version == Accounts.legal_document(:terms).version
      assert user.privacy_version == Accounts.legal_document(:privacy).version
      refute user.terms_accepted_at == ~U[2020-01-01 00:00:00Z]
      refute user.privacy_accepted_at == ~U[2020-01-01 00:00:00Z]
    end

    test "validates the email" do
      assert {:error, changeset} = Accounts.register_user(attrs(%{email: "not valid"}))
      assert %{email: ["precisa ter o sinal @ e nenhum espaço"]} = errors_on(changeset)

      user = user_fixture()
      assert {:error, changeset} = Accounts.register_user(attrs(%{email: user.email}))
      assert %{email: ["já está em uso"]} = errors_on(changeset)
    end
  end

  describe "legal_document/1" do
    test "returns the placeholder terms and privacy policy with a version" do
      for kind <- [:terms, :privacy] do
        document = Accounts.legal_document(kind)

        assert is_binary(document.version) and document.version != ""
        assert is_binary(document.title)
        assert [_ | _] = document.paragraphs
      end
    end
  end
end
