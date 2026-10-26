# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Admin provisioning (issue #331): admins never sign up through a public page.
# An operator creates one by running the seeds with both variables set:
#
#     ADMIN_EMAIL=medica@example.com ADMIN_PASSWORD='at least 12 chars' \
#       mix run priv/repo/seeds.exs
#
# It is idempotent: an existing email is left unchanged. The password is never
# printed.

alias Backend.Accounts

case {System.get_env("ADMIN_EMAIL"), System.get_env("ADMIN_PASSWORD")} do
  {email, password} when is_binary(email) and email != "" and is_binary(password) ->
    if Accounts.get_user_by_email(email) do
      IO.puts("seeds: admin #{email} already exists, left unchanged")
    else
      case Accounts.create_admin(%{email: email, password: password}) do
        {:ok, _admin} ->
          IO.puts("seeds: admin #{email} created")

        {:error, changeset} ->
          errors =
            Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

          IO.puts("seeds: admin #{email} not created: #{inspect(errors)}")
      end
    end

  _missing ->
    IO.puts("seeds: ADMIN_EMAIL and ADMIN_PASSWORD not set, no admin created")
end
