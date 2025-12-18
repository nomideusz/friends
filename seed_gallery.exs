import Ecto.Query
alias Friends.Repo
alias Friends.Social.Photo

# Get 2 IDs
ids = 
  Photo 
  |> limit(2) 
  |> select([p], p.id) 
  |> Repo.all()

IO.inspect(ids, label: "Grouping photos")

if length(ids) >= 2 do
  Photo 
  |> where([p], p.id in ^ids) 
  |> Repo.update_all(set: [batch_id: "test-batch-1"])
  IO.puts("Grouped #{length(ids)} photos into batch 'test-batch-1'")
else
  IO.puts("Not enough photos to group (found #{length(ids)})")
end
