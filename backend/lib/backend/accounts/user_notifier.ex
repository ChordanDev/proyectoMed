defmodule Backend.Accounts.UserNotifier do
  @moduledoc """
  Account emails in pt-BR (`mix phx.gen.auth`): email change, login link,
  account confirmation and password reset (#336). The sender is
  `:mailer_from` (`MAILER_FROM_NAME` and `MAILER_FROM_EMAIL` in production).
  """

  import Swoosh.Email

  alias Backend.Accounts.Mailer
  alias Backend.Accounts.User

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Application.fetch_env!(:backend, :mailer_from))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Confirme a alteração do seu e-mail", """

    ==============================

    Olá, #{user.email}.

    Para alterar o seu e-mail, acesse o link abaixo:

    #{url}

    Se você não pediu esta alteração, ignore esta mensagem.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to reset the password (#336).
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Redefina a sua senha", """

    ==============================

    Olá, #{user.email}.

    Para redefinir a sua senha, acesse o link abaixo:

    #{url}

    O link vale por 24 horas. Se você não pediu esta alteração, ignore esta mensagem.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Seu link para entrar", """

    ==============================

    Olá, #{user.email}.

    Para entrar na sua conta, acesse o link abaixo:

    #{url}

    Se você não pediu este e-mail, ignore esta mensagem.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirme a sua conta", """

    ==============================

    Olá, #{user.email}.

    Para confirmar a sua conta, acesse o link abaixo:

    #{url}

    Se você não criou uma conta, ignore esta mensagem.

    ==============================
    """)
  end
end
