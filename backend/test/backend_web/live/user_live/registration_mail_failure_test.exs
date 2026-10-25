defmodule BackendWeb.UserLive.RegistrationMailFailureTest do
  # Swaps the global mailer adapter, so it cannot run alongside other tests.
  use BackendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Backend.AccountsFixtures

  alias Backend.Accounts
  alias Backend.AppEnvHelpers

  defmodule FailingAdapter do
    @moduledoc false
    use Swoosh.Adapter

    @impl true
    def deliver(_email, _config), do: {:error, :provider_unavailable}
  end

  setup do
    previous = AppEnvHelpers.snapshot(Backend.Accounts.Mailer)
    Application.put_env(:backend, Backend.Accounts.Mailer, adapter: FailingAdapter)
    on_exit(fn -> AppEnvHelpers.restore(Backend.Accounts.Mailer, previous) end)
  end

  test "a failed confirmation email still keeps the account and leads to the login page", %{
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

    assert html =~ "Não conseguimos enviar o e-mail de confirmação"
    assert Accounts.get_user_by_email(email)
  end
end
