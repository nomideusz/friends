defmodule Friends.Social.Notes do
  @moduledoc """
  Manages Notes (text items in rooms/feed).
  """
  import Ecto.Query, warn: false
  alias Friends.Repo
  alias Friends.Social.{Note, Room}
  alias Friends.Social.Relationships

  def list_notes(room_id, limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)

    Note
    |> where([n], n.room_id == ^room_id)
    # Pinned items first (DESC NULLS LAST), then chronological
    |> order_by([n], [desc_nulls_last: n.pinned_at, desc: n.inserted_at])
    |> limit(^limit)
    |> offset(^offset_val)
    |> Repo.all()
  end

  def list_friends_notes(user_id, limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)
    friend_user_ids = Relationships.get_friend_network_ids(user_id)

    Note
    |> where([n], n.user_id in ^friend_user_ids)
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> offset(^offset_val)
    |> Repo.all()
  end
  
  def list_user_notes(user_id, limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)
    user_id_str = if is_integer(user_id), do: "user-#{user_id}", else: user_id

    Note
    |> where([n], n.user_id == ^user_id_str)
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> offset(^offset_val)
    |> Repo.all()
  end
  
  def list_public_notes(limit \\ 50, opts \\ []) do
    offset_val = Keyword.get(opts, :offset, 0)

    Note
    |> join(:inner, [n], r in Room, on: n.room_id == r.id and r.is_private == false)
    |> order_by([n, _r], desc: n.inserted_at)
    |> limit(^limit)
    |> offset(^offset_val)
    |> Repo.all()
  end

  def get_note(id), do: Repo.get(Note, id)

  def create_note(attrs, room_code) do
    result =
      %Note{}
      |> Note.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, note} ->
        Phoenix.PubSub.broadcast(Friends.PubSub, "friends:room:#{room_code}", {:new_note, note})
        {:ok, note}

      error ->
        error
    end
  end

  @doc """
  Creates a public note (without room_id) and broadcasts to contacts.
  """
  def create_public_note(attrs, user_id) do
    result =
      %Note{}
      |> Note.public_changeset(Map.put(attrs, :room_id, nil))
      |> Repo.insert()

    case result do
      {:ok, note} ->
        # Broadcast to user's contacts
        Relationships.broadcast_to_contacts(user_id, :new_public_note, note)
        {:ok, note}

      error ->
        error
    end
  end

  def update_note(note_id, attrs, user_id) do
    case Repo.get(Note, note_id) do
      nil ->
        {:error, :not_found}

      note ->
        cond do
          note.user_id != user_id ->
            {:error, :unauthorized}

          not Note.editable?(note) ->
            {:error, :grace_period_expired}

          true ->
            note
            |> Note.changeset(attrs)
            |> Repo.update()
        end
    end
  end

  def delete_note(note_id, user_id, room_code) do
    case Repo.get(Note, note_id) do
      nil ->
        {:error, :not_found}

      note ->
        cond do
          note.user_id != user_id ->
            {:error, :unauthorized}

          not Note.editable?(note) ->
            {:error, :grace_period_expired}

          true ->
            case Repo.delete(note) do
              {:ok, _} ->
                Phoenix.PubSub.broadcast(Friends.PubSub, "friends:room:#{room_code}", {:note_deleted, %{id: note_id}})
                {:ok, note}

              error ->
                error
            end
        end
    end
  end

  # --- PIN / UNPIN ---

  @doc """
  Pin a note to the top of the room.
  """
  def pin_note(note_id, room_code) do
    case Repo.get(Note, note_id) do
      nil ->
        {:error, :not_found}

      note ->
        note
        |> Ecto.Changeset.change(%{pinned_at: DateTime.utc_now()})
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            if room_code do
              Phoenix.PubSub.broadcast(
                Friends.PubSub,
                "friends:room:#{room_code}",
                {:note_pinned, %{id: note_id, pinned_at: updated.pinned_at}}
              )
            end
            {:ok, updated}

          error ->
            error
        end
    end
  end

  @doc """
  Unpin a note.
  """
  def unpin_note(note_id, room_code) do
    case Repo.get(Note, note_id) do
      nil ->
        {:error, :not_found}

      note ->
        note
        |> Ecto.Changeset.change(%{pinned_at: nil})
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            if room_code do
              Phoenix.PubSub.broadcast(
                Friends.PubSub,
                "friends:room:#{room_code}",
                {:note_unpinned, %{id: note_id}}
              )
            end
            {:ok, updated}

          error ->
            error
        end
    end
  end
end
