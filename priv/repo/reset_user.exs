alias Friends.Repo
alias Friends.Social.User
import Ecto.Query

# Find and delete user "nom"
user = Repo.get_by(User, username: "nom")

if user do
  # Delete associated records first
  Repo.delete_all(from tf in Friends.Social.TrustedFriend, where: tf.user_id == ^user.id or tf.trusted_user_id == ^user.id)
  Repo.delete_all(from rv in Friends.Social.RecoveryVote, where: rv.recovering_user_id == ^user.id or rv.voting_user_id == ^user.id)
  Repo.delete_all(from i in Friends.Social.Invite, where: i.created_by_id == ^user.id)
  Repo.delete_all(from rm in Friends.Social.RoomMember, where: rm.user_id == ^user.id)
  
  # Delete the user
  Repo.delete!(user)
  IO.puts("✓ Deleted user 'nom' - you can now re-register")
else
  IO.puts("User 'nom' not found")
end

