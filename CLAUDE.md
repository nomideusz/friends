# CLAUDE.md - AI Assistant Guide for Friends Codebase

Last Updated: 2025-12-20

## Project Overview

**Friends** is a revolutionary social network built on the principle that authentication should be social, not technical. Users authenticate using WebAuthn/FIDO2 passkeys, with social recovery mechanisms where friends verify identity rather than relying on passwords or email verification.

### Core Vision
- **No passwords, no emails, no verification codes** - Just passkeys and social verification
- **Authentication is social** - Your identity is vouched for by people who know you
- **Invite-only network** - Requires friends to use it, creating genuine network effects
- **Simple UX** - "Just type your name" and you're in

### Key Features
- Photo & note sharing in rooms
- Real-time updates via Phoenix PubSub
- End-to-end encrypted messaging
- Voice notes with waveform visualization
- WebAuthn/FIDO2 authentication
- Social account recovery (4 of 5 trusted friends)
- Device linking via QR codes
- Progressive Web App (PWA) support

## Tech Stack

### Backend
- **Elixir ~> 1.15**
- **Phoenix ~> 1.8.1**
- **Phoenix LiveView ~> 1.1.0**
- **LiveSvelte ~> 0.16.0** - Svelte 5 integration
- **PostgreSQL** - Shared database (`rzeczywiscie_dev`)
- **Ecto 3.13** - ORM
- **Bandit 1.5** - HTTP server

### Frontend
- **Svelte 5** - Interactive components
- **Tailwind CSS v4** - Styling
- **esbuild 0.27** - JavaScript bundling
- **D3.js 7.9** - Graph visualizations
- **JavaScript Modules** - WebAuthn, crypto, voice recording

### Infrastructure
- **MinIO/S3** - Media storage (photos, voice notes)
- **ExAws** - AWS SDK for Elixir
- **Image (libvips)** - Thumbnail generation (production only, Linux)
- **CBOR** - WebAuthn attestation decoding

## Architecture Overview

### Project Structure

```
friends/
├── lib/
│   ├── friends/
│   │   ├── application.ex           # App supervisor
│   │   ├── social.ex                # Main context facade
│   │   ├── social/                  # Business logic & schemas
│   │   │   ├── user.ex, room.ex, photo.ex, message.ex (Schemas)
│   │   │   ├── rooms.ex, photos.ex, notes.ex, chat.ex (Logic)
│   │   │   ├── relationships.ex     # Friendships & recovery
│   │   │   └── presence.ex          # Real-time presence tracking
│   │   ├── storage.ex               # S3/MinIO integration
│   │   ├── webauthn.ex              # FIDO2 authentication
│   │   └── image_processor.ex       # Thumbnail generation
│   └── friends_web/
│       ├── endpoint.ex, router.ex
│       ├── live/
│       │   ├── home_live.ex         # Main app (modular dispatcher)
│       │   ├── home_live/
│       │   │   ├── components/      # UI components
│       │   │   ├── events/          # Event handler modules
│       │   │   ├── lifecycle.ex     # Mount/params logic
│       │   │   ├── pub_sub_handlers.ex  # PubSub message handlers
│       │   │   └── helpers.ex       # Utilities
│       │   ├── auth_live.ex         # Login/register unified
│       │   ├── hooks/user_auth.ex   # LiveView auth hook
│       │   └── [other_live].ex      # Devices, Network, Graph, etc.
│       ├── plugs/user_session.ex    # Cookie→session sync
│       └── components/              # Shared components
├── assets/
│   ├── svelte/                      # Svelte 5 components
│   ├── js/                          # JavaScript modules
│   ├── css/app.css                  # Tailwind styles
│   └── build.js                     # esbuild config
├── priv/
│   ├── repo/migrations/             # Database migrations
│   └── static/                      # Compiled assets
├── config/
│   ├── config.exs                   # Base config
│   ├── dev.exs                      # Development
│   ├── prod.exs                     # Production
│   └── runtime.exs                  # Runtime (env vars)
└── test/                            # Tests (minimal currently)
```

### Architectural Patterns

#### 1. Facade Pattern
`Friends.Social` is the main context that delegates to specialized sub-modules:
- `Social.Rooms` - Room lifecycle, access control, membership
- `Social.Photos` - Photo upload, storage, galleries
- `Social.Notes` - Text & voice notes
- `Social.Chat` - E2E encrypted messaging
- `Social.Relationships` - Friendships, trust, recovery

