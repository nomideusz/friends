defmodule Friends.Repo.Migrations.AddPrivateAndOwnerToRooms do
  use Ecto.Migration

  def change do
    alter table(:friends_rooms) do
      add_if_not_exists :is_private, :boolean, default: false, null: false
      # Add owner_id without creating a duplicate foreign key if it already exists
      add_if_not_exists :owner_id, :integer
    end

    create_if_not_exists index(:friends_rooms, [:owner_id])
  end
end


