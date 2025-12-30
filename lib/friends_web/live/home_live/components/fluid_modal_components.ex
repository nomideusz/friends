defmodule FriendsWeb.HomeLive.Components.FluidModalComponents do
  @moduledoc """
  Fluid-styled modals for the new design system.
  All modals use: glass effect, centered content, smooth animations.
  """
  use FriendsWeb, :html

  # ============================================================================
  # FLUID IMAGE MODAL
  # Full-screen, minimal chrome, gesture-friendly
  # ============================================================================

  attr :show, :boolean, default: false
  attr :photo, :map, default: nil
  attr :photo_order, :list, default: []

  def fluid_image_modal(assigns) do
    ~H"""
    <%= if @show and @photo do %>
      <div
        id="fluid-image-modal"
        class="fixed inset-0 z-[200] bg-black"
        phx-hook="ImageModal"
        phx-window-keydown="handle_keydown"
      >
        <%!-- Close button --%>
        <button
          phx-click="close_image_modal"
          class="absolute top-4 right-4 z-50 w-10 h-10 rounded-full bg-white/10 backdrop-blur-xl border border-white/20 flex items-center justify-center text-white/70 hover:text-white hover:bg-white/20 transition-all cursor-pointer"
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>

        <%!-- Navigation --%>
        <%= if length(@photo_order) > 1 do %>
          <button
            phx-click="prev_photo"
            class="absolute left-4 top-1/2 -translate-y-1/2 z-50 w-12 h-12 rounded-full bg-white/10 backdrop-blur-xl border border-white/20 flex items-center justify-center text-white/70 hover:text-white hover:bg-white/20 transition-all cursor-pointer"
          >
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
            </svg>
          </button>
          <button
            phx-click="next_photo"
            class="absolute right-4 top-1/2 -translate-y-1/2 z-50 w-12 h-12 rounded-full bg-white/10 backdrop-blur-xl border border-white/20 flex items-center justify-center text-white/70 hover:text-white hover:bg-white/20 transition-all cursor-pointer"
          >
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
            </svg>
          </button>
        <% end %>

        <%!-- Image --%>
        <div class="w-full h-full flex items-center justify-center p-4">
          <%= if @photo.data do %>
            <img
              src={@photo.data}
              alt=""
              class="max-w-full max-h-full object-contain animate-in zoom-in-95 duration-200"
            />
          <% else %>
            <div class="flex items-center justify-center h-64 w-64 bg-white/5 rounded-2xl border border-white/10">
              <div class="w-8 h-8 rounded-full border-2 border-white/20 border-t-white/60 animate-spin"></div>
            </div>
          <% end %>
        </div>

        <%!-- Position indicator --%>
        <%= if length(@photo_order) > 1 do %>
          <div class="absolute bottom-6 left-1/2 -translate-x-1/2 px-4 py-2 rounded-full bg-black/60 backdrop-blur-xl border border-white/10">
            <% current_idx = Enum.find_index(@photo_order, fn id -> id == @photo.id end) %>
            <%= if current_idx do %>
              <span class="text-sm font-medium text-white/70"><%= current_idx + 1 %> / <%= length(@photo_order) %></span>
            <% end %>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  # ============================================================================
  # FLUID NOTE MODAL
  # Bottom sheet style, minimal input
  # ============================================================================

  attr :show, :boolean, default: false
  attr :action, :string, default: "post_feed_note"

  def fluid_note_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div
        id="fluid-note-modal"
        class="fixed inset-0 z-[200]"
        phx-mounted={JS.add_class("overflow-hidden", to: "body")}
        phx-remove={JS.remove_class("overflow-hidden", to: "body")}
      >
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click="close_note_modal"
        ></div>

        <%!-- Modal --%>
        <div class="absolute inset-x-0 bottom-0 z-10 animate-in slide-in-from-bottom duration-300">
          <div class="mx-auto max-w-lg bg-neutral-900/95 backdrop-blur-xl border-t border-x border-white/10 rounded-t-3xl shadow-2xl">
            <%!-- Handle --%>
            <div class="py-3 flex justify-center" phx-click="close_note_modal">
              <div class="w-10 h-1 rounded-full bg-white/20"></div>
            </div>

            <%!-- Content --%>
            <form phx-submit={@action} class="px-4 pb-8">
              <textarea
                id="fluid-note-textarea"
                name="note"
                rows="4"
                maxlength="500"
                phx-mounted={JS.focus()}
                class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 text-white placeholder-white/30 focus:border-white/30 focus:outline-none resize-none text-lg"
                placeholder="..."
              ></textarea>

              <div class="flex gap-3 mt-4">
                <button
                  type="button"
                  phx-click="close_note_modal"
                  class="flex-1 py-3 rounded-xl bg-white/5 border border-white/10 text-white/70 font-medium hover:bg-white/10 transition-colors cursor-pointer"
                >
                  ×
                </button>
                <button
                  type="submit"
                  class="flex-1 py-3 rounded-xl bg-white text-black font-bold hover:bg-white/90 transition-colors cursor-pointer"
                >
                  Post
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ============================================================================
  # FLUID VIEW NOTE MODAL
  # For viewing existing notes
  # ============================================================================

  attr :note, :map, default: nil

  def fluid_view_note_modal(assigns) do
    ~H"""
    <%= if @note do %>
      <div
        id="fluid-view-note-modal"
        class="fixed inset-0 z-[200]"
      >
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click="close_view_note"
        ></div>

        <%!-- Modal --%>
        <div class="absolute inset-4 z-10 flex items-center justify-center">
          <div class="w-full max-w-md bg-neutral-900/95 backdrop-blur-xl border border-white/10 rounded-3xl shadow-2xl p-6 animate-in zoom-in-95 duration-200">
            <%!-- Close --%>
            <button
              phx-click="close_view_note"
              class="absolute top-4 right-4 w-8 h-8 rounded-full bg-white/10 flex items-center justify-center text-white/50 hover:text-white hover:bg-white/20 transition-colors cursor-pointer"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>

            <%!-- Note content --%>
            <p class="text-white/90 text-lg leading-relaxed pr-8"><%= @note.content %></p>

            <%!-- Author --%>
            <div class="mt-6 pt-4 border-t border-white/5 flex items-center gap-3">
              <div class="w-6 h-6 rounded-full bg-white/20"></div>
              <span class="text-sm text-white/50">
                @<%= if Map.has_key?(@note, :user), do: @note.user.username, else: "unknown" %>
              </span>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ============================================================================
  # FLUID CREATE GROUP MODAL
  # Simple group creation
  # ============================================================================

  attr :show, :boolean, default: false
  attr :new_room_name, :string, default: ""

  def fluid_create_group_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div
        id="fluid-create-group-modal"
        class="fixed inset-0 z-[200]"
      >
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click="close_create_group_modal"
        ></div>

        <%!-- Modal --%>
        <div class="absolute inset-x-0 bottom-0 z-10 animate-in slide-in-from-bottom duration-300">
          <div class="mx-auto max-w-lg bg-neutral-900/95 backdrop-blur-xl border-t border-x border-white/10 rounded-t-3xl shadow-2xl">
            <%!-- Handle --%>
            <div class="py-3 flex justify-center" phx-click="close_create_group_modal">
              <div class="w-10 h-1 rounded-full bg-white/20"></div>
            </div>

            <%!-- Content --%>
            <form phx-submit="create_group" class="px-4 pb-8">
              <input
                type="text"
                name="name"
                value={@new_room_name}
                phx-mounted={JS.focus()}
                placeholder="Group name..."
                required
                class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-white placeholder-white/30 focus:border-white/30 focus:outline-none text-lg"
              />

              <button
                type="submit"
                class="w-full mt-4 py-3 rounded-xl bg-white text-black font-bold hover:bg-white/90 transition-colors cursor-pointer"
              >
                Create
              </button>
            </form>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
  # ============================================================================
  # FLUID MODAL BASE
  # Reusable base for general modals
  # ============================================================================

  attr :id, :string, required: true
  attr :on_cancel, :string, required: true
  slot :title
  slot :inner_block, required: true

  def fluid_modal_base(assigns) do
    ~H"""
      <div
        id={@id}
        class="fixed inset-0 z-[200]"
      >
        <%!-- Backdrop --%>
        <div
          class="absolute inset-0 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200"
          phx-click={@on_cancel}
        ></div>

        <%!-- Modal --%>
        <div class="absolute inset-x-0 top-1/2 -translate-y-1/2 z-10 animate-in zoom-in-95 duration-200 px-4">
          <div class="mx-auto max-w-sm bg-neutral-900/95 backdrop-blur-xl border border-white/10 rounded-3xl shadow-2xl overflow-hidden">
            <%!-- Header --%>
            <%= if @title != [] do %>
              <div class="py-4 border-b border-white/5 text-center">
                 <h3 class="text-white font-medium text-lg"><%= render_slot(@title) %></h3>
              </div>
            <% end %>

            <%!-- Content --%>
            <div class="">
              <%= render_slot(@inner_block) %>
            </div>
          </div>
        </div>
      </div>
    """
  end
end