#### 2. Event-Driven Architecture
Heavy use of Phoenix PubSub for real-time updates:
- Room-specific topics: `"friends:room:#{room_code}"`
- User-specific topics: `"friends:user:#{user_id}"`
- Global presence: `"friends:presence:global"`
- Public feed: `"friends:public_feed:#{user_id}"`

#### 3. Modular LiveView
`HomeLive` is a thin dispatcher that delegates to specialized modules:
- **Lifecycle**: Mount & param handling
- **Events**: Domain-specific event handlers (PhotoEvents, ChatEvents, etc.)
- **PubSubHandlers**: Real-time broadcast processing
- **Components**: Reusable UI components

#### 4. Client-Server Optimization
Images are optimized client-side before upload:
- Thumbnails generated (600px, JPEG 0.7 quality)
- Images optimized (1200px max, JPEG 0.85 quality)
- Server generates additional variants (thumb, medium, large)

## Database Schema

### User & Identity Tables

**friends_users**
- `id` - Primary key
- `username` - Unique username (lowercase)
- `display_name` - Display name (original case)
- `user_color` - Hex color for avatar/presence
- `status` - "active" or other states
- `recovery_*` fields - Recovery flow state
- `is_admin` - Admin flag
- `public_key_fingerprint` - Legacy crypto auth

**friends_user_devices**
- Device fingerprinting for recovery hints
- `fingerprint` - Unique device fingerprint
- `public_key_fingerprint` - Device public key
- `is_trusted` - Trusted device flag
- `device_name` - Human-readable name

**friends_webauthn_credentials**
- WebAuthn/FIDO2 passkey storage
- `credential_id` - Unique credential ID (Base64)
- `public_key` - COSE public key (binary)
- `sign_count` - Signature counter (replay protection)
- `transports` - ["usb", "nfc", "ble", "internal"]

### Social Graph Tables

**friends_friendships**
- `user_id`, `friend_user_id` - Friend relationship
- `status` - "pending", "accepted", "declined"

**friends_trusted_friends**
- Recovery circle (4-5 trusted friends)
- `user_id`, `trusted_user_id`
- `confirmed_at` - When trusted friend confirmed

**friends_invites**
- Invite codes for new user registration
- `code` - Unique invite code
- `created_by_id` - User who created invite
- `used_by_id` - User who used invite
- `expires_at` - Expiration timestamp

### Content Tables

**friends_rooms**
- `code` - Unique room code (URL-safe)
- `name` - Room display name
- `is_private` - Boolean (private vs public)
- `room_type` - "public", "private", "dm"
- `owner_id` - Room creator

**friends_room_members**
- `room_id`, `user_id` - Membership
- `role` - "owner", "admin", "member"
- `joined_at` - Timestamp

**friends_photos**
- `image_url_original`, `image_url_thumb`, `image_url_medium`, `image_url_large`
- `batch_id` - Groups photos uploaded together (galleries)
- `pinned_at` - Admin can pin photos
- `content_type` - "image/jpeg" or "audio/encrypted" (voice notes)
- `duration` - Audio duration in seconds

**friends_text_cards** (Notes)
- `content` - Note text (supports markdown)
- `room_id` - Room association
- `pinned_at` - Admin can pin notes

**friends_messages** (E2E Encrypted)
- `encrypted_content` - AES-GCM encrypted message
- `nonce` - Encryption nonce
- `content_type` - "text", "audio", etc.
- `metadata` - JSON metadata (duration, waveform)

**friends_conversations**
- `type` - "direct" (1:1 DM)
- `participant_count` - Number of participants

**friends_conversation_participants**
- `conversation_id`, `user_id`
- `last_read_at` - Last read timestamp
- `unread_count` - Unread message count

## Code Conventions & Patterns

### Module Naming

- **Contexts**: `Friends.Social`, `Friends.Storage`, `Friends.WebAuthn`
- **Schemas**: `Friends.Social.User`, `Friends.Social.Room`
- **LiveViews**: `FriendsWeb.HomeLive`, `FriendsWeb.AuthLive`
- **Event Handlers**: `FriendsWeb.HomeLive.Events.PhotoEvents`
- **Components**: `FriendsWeb.HomeLive.Components.FluidFeedComponents`

### LiveView Event Handling

**Pattern**: Main LiveView delegates to event modules

```elixir
# In home_live.ex
def handle_event("delete_photo", %{"id" => id}, socket) do
  PhotoEvents.delete_photo(socket, id)
end

# In events/photo_events.ex
def delete_photo(socket, id) do
  Social.delete_photo(id, socket.assigns.room.code)
  {:noreply, stream_delete(socket, :items, %{id: id})}
end
```

