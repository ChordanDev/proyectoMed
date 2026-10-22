defmodule Backend.Accounts.Mailer do
  @moduledoc """
  Sends the account emails of `Backend.Accounts` (login links, email change).

  Development and production use `Swoosh.Adapters.Local` until an email
  provider is chosen (#336); tests use `Swoosh.Adapters.Test`.
  """

  use Swoosh.Mailer, otp_app: :backend
end
