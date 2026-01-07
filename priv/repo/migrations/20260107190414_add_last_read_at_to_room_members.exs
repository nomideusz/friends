defmodule Friends.Repo.Migrations.AddLastReadAtToRoomMembers do
  use Ecto.Migration

  def change do
    alter table(:friends_room_members) do
      add :last_read_at, :utc_datetime
    end
  end
end
