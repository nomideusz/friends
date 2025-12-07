alias Friends.Repo
alias Friends.Social.User
import Ecto.Query

user = Repo.get_by(User, username: "nom")

IO.puts("User record:")
IO.inspect(user)

if user && user.public_key do
  pk = user.public_key
  IO.puts("Public key x/y:")
  IO.puts("x=#{pk["x"]}")
  IO.puts("y=#{pk["y"]}")
end

