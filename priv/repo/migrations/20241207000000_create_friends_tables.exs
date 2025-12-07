defmodule Friends.Repo.Migrations.CreateFriendsTables do
  use Ecto.Migration

  def change do
    # Rooms table
    create_if_not_exists table(:friends_rooms) do
      add :code, :string, null: false
      add :name, :string
      add :emoji, :string, default: ""
      add :created_by, :string

      timestamps()
    end

    create_if_not_exists unique_index(:friends_rooms, [:code])

    # Device links table
    create_if_not_exists table(:friends_device_links) do
      add :browser_id, :string, null: false
      add :device_fingerprint, :string
      add :master_user_id, :string, null: false
      add :user_name, :string

      timestamps()
    end

    create_if_not_exists unique_index(:friends_device_links, [:browser_id])

    # Photos table
    create_if_not_exists table(:friends_photos) do
      add :user_id, :string, null: false
      add :user_color, :string
      add :user_name, :string
      add :image_data, :text
      add :thumbnail_data, :text
      add :content_type, :string
      add :file_size, :integer
      add :description, :string
      add :uploaded_at, :utc_datetime
      add :room_id, references(:friends_rooms, on_delete: :delete_all)

      timestamps()
    end

    create_if_not_exists index(:friends_photos, [:room_id])

    # Notes/text cards table
    create_if_not_exists table(:friends_text_cards) do
      add :user_id, :string, null: false
      add :user_color, :string
      add :user_name, :string
      add :content, :text, null: false
      add :room_id, references(:friends_rooms, on_delete: :delete_all)

      timestamps()
    end

    create_if_not_exists index(:friends_text_cards, [:room_id])
  end
end

