alias Friends.Repo
alias Friends.Social.Invite
import Ecto.Query

code = "friend-0003"

# Delete existing invite with this code
Repo.delete_all(from i in Invite, where: i.code == ^code)

expires_at =
  DateTime.utc_now()
  |> DateTime.add(60 * 24 * 60 * 60, :second) # 60 days
  |> DateTime.truncate(:second)

changeset = Invite.changeset(%Invite{}, %{code: code, status: "active", expires_at: expires_at})

case Repo.insert(changeset) do
  {:ok, _invite} ->
    IO.puts("✓ Reset invite code: #{code} (valid for 60 days)")

  {:error, cs} ->
    IO.puts("Error inserting invite: #{inspect(cs.errors)}")
end

