alias Friends.Repo
alias Friends.Social.User
import Ecto.Query

new_public_key = %{
  "crv" => "P-256",
  "ext" => true,
  "key_ops" => ["verify"],
  "kty" => "EC",
  "x" => "-oROprRrbGjPCFiQmYD29B7FMnbf_eqSLIdN4GZzKaM",
  "y" => "YSIV5FR10p4gYvYTeqOVn98kjjai2J9v1eg35L2qzuE"
}

username = "nom"

case Repo.get_by(User, username: username) do
  nil ->
    IO.puts("User #{username} not found")

  user ->
    changeset = User.changeset(user, %{public_key: new_public_key})

    case Repo.update(changeset) do
      {:ok, _} ->
        IO.puts("✓ Updated user #{username} with new public key")
      {:error, cs} ->
        IO.puts("Failed to update user: #{inspect(cs.errors)}")
    end
end

