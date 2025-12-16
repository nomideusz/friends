defmodule FriendsWeb.HomeLive.Components.ModalComponents do
  use FriendsWeb, :html


  # --- Photo Modal ---
  attr :show, :boolean, default: false
  attr :photo, :map, default: nil

  def photo_modal(assigns) do
    ~H"""
    <%= if @show and @photo do %>
      <div
        class="fixed inset-0 z-[100]"
        phx-window-keydown="close_image_modal"
        phx-key="escape"
      >
        <!-- Backdrop -->
        <div 
          class="absolute inset-0 bg-black/90 backdrop-blur-sm transition-opacity" 
          phx-click="close_image_modal"
        ></div>

        <!-- Modal Content Container -->
        <div class="absolute inset-0 flex items-center justify-center p-4 pointer-events-none">
          <div
            class="max-w-4xl max-h-[90vh] relative aether-card bg-black/90 p-4 rounded-xl shadow-2xl pointer-events-auto"
          >
          <%= if @photo.data do %>
            <img
              src={@photo.data}
              alt="Photo"
              class="max-w-full max-h-[80vh] object-contain rounded-lg shadow-2xl mx-auto"
            />
          <% else %>
            <div class="flex items-center justify-center h-64 w-64 bg-neutral-800 rounded-lg">
              <p class="text-red-500">No image data</p>
            </div>
          <% end %>
          
          <button
            phx-click="close_image_modal"
            class="absolute top-2 right-2 w-10 h-10 bg-black/50 hover:bg-black/80 rounded-full flex items-center justify-center text-white transition-colors cursor-pointer backdrop-blur-md"
          >
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>
        </div>
        </div>
      </div>
    <% end %>
    """
  end

  # --- Note Modal ---
  # Responsive: Drawer on mobile, centered modal on desktop
  attr :show, :boolean, default: false
  attr :action, :string, default: "post_feed_note"

  def note_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div
        class="fixed inset-0 z-50"
        phx-mounted={JS.add_class("overflow-hidden", to: "body")}
        phx-remove={JS.remove_class("overflow-hidden", to: "body")}
        phx-window-keydown="close_note_modal"
        phx-key="escape"
      >
        <%!-- Backdrop --%>
        <div 
          class="absolute inset-0 bg-black/60 backdrop-blur-sm transition-opacity" 
          phx-click="close_note_modal"
        ></div>

        <%!-- Mobile: Bottom Drawer --%>
        <div class="lg:hidden fixed inset-x-0 bottom-0 z-50 animate-in slide-in-from-bottom duration-300">
          <%!-- Tappable drag handle area --%>
          <button
            phx-click="close_note_modal"
            class="w-full pt-3 pb-2 flex flex-col items-center cursor-pointer group bg-black/95 rounded-t-3xl border-t border-white/10"
          >
            <div class="w-12 h-1.5 bg-white/30 rounded-full group-hover:bg-white/50 transition-colors"></div>
            <span class="text-[10px] text-neutral-600 mt-1">tap to close</span>
          </button>
          
          <div class="aether-card rounded-t-3xl border-t-0 p-5 pb-8 bg-black/95">
            <h3 class="text-sm font-bold uppercase tracking-wider text-neutral-400 mb-4">
              <%= if @action == "post_feed_note", do: "Public Note", else: "Room Note" %>
            </h3>
            
            <form phx-submit={@action}>
              <div class="relative">
                <textarea
                  id="note-textarea-mobile"
                  name="note"
                  rows="4"
                  maxlength="500"
                  phx-mounted={JS.focus()}
                  oninput="document.getElementById('note-char-count-mobile').textContent = this.value.length"
                  class="w-full bg-neutral-900/50 border border-white/10 rounded-xl p-4 text-white placeholder-neutral-600 focus:border-blue-500/50 focus:outline-none resize-none"
                  placeholder="What's on your mind?"
                ></textarea>
                <div class="absolute bottom-3 right-3 text-xs text-neutral-600 font-mono">
                  <span id="note-char-count-mobile" class="text-neutral-500">0</span>/500
                </div>
              </div>
              
              <div class="flex gap-3 mt-4">
                <button
                  type="button"
                  phx-click="close_note_modal"
                  class="flex-1 py-3 rounded-xl text-sm font-bold uppercase tracking-wider text-neutral-400 hover:bg-white/5 transition-all cursor-pointer aether-card"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="flex-1 py-3 rounded-xl bg-white text-black text-sm font-bold uppercase tracking-wider cursor-pointer shadow-lg active:translate-y-px"
                >
                  Post
                </button>
              </div>
            </form>
          </div>
        </div>

        <%!-- Desktop: Centered Modal --%>
        <div class="hidden lg:flex absolute inset-0 items-center justify-center p-4 pointer-events-none">
          <div class="aether-card w-full max-w-lg rounded-2xl p-6 shadow-2xl bg-black/90 pointer-events-auto relative">
          <h3 class="text-lg font-bold uppercase tracking-wider text-neutral-400 mb-4">
            <%= if @action == "post_feed_note", do: "Create a Public Note", else: "Create a Room Note" %>
          </h3>
          
          <form phx-submit={@action} class="relative">
            <div class="relative">
            <textarea
              id="note-textarea"
              name="note"
              rows="5"
              maxlength="500"
              phx-mounted={JS.focus()}
              oninput="document.getElementById('note-char-count').textContent = this.value.length"
              class="w-full bg-neutral-900/50 border border-white/10 rounded-xl p-4 text-white placeholder-neutral-600 focus:border-blue-500/50 focus:ring-1 focus:ring-blue-500/50 focus:outline-none resize-none transition-all"
              placeholder="What's on your mind?"
            ></textarea>
              <div class="absolute bottom-3 right-3 text-xs text-neutral-600 font-mono pointer-events-none">
                <span id="note-char-count" class="text-neutral-500">0</span>/500
              </div>
            </div>
            
            <div class="flex justify-end gap-3 mt-6">
              <button
                type="button"
                phx-click="close_note_modal"
                class="px-5 py-2.5 rounded-lg text-sm font-bold uppercase tracking-wider text-neutral-400 hover:text-white hover:bg-white/5 transition-all cursor-pointer"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="px-6 py-2.5 rounded-lg bg-white hover:bg-neutral-100 text-black text-sm font-bold uppercase tracking-wider transition-all cursor-pointer shadow-lg active:translate-y-px"
              >
                Post Note
              </button>
            </div>
          </form>
        </div>
        </div>
      </div>
    <% end %>
    """
  end


end
