defmodule Friends.Repo.Migrations.ResetNomPasskey do
  use Ecto.Migration

  def up do
    # Get the user ID for "nom"
    execute """
    DELETE FROM friends_webauthn_credentials 
    WHERE user_id = (SELECT id FROM friends_users WHERE username = 'nom')
    """
  end

  def down do
    # No way to restore deleted credentials
    :ok
  end
end
