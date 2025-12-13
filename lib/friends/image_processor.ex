defmodule Friends.ImageProcessor do
  @moduledoc """
  Processes uploaded images to generate multiple size variants for responsive display.
  Uses the Image library (libvips) when available.
  On Windows where libvips isn't available, falls back to returning the original image for all sizes.
  """

  require Logger

  @sizes %{
    thumb: 200,
    medium: 800,
    large: 1600
  }

  # Check if Image library is available at compile time
  @image_available Code.ensure_loaded?(Image)

  @doc """
  Processes an uploaded image binary and generates all size variants.
  Returns {:ok, %{thumb: binary, medium: binary, large: binary, original: binary}, processed: boolean}
  where processed indicates if actual image processing was done (false = all same as original)
  """
  def process_upload(binary, content_type) when is_binary(binary) do
    if @image_available and image_processing_enabled?() do
      case process_with_image_library(binary, content_type) do
        {:ok, variants} -> {:ok, variants, true}
        {:error, _} = error -> error
      end
    else
      # Fallback: return original for all sizes (Windows or disabled)
      Logger.info("Image processing not available, using original for all sizes")
      {:ok, %{thumb: binary, medium: binary, large: binary, original: binary}, false}
    end
  end

  defp process_with_image_library(binary, content_type) do
    with {:ok, image} <- apply(Image, :from_binary, [binary]) do
      variants = %{original: binary}

      variants =
        Enum.reduce(@sizes, variants, fn {size_name, max_dim}, acc ->
          case generate_thumbnail_impl(image, max_dim, content_type) do
            {:ok, resized_binary} ->
              Map.put(acc, size_name, resized_binary)

            {:error, reason} ->
              Logger.warning("Failed to generate #{size_name} thumbnail: #{inspect(reason)}")
              Map.put(acc, size_name, binary)
          end
        end)

      {:ok, variants}
    else
      {:error, reason} ->
        Logger.error("Failed to open image: #{inspect(reason)}")
        {:ok, %{thumb: binary, medium: binary, large: binary, original: binary}}
    end
  end

  defp generate_thumbnail_impl(image, max_dimension, _content_type) do
    with {:ok, resized} <- apply(Image, :thumbnail, [image, max_dimension, [crop: :none]]) do
      apply(Image, :write, [resized, :memory, [suffix: ".jpg", quality: 85]])
    end
  end

  @doc """
  Returns whether image processing is enabled.
  Can be disabled via config for testing or Windows dev.
  """
  def image_processing_enabled? do
    Application.get_env(:friends, :enable_image_processing, true)
  end

  @doc """
  Returns the configured sizes for reference.
  """
  def sizes, do: @sizes
end

