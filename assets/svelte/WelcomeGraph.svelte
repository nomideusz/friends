<script>
    import { onMount, onDestroy } from "svelte";
    import * as d3 from "d3";
    import * as cola from "webcola";

    // Props from Phoenix LiveView
    export let graphData = null;
    export let live = null;
    export let onSkip = null;
    // Whether to hide controls and fixed positioning (for background usage)
    export let hideControls = false;
    // Current user ID for highlighting
    export let currentUserId = null;

    // Aether palette (subtle)
    const COLORS = {
        light: "#EAE6DD", // Primary text
        dim: "#888888", // Secondary
        energy: "#3B82F6", // Blue accent
        you: "#14B8A6", // Teal/cyan
        friend: "#F59E0B", // SVG/D3 references replaced with Canvas refs
    };
    let container;
    let canvas;
    let ctx;
    let width = 800;
    let height = 600;
    let transform = d3.zoomIdentity;
    let simulation;

    // Canvas optimization
    const dpi =
        typeof window !== "undefined" ? window.devicePixelRatio || 1 : 1;
    let animationFrame;

    // Image cache for avatars
    const imageCache = new Map();
    const placeholderImage = new Image();
    placeholderImage.src = "/images/default_avatar.png"; // Fallback URL

    // State for interactions
    let draggedSubject = null;
    let hoverSubject = null;

    // Data storage
    let nodesData = [];
    let linksData = [];
    let nodeMap = new Map();

    // Queue for batched updates
    let pendingUpdates = { nodes: [], links: [], removals: [] };
    let updateTimeout = null;
    const UPDATE_THROTTLE_MS = 1000;

    // Context menu state
    let showContextMenu = false;
    let contextMenuX = 0;
    let contextMenuY = 0;
    let contextMenuUser = null;

    let isMobile = false;
    let contextMenuStatus = "none"; // 'connected', 'pending', or 'none'

    // === Exported functions for live updates from LiveView ===

    // Process batched updates (called after throttle delay)
    function processPendingUpdates() {
        if (!simulation) return;

        let needsUpdate = false;

        // Process pending node additions
        for (const userData of pendingUpdates.nodes) {
            const id = String(userData.id);
            if (nodeMap.has(id)) continue;

            const newNode = {
                id: id,
                username: userData.username,
                display_name: userData.display_name || userData.username,
                avatar_url: userData.avatar_url,
                x: width / 2 + (Math.random() - 0.5) * 100,
                y: height / 2 + (Math.random() - 0.5) * 100,
            };

            // Preload image
            if (newNode.avatar_url && !imageCache.has(newNode.avatar_url)) {
                const img = new Image();
                img.src = newNode.avatar_url;
                imageCache.set(newNode.avatar_url, img);
            }

            nodesData.push(newNode);
            nodeMap.set(id, newNode);
            needsUpdate = true;
        }

        // Process pending link additions
        for (const link of pendingUpdates.links) {
            const sourceNode = nodeMap.get(String(link.fromId));
            const targetNode = nodeMap.get(String(link.toId));
            if (sourceNode && targetNode) {
                const exists = linksData.some(
                    (l) =>
                        (String(l.source.id || l.source) ===
                            String(link.fromId) &&
                            String(l.target.id || l.target) ===
                                String(link.toId)) ||
                        (String(l.source.id || l.source) ===
                            String(link.toId) &&
                            String(l.target.id || l.target) ===
                                String(link.fromId)),
                );
                if (!exists) {
                    linksData.push({ source: sourceNode, target: targetNode });
                    needsUpdate = true;
                }
            }
        }

        // Clear pending updates
        pendingUpdates = { nodes: [], links: [], removals: [] };

        if (needsUpdate) {
            // Restart simulation
            simulation.nodes(nodesData);
            simulation.links(linksData);
            simulation.start(10, 10, 10);
        }
    }

    // Schedule batched update
    function scheduleUpdate() {
        if (updateTimeout) return; // Already scheduled
        updateTimeout = setTimeout(() => {
            processPendingUpdates();
            updateTimeout = null;
        }, UPDATE_THROTTLE_MS);
    }

    // Add a new node (user joined) - throttled
    export function addNode(userData) {
        if (!simulation) return;
        pendingUpdates.nodes.push(userData);
        scheduleUpdate();
    }

    // Remove a node (user left/removed) - immediate
    export function removeNode(userId) {
        if (!simulation) return;

        const id = String(userId);
        const nodeIndex = nodesData.findIndex((n) => n.id === id);
        if (nodeIndex === -1) return;

        // Remove associated links first
        linksData = linksData.filter(
            (l) =>
                String(l.source.id || l.source) !== id &&
                String(l.target.id || l.target) !== id,
        );

        // Remove the node
        nodesData.splice(nodeIndex, 1);
        nodeMap.delete(id);

        simulation.nodes(nodesData);
        simulation.links(linksData);
        simulation.start(15, 10, 10);
    }

    // Add a connection between two nodes with animation (throttled)
    export function addLink(fromId, toId) {
        if (!simulation) return;
        pendingUpdates.links.push({ fromId, toId });
        scheduleUpdate();
    }

    // Remove a connection between two nodes with animation
    export function removeLink(fromId, toId) {
        if (!simulation) return;

        const sourceId = String(fromId);
        const targetId = String(toId);

        linksData = linksData.filter((l) => {
            const sId = String(l.source.id || l.source);
            const tId = String(l.target.id || l.target);
            return !(
                (sId === sourceId && tId === targetId) ||
                (sId === targetId && tId === sourceId)
            );
        });

        simulation.links(linksData);
        simulation.start(10, 10, 10);
    }

    // Pulse a node to indicate activity (e.g., new post)
    export function pulseNode(userId) {
        // Todo: Implement canvas-based pulse animation (e.g. set a 'pulse' property on node)
        // For now, no-op to avoid errors
    }

    // Handle node click - show context menu at node position
    function handleNodeClick(event, d) {
        // D3 event propagation is different in Canvas manual handling
        // event.stopPropagation() might not work if it's a native event, but check dispatch

        const currentUserIdStr = currentUserId ? String(currentUserId) : null;

        // Don't trigger on self
        if (d.id === currentUserIdStr) return;

        // Get mouse position relative to container
        // Event clientX/Y are global
        const rect = container.getBoundingClientRect();
        contextMenuX = event.clientX - rect.left;
        contextMenuY = event.clientY - rect.top;

        // Store user info
        contextMenuUser = d;

        // Check connection status from server
        if (live) {
            live.pushEvent(
                "check_friendship_status",
                { user_id: d.id },
                (reply) => {
                    contextMenuStatus = reply?.status || "none";
                    showContextMenu = true;
                },
            );
        } else {
            // Fallback: show without status info
            contextMenuStatus = "none";
            showContextMenu = true;
        }
    }

    // Handle context menu action
    function handleMenuAction(action) {
        if (live && contextMenuUser) {
            live.pushEvent("graph_node_action", {
                user_id: contextMenuUser.id,
                action: action,
            });
        }
        closeContextMenu();
    }

    // Close context menu
    function closeContextMenu() {
        showContextMenu = false;
        contextMenuUser = null;
    }

    // Close menu when clicking outside
    function handleBackdropClick(event) {
        if (showContextMenu) {
            closeContextMenu();
        }
    }

    // showLabel and hideLabel are removed - handled in draw() loop

    // Helper: hide label on hover out (module level for access from updateNodes)
    function hideLabel(d) {
        if (!labelGroup) return;
        labelGroup
            .select(`text[data-node-id="${d.id}"]:not(.current-user-label)`)
            .transition()
            .duration(200)
            .style("opacity", 0)
            .remove()
            .on("end", () => {
                // Update cached selection after removal
                labelSelection = labelGroup.selectAll("text");
            });
    }

    // Helper: Determine node fill color (fallback)
    function getNodeFill(type) {
        return COLORS[type] || COLORS.friend;
    }

    // Helper: Determine node stroke
    function getNodeStroke(d, currentUserIdStr) {
        if (d.avatar_url) return "#ffffff"; // White border for photos
        return String(d.id) === currentUserIdStr ? "#FFFFFF" : COLORS.energy;
    }

    // Animation loop
    function animate() {
        draw();
        animationFrame = requestAnimationFrame(animate);
    }

    // Main draw function
    function draw() {
        if (!ctx) return;

        ctx.save();
        ctx.clearRect(0, 0, width * dpi, height * dpi);

        // Apply zoom transform
        ctx.translate(transform.x * dpi, transform.y * dpi);
        ctx.scale(transform.k, transform.k);

        // Draw Links
        ctx.beginPath();
        linksData.forEach((d) => {
            const src = getObj(d.source);
            const tgt = getObj(d.target);
            if (src && tgt) {
                ctx.moveTo(src.x, src.y);
                ctx.lineTo(tgt.x, tgt.y);
            }
        });
        ctx.strokeStyle = "rgba(255, 255, 255, 0.15)";
        ctx.lineWidth = 0.5;
        ctx.stroke();

        // Draw Nodes
        nodesData.forEach((d) => drawNode(d));

        // Draw Labels (only on hover or for current user)
        const currentIdStr = String(currentUserId);
        nodesData.forEach((d) => {
            if (String(d.id) === currentIdStr || d === hoverSubject) {
                drawLabel(d);
            }
        });

        ctx.restore();
    }

    // Helper to resolve Cola's index vs object refs
    function getObj(ref) {
        return typeof ref === "number" ? nodesData[ref] : ref;
    }

    function drawNode(d) {
        const r = isMobile ? 12 : 15;

        ctx.beginPath();
        ctx.arc(d.x, d.y, r, 0, 2 * Math.PI);

        // Draw avatar if available
        if (d.avatar_url && imageCache.has(d.avatar_url)) {
            const img = imageCache.get(d.avatar_url);
            if (img.complete && img.naturalWidth > 0) {
                ctx.save();
                ctx.clip();
                // Draw image centered
                ctx.drawImage(img, d.x - r, d.y - r, r * 2, r * 2);
                ctx.restore();

                // Border for avatar
                ctx.strokeStyle = getNodeStroke(d, String(currentUserId));
                ctx.lineWidth = 1.5;
                ctx.stroke();
                return;
            }
        }

        // Fallback circle
        ctx.fillStyle = getNodeFill(d, String(currentUserId));
        ctx.fill();
        ctx.strokeStyle = getNodeStroke(d, String(currentUserId));
        ctx.lineWidth = 1.5;
        ctx.stroke();
    }

    function drawLabel(d) {
        ctx.font = "600 11px Inter, sans-serif";
        ctx.fillStyle = "#FFFFFF";
        const label = d.username || d.display_name || "User";
        ctx.fillText(label, d.x, d.y - 20);
    }

    // --- Interaction Handlers ---

    function dragSubject(event) {
        // Find closest node within radius
        const transform = d3.zoomTransform(canvas);
        const x = transform.invertX(event.x * dpi) / dpi; // Unsure about DPI here, check invert logic
        // Actually d3.drag on canvas passes event.x relative to canvas container.
        // We need to invert transform.

        // Let's use d3.pointer which gives [x,y] relative to target
        // But the zoom transform is applied.

        // Simpler: use the inverted mouse position from transform
        const mx = transform.invertX(event.x);
        const my = transform.invertY(event.y);

        let subject = null;
        let minDist2 = 400; // 20px radius squared

        for (const n of nodesData) {
            const dx = mx - n.x;
            const dy = my - n.y;
            const dist2 = dx * dx + dy * dy;
            if (dist2 < minDist2) {
                minDist2 = dist2;
                subject = n;
            }
        }
        return subject;
    }

    function dragStarted(event) {
        if (!event.active && simulation.start) simulation.start();
        event.subject.fixed = true;
        // event.subject.px = event.subject.x;
        // event.subject.py = event.subject.y;
        draggedSubject = event.subject;
    }

    function dragged(event) {
        // Drag event gives adjusted x/y if using Subject correctly?
        // D3 drag subject updates position automatically if we modify it
        event.subject.x = event.x;
        event.subject.y = event.y;
        event.subject.px = event.x;
        event.subject.py = event.y;
        simulation.resume();
    }

    function dragEnded(event) {
        if (!event.active && simulation.alphaTarget) simulation.alphaTarget(0); // For Cola just stop forcing?
        draggedSubject = null;
        // Don't unfix if we want sticky nodes
        // event.subject.fixed = false;
    }

    function handleCanvasMouseMove(event) {
        const [mx, my] = d3.pointer(event);
        const t = d3.zoomTransform(canvas);
        const worldX = t.invertX(mx);
        const worldY = t.invertY(my);

        // Find node under mouse
        let found = null;
        const r2 = 400; // 20px radius

        for (const n of nodesData) {
            const dx = worldX - n.x;
            const dy = worldY - n.y;
            if (dx * dx + dy * dy < r2) {
                found = n;
                break;
            }
        }

        if (found !== hoverSubject) {
            hoverSubject = found;
            canvas.style.cursor = found ? "pointer" : "default";
        }
    }

    function handleCanvasClick(event) {
        if (hoverSubject) {
            handleNodeClick(event, hoverSubject);
        } else {
            handleBackdropClick(event);
        }
    }

    // Cached selections for performance
    let nodeSelection;
    let linkSelection;
    let labelSelection;

    // Clean up empty SVG functions
    function ticked() {
        // Empty - drawing handled by animate loop
    }
    function updatePatterns() {}
    function updateNodes() {}
    function updateLinks() {}

    function initGraph() {
        if (!container || !graphData || !canvas) return;

        const rect = container.getBoundingClientRect();
        width = rect.width || window.innerWidth;
        height = rect.height || window.innerHeight;
        isMobile = width < 600;

        // Set canvas size with DPI scaling
        canvas.width = width * dpi;
        canvas.height = height * dpi;
        canvas.style.width = `${width}px`;
        canvas.style.height = `${height}px`;

        ctx = canvas.getContext("2d");
        ctx.scale(dpi, dpi);
        ctx.textBaseline = "middle";
        ctx.textAlign = "center";

        // Build initial data
        const data = buildData(graphData);
        nodesData = data.nodes;
        linksData = data.links;
        nodeMap.clear();

        // Prepare image cache
        nodesData.forEach((n) => {
            nodeMap.set(n.id, n);
            if (n.avatar_url && !imageCache.has(n.avatar_url)) {
                const img = new Image();
                img.src = n.avatar_url;
                imageCache.set(n.avatar_url, img);
            }
        });

        // Cola.js simulation setup
        const linkDistance = isMobile ? 60 : 100;

        const nodeIndexMap = new Map();
        nodesData.forEach((n, i) => nodeIndexMap.set(n.id, i));

        const colaLinks = linksData
            .map((l) => ({
                source:
                    typeof l.source === "object"
                        ? nodeIndexMap.get(l.source.id)
                        : nodeIndexMap.get(l.source),
                target:
                    typeof l.target === "object"
                        ? nodeIndexMap.get(l.target.id)
                        : nodeIndexMap.get(l.target),
                length: linkDistance,
            }))
            .filter((l) => l.source !== undefined && l.target !== undefined);

        simulation = cola
            .d3adaptor(d3)
            .size([width, height])
            .nodes(nodesData)
            .links(colaLinks)
            .linkDistance(linkDistance)
            .symmetricDiffLinkLengths(15)
            .avoidOverlaps(true)
            .on("tick", ticked)
            .start(30);

        // Zoom behavior
        const zoom = d3
            .zoom()
            .scaleExtent([0.1, 4])
            .on("zoom", (event) => {
                transform = event.transform;
                // Redraw on zoom
                // We don't need to call ticked() explicitly as the loop handles it,
                // but for static graphs it helps to trigger a frame.
            });

        d3.select(canvas)
            .call(zoom)
            .on("click", handleCanvasClick)
            .on("mousemove", handleCanvasMouseMove)
            .call(
                d3
                    .drag()
                    .subject(dragSubject)
                    .on("start", dragStarted)
                    .on("drag", dragged)
                    .on("end", dragEnded),
            );

        // Initial Transform
        const contentSize = isMobile ? 500 : 350;
        const minDimension = Math.min(width, height);
        const padding = isMobile ? 60 : 20;
        let initialScale = (minDimension - padding) / contentSize;
        initialScale = Math.min(initialScale, isMobile ? 0.85 : 1.2);
        initialScale = Math.max(initialScale, 0.3);

        const initialTransform = d3.zoomIdentity
            .translate(width / 2, height / 2)
            .scale(initialScale)
            .translate(-width / 2, -height / 2);

        d3.select(canvas).call(zoom.transform, initialTransform);

        // Start animation loop
        if (animationFrame) cancelAnimationFrame(animationFrame);
        animate();
    }

    function buildData(data) {
        if (!data || !data.nodes) return { nodes: [], links: [] };

        const nodes = [];
        const links = [];
        const nodeMap = new Map();

        // Process nodes - smaller scatter on mobile
        const scatterRange = width < 600 ? 150 : 300;
        data.nodes.forEach((node) => {
            const n = {
                ...node,
                id: String(node.id),
                x: width / 2 + (Math.random() - 0.5) * scatterRange,
                y: height / 2 + (Math.random() - 0.5) * scatterRange,
            };
            nodes.push(n);
            nodeMap.set(n.id, n);
        });

        // Process edges
        if (data.edges) {
            data.edges.forEach((edge) => {
                const source = nodeMap.get(String(edge.from));
                const target = nodeMap.get(String(edge.to));
                if (source && target) {
                    links.push({ source: source.id, target: target.id });
                }
            });
        }

        return { nodes, links };
    }

    function handleSkip() {
        // Always skip for this session
        sessionStorage.setItem("graphViewed", "true");

        // If they checked "don't show again", also persist permanently
        if (dontShowAgain) {
            localStorage.setItem("hideWelcomeGraph", "true");
        }
        if (onSkip) {
            onSkip();
        } else if (live) {
            live.pushEvent("skip_welcome_graph", {});
        }
    }

    // ResizeObserver for robust responsiveness (like FriendGraph)
    let resizeObserver;

    onMount(() => {
        initGraph();

        // Handle real-time updates from LiveView
        if (live) {
            live.handleEvent("welcome_new_user", (data) => {
                addNode(data);
            });

            live.handleEvent("welcome_new_connection", (data) => {
                addLink(data.from_id, data.to_id);
            });

            live.handleEvent("welcome_connection_removed", (data) => {
                removeLink(data.from_id, data.to_id);
            });

            live.handleEvent("welcome_user_removed", (data) => {
                removeNode(data.user_id);
            });
        }

        // Handle resize with ResizeObserver + threshold (performance optimization)
        if (container) {
            resizeObserver = new ResizeObserver((entries) => {
                for (const entry of entries) {
                    const newWidth = entry.contentRect.width;
                    // Only reinitialize if size changed significantly (50px threshold)
                    if (Math.abs(newWidth - width) > 50) {
                        initGraph();
                    }
                }
            });
            resizeObserver.observe(container);
        }
    });

    onDestroy(() => {
        if (simulation) simulation.stop();
        if (animationFrame) cancelAnimationFrame(animationFrame);
        if (updateTimeout) clearTimeout(updateTimeout);
        if (resizeObserver) resizeObserver.disconnect();
    });
