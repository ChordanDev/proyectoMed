defmodule Backend.Repo.Migrations.RenameSessionUsageTtsCharacters do
  use Ecto.Migration

  # Real-time patient speech moved to Cartesia (#360, #398): the characters the
  # voice worker sends to synthesis are now Cartesia's billing unit.
  def change do
    rename table(:session_usages), :elevenlabs_characters, to: :cartesia_characters
  end
end