**Event Naming Conventions**:
- Actions: `"delete_photo"`, `"save_note"`, `"send_message"`
- UI state: `"toggle_modal"`, `"open_settings"`, `"close_drawer"`
- Data updates: `"update_name_input"`, `"set_feed_view"`

### PubSub Patterns

**Broadcasting with Session Exclusion** (avoid echo):
```elixir
# In Social module
def broadcast(room_code, event_type, payload, exclude_session_id \\ nil) do
  message = {event_type, payload, exclude_session_id}
  Phoenix.PubSub.broadcast(Friends.PubSub, "friends:room:#{room_code}", message)
end
```

**Topic Structure**:
- `"friends:room:#{room_code}"` - Room events (photos, notes, messages)
- `"friends:user:#{user_id}"` - User events (room creation, friend requests)
- `"friends:public_feed:#{user_id}"` - User's public feed updates
- `"friends:presence:global"` - App-wide online/offline presence
- `"friends:new_users"` - New user registrations (for constellation graph)
- `"room:#{room_id}:typing"` - Typing indicators

**Handling in LiveView**:
```elixir
# In lifecycle.ex (mount)
if connected?(socket) do
  Phoenix.PubSub.subscribe(Friends.PubSub, "friends:room:#{room_code}")
  Phoenix.PubSub.subscribe(Friends.PubSub, "friends:presence:global")
end

# In pub_sub_handlers.ex
def handle_info({:new_photo, photo, session_id}, socket) do
  if session_id != socket.assigns.session_id do
    {:noreply, stream_insert(socket, :items, photo, at: 0)}
  else
    {:noreply, socket}
  end
end
```

### Stream Usage (Not Assigns!)

For dynamic lists (photos, notes, messages), use streams for efficient updates:

```elixir
# In mount
socket = stream(socket, :items, items, reset: true)

# Insert new item
socket = stream_insert(socket, :items, new_item, at: 0)

# Delete item
socket = stream_delete(socket, :items, item)

# In template
<div id="items" phx-update="stream">
  <%= for {id, item} <- @streams.items do %>
    <div id={id}>...</div>
  <% end %>
</div>
```

### File Upload Pattern

```elixir
# In mount/lifecycle
socket = allow_upload(socket, :photo,
  accept: ~w(.jpg .jpeg .png .gif .webp .heic),
  max_entries: 10,
  max_file_size: 50_000_000,
  auto_upload: true
)

# Handle upload completion
def handle_event("save_photo", params, socket) do
  uploaded_files = consume_uploaded_entries(socket, :photo, fn %{path: path}, entry ->
    # Process file
    {:ok, url} = Storage.upload(path, entry.client_name)
    url
  end)

  {:noreply, socket}
end
```

### User ID Normalization

**CRITICAL**: User IDs can be integer or string format. Always normalize:

```elixir
# Normalize to integer
user_id = case user_id do
  "user-" <> id_str -> String.to_integer(id_str)
  id when is_binary(id) -> String.to_integer(id)
  id when is_integer(id) -> id
end

# Or use helper
def normalize_user_id("user-" <> id), do: String.to_integer(id)
def normalize_user_id(id) when is_binary(id), do: String.to_integer(id)
def normalize_user_id(id) when is_integer(id), do: id
```

## Frontend Architecture

### LiveSvelte Integration

**Mounting Svelte 5 Components**:
```javascript
// In app.js hooks
Hooks.ConstellationGraph = {
  mounted() {
    import("../svelte/ConstellationGraph.svelte").then(({ default: Component }) => {
      this.component = mount(Component, {
        target: this.el,
        props: {
          users: JSON.parse(this.el.dataset.users),
          live: this  // Pass LiveView hook for pushEvent
        }
      });
    });
  },
  destroyed() {
    this.component?.$destroy();
  }
}
```

**Communication Patterns**:
- **LiveView → Svelte**: Via `phx-update="ignore"` + data attributes + props
- **Svelte → LiveView**: Via `this.pushEvent()` passed as `live` prop

### JavaScript Modules

**Key Modules** (`/assets/js/`):

1. **`webauthn.js`** - WebAuthn credential registration/authentication
   - `registerCredential(challenge)` - Register new passkey
   - `authenticateCredential(challenge)` - Authenticate with passkey

2. **`message-encryption.js`** - E2E encryption using AES-GCM
   - `generateConversationKey()` - Generate symmetric key
   - `encryptMessage(message, key)` - Encrypt plaintext
   - `decryptMessage(encrypted, nonce, key)` - Decrypt ciphertext

