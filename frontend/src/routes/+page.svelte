<script lang="ts">
    import { api } from "$lib/phoenix";
    import { onMount } from "svelte";
    import {
        user,
        isAuthenticated,
        isLoading,
        authError,
        register,
        login,
        initAuth,
    } from "$lib/stores/auth";
    import { isWebAuthnSupported } from "$lib/webauthn";

    let friends: any[] = [];
    let rooms: any[] = [];
    let dataLoading = true;
    let username = "";
    let authMode: "login" | "register" = "login";

    onMount(async () => {
        // Check if already authenticated
        await initAuth();

        if ($user) {
            await loadUserData();
        }
        dataLoading = false;
    });

    async function loadUserData() {
        try {
            const [friendsResponse, roomsResponse] = await Promise.all([
                api.getFriends().catch(() => ({ friends: [] })),
                api.getRooms().catch(() => ({ rooms: [] })),
            ]);
            friends = friendsResponse?.friends || [];
            rooms = roomsResponse?.rooms || [];
        } catch (e) {
            console.error("Failed to load data:", e);
        }
    }

    async function handleAuth() {
        if (!username.trim()) return;

        const success =
            authMode === "register"
                ? await register(username.trim())
                : await login(username.trim());

        if (success) {
            await loadUserData();
        }
    }

    function toggleMode() {
        authMode = authMode === "login" ? "register" : "login";
        authError.set(null);
    }
</script>

