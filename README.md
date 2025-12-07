Friends: The App
The Vision:
A social network so simple your grandmother could use it. No passwords, no emails, no verification codes. Just type your name once per device and you're in. If you lose access, your actual friends verify it's you.
Core mechanic:

Authentication is social, not technical
Your identity is vouched for by people who know you
A network called "Friends" that literally requires friends to work


Recommended Technical Approach
Authentication
First visit:

User enters username
Browser generates cryptographic keypair (invisible)
Private key stored in browser (IndexedDB + localStorage)
Device fingerprint collected (hidden, for recovery hints)
Done

Return visits:

Automatic sign-in (browser has the key)

Lost access:

4 out of 5 trusted friends confirm your identity
Device fingerprint helps determine recovery difficulty (familiar device = easier)

Key Features

Username-only (no email, no password)
Browser-based crypto keys
Hidden device fingerprinting for recovery assistance
Social recovery circle (4-5 friends)
Multi-browser linking via QR code
Invite-only to prevent spam/bots

Why It Works
Simple: "Just type your name"
Secure: Can't phish what doesn't exist
Human: Trust friends, not corporations
Viral: Need friends to use it, creates network effects
The constraint becomes the feature: you literally need friends.

## Features

- **Photo sharing** - Upload and share photos in rooms
- **Notes** - Share text notes with friends
- **Rooms** - Create private spaces to share with specific people
- **Real-time** - Live updates when others share content
- **No auth** - Device fingerprint based identity, no accounts needed

## Design Philosophy

- Minimal, text-based interface
- No icons, no emojis in UI
- Monospace typography
- Dark theme
- Fast, responsive

## Setup

```bash
# Install dependencies
mix deps.get
cd assets && npm install

# Start the server
mix phx.server
```

Server runs on http://localhost:4001

## Database

This app shares the database with rzeczywiscie (rzeczywiscie_dev).

## Tech Stack

- Phoenix 1.8 + LiveView
- LiveSvelte for Svelte components
- Tailwind CSS v4
- PostgreSQL

