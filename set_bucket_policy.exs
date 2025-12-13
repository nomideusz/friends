#!/usr/bin/env elixir
# Script to set public read bucket policy on MinIO
# Run with: mix run set_bucket_policy.exs

Application.ensure_all_started(:hackney)
Application.ensure_all_started(:ex_aws)

bucket = Application.get_env(:friends, :media_bucket, "friends-images")

# MinIO bucket policy for public read access
policy = %{
  "Version" => "2012-10-17",
  "Statement" => [
    %{
      "Sid" => "PublicReadGetObject",
      "Effect" => "Allow",
      "Principal" => "*",
      "Action" => ["s3:GetObject"],
      "Resource" => ["arn:aws:s3:::#{bucket}/*"]
    }
  ]
}

policy_json = Jason.encode!(policy)

IO.puts("Setting bucket policy for: #{bucket}")
IO.puts("Policy:\n#{policy_json}")

# Use ExAws.S3.put_bucket_policy
request = ExAws.S3.put_bucket_policy(bucket, policy_json)

case ExAws.request(request) do
  {:ok, _} ->
    IO.puts("\n✅ Bucket policy set successfully!")
    IO.puts("Files should now be publicly accessible.")

  {:error, {:http_error, status, %{body: body}}} ->
    IO.puts("\n❌ Failed to set bucket policy:")
    IO.puts("Status: #{status}")
    IO.puts("Body: #{body}")

  {:error, reason} ->
    IO.puts("\n❌ Failed to set bucket policy:")
    IO.inspect(reason)
end
