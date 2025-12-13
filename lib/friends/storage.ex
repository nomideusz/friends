defmodule Friends.Storage do
  @moduledoc """
  Handles S3 storage operations.
  """
  alias ExAws.S3

  defp bucket, do: Application.get_env(:friends, :media_bucket, "friends-images")

  def upload_file(data, filename, content_type) do
    # Simple upload for small files (or base64 decoded data)
    S3.put_object(bucket(), filename, data, [content_type: content_type, acl: :public_read])
    |> ExAws.request()
    |> case do
      {:ok, _result} ->
        {:ok, get_file_url(filename)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Uploads multiple image variants (thumb, medium, large, original).
  Returns {:ok, %{thumb_url, medium_url, large_url, original_url}} or {:error, reason}
  """
  def upload_with_variants(variants, base_filename, original_content_type) do
    results =
      Enum.reduce(variants, %{}, fn {size, binary}, acc ->
        # Thumbnails are JPEG for better compression, original keeps its type
        {suffix, content_type} =
          if size == :original do
            {Path.extname(base_filename), original_content_type}
          else
            {".jpg", "image/jpeg"}
          end

        filename = build_variant_filename(base_filename, size, suffix)

        case upload_file(binary, filename, content_type) do
          {:ok, url} ->
            Map.put(acc, :"#{size}_url", url)

          {:error, reason} ->
            Map.put(acc, :"#{size}_error", reason)
        end
      end)

    # Check if we have at least the original
    if Map.has_key?(results, :original_url) do
      {:ok, results}
    else
      {:error, results[:original_error] || :upload_failed}
    end
  end

  defp build_variant_filename(base_filename, :original, _suffix) do
    base_filename
  end

  defp build_variant_filename(base_filename, size, suffix) do
    # Remove extension and add size suffix
    base = Path.rootname(base_filename)
    "#{base}_#{size}#{suffix}"
  end

  def presigned_url(filename, opts \\ []) do
     # Generate presigned URL for direct upload if needed later
     # For now we stream through server for simplicity with LiveView uploads
     S3.presigned_url(ExAws.Config.new(:s3), :put, bucket(), filename, opts)
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
       "#{scheme}#{bucket()}.s3.amazonaws.com/#{filename}"
     else
       port_str = if port && port != 80 && port != 443, do: ":#{port}", else: ""
       "#{scheme}#{host}#{port_str}/#{bucket()}/#{filename}"
     end
  end
end

