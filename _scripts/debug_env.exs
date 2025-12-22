# Debug Env Vars
IO.puts "--- Environment Variables ---"
IO.puts "MINIO_ENDPOINT: #{inspect System.get_env("MINIO_ENDPOINT")}"
IO.puts "MINIO_PORT: #{inspect System.get_env("MINIO_PORT")}"
IO.puts "MINIO_ROOT_USER: #{inspect System.get_env("MINIO_ROOT_USER")}"

IO.puts "\n--- Loaded ExAws Config ---"
IO.inspect(ExAws.Config.new(:s3), label: "S3 Config")
