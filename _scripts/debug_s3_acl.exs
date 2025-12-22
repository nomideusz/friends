# Debug script for S3 with ACL
IO.puts "--- S3 Configuration ---"
config = ExAws.Config.new(:s3)
IO.inspect(config, label: "ExAws Config")

IO.puts "\n--- Attempting Put Object WITH ACL ---"
bucket = Application.get_env(:friends, :media_bucket)
IO.puts "Bucket: #{bucket}"

output = 
  ExAws.S3.put_object(bucket, "test-acl.txt", "ACL TEST", [acl: :public_read]) 
  |> ExAws.request(config)

IO.inspect(output, label: "Upload Result with ACL")
