defmodule Friends.Repo.Migrations.AddAvatarUrlToUsersSafe do
  use Ecto.Migration

  def change do
    # Safe migration: only add columns if they don't exist
    # This handles cases where the previous migration was marked as run but failed
    execute(
      """
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = 'friends_users' AND column_name = 'avatar_url'
        ) THEN
          ALTER TABLE friends_users ADD COLUMN avatar_url VARCHAR(255);
        END IF;
      END $$;
      """,
      "SELECT 1"
    )

    execute(
      """
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = 'friends_users' AND column_name = 'user_color'
        ) THEN
          ALTER TABLE friends_users ADD COLUMN user_color VARCHAR(255);
        END IF;
      END $$;
      """,
      "SELECT 1"
    )
  end
end
