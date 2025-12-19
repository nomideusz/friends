defmodule Friends.Social.Photos do
  @moduledoc """
  Manages Photos (uploaded to rooms or public feed).
  """
  import Ecto.Query, warn: false
  alias Friends.Repo
  alias Friends.Social.{Photo, Room}
  # Note: Requires Relationships alias if we keep list_friends_photos implementation here.
  # But get_friend_network_ids is in Relationships.
  # We will probably need to alias Friends.Social.Relationships if we move get_friend_network_ids there.
  # OR we delegate list_friends_photos in the Facade to this module, but this module needs helper from Relationships.
  # Decided: list_friends_photos stays here, but calls Relationships.get_friend_network_ids.
  # alias Friends.Social.Relationships

  def list_photos(room_id, limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)

    Photo
    |> where([p], p.room_id == ^room_id)
    # Pinned items first (DESC NULLS LAST), then chronological
    |> order_by([p], [desc_nulls_last: p.pinned_at, desc: p.uploaded_at, desc: p.id])
    |> limit(^limit)
    |> offset(^offset_val)
    |> select([p], %{
      id: p.id,
      user_id: p.user_id,
      user_color: p.user_color,
      user_name: p.user_name,
      thumbnail_data: p.thumbnail_data,
      content_type: p.content_type,
      file_size: p.file_size,
      description: p.description,
      uploaded_at: p.uploaded_at,
      pinned_at: p.pinned_at,
      batch_id: p.batch_id,
      room_id: p.room_id,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at,
      image_data:
        fragment(
          "CASE WHEN ? = 'audio/encrypted' THEN ? ELSE NULL END",
          p.content_type,
          p.image_data
        )
    })
    |> Repo.all()
  end

  def list_friends_photos(user_id, limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)
    # We assume Friends.Social.Relationships exists and has this function.
    # Since we are creating modules in order, Relationships isn't created yet.
    # But elixir compilation allows this as long as available at runtime.
    friend_user_ids = Friends.Social.Relationships.get_friend_network_ids(user_id)

    Photo
    |> where([p], p.user_id in ^friend_user_ids)
    |> order_by([p], desc: p.uploaded_at)
    |> limit(^limit)
    |> offset(^offset_val)
    |> select([p], %{
      id: p.id,
      user_id: p.user_id,
      user_color: p.user_color,
      user_name: p.user_name,
      thumbnail_data: p.thumbnail_data,
      content_type: p.content_type,
      file_size: p.file_size,
      description: p.description,
      uploaded_at: p.uploaded_at,
      batch_id: p.batch_id,
      room_id: p.room_id,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at,
      image_data:
        fragment(
          "CASE WHEN ? = 'audio/encrypted' THEN ? ELSE NULL END",
          p.content_type,
          p.image_data
        )
    })
    |> Repo.all()
  end
  
  def list_user_photos(user_id, limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)
    user_id_str = if is_integer(user_id), do: "user-#{user_id}", else: user_id

    Photo
    |> where([p], p.user_id == ^user_id_str)
    |> order_by([p], desc: p.uploaded_at)
    |> limit(^limit)
    |> offset(^offset_val)
    |> select([p], %{
      id: p.id,
      user_id: p.user_id,
      user_color: p.user_color,
      user_name: p.user_name,
      thumbnail_data: p.thumbnail_data,
      content_type: p.content_type,
      file_size: p.file_size,
      description: p.description,
      uploaded_at: p.uploaded_at,
      batch_id: p.batch_id,
      room_id: p.room_id,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at,
      image_data:
        fragment(
          "CASE WHEN ? = 'audio/encrypted' THEN ? ELSE NULL END",
          p.content_type,
          p.image_data
        )
    })
    |> Repo.all()
  end

  def list_public_photos(limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)

    Photo
    |> join(:inner, [p], r in Room, on: p.room_id == r.id and r.is_private == false)
    |> order_by([p, _r], desc: p.uploaded_at)
    |> limit(^limit)
    |> offset(^offset_val)
    |> select([p, _r], %{
      id: p.id,
      user_id: p.user_id,
      user_color: p.user_color,
      user_name: p.user_name,
      thumbnail_data: p.thumbnail_data,
      content_type: p.content_type,
      file_size: p.file_size,
      description: p.description,
      uploaded_at: p.uploaded_at,
      batch_id: p.batch_id,
      room_id: p.room_id,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at,
      image_data:
        fragment(
          "CASE WHEN ? = 'audio/encrypted' THEN ? ELSE NULL END",
          p.content_type,
          p.image_data
        )
    })
    |> Repo.all()
  end

  def get_photo(id), do: Repo.get(Photo, id)

  def get_photo_image_data(id) do
    Photo
    |> where([p], p.id == ^id)
    |> select([p], %{
      image_data: p.image_data,
      thumbnail_data: p.thumbnail_data,
      content_type: p.content_type
    })
    |> Repo.one()
  end

  @doc """
  Lists photos grouped into galleries by batch_id for feed display.
  Single photos (no batch_id) are returned as individual items.
  Photos with the same batch_id are grouped into a gallery.
  """
  def list_photo_galleries(user_id_or_scope, limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)
    
    # Get base photos query depending on scope
    photos = case user_id_or_scope do
      :public -> list_public_photos(limit * 3, offset: offset_val)  # Get more to account for grouping
      {:user, user_id} -> list_user_photos(user_id, limit * 3, offset: offset_val)
      {:friends, user_id} -> list_friends_photos(user_id, limit * 3, offset: offset_val)
      {:room, room_id} -> list_photos(room_id, limit * 3, offset: offset_val)
    end

    # Group photos by batch_id
    {batched, singles} = Enum.split_with(photos, & &1.batch_id)
    
    # Create gallery items from batched photos
    galleries =
      batched
      |> Enum.group_by(& &1.batch_id)
      |> Enum.map(fn {batch_id, batch_photos} ->
        first_photo = List.first(batch_photos)
        %{
          type: :gallery,
          batch_id: batch_id,
          photo_count: length(batch_photos),
          first_photo: first_photo,
          all_photos: batch_photos,
          user_id: first_photo.user_id,
          user_color: first_photo.user_color,
          user_name: first_photo.user_name,
          uploaded_at: first_photo.uploaded_at,
          id: "gallery-#{batch_id}",  # Unique ID for stream
          unique_id: "gallery-#{batch_id}"
        }
      end)
    
    # Combine galleries and single photos, sort by uploaded_at
    all_items = galleries ++ Enum.map(singles, &Map.put(&1, :type, :photo))
    
    all_items
    |> Enum.sort_by(& &1.uploaded_at, {:desc, DateTime})
    |> Enum.take(limit)
  end

  def list_batch_photos(batch_id) do
    Photo
    |> where([p], p.batch_id == ^batch_id)
    |> order_by([p], asc: p.id)
    |> Repo.all()
  end

  def create_photo(attrs, room_code) do
    result =
      %Photo{}
      |> Photo.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, photo} ->
        # Use main Social module for PubSub broadcasting to avoid duplicating that logic?
        # Or just call Phoenix.PubSub directly.
        # Social.broadcast/3 is a wrapper around Phoenix.PubSub.
        # We can implement broadcast locally or call Social.broadcast.
        # Calling Social.broadcast creates a dependency loop if Social uses Photos.
        # Better to duplicate simple broadcast wrapper or use Phoenix.PubSub directly.
        
        Phoenix.PubSub.broadcast(Friends.PubSub, "friends:room:#{room_code}", {:new_photo, photo})
        {:ok, photo}

      error ->
        error
    end
  end
  
  def create_public_photo(attrs, user_id) do
    result =
      %Photo{}
      |> Photo.changeset(Map.put(attrs, :room_id, nil))
      |> Repo.insert()

    case result do
      {:ok, photo} ->
         # We need to broadcast to contacts. This logic is complex in Social.ex.
         # It calls broadcast_to_contacts.
         # We should probably expose broadcast_to_contacts or move it to Relations.
         # For now, let's assume we call Friends.Social.broadcast_to_contacts in the Facade
         # OR we implement it here by calling Relations to get IDs.
         
         # Let's delegate the broadcasting responsibility back to the caller or Facade if possible?
         # Or better: This module returns {:ok, photo} and the Facade does the broadcasting.
         # BUT existing callers expect create_public_photo to handle broadcasting.
         
         # I will implement broadcast here using Relationships to get IDs.
         Friends.Social.Relationships.broadcast_to_contacts(user_id, :new_public_photo, photo)
         {:ok, photo}

      error ->
        error
    end
  end

  def set_photo_thumbnail(photo_id, thumbnail_data, user_id, room_code)
      when is_integer(photo_id) and is_binary(thumbnail_data) do
    result =
      Photo
      |> where([p], p.id == ^photo_id and p.user_id == ^user_id)
      |> Repo.update_all(set: [thumbnail_data: thumbnail_data])

    case result do
      {1, _} ->
        Phoenix.PubSub.broadcast(
          Friends.PubSub, 
          "friends:room:#{room_code}", 
          {:photo_thumbnail_updated, %{id: photo_id, thumbnail_data: thumbnail_data}}
        )
        :ok

      _ ->
        :error
    end
  end

  def update_photo_thumbnail(photo_id, thumbnail_data, user_id) do
    case Repo.get(Photo, photo_id) do
      nil ->
        {:error, :not_found}

      photo ->
        current_user_id_str = if is_integer(user_id), do: "user-#{user_id}", else: user_id
        
        if photo.user_id == current_user_id_str do
          photo
          |> Photo.changeset(%{thumbnail_data: thumbnail_data})
          |> Repo.update()
          |> case do
            {:ok, updated_photo} ->
              if updated_photo.room_id do
                # It's a room photo - need room code to broadcast!
                # We need to fetch the room to get the code.
                room = Friends.Social.Rooms.get_room(updated_photo.room_id)
                if room do
                  Phoenix.PubSub.broadcast(
                    Friends.PubSub, 
                    "friends:room:#{room.code}", 
                    {:photo_thumbnail_updated, %{id: photo_id, thumbnail_data: thumbnail_data}}
                  )
                end
              else
                 # It's a public photo
                 case Integer.parse(String.replace(current_user_id_str, "user-", "")) do
                   {int_id, ""} -> 
                      Friends.Social.Relationships.broadcast_to_contacts(int_id, :photo_thumbnail_updated, %{
                        id: photo_id,
                        thumbnail_data: thumbnail_data
                      })
                   _ -> nil
                 end
              end
              
              {:ok, updated_photo}

            error ->
              error
          end
        else
          {:error, :unauthorized}
        end
    end
  end

  def update_photo_urls(photo_id, urls, user_id) do
    case Repo.get(Photo, photo_id) do
      nil ->
        {:error, :not_found}

      photo ->
        current_user_id_str = if is_integer(user_id), do: "user-#{user_id}", else: user_id

        if photo.user_id == current_user_id_str do
          changes = %{
            image_data: urls.original_url,
            image_url_thumb: urls.thumb_url,
            image_url_medium: urls.medium_url,
            image_url_large: urls.large_url
          }

          photo
          |> Photo.changeset(changes)
          |> Repo.update()
          |> case do
            {:ok, updated_photo} ->
              # Broadcast update so UI refreshes with high-res images
              if updated_photo.room_id do
                room = Friends.Social.Rooms.get_room(updated_photo.room_id)
                if room do
                  Phoenix.PubSub.broadcast(
                    Friends.PubSub,
                    "friends:room:#{room.code}",
                    {:photo_updated, updated_photo}
                  )
                end
              else
                 # Public photo
                 case Integer.parse(String.replace(current_user_id_str, "user-", "")) do
                   {int_id, ""} ->
                      Friends.Social.Relationships.broadcast_to_contacts(int_id, :photo_updated, updated_photo)
                   _ -> nil
                 end
              end

              {:ok, updated_photo}

            error ->
              error
          end
        else
          {:error, :unauthorized}
        end
    end
  end

  def update_photo_description(photo_id, description, user_id) do
    case Repo.get(Photo, photo_id) do
      nil ->
        {:error, :not_found}

      photo ->
        if photo.user_id == user_id do
          photo
          |> Photo.changeset(%{description: description})
          |> Repo.update()
        else
          {:error, :unauthorized}
        end
    end
  end

  def delete_photo(photo_id, room_code) do
    case Repo.get(Photo, photo_id) do
      nil ->
        {:error, :not_found}

      photo ->
        case Repo.delete(photo) do
          {:ok, _} ->
            if room_code do
              Phoenix.PubSub.broadcast(
                Friends.PubSub, 
                "friends:room:#{room_code}", 
                {:photo_deleted, %{id: photo_id}}
              )
            else
              Phoenix.PubSub.broadcast(
                Friends.PubSub, 
                "friends:public_feed:#{photo.user_id}", 
                {:photo_deleted, %{id: photo_id}}
              )
            end
            {:ok, photo}

          error ->
            error
        end
    end
  end

  # --- PIN / UNPIN ---

  @doc """
  Pin a photo to the top of the room. Only room owner/admins should call this.
  """
  def pin_photo(photo_id, room_code) do
    case Repo.get(Photo, photo_id) do
      nil ->
        {:error, :not_found}

      photo ->
        photo
        |> Ecto.Changeset.change(%{pinned_at: DateTime.utc_now()})
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            if room_code do
              Phoenix.PubSub.broadcast(
                Friends.PubSub,
                "friends:room:#{room_code}",
                {:photo_pinned, %{id: photo_id, pinned_at: updated.pinned_at}}
              )
            end
            {:ok, updated}

          error ->
            error
        end
    end
  end

  @doc """
  Unpin a photo.
  """
  def unpin_photo(photo_id, room_code) do
    case Repo.get(Photo, photo_id) do
      nil ->
        {:error, :not_found}

      photo ->
        photo
        |> Ecto.Changeset.change(%{pinned_at: nil})
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            if room_code do
              Phoenix.PubSub.broadcast(
                Friends.PubSub,
                "friends:room:#{room_code}",
                {:photo_unpinned, %{id: photo_id}}
              )
            end
            {:ok, updated}

          error ->
            error
        end
    end
  end
end
