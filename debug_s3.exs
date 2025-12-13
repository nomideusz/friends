# Debug script for S3
IO.puts "--- S3 Configuration ---"
config = ExAws.Config.new(:s3)
IO.inspect(config, label: "ExAws Config")

IO.puts "\n--- Attempting List Buckets ---"
case ExAws.S3.list_buckets() |> ExAws.request(config) do
  {:ok, result} -> 
    IO.puts "Success! Buckets: #{inspect result}"
  {:error, reason} -> 
    IO.puts "Error listing buckets: #{inspect reason}"
end

IO.puts "\n--- Attempting Put Object (Test) ---"
bucket = Application.get_env(:friends, :media_bucket)
IO.puts "Bucket: #{bucket}"

case ExAws.S3.put_object(bucket, "test-connection.txt", "OK") |> ExAws.request(config) do
  {:ok, result} ->
    IO.puts "Success! Upload result: #{inspect result}"
  {:error, reason} ->
    IO.puts "Error uploading: #{inspect reason}"
end
