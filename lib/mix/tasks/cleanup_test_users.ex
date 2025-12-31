defmodule Mix.Tasks.CleanupTestUsers do
  @moduledoc """
  One-time task to remove test/fake accounts.
  
  Usage: mix cleanup_test_users
  
  This will delete ALL users except the protected list and cascade
  to related data (credentials, friendships, photos, notes, etc.)
  """
  use Mix.Task
  
  alias Friends.Repo
  alias Friends.Social.User
  import Ecto.Query

  # Protected usernames - these will NOT be deleted
  @protected_usernames [
    "rietarius",
    "irka",
    "whatkejtidid",
    "salibarin",
    "non",
    "varna_morena",
    "alexa",
    "sjo",
    "gugu"
  ]

  @shortdoc "Remove test accounts (keeps only protected users)"
  
  def run(_args) do
    # Start the app
    Mix.Task.run("app.start")
    
    IO.puts("\n=== Cleanup Test Users ===\n")
    IO.puts("Protected usernames (will NOT be deleted):")
    Enum.each(@protected_usernames, fn username ->
      IO.puts("  ✓ #{username}")
    end)
    
    # Find users to delete
    users_to_delete = Repo.all(
      from u in User,
        where: u.username not in ^@protected_usernames,
        select: {u.id, u.username}
    )
    
    # Find protected users that exist
    protected_users = Repo.all(
      from u in User,
        where: u.username in ^@protected_usernames,
        select: {u.id, u.username}
    )
    
    IO.puts("\n--- Protected Users Found ---")
    if Enum.empty?(protected_users) do
      IO.puts("  (none found in database)")
    else
      Enum.each(protected_users, fn {id, username} ->
        IO.puts("  ID #{id}: @#{username}")
      end)
    end
    
    IO.puts("\n--- Users to DELETE ---")
    if Enum.empty?(users_to_delete) do
      IO.puts("  (no test users to delete)")
      IO.puts("\n✅ Nothing to clean up!")
    else
      Enum.each(users_to_delete, fn {id, username} ->
        IO.puts("  ID #{id}: @#{username}")
      end)
      
      IO.puts("\nTotal: #{length(users_to_delete)} users will be DELETED")
      IO.puts("This will also delete their:")
      IO.puts("  - WebAuthn credentials")
      IO.puts("  - Friendships")
      IO.puts("  - Photos and notes")
      IO.puts("  - Room memberships")
      IO.puts("  - Device pairings")
      IO.puts("  - And all other related data")
      
      IO.puts("\n⚠️  THIS ACTION CANNOT BE UNDONE!")
      
      case IO.gets("Type 'DELETE' to confirm: ") do
        "DELETE\n" ->
          IO.puts("\nDeleting users...")
          
          user_ids = Enum.map(users_to_delete, fn {id, _} -> id end)
          
          {count, _} = Repo.delete_all(
            from u in User,
              where: u.id in ^user_ids
          )
          
          IO.puts("\n✅ Successfully deleted #{count} test users!")
          
        _ ->
          IO.puts("\n❌ Cancelled. No users were deleted.")
      end
    end
  end
end