3. **`voice-recorder.js`** - MediaRecorder API for voice notes
   - `startRecording()` - Begin audio capture
   - `stopRecording()` - Stop & return Blob
   - Supports waveform visualization

4. **`device-attestation.js`** - Device fingerprinting
   - Canvas fingerprinting
   - WebGL renderer detection
   - Browser and OS detection

5. **`crypto-identity.js`** - Legacy crypto key generation
   - Mostly replaced by WebAuthn
   - Still used for device linking

### LiveView Hooks

**Common Hooks** (`Hooks` object in `app.js`):

- **`FriendsApp`** - Main app hook (identity, sign out, image optimization)
- **`WebAuthnAuth`** - Unified auth hook for login/register
- **`VoiceWaveform`** - Audio waveform visualization using Canvas
- **`PhotoModal`** - Image modal with swipe gestures and keyboard navigation
- **`RoomChatEncryption`** - Encrypts room messages before sending
- **`ConstellationGraph`** - Mounts Svelte constellation graph component
- **`FriendGraph`** - Mounts Svelte friend graph component

## Authentication & Security

### WebAuthn Flow

**Registration** (`/auth` with username):
1. User enters username
2. Server generates challenge
3. Client calls `navigator.credentials.create()`
4. Server verifies attestation object (CBOR)
5. Store credential in `friends_webauthn_credentials`
6. Set session cookie

**Login** (`/auth` without username):
1. Server generates challenge
2. Client calls `navigator.credentials.get()`
3. Server verifies assertion
4. Verify sign count (replay protection)
5. Set session cookie

**Session Management**:
- Cookie: `friends_user_id` (365 days)
- Session token: `friends_session_token` (30 days)
- Plug: `UserSession` syncs cookie to session for fast initial render
- Hook: `Hooks.UserAuth` loads user data on LiveView mount

### Social Recovery

**Recovery Circle Setup**:
- User selects 4-5 trusted friends
- Trusted friends confirm participation
- Stored in `friends_trusted_friends`

**Recovery Process**:
1. User initiates recovery (`/recover`)
2. Device fingerprint collected (recovery hints)
3. 4 of 5 trusted friends vote to confirm identity
4. Votes stored in `friends_recovery_votes`
5. Once threshold met, user can register new credential

### E2E Encryption

**Demo Implementation** (conversation-based keys):
```javascript
// Generate conversation key (stored locally)
const key = await generateConversationKey();

// Encrypt message
const { encrypted, nonce } = await encryptMessage(message, key);

// Send to server
pushEvent("send_message", { encrypted, nonce });

// Decrypt received message
const plaintext = await decryptMessage(encrypted, nonce, key);
```

**Security Notes**:
- Current implementation is a demo/POC
- Keys stored in localStorage (not ideal for production)
- No key exchange mechanism yet
- Future: Use WebCrypto for key derivation + secure storage

## Development Workflows

### Initial Setup

```bash
# Install Elixir dependencies
mix deps.get

# Install Node dependencies
cd assets && npm install

# Create & migrate database
mix ecto.setup

# Start Phoenix server
mix phx.server
```

Server runs on `http://localhost:4001`

### Database Setup

**Important**: This app shares the database with another project (`rzeczywiscie_dev`).

```bash
# Reset database
mix ecto.reset

# Run migrations
mix ecto.migrate

# Rollback
mix ecto.rollback

# Seed data (if needed)
mix run priv/repo/seeds.exs
```

### Asset Development

**Watch Mode** (auto-rebuild):
```bash
# Phoenix handles watchers automatically
mix phx.server

# Watchers configured in config/dev.exs:
# - Tailwind CSS
# - esbuild (JavaScript + Svelte)
```

**Manual Build**:
```bash
cd assets
npm run build         # Development build
npm run deploy        # Production build (minified)
```

### Testing

```bash
mix test              # Run all tests
mix test path/to/test # Run specific test
```

**Note**: Tests are minimal currently. Test setup is standard ExUnit.

### Deployment

```bash
# Production build
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release

# Docker
docker build -t friends .
docker run -p 4000:4000 friends
```

