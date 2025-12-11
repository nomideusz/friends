defmodule Friends.Repo.Migrations.CreateFriendships do
  use Ecto.Migration

  def change do
    create table(:friends_friendships) do
      add :user_id, references(:friends_users, on_delete: :delete_all), null: false
      add :friend_user_id, references(:friends_users, on_delete: :delete_all), null: false
      add :status, :string, default: "pending", null: false
      add :accepted_at, :utc_datetime

      timestamps()
    end

    create unique_index(:friends_friendships, [:user_id, :friend_user_id], name: :friends_friendships_user_friend_unique)
    create index(:friends_friendships, [:friend_user_id])
    create index(:friends_friendships, [:status])
    
    create constraint(:friends_friendships, :no_self_friend, check: "user_id != friend_user_id")
  end
end
