defmodule Friends.Repo.Migrations.SocialSpacesArchitecture do
  use Ecto.Migration

  def change do
    # Add room_type to distinguish public, private, and DM rooms
    alter table(:friends_rooms) do
      add :room_type, :string, default: "public"
    end

    # Add editable_until to notes for 15-minute grace period
    alter table(:friends_text_cards) do
      add :editable_until, :utc_datetime
    end

    create index(:friends_rooms, [:room_type])

    # Set room_type based on existing is_private flag
    execute """
      UPDATE friends_rooms 
      SET room_type = CASE 
        WHEN is_private = true THEN 'private' 
        ELSE 'public' 
      END
    """, ""

    # Set existing notes as already expired (inserted_at = editable_until)
    execute """
      UPDATE friends_text_cards 
      SET editable_until = inserted_at
    """, ""
  end
end
