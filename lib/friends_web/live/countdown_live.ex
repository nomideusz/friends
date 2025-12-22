defmodule FriendsWeb.CountdownLive do
  @moduledoc """
  Countdown to New Internet launch on January 1st, 2026 00:00 Warsaw time.
  Server-time based countdown with real-time updates via Phoenix LiveView.
  """
  use FriendsWeb, :live_view

  @launch_datetime ~U[2025-12-31 23:00:00Z]  # Jan 1, 2026 00:00 Warsaw (UTC+1)

  @impl true
  def mount(_params, session, socket) do
    # If already logged in, redirect to home
    if session["user_id"] do
      {:ok, socket |> redirect(to: "/")}
    else
      if connected?(socket) do
        # Update countdown every second
        schedule_tick()
      end

      {:ok,
       socket
       |> assign(:page_title, "New Internet")
       |> assign_countdown()}
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    schedule_tick()
    {:noreply, assign_countdown(socket)}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, 1000)
  end

  defp assign_countdown(socket) do
    now = DateTime.utc_now()
    diff = DateTime.diff(@launch_datetime, now, :second)

    if diff <= 0 do
      # Launch has happened, redirect to auth
      assign(socket,
        days: 0,
        hours: 0,
        minutes: 0,
        seconds: 0,
        launched: true
      )
    else
      days = div(diff, 86400)
      remaining = rem(diff, 86400)
      hours = div(remaining, 3600)
      remaining = rem(remaining, 3600)
      minutes = div(remaining, 60)
      seconds = rem(remaining, 60)

      assign(socket,
        days: days,
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        launched: false
      )
    end
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center p-4 relative overflow-hidden">
      <div class="opal-bg"></div>

      <div class="w-full max-w-4xl relative z-10">
        <%= if @launched do %>
          <div class="text-center animate-fade-in">
            <h1 class="text-5xl md:text-7xl font-bold text-white mb-6" style="text-shadow: 0 0 60px rgba(255,255,255,0.4), 0 0 120px rgba(255,255,255,0.2);">
              Welcome to the New Internet
            </h1>
            <p class="text-neutral-400 text-lg">Redirecting...</p>
          </div>
        <% else %>
          <div class="text-center space-y-8">
            <!-- Title -->
            <div class="mb-12">
              <h1 class="text-4xl md:text-6xl font-bold text-white mb-4" style="text-shadow: 0 0 60px rgba(255,255,255,0.4), 0 0 120px rgba(255,255,255,0.2); animation: gentle-pulse 3s ease-in-out infinite;">
                New Internet
              </h1>
              <p class="text-neutral-400 text-sm md:text-base uppercase tracking-wider font-mono">
                Launching Soon
              </p>
            </div>

            <!-- Countdown Display -->
            <div class="grid grid-cols-4 gap-4 md:gap-8 max-w-3xl mx-auto">
              <!-- Days -->
              <div class="countdown-unit">
                <div class="countdown-value">
                  <%= String.pad_leading(Integer.to_string(@days), 2, "0") %>
                </div>
                <div class="countdown-label">Days</div>
              </div>

              <!-- Hours -->
              <div class="countdown-unit">
                <div class="countdown-value">
                  <%= String.pad_leading(Integer.to_string(@hours), 2, "0") %>
                </div>
                <div class="countdown-label">Hours</div>
              </div>

              <!-- Minutes -->
              <div class="countdown-unit">
                <div class="countdown-value">
                  <%= String.pad_leading(Integer.to_string(@minutes), 2, "0") %>
                </div>
                <div class="countdown-label">Minutes</div>
              </div>

              <!-- Seconds -->
              <div class="countdown-unit">
                <div class="countdown-value animate-pulse-subtle">
                  <%= String.pad_leading(Integer.to_string(@seconds), 2, "0") %>
                </div>
                <div class="countdown-label">Seconds</div>
              </div>
            </div>

            <!-- Launch Date -->
            <div class="mt-12">
              <p class="text-neutral-500 text-xs md:text-sm uppercase tracking-widest font-mono">
                January 1st, 2026 • 00:00 Warsaw Time
              </p>
            </div>
          </div>
        <% end %>
      </div>
    </div>

    <style>
      @keyframes gentle-pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.7; }
      }

      @keyframes pulse-subtle {
        0%, 100% { opacity: 1; transform: scale(1); }
        50% { opacity: 0.9; transform: scale(0.98); }
      }

      .countdown-unit {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.75rem;
      }

      .countdown-value {
        font-family: var(--font-family-mono);
        font-size: clamp(2.5rem, 8vw, 5rem);
        font-weight: 700;
        line-height: 1;
        color: white;
        text-shadow:
          0 0 40px rgba(255,255,255,0.3),
          0 0 80px rgba(255,255,255,0.1);
        background: linear-gradient(180deg,
          rgba(255,255,255,1) 0%,
          rgba(255,255,255,0.8) 100%
        );
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        background-clip: text;
        padding: 1rem;
        border-radius: 1rem;
        backdrop-filter: blur(10px);
        border: 1px solid rgba(255,255,255,0.1);
        min-width: 120px;
        transition: all 0.3s var(--ease-fluid);
      }

      @media (max-width: 768px) {
        .countdown-value {
          min-width: 70px;
          padding: 0.5rem;
        }
      }

      .countdown-label {
        font-family: var(--font-family-mono);
        font-size: 0.75rem;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        color: rgba(255,255,255,0.5);
        font-weight: 500;
      }

      .animate-pulse-subtle {
        animation: pulse-subtle 1s ease-in-out infinite;
      }

      .animate-fade-in {
        animation: fadeIn 1s ease-in-out;
      }

      @keyframes fadeIn {
        from { opacity: 0; transform: translateY(20px); }
        to { opacity: 1; transform: translateY(0); }
      }
    </style>
    """
  end
end
