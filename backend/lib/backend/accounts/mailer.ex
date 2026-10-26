defmodule Backend.Accounts.Mailer do
  @moduledoc """
  Sends the account emails of `Backend.Accounts` (login links, email change).

  Production sends through the provider named by `MAILER_PROVIDER` (Resend,
  Postmark, SendGrid, Brevo or Mailgun, configured in config/runtime.exs, #336);
  development keeps `Swoosh.Adapters.Local` unless it names one too, and tests
  use `Swoosh.Adapters.Test`.
  """

  use Swoosh.Mailer, otp_app: :backend
end
