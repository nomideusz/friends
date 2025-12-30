<script lang="ts">
	import "../app.css";
	import { onMount } from "svelte";
	import { initSocket, connected } from "$lib/phoenix";

	onMount(() => {
		// Initialize Phoenix WebSocket connection
		initSocket();
	});
</script>

<svelte:head>
	<title>New Internet</title>
	<meta name="description" content="A new way to connect" />
</svelte:head>

<!-- Animated background -->
<div class="opal-bg"></div>

<div class="app">
	<header class="fluid-glass">
		<nav>
			<a href="/" class="logo">New Internet</a>
			<div class="nav-links">
				<a href="/">Home</a>
				<a href="/graph">Network</a>
			</div>
			<div class="connection-status" class:connected={$connected}>
				<span
					class="presence-dot"
					class:presence-dot-online={$connected}
				></span>
				{$connected ? "Connected" : "Connecting..."}
			</div>
		</nav>
	</header>

	<main>
		<slot />
	</main>
</div>

<style>
	.app {
		min-height: 100vh;
		display: flex;
		flex-direction: column;
	}

	header {
		position: sticky;
		top: 0;
		z-index: 100;
		border-bottom: 1px solid rgba(255, 255, 255, 0.08);
	}

	nav {
		max-width: 1200px;
		margin: 0 auto;
		padding: 1rem 1.5rem;
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 2rem;
	}

	.logo {
		font-family: var(--font-family-display);
		font-weight: 700;
		font-size: 1.25rem;
		background: linear-gradient(
			135deg,
			var(--color-accent),
			var(--color-accent-pink)
		);
		-webkit-background-clip: text;
		-webkit-text-fill-color: transparent;
		background-clip: text;
		text-decoration: none;
	}

	.nav-links {
		display: flex;
		gap: 1.5rem;
	}

	.nav-links a {
		color: var(--color-dim);
		text-decoration: none;
		font-size: 0.9rem;
		transition: color 0.3s var(--ease-fluid);
	}

	.nav-links a:hover {
		color: var(--color-photon);
	}

	.connection-status {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		font-size: 0.8rem;
		color: var(--color-dim);
		transition: color 0.3s var(--ease-fluid);
	}

	.connection-status .presence-dot {
		background-color: var(--color-dim);
		box-shadow: none;
	}

	.connection-status.connected {
		color: var(--color-success);
	}

	.connection-status.connected .presence-dot {
		background-color: var(--color-success);
		box-shadow: 0 0 6px 1px var(--color-success);
	}

	main {
		flex: 1;
		max-width: 1200px;
		margin: 0 auto;
		padding: 2rem 1.5rem;
		width: 100%;
	}

	@media (max-width: 640px) {
		nav {
			padding: 0.75rem 1rem;
		}

		.nav-links a {
			font-size: 0.8rem;
		}
	}
</style>
