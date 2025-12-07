defmodule Friends.Repo.Migrations.AddPrivateRooms do
  use Ecto.Migration

  def change do
    # Add private flag to rooms
    alter table(:friends_rooms) do
      add :is_private, :boolean, default: false
      add :owner_id, references(:friends_users, on_delete: :nilify_all)
    end

    create index(:friends_rooms, [:owner_id])
    create index(:friends_rooms, [:is_private])

    # Room members table
    create table(:friends_room_members) do
      add :room_id, references(:friends_rooms, on_delete: :delete_all), null: false
      add :user_id, references(:friends_users, on_delete: :delete_all), null: false
      add :role, :string, size: 20, default: "member"  # owner, admin, member
      add :invited_by_id, references(:friends_users, on_delete: :nilify_all)
      
      timestamps()
    end

    create unique_index(:friends_room_members, [:room_id, :user_id])
    create index(:friends_room_members, [:user_id])
  end
end