</script>

<div
    class="w-full h-full"
    on:click={handleBackdropClick}
    on:keydown={(e) => e.key === "Escape" && closeContextMenu()}
    role="presentation"
>
    <!-- Graph Container -->
    <div bind:this={container} class="w-full h-full relative z-10">
        <canvas
            bind:this={canvas}
            class="block w-full h-full cursor-grab active:cursor-grabbing"
        ></canvas>
    </div>

    <!-- Context Menu -->
    {#if showContextMenu && contextMenuUser}
        <div
            class="context-menu"
            style="left: {contextMenuX}px; top: {contextMenuY}px;"
            on:click|stopPropagation
            on:keydown|stopPropagation
            role="menu"
            tabindex="-1"
        >
            <!-- User header -->
            <div class="menu-header">
                <span class="menu-username"
                    >@{contextMenuUser.username ||
                        contextMenuUser.display_name}</span
                >
            </div>

            <!-- Actions -->
            <div class="menu-actions">
                {#if contextMenuStatus === "connected"}
                    <button
                        class="menu-item"
                        on:click={() => handleMenuAction("message")}
                    >
                        <span>Message</span>
                    </button>
                {:else if contextMenuStatus === "pending"}
                    <button class="menu-item menu-item-pending" disabled>
                        <span>Pending...</span>
                    </button>
                {:else}
                    <button
                        class="menu-item"
                        on:click={() => handleMenuAction("add_friend")}
                    >
                        <span>Connect</span>
                    </button>
                {/if}
            </div>
        </div>
    {/if}
</div>

<style>
    .context-menu {
        position: absolute;
        z-index: 100;
        min-width: 160px;
        transform: translate(-50%, 10px);

        /* Fluid Glass Design */
        background: rgba(10, 10, 10, 0.85);
        backdrop-filter: blur(24px);
        -webkit-backdrop-filter: blur(24px);
        border: 1px solid rgba(255, 255, 255, 0.12);
        border-top: 1px solid rgba(255, 255, 255, 0.2);
        border-radius: 1rem;
        box-shadow:
            0 10px 40px -10px rgba(0, 0, 0, 0.6),
            0 0 0 1px rgba(255, 255, 255, 0.05) inset;

        /* Spring animation */
        animation: menu-pop 0.25s cubic-bezier(0.3, 1.5, 0.6, 1);
        overflow: hidden;
    }

    @keyframes menu-pop {
        0% {
            transform: translate(-50%, 10px) scale(0.9);
            opacity: 0;
        }
        100% {
            transform: translate(-50%, 10px) scale(1);
            opacity: 1;
        }
    }

    .menu-header {
        padding: 0.75rem 1rem 0.5rem;
        border-bottom: 1px solid rgba(255, 255, 255, 0.08);
    }

    .menu-username {
        font-size: 0.8rem;
        font-weight: 600;
        color: rgba(255, 255, 255, 0.7);
        letter-spacing: 0.01em;
    }

    .menu-actions {
        padding: 0.5rem;
    }

    .menu-item {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        width: 100%;
        padding: 0.65rem 0.75rem;
        border: none;
        background: transparent;
        color: #f5f5f7;
        font-size: 0.9rem;
        font-weight: 500;
        text-align: left;
        border-radius: 0.6rem;
        cursor: pointer;
        transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
    }

    .menu-item:hover {
        background: rgba(255, 255, 255, 0.1);
    }

    .menu-item:active {
        transform: scale(0.98);
        background: rgba(255, 255, 255, 0.15);
    }

    .menu-item-pending {
        color: rgba(255, 255, 255, 0.4);
        cursor: default;
    }

    .menu-item-pending:hover {
        background: transparent;
    }
</style>
