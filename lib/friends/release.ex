defmodule Friends.Release do
  @moduledoc """
  Release tasks that can be run via:
    bin/friends eval "Friends.Release.cleanup_test_users()"
  """
  
  alias Friends.Repo
  alias Friends.Social.User
  import Ecto.Query
  
  @app :friends

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

  @doc """
  Delete all test users except protected accounts.
  Run via: bin/friends eval "Friends.Release.cleanup_test_users()"
  """
  def cleanup_test_users do
    load_app()
    
    IO.puts("\n=== Cleanup Test Users ===\n")
    IO.puts("Protected usernames:")
    Enum.each(@protected_usernames, &IO.puts("  ✓ #{&1}"))
    
    # Find users to delete
    users_to_delete = Repo.all(
      from u in User,
        where: u.username not in ^@protected_usernames,
        select: {u.id, u.username}
    )
    
    IO.puts("\n--- Users to DELETE ---")
    Enum.each(users_to_delete, fn {id, username} ->
      IO.puts("  ID #{id}: @#{username}")
    end)
    
    if Enum.empty?(users_to_delete) do
      IO.puts("\n✅ No test users to delete!")
      {:ok, 0}
    else
      IO.puts("\nTotal: #{length(users_to_delete)} users")
      IO.puts("\nDeleting...")
      
      user_ids = Enum.map(users_to_delete, fn {id, _} -> id end)
      
      {count, _} = Repo.delete_all(
        from u in User,
          where: u.id in ^user_ids
      )
      
      IO.puts("✅ Deleted #{count} test users!")
      {:ok, count}
    end
  end

  @doc """
  Preview which users would be deleted (dry run).
  Run via: bin/friends eval "Friends.Release.preview_cleanup()"
  """
  def preview_cleanup do
    load_app()
    
    protected = Repo.all(
      from u in User,
        where: u.username in ^@protected_usernames,
        select: {u.id, u.username}
    )
    
    to_delete = Repo.all(
      from u in User,
        where: u.username not in ^@protected_usernames,
        select: {u.id, u.username}
    )
    
    IO.puts("\n=== DRY RUN ===\n")
    IO.puts("Protected (#{length(protected)}):")
    Enum.each(protected, fn {id, u} -> IO.puts("  ✓ ID #{id}: @#{u}") end)
    
    IO.puts("\nWould DELETE (#{length(to_delete)}):")
    Enum.each(to_delete, fn {id, u} -> IO.puts("  ✗ ID #{id}: @#{u}") end)
    
    {:ok, length(to_delete)}
  end
  
  # --- Standard release tasks ---
  
  def migrate do
    load_app()
    
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
    Application.ensure_all_started(@app)
  end
end
