defmodule Friends.Storage do
  @moduledoc """
  Handles S3 storage operations.
  """
  alias ExAws.S3

  @bucket Application.compile_env(:friends, :media_bucket, "friends-images")

  def upload_file(data, filename, content_type) do
    # Simple upload for small files (or base64 decoded data)
    S3.put_object(@bucket, filename, data, [content_type: content_type, acl: :public_read])
    |> ExAws.request()
    |> case do
      {:ok, _result} ->
        {:ok, get_file_url(filename)}

      {:error, reason} ->
        {:error, reason}
    end
  end
  
  def presigned_url(filename, opts \\ []) do
     # Generate presigned URL for direct upload if needed later
     # For now we stream through server for simplicity with LiveView uploads
     S3.presigned_url(ExAws.Config.new(:s3), :put, @bucket, filename, opts)
  end

  def get_file_url(filename) do
     # Construct public URL
     # Assuming public-read ACL
     config = ExAws.Config.new(:s3)
     scheme = config[:scheme] || "https://"
     host = config[:host]
     port = config[:port]
     
     # Construct URL based on host/port config
     # For localhost minio: http://localhost:9000/bucket/filename
     # For real S3: https://bucket.s3.amazonaws.com/filename or similar
     
     if host == "s3.amazonaws.com" do
       "#{scheme}#{@bucket}.s3.amazonaws.com/#{filename}"
     else
       port_str = if port && port != 80 && port != 443, do: ":#{port}", else: ""
       "#{scheme}#{host}#{port_str}/#{@bucket}/#{filename}"
     end
  end
end
