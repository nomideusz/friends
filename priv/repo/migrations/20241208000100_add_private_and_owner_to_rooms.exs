defmodule Friends.Repo.Migrations.AddPrivateAndOwnerToRooms do
  use Ecto.Migration

  def change do
    alter table(:friends_rooms) do
      add_if_not_exists :is_private, :boolean, default: false, null: false
      add_if_not_exists :owner_id, references(:friends_users, on_delete: :nilify_all)
    end

    create_if_not_exists index(:friends_rooms, [:owner_id])
  end
end


