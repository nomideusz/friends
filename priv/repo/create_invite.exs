alias Friends.Repo
alias Friends.Social.Invite

# Create bootstrap invite
expires = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)

invite = %Invite{
  code: "bootstrap-2024",
  status: "active",
  expires_at: expires
}

case Repo.insert(invite) do
  {:ok, _} -> IO.puts("✓ Created invite code: bootstrap-2024")
  {:error, changeset} -> IO.puts("Error: #{inspect(changeset.errors)}")
end

