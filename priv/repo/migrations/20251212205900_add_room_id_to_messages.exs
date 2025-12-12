defmodule Friends.Repo.Migrations.AddRoomIdToMessages do
  use Ecto.Migration

  def change do
    alter table(:friends_messages) do
      add :room_id, references(:friends_rooms, on_delete: :delete_all)
      # Make conversation_id nullable since we might have room-only messages
      modify :conversation_id, :id, null: true, from: {:id, null: false}
    end

    create index(:friends_messages, [:room_id])
    
    # Ensure we have either conversation_id OR room_id
    create constraint(:friends_messages, :must_have_conversation_or_room, check: "conversation_id IS NOT NULL OR room_id IS NOT NULL")
  end
end
