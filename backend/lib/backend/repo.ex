defmodule Backend.Repo do
  @moduledoc """
  The Postgres repository (ADR-014 #346). Phoenix is the only writer; contexts
  own their schemas and queries, and `BackendWeb` never calls the Repo directly.
  """

  use Ecto.Repo,
    otp_app: :backend,
    adapter: Ecto.Adapters.Postgres
end
