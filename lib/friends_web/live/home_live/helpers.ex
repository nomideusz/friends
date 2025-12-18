defmodule FriendsWeb.HomeLive.Helpers do
  @moduledoc """
  Shared helper functions for HomeLive.
  """

  alias Friends.Social

  @colors ~w(#ef4444 #f97316 #eab308 #22c55e #14b8a6 #3b82f6 #8b5cf6 #ec4899)

  # --- Session & Identity Helpers ---

  def generate_session_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

  def generate_user_color(user_id) do
    hash = :crypto.hash(:md5, user_id)
    <<r, g, b, _::binary>> = hash
    "rgb(#{rem(r, 156) + 100}, #{rem(g, 156) + 100}, #{rem(b, 156) + 100})"
  end

  def colors, do: @colors

  # --- Color Helpers ---

  def trusted_user_color(%{id: id}), do: color_from_user_id(id)
  def trusted_user_color(_), do: "#666"

  def member_color(%{user: user}), do: trusted_user_color(user)
  def member_color(_), do: "#666"

  def friend_color(%{id: id}) when is_integer(id) do
    Enum.at(@colors, rem(id, length(@colors)))
  end

  def friend_color(_), do: "#888"

  @doc """
  Generate DM room code from two user IDs.
  Uses format: dm-{lower_id}-{higher_id}
  """
  def dm_room_code(user1_id, user2_id) when is_integer(user1_id) and is_integer(user2_id) do
    {lower, higher} = if user1_id < user2_id, do: {user1_id, user2_id}, else: {user2_id, user1_id}
    "dm-#{lower}-#{higher}"
  end

  def dm_room_code(_, _), do: nil

  def color_from_user_id("user-" <> id_str) do
    case Integer.parse(id_str) do
      {int, ""} -> color_from_user_id(int)
      _ -> generate_user_color(id_str)
    end
  end

  def color_from_user_id(user_id) when is_integer(user_id) do
    Enum.at(@colors, rem(user_id, length(@colors)))
  end

  def color_from_user_id(user_id) when is_binary(user_id), do: generate_user_color(user_id)
  def color_from_user_id(_), do: "#666"

  # --- Integer Parsing Helpers ---

  def safe_to_integer(value) when is_integer(value), do: {:ok, value}

  def safe_to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {num, ""} -> {:ok, num}
      _ -> {:error, :invalid_integer}
    end
  end

  def safe_to_integer(_), do: {:error, :invalid_integer}

  def normalize_photo_id(photo_id) when is_integer(photo_id), do: photo_id

  def normalize_photo_id(photo_id) when is_binary(photo_id) do
    case safe_to_integer(photo_id) do
      {:ok, id} -> id
      {:error, _} -> nil
    end
  end

  def normalize_photo_id(_), do: nil

  # --- Photo Order Helpers ---

  def photo_ids(items) do
    items
    |> Enum.filter(fn item -> 
      type = Map.get(item, :type)
      content_type = Map.get(item, :content_type) || ""
      
      (type == :photo or type == "photo") and 
        not String.starts_with?(content_type, "audio/") and
        not String.starts_with?(content_type, "video/")
    end)
    |> Enum.map(& &1.id)
  end

  def merge_photo_order(order, ids, position) do
    order = order || []
    ids = ids |> Enum.reject(&is_nil/1) |> Enum.uniq()
    remaining = Enum.reject(order, &(&1 in ids))

    case position do
      :front -> ids ++ remaining
      :back -> remaining ++ ids
      _ -> remaining
    end
  end

  def ensure_photo_in_order(order, id) do
    order = order || []

    cond do
      is_nil(id) -> order
      Enum.member?(order, id) -> order
      true -> order ++ [id]
    end
  end

  def remove_photo_from_order(order, id) do
    order = order || []
    normalized = normalize_photo_id(id)
    Enum.reject(order, &(&1 == normalized))
  end

  def current_photo_order(socket) do
    case socket.assigns[:photo_order] do
      list when is_list(list) -> list
      _ -> []
    end
  end

  # --- Item Building Helpers ---

  def build_items(photos, notes) do
    {galleries, singles} = Friends.Social.group_photos_into_galleries(photos)

    photo_items =
      Enum.map(singles, fn p ->
        p
        |> Map.put(:type, :photo)
        |> Map.put(:unique_id, "photo-#{p.id}")
      end)

    note_items =
      Enum.map(notes, fn n ->
        n
        |> Map.put(:type, :note)
        |> Map.put(:unique_id, "note-#{n.id}")
      end)

    (galleries ++ photo_items ++ note_items)
    |> Enum.sort_by(
      fn item ->
        timestamp = Map.get(item, :uploaded_at) || Map.get(item, :inserted_at)

        case timestamp do
          %DateTime{} -> DateTime.to_unix(timestamp)
          %NaiveDateTime{} -> NaiveDateTime.diff(timestamp, ~N[1970-01-01 00:00:00])
          _ -> 0
        end
      end,
      :desc
    )
  end

  # --- Formatting Helpers ---

  def format_time(datetime) do
    now = DateTime.utc_now()

    datetime =
      case datetime do
        %NaiveDateTime{} -> DateTime.from_naive!(datetime, "Etc/UTC")
        %DateTime{} -> datetime
        _ -> DateTime.utc_now()
      end

    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "now"
      diff < 3600 -> "#{div(diff, 60)}m"
      diff < 86400 -> "#{div(diff, 3600)}h"
      true -> "#{div(diff, 86400)}d"
    end
  end

  def format_voice_duration(ms) when is_integer(ms) do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(to_string(secs), 2, "0")}"
  end

  def format_voice_duration(_), do: "0:00"

  # --- Image Validation Helpers ---

  def validate_image_content(binary) do
    case binary do
      # JPEG: starts with FF D8 FF
      <<0xFF, 0xD8, 0xFF, _rest::binary>> -> {:ok, "image/jpeg"}
      # PNG: starts with 89 50 4E 47 0D 0A 1A 0A
      <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>> -> {:ok, "image/png"}
      # GIF: starts with GIF87a or GIF89a
      <<"GIF87a", _rest::binary>> -> {:ok, "image/gif"}
      <<"GIF89a", _rest::binary>> -> {:ok, "image/gif"}
      # WebP: starts with RIFF....WEBP
      <<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>> -> {:ok, "image/webp"}
      _ -> {:error, :invalid_image}
    end
  end

  # --- Photo Modal Helpers ---

  def load_photo_into_modal(socket, photo_id) do
    import Phoenix.Component, only: [assign: 3]
    import Phoenix.LiveView, only: [put_flash: 3]

    photo_id_int = normalize_photo_id(photo_id)

    case photo_id_int do
      nil ->
        put_flash(socket, :error, "Invalid photo")

      _ ->
        case Social.get_photo(photo_id_int) do
          nil ->
            put_flash(socket, :error, "Could not load image")

          photo ->
            # Determine if user can view the photo
            can_view? = 
              if photo.room_id do
                photo_room = Social.get_room(photo.room_id)
                
                current_user_id =
                  case socket.assigns.current_user do
                    nil -> nil
                    user -> user.id
                  end
                  
                photo_room && Social.can_access_room?(photo_room, current_user_id)
              else
                # Public photo (no room) - visible to all
                true
              end

            if can_view? do
              # Prefer image_url_large for modal (best quality), fallback to image_data, then thumbnail_data
              raw = photo.image_url_large || photo.image_url_medium || photo.image_data || photo.thumbnail_data
              content_type = photo.content_type || "image/jpeg"

              src =
                cond do
                  is_nil(raw) -> nil
                  String.starts_with?(raw, "data:") -> raw
                  String.starts_with?(raw, "http://") or String.starts_with?(raw, "https://") -> raw
                  true -> "data:#{content_type};base64,#{raw}"
                end

              if is_nil(src) do
                put_flash(socket, :error, "Could not load image")
              else
                base_order = current_photo_order(socket)
                order = ensure_photo_in_order(base_order, photo_id_int)
                current_idx = Enum.find_index(order, &(&1 == photo_id_int))

                socket
                |> assign(:show_image_modal, true)
                |> assign(:full_image_data, %{
                  data: src,
                  content_type: content_type,
                  photo_id: photo.id,
                  user_id: photo.user_id
                })
                |> assign(:photo_order, order)
                |> assign(:current_photo_id, photo_id_int)
                |> assign(:current_photo_index, current_idx)
              end
            else
              put_flash(socket, :error, "Access denied")
            end
        end
    end
  end

  def navigate_photo(socket, direction) do
    import Phoenix.Component, only: [assign: 3]

    base_order = current_photo_order(socket)
    order = ensure_photo_in_order(base_order, socket.assigns.current_photo_id)
    current = socket.assigns.current_photo_id

    cond do
      current == nil ->
        socket

      order == [] ->
        socket

      true ->
        idx = Enum.find_index(order, &(&1 == current)) || 0
        len = length(order)

        new_idx =
          case direction do
            :next -> rem(idx + 1, len)
            :prev -> rem(idx - 1 + len, len)
            _ -> idx
          end

        new_id = Enum.at(order, new_idx)
        load_photo_into_modal(socket, new_id)
    end
  end

  def maybe_close_deleted_photo(socket, photo_id) do
    import Phoenix.Component, only: [assign: 3]

    if socket.assigns.current_photo_id == photo_id do
      socket
      |> assign(:show_image_modal, false)
      |> assign(:full_image_data, nil)
      |> assign(:current_photo_id, nil)
    else
      socket
    end
  end
end
