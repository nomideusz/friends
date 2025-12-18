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
        phx-keyup="prev_photo"
        phx-key="ArrowLeft"
        phx-keyup="next_photo"
        phx-key="ArrowRight"
      >
        <!-- Backdrop -->
        <div 
          class="absolute inset-0 bg-black/95 backdrop-blur-md transition-opacity" 
          phx-click="close_image_modal"
        ></div>

        <div class="surface-overlay !p-0">
          <div class="surface-island !bg-transparent !shadow-none !border-0 w-full max-w-5xl h-full flex items-center justify-center p-4">
            <!-- Navigation Arrows (Desktop focus) -->
            <%= if length(@photo_order || []) > 1 do %>
              <button
                phx-click="prev_photo"
                class="hidden md:flex absolute left-8 top-1/2 -translate-y-1/2 w-14 h-14 bg-white/5 hover:bg-white/10 rounded-full items-center justify-center text-white transition-all cursor-pointer backdrop-blur-xl border border-white/10 z-50 group"
              >
                <svg class="w-8 h-8 group-hover:-translate-x-1 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M15 19l-7-7 7-7" />
                </svg>
              </button>
              <button
                phx-click="next_photo"
                class="hidden md:flex absolute right-8 top-1/2 -translate-y-1/2 w-14 h-14 bg-white/5 hover:bg-white/10 rounded-full items-center justify-center text-white transition-all cursor-pointer backdrop-blur-xl border border-white/10 z-50 group"
              >
                <svg class="w-8 h-8 group-hover:translate-x-1 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M9 5l7 7-7 7" />
                </svg>
              </button>
            <% end %>

            <div class="relative group">
              <%= if @photo.data do %>
                <img
                  src={@photo.data}
                  alt="Photo"
                  class="max-w-full max-h-[90vh] object-contain rounded-2xl shadow-2xl mx-auto"
                />
              <% else %>
                <div class="flex items-center justify-center h-64 w-64 bg-white/5 rounded-2xl border border-white/10">
                  <p class="text-red-400 font-bold uppercase tracking-widest text-xs">No image data</p>
                </div>
              <% end %>
              
              <%= if length(@photo_order || []) > 1 do %>
                <% 
                   current_idx = Enum.find_index(@photo_order, fn id -> id == @photo.id end) 
                   total = length(@photo_order)
                %>
                <%= if current_idx do %>
                  <div class="absolute bottom-4 left-1/2 -translate-x-1/2 bg-black/50 backdrop-blur-md text-white/80 px-4 py-2 rounded-full text-sm font-bold border border-white/10 select-none">
                    <%= current_idx + 1 %> / <%= total %>
                  </div>
                <% end %>
              <% end %>
              
              <button
                phx-click="close_image_modal"
                class="absolute -top-4 -right-4 w-12 h-12 bg-white text-black rounded-full flex items-center justify-center hover:scale-110 active:scale-90 transition-all cursor-pointer shadow-2xl z-[60]"
              >
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
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
        class="fixed inset-0 z-[200]"
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

        <div class="surface-overlay">
          <div class="surface-island aether-card w-full max-w-3xl">
            <div class="sheet-handle" phx-click="close_note_modal"><div></div></div>
            
            <div class="p-8 pb-4">
              <h3 class="text-sm font-bold uppercase tracking-wider text-white/40 mb-4">
                <%= if @action == "post_feed_note", do: "Public Note", else: "Room Note" %>
              </h3>
              
              <form phx-submit={@action}>
                <div class="relative">
                  <textarea
                    id="note-textarea-responsive"
                    name="note"
                    rows="5"
                    maxlength="500"
                    phx-mounted={JS.focus()}
                    oninput="document.getElementById('note-char-count-responsive').textContent = this.value.length"
                    class="w-full bg-white/5 border border-white/10 rounded-2xl p-6 text-white text-lg placeholder-white/20 focus:border-blue-500/50 focus:outline-none resize-none transition-all"
                    placeholder="What's on your mind?"
                  ></textarea>
                  <div class="absolute bottom-4 right-4 text-xs text-white/20 font-mono">
                    <span id="note-char-count-responsive">0</span>/500
                  </div>
                </div>
                
                <div class="flex gap-4 mt-8 pb-4">
                  <button
                    type="button"
                    phx-click="close_note_modal"
                    class="flex-1 btn-aether"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="flex-1 btn-aether btn-aether-primary"
                  >
                    Post
                  </button>
                </div>
              </form>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