<div class="home">
    {#if dataLoading}
        <div class="loading-state">
            <div class="spinner"></div>
            <p class="text-muted">Loading your space...</p>
        </div>
    {:else if $user}
        <!-- Authenticated Dashboard -->
        <section class="hero">
            <h1>
                Welcome back, <span class="gradient"
                    >{$user.display_name || $user.username}</span
                >
            </h1>
            <p class="text-muted">Your personal corner of the New Internet</p>
        </section>

        <div class="dashboard">
            <!-- User Card -->
            <section class="aether-card user-card">
                <div
                    class="avatar avatar-online"
                    style="color: var(--color-accent)"
                >
                    {#if $user.avatar_url}
                        <img src={$user.avatar_url} alt={$user.display_name} />
                    {:else}
                        <div class="avatar-placeholder">
                            {$user.username?.[0]?.toUpperCase() || "?"}
                        </div>
                    {/if}
                </div>
                <div class="user-info">
                    <h2>{$user.display_name || $user.username}</h2>
                    <p class="text-muted">@{$user.username}</p>
                </div>
            </section>

            <!-- Friends -->
            <section class="aether-card">
                <h3>
                    Friends <span class="fluid-label">({friends.length})</span>
                </h3>
                {#if friends.length === 0}
                    <p class="text-muted-subtle">
                        No friends yet. Explore the network to connect!
                    </p>
                {:else}
                    <ul class="list">
                        {#each friends.slice(0, 5) as friend}
                            <li class="list-item glass-surface">
                                <div class="friend-avatar">
                                    {friend.username?.[0]?.toUpperCase() || "?"}
                                </div>
                                <span
                                    >{friend.display_name ||
                                        friend.username}</span
                                >
                            </li>
                        {/each}
                    </ul>
                {/if}
                <a href="/graph" class="link">View network →</a>
            </section>

            <!-- Rooms -->
            <section class="aether-card">
                <h3>Rooms <span class="fluid-label">({rooms.length})</span></h3>
                {#if rooms.length === 0}
                    <p class="text-muted-subtle">
                        No rooms yet. Create one to get started!
                    </p>
                {:else}
                    <ul class="list">
                        {#each rooms.slice(0, 5) as room}
                            <li class="list-item glass-surface">
                                <span class="room-icon">#</span>
                                <span>{room.name || room.code}</span>
                            </li>
                        {/each}
                    </ul>
                {/if}
            </section>
        </div>
    {:else}
        <!-- Guest / Auth View -->
        <section class="hero">
            <h1>Welcome to the <span class="gradient">New Internet</span></h1>
            <p>A space for genuine connection, not endless scrolling.</p>
        </section>

        <!-- Auth Card -->
        <section class="auth-container">
            <div class="aether-card auth-card">
                <div class="sheet-handle"><div></div></div>

                <h2>
                    {authMode === "login" ? "Welcome Back" : "Join the Network"}
                </h2>
                <p class="text-muted">
                    {authMode === "login"
                        ? "Sign in with your device"
                        : "Create your identity"}
                </p>

                {#if !isWebAuthnSupported()}
                    <div class="error-surface">
                        WebAuthn is not supported in this browser. Please use
                        Chrome, Safari, or Firefox.
                    </div>
                {:else}
                    <form on:submit|preventDefault={handleAuth}>
                        <input
                            type="text"
                            bind:value={username}
                            placeholder="Enter your username"
                            disabled={$isLoading}
                        />

                        {#if $authError}
                            <div class="error-surface">{$authError}</div>
                        {/if}

                        <button
                            type="submit"
                            class="btn-aether btn-aether-primary"
                            disabled={$isLoading || !username.trim()}
                        >
                            {#if $isLoading}
                                <span class="spinner-small"></span>
                            {:else}
                                {authMode === "login"
                                    ? "🔐 Authenticate"
                                    : "✨ Create Account"}
                            {/if}
                        </button>
                    </form>

                    <button class="mode-toggle" on:click={toggleMode}>
                        {authMode === "login"
                            ? "New here? Create an account"
                            : "Already have an account? Sign in"}
                    </button>
                {/if}
            </div>
        </section>

        <!-- Features -->
        <section class="features">
            <div class="feature aether-card">
                <span class="icon">🌐</span>
                <h4>3D Network View</h4>
                <p class="text-muted-subtle">
                    Visualize your connections in an interactive graph
                </p>
            </div>
            <div class="feature aether-card">
                <span class="icon">💬</span>
                <h4>Real-time Chat</h4>
                <p class="text-muted-subtle">
                    End-to-end encrypted conversations
                </p>
            </div>
            <div class="feature aether-card">
                <span class="icon">🔐</span>
                <h4>No Passwords</h4>
                <p class="text-muted-subtle">
                    Secure login with WebAuthn biometrics
                </p>
            </div>
        </section>
    {/if}
</div>

<style>
    .home {
        display: flex;
        flex-direction: column;
        gap: 3rem;
    }

    .hero {
        text-align: center;
        padding: 4rem 0 2rem;
    }

    .hero h1 {
        font-size: clamp(2rem, 5vw, 3rem);
        margin-bottom: 1rem;
    }

    .gradient {
        background: linear-gradient(
            135deg,
            var(--color-accent),
            var(--color-accent-pink)
        );
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        background-clip: text;
    }

    .hero > p {
        font-size: 1.25rem;
        color: var(--color-dim);
    }

    /* Loading */
    .loading-state {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 1rem;
        padding: 6rem 0;
    }

    .spinner {
        width: 40px;
        height: 40px;
        border: 3px solid rgba(255, 255, 255, 0.1);
        border-top-color: var(--color-accent);
        border-radius: 50%;
        animation: spin 1s linear infinite;
    }

    .spinner-small {
        width: 16px;
        height: 16px;
        border: 2px solid rgba(0, 0, 0, 0.2);
        border-top-color: var(--color-void);
        border-radius: 50%;
        animation: spin 1s linear infinite;
        display: inline-block;
    }

    @keyframes spin {
        to {
            transform: rotate(360deg);
        }
    }

    /* Dashboard */
    .dashboard {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
        gap: 1.5rem;
    }

    .user-card {
        display: flex;
        align-items: center;
        gap: 1.5rem;
        padding: 1.5rem;
        grid-column: 1 / -1;
    }

    .avatar img,
    .avatar-placeholder {
        width: 80px;
        height: 80px;
        border-radius: 50%;
        background: linear-gradient(
            135deg,
            var(--color-accent),
            var(--color-accent-pink)
        );
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 2rem;
        font-weight: 700;
        color: white;
        object-fit: cover;
    }

    .user-info h2 {
        margin-bottom: 0.25rem;
    }

    .aether-card {
        padding: 1.5rem;
    }

    .aether-card h3 {
        margin-bottom: 1rem;
        display: flex;
        align-items: center;
        gap: 0.5rem;
    }

    .list {
        list-style: none;
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
        margin-bottom: 1rem;
    }

    .list-item {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        padding: 0.5rem 0.75rem;
        border-radius: var(--radius-button);
        transition: all 0.3s var(--ease-fluid);
    }

    .list-item:hover {
        background: rgba(255, 255, 255, 0.08);
    }

    .friend-avatar {
        width: 32px;
        height: 32px;
        border-radius: 50%;
        background: linear-gradient(
            135deg,
            var(--color-accent),
            var(--color-accent-pink)
        );
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 0.8rem;
        font-weight: 600;
    }

    .room-icon {
        width: 32px;
        height: 32px;
        display: flex;
        align-items: center;
        justify-content: center;
        background: rgba(255, 255, 255, 0.1);
        border-radius: 8px;
        font-weight: 600;
        color: var(--color-accent);
    }

    .link {
        color: var(--color-accent);
        text-decoration: none;
        font-size: 0.9rem;
        transition: opacity 0.2s;
    }

    .link:hover {
        opacity: 0.8;
    }

    /* Auth */
    .auth-container {
        display: flex;
        justify-content: center;
    }

    .auth-card {
        width: 100%;
        max-width: 400px;
        padding: 2rem;
        text-align: center;
    }

    .auth-card h2 {
        margin-bottom: 0.5rem;
    }

    .auth-card > p {
        margin-bottom: 2rem;
    }

    form {
        display: flex;
        flex-direction: column;
        gap: 1rem;
    }

    .mode-toggle {
        margin-top: 1.5rem;
        color: var(--color-dim);
        font-size: 0.9rem;
        background: none;
        border: none;
        cursor: pointer;
        transition: color 0.2s;
    }

    .mode-toggle:hover {
        color: var(--color-light);
    }

    /* Features */
    .features {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
        gap: 1.5rem;
    }

    .feature {
        text-align: center;
        padding: 2rem 1.5rem;
    }

    .feature .icon {
        font-size: 2.5rem;
        display: block;
        margin-bottom: 1rem;
    }

    .feature h4 {
        margin-bottom: 0.5rem;
    }

    @media (max-width: 640px) {
        .hero {
            padding: 2rem 0 1rem;
        }

        .user-card {
            flex-direction: column;
            text-align: center;
        }
    }
</style>
