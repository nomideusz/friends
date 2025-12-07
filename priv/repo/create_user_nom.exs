alias Friends.Repo
alias Friends.Social.User
import Ecto.Query

# Public key provided by the user
public_key = %{
  "crv" => "P-256",
  "ext" => true,
  "key_ops" => ["verify"],
  "kty" => "EC",
  "x" => "ByLygZQCnGgw9T0FYMWI6K0ueL40UurHlFMwPicEbAE",
  "y" => "wrlm_FeWSk93JtPZ3n2WmF_To7tO8XtzAA1gKVLp5oI"
}

username = "nom"

# Clean any existing user with this username
Repo.delete_all(from u in User, where: u.username == ^username)

changeset =
  User.registration_changeset(%User{}, %{
    username: username,
    public_key: public_key,
    display_name: nil,
    invite_code: "friend-0003",
    status: "active"
  })

case Repo.insert(changeset) do
  {:ok, user} ->
    IO.puts("✓ Created user #{user.username} (id=#{user.id}) with provided public key")

  {:error, cs} ->
    IO.puts("Failed to insert user: #{inspect(cs.errors)}")
end

