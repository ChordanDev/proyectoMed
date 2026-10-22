defmodule BackendWeb.UserLive.RegistrationTest do
  use BackendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Backend.AccountsFixtures

  alias Backend.Accounts

  describe "sign-up page" do
    test "asks for the email and both acceptances, linking the legal texts", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Criar conta"
      assert has_element?(lv, "#registration_form input[type=email]")

      assert has_element?(
               lv,
               "#registration_form input[type=checkbox][name='user[terms_accepted]']"
             )

      assert has_element?(
               lv,
               "#registration_form input[type=checkbox][name='user[privacy_accepted]']"
             )

      assert has_element?(lv, ~s|#registration_form a[href="/termos"]|)
      assert has_element?(lv, ~s|#registration_form a[href="/privacidade"]|)
    end

    test "sends a logged-in user to the account settings", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/users/settings")

      assert {:ok, _conn} = result
    end

    test "the login page links to the sign-up page", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      assert has_element?(lv, ~s|a[href="/users/register"]|)
    end
  end

  describe "sign-up" do
    test "creates a student, stores the acceptances and emails a confirmation link", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      email = unique_user_email()

      {:ok, _lv, html} =
        lv
        |> form("#registration_form",
          user: %{email: email, terms_accepted: "true", privacy_accepted: "true"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Enviamos um e-mail para #{email}"

      user = Accounts.get_user_by_email(email)
      assert user.role == :student
      assert user.terms_version == Accounts.legal_document(:terms).version
      assert user.privacy_version == Accounts.legal_document(:privacy).version
      assert user.terms_accepted_at
      assert user.privacy_accepted_at

      assert Backend.Repo.get_by!(Backend.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end

    test "refuses to create the account without both acceptances", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      email = unique_user_email()

      html =
        lv
        |> form("#registration_form",
          user: %{email: email, terms_accepted: "false", privacy_accepted: "false"}
        )
        |> render_submit()

      assert html =~ "você precisa aceitar os Termos de Uso"
      assert html =~ "você precisa aceitar a Política de Privacidade"
      refute Accounts.get_user_by_email(email)
    end

    test "shows email errors while typing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      html =
        lv
        |> element("#registration_form")
        |> render_change(user: %{email: "with spaces"})

      assert html =~ "precisa ter o sinal @ e nenhum espaço"
    end

    test "an admin role in the form is ignored", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      email = unique_user_email()

      lv
      |> render_submit("save", %{
        "user" => %{
          "email" => email,
          "role" => "admin",
          "terms_accepted" => "true",
          "privacy_accepted" => "true"
        }
      })

      assert Accounts.get_user_by_email(email).role == :student
    end
  end

  describe "legal pages" do
    test "show the placeholder terms and privacy policy with their versions", %{conn: conn} do
      for {path, kind} <- [{~p"/termos", :terms}, {~p"/privacidade", :privacy}] do
        document = Accounts.legal_document(kind)
        {:ok, _lv, html} = live(conn, path)

        assert html =~ document.title
        assert html =~ document.version
      end
    end
  end
end
