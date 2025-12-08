defmodule Friends.Repo.Migrations.SeedNomInvite do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO friends_invites (code, status, inserted_at, updated_at)
    VALUES ('NOM1', 'active', now(), now())
    ON CONFLICT DO NOTHING;
    """)
  end

  def down do
    execute("DELETE FROM friends_invites WHERE code = 'NOM1';")
  end
end