**Environment Variables** (see `config/runtime.exs`):
- `DATABASE_URL` - PostgreSQL connection string
- `SECRET_KEY_BASE` - Phoenix secret
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` - S3 credentials
- `S3_BUCKET`, `S3_REGION`, `S3_ENDPOINT` - S3 config
- `WEBAUTHN_RP_ID`, `WEBAUTHN_ORIGIN` - WebAuthn relying party config

## Common Tasks for AI Assistants

### Adding a New Feature to a Room

1. **Add Schema/Migration** (if database changes needed)
   ```bash
   mix ecto.gen.migration add_new_feature
   ```

2. **Add Logic to Context** (`lib/friends/social/feature.ex`)
   ```elixir
   defmodule Friends.Social.Features do
     def create_feature(attrs, room_code) do
       # Insert into database
       # Broadcast to room
       Social.broadcast(room_code, :new_feature, feature)
     end
   end
   ```

3. **Add Event Handler** (`lib/friends_web/live/home_live/events/feature_events.ex`)
   ```elixir
   defmodule FriendsWeb.HomeLive.Events.FeatureEvents do
     def create(socket, attrs) do
       case Social.create_feature(attrs, socket.assigns.room.code) do
         {:ok, feature} ->
           {:noreply, stream_insert(socket, :features, feature, at: 0)}
         {:error, _} ->
           {:noreply, socket}
       end
     end
   end
   ```

4. **Wire Up in HomeLive** (`lib/friends_web/live/home_live.ex`)
   ```elixir
   def handle_event("create_feature", attrs, socket) do
     FeatureEvents.create(socket, attrs)
   end
   ```

5. **Add PubSub Handler** (`lib/friends_web/live/home_live/pub_sub_handlers.ex`)
   ```elixir
   def handle_info({:new_feature, feature, session_id}, socket) do
     if session_id != socket.assigns.session_id do
       {:noreply, stream_insert(socket, :features, feature, at: 0)}
     else
       {:noreply, socket}
     end
   end
   ```

6. **Add UI Component** (`lib/friends_web/live/home_live/components/feature_components.ex`)
   ```elixir
   def feature_card(assigns) do
     ~H"""
     <div class="feature">
       <%= @feature.content %>
     </div>
     """
   end
   ```

### Modifying Authentication Flow

1. **Update WebAuthn Logic** (`lib/friends/webauthn.ex`)
2. **Update AuthLive** (`lib/friends_web/live/auth_live.ex`)
3. **Update JavaScript** (`assets/js/webauthn.js`)
4. **Test thoroughly** - auth is critical!

### Adding Real-time Features

1. **Choose PubSub Topic** (or create new one)
2. **Subscribe in Lifecycle** (`lifecycle.ex`)
   ```elixir
   Phoenix.PubSub.subscribe(Friends.PubSub, "friends:new_topic")
   ```
3. **Broadcast from Context**
   ```elixir
   Phoenix.PubSub.broadcast(Friends.PubSub, "friends:new_topic", {:event, data})
   ```
4. **Handle in PubSubHandlers** (`pub_sub_handlers.ex`)
   ```elixir
   def handle_info({:event, data}, socket) do
     # Update socket state
     {:noreply, assign(socket, data: data)}
   end
   ```

### Updating Database Schema

1. **Generate Migration**
   ```bash
   mix ecto.gen.migration update_table_name
   ```

2. **Edit Migration** (`priv/repo/migrations/TIMESTAMP_update_table_name.exs`)
   ```elixir
   def change do
     alter table(:friends_table) do
       add :new_field, :string
       modify :existing_field, :text
       remove :old_field
     end

     create index(:friends_table, [:new_field])
   end
   ```

3. **Update Schema** (`lib/friends/social/table.ex`)
   ```elixir
   schema "friends_table" do
     field :new_field, :string
     # Remove old_field
   end

   def changeset(struct, attrs) do
     struct
     |> cast(attrs, [:new_field])
     |> validate_required([:new_field])
   end
   ```

4. **Run Migration**
   ```bash
   mix ecto.migrate
   ```

## Important Gotchas & Constraints

### Database Sharing
- **Critical**: This app shares the database with `rzeczywiscie` project
- All tables prefixed with `friends_`
- Be careful with database-wide operations

### User ID Format Gotcha
- User IDs can be integer or `"user-#{id}"` string format
- Always normalize before database queries
- See "User ID Normalization" section above

### Image Processing Platform Limitation
- **Windows**: `Image` library (libvips) not supported
- Graceful fallback to client-side thumbnails only
- **Production/Linux**: Server-side thumbnail generation works

### WebAuthn Requirements
- **HTTPS required** in production (except localhost)
- Relying Party ID must match domain
- Origin must match exactly (protocol + domain + port)
- Configure `WEBAUTHN_RP_ID` and `WEBAUTHN_ORIGIN` environment variables

### Admin Features
- Admin usernames configured in `config/config.exs`: `admin_usernames: ["nom"]`
- Admins can pin/unpin content
- Admin invite code: `"ADMIN"` (bypasses normal invite system)

### Invite System
- **Invite-only network** by design
- Users must have an invite code to register
- Invite codes created by existing users or admins
- One-time use codes (tracked in `friends_invites`)

### S3/MinIO Configuration
- **Development**: MinIO on `localhost:9000`
- **Production**: Configurable via environment variables
- Files uploaded with `public-read` ACL
- Multiple variants stored (original, thumb, medium, large)

### LiveView Streams vs Assigns
- **Use streams** for dynamic lists (photos, notes, messages)
- **Use assigns** for single values (room, user, settings)
- Streams provide efficient DOM patching for large lists
- Don't mix streams and assigns for the same data

### PubSub Session Exclusion
- Always pass `session_id` when broadcasting
- Check `session_id` in handlers to avoid echo
- Prevents user seeing duplicate updates from their own actions

### Presence Tracking
- Two types: room presence and global presence
- Room presence: per-room viewer tracking
- Global presence: app-wide online/offline status
- Metadata includes `user_id`, `user_color`, `user_name`

### Voice Notes as Photos
- Voice notes stored as photos with `content_type: "audio/encrypted"`
- Encrypted with AES-GCM (E2E encrypted)
- Waveform data stored in metadata JSON
- Duration stored in seconds

### Batch Uploads (Galleries)
- Photos uploaded together share `batch_id` (UUID)
- Displayed as galleries in UI
- All photos in batch share same timestamp
- Used for multi-photo posts

### Design Philosophy Constraints
- **Minimal, text-based interface** - No unnecessary icons
- **No emojis in UI** - Text-only aesthetic
- **Monospace typography** - Consistent with design
- **Dark theme** - Primary color scheme
- **Fast, responsive** - Performance is key

## Code Style Guidelines

### Elixir Style
- Follow standard Elixir conventions
- Use `.formatter.exs` configuration
- Format code: `mix format`
- Prefer pattern matching over conditionals
- Use `with` for nested success cases
- Pipe operator for data transformations

### LiveView Style
- Keep `*_live.ex` files thin (delegates only)
- Domain logic in context modules (`Social.*`)
- Event handlers in `events/` modules
- PubSub handlers in `pub_sub_handlers.ex`
- UI components in `components/` modules
- Lifecycle logic in `lifecycle.ex`

### JavaScript Style
- ES6+ modules
- Async/await for promises
- Clear function names
- Document security-critical code (crypto, auth)
- Use hooks for DOM interactions

### Testing Style
- ExUnit for backend tests
- Test contexts, not LiveViews directly
- Mock PubSub broadcasts where needed
- Integration tests for critical flows (auth, recovery)

## Documentation References

- **README.md** - Project overview, vision, setup
- **AUTHENTICATION_ENHANCEMENTS.md** - Auth features implementation details
- **WEBAUTHN_SIGNOUT.md** - WebAuthn sign-out flow documentation
- **Phoenix Guides** - https://hexdocs.pm/phoenix/
- **LiveView Docs** - https://hexdocs.pm/phoenix_live_view/
- **LiveSvelte** - https://hexdocs.pm/live_svelte/

## Key Takeaways for AI Assistants

1. **Always use `Friends.Social` facade** - Don't access Repo directly
2. **PubSub for real-time** - Broadcast all state changes
3. **Modular LiveView** - Delegate to `Events.*` and `PubSubHandlers`
4. **Streams for lists** - Never assigns for dynamic collections
5. **Normalize user IDs** - Handle both integer and string formats
6. **Session exclusion** - Pass `session_id` to avoid echo
7. **WebAuthn primary** - Passkeys are the main authentication method
8. **E2E encryption** - Messages and voice notes are encrypted
9. **Batch operations** - Photos uploaded together share `batch_id`
10. **Admin features** - Pinning, special access (configured in config)
11. **Invite-only** - Users need invite codes to register
12. **Design constraints** - Minimal, text-based, monospace, dark
13. **Database shared** - All tables prefixed with `friends_`
14. **Image variants** - Multiple sizes stored (thumb, medium, large, original)
15. **Platform limitations** - Image processing only on Linux production

---

**When in doubt, check the existing patterns in the codebase. This is a well-structured Phoenix LiveView application with clear conventions. Follow the established patterns for consistency.**
