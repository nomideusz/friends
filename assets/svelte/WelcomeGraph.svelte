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
        friend: "#F59E0B", // Amber/Gold
    };

    let container;
    let svg;
    let simulation;
    let width = 800;
    let height = 600;
    let isMobile = false;
    let animationFrame;

    // Live update state
    let nodesData = [];
    let linksData = [];
    let nodeGroup;
    let labelGroup;
    let linkGroup;
    let nodeMap = new Map();

    // Throttling for live updates (performance optimization)
    let pendingUpdates = { nodes: [], links: [], removals: [] };
    let updateTimeout = null;
    const UPDATE_THROTTLE_MS = 500; // Batch updates every 500ms

    // Context menu state
    let showContextMenu = false;
    let contextMenuX = 0;
    let contextMenuY = 0;
    let contextMenuUser = null;
    let contextMenuStatus = "none"; // 'connected', 'pending', or 'none'

    // === Exported functions for live updates from LiveView ===

    // Process batched updates (called after throttle delay)
    function processPendingUpdates() {
        if (!simulation || !nodeGroup) return;

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
            // Cola.js API for updating - different from D3 force
            simulation.nodes(nodesData);
            simulation.links(linksData);
            // Restart with minimal iterations for smooth update
            simulation.start(10, 10, 10);
            updatePatterns();
            updateNodes();
            updateLinks();
        }
    }

    // Schedule batched update
    function scheduleUpdate() {
        if (updateTimeout) return; // Already scheduled
        updateTimeout = setTimeout(() => {
            updateTimeout = null;
            processPendingUpdates();
        }, UPDATE_THROTTLE_MS);
    }

    // Add a new user node to the graph with animation (throttled)
    export function addNode(userData) {
        if (!simulation || !nodeGroup) return;

        const id = String(userData.id);
        if (nodeMap.has(id)) return; // Already exists

        // Queue for batched processing
        pendingUpdates.nodes.push(userData);
        scheduleUpdate();
    }

    // Remove a user node from the graph with animation
    export function removeNode(userId) {
        if (!simulation || !nodeGroup) return;

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

        // Update simulation - Cola.js API
        simulation.nodes(nodesData);
        simulation.links(linksData);
        simulation.start(15, 10, 10);

        updatePatterns();
        updateNodes();
        updateLinks();
    }

    // Add a connection between two nodes with animation (throttled)
    export function addLink(fromId, toId) {
        if (!simulation || !linkGroup) return;

        // Queue for batched processing
        pendingUpdates.links.push({ fromId, toId });
        scheduleUpdate();
    }

    // Remove a connection between two nodes with animation
    export function removeLink(fromId, toId) {
        if (!simulation || !linkGroup) return;

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

        // Update simulation - Cola.js API
        simulation.links(linksData);
        simulation.start(10, 5, 5);

        updateLinks();
    }

    // Pulse a node to indicate activity (e.g., new post)
    export function pulseNode(userId) {
        if (!nodeGroup) return;

        const id = String(userId);
        nodeGroup
            .selectAll("circle")
            .filter((d) => d.id === id)
            .transition()
            .duration(200)
            .attr("r", 14)
            .style("fill-opacity", 0.6)
            .transition()
            .duration(400)
            .attr("r", 8)
            .style("fill-opacity", 0.3);
    }

    // Handle node click - show context menu at node position
    function handleNodeClick(event, d) {
        event.stopPropagation();
        const currentUserIdStr = currentUserId ? String(currentUserId) : null;

        // Don't trigger on self
        if (d.id === currentUserIdStr) return;

        // Get mouse position relative to container
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

    // Helper: show label on hover (module level for access from updateNodes)
    // Helper: show label on hover (module level for access from updateNodes)
    function showLabel(d) {
        if (!labelGroup) return;
        const label = labelGroup.select(`text[data-node-id="${d.id}"]`);
        if (label.empty()) {
            labelGroup
                .append("text")
                .attr("data-node-id", d.id)
                .attr("x", d.x)
                .attr("y", d.y - 15)
                .attr("text-anchor", "middle")
                .attr("fill", "#E5E7EB")
                .attr("font-size", "10px")
                .attr("font-family", "Inter, sans-serif")
                .attr("font-weight", "500")
                .style("opacity", 0)
                .style("pointer-events", "none")
                .text(d.display_name || d.username || d.id)
                .transition()
                .duration(200)
                .style("opacity", 1);

            // Update cached selection so the new label moves with the node
            labelSelection = labelGroup.selectAll("text");
        }
    }

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

    // Helper: update SVG patterns for avatars
    function updatePatterns() {
        if (!svg) return;
        let defs = svg.select("defs");
        if (defs.empty()) defs = svg.append("defs");

        // Select patterns bound to nodes with avatars
        const patterns = defs.selectAll("pattern").data(
            nodesData.filter((d) => d.avatar_url),
            (d) => d.id,
        );

        const enter = patterns
            .enter()
            .append("pattern")
            .attr("id", (d) => `avatar-pattern-${d.id}`)
            .attr("width", 1)
            .attr("height", 1)
            .attr("patternContentUnits", "objectBoundingBox");

        // Add image to pattern
        enter
            .append("image")
            .attr("href", (d) => d.avatar_url)
            .attr("width", 1)
            .attr("height", 1)
            .attr("preserveAspectRatio", "xMidYMid slice");

        patterns.exit().remove();
    }

    // Helper: Determine node fill
    function getNodeFill(d, currentUserIdStr) {
        if (d.avatar_url) return `url(#avatar-pattern-${d.id})`;
        return d.id === currentUserIdStr ? "#60A5FA" : "#3B82F6";
    }

    // Helper: Determine node stroke
    function getNodeStroke(d, currentUserIdStr) {
        if (d.avatar_url) return "#ffffff"; // White border for photos
        return d.id === currentUserIdStr ? "#FFFFFF" : "#93C5FD";
    }

    // Helper: Determine node fill opacity
    function getNodeFillOpacity(d) {
        if (d.avatar_url) return 1; // Solid for photos
        return 0.3; // Glassy for colors
    }

    // Cached selections for performance
    let nodeSelection;
    let linkSelection;
    let labelSelection;

    function updateNodes() {
        const nodes = nodeGroup
            .selectAll("circle")
            .data(nodesData, (d) => d.id);

        const currentUserIdStr = currentUserId ? String(currentUserId) : null;

        // Enter new nodes with animation
        const enter = nodes
            .enter()
            .append("circle")
            .attr("r", 0)
            .attr("cx", (d) => d.x)
            .attr("cy", (d) => d.y)
            .style("fill", (d) => getNodeFill(d, currentUserIdStr))
            .style("fill-opacity", (d) => getNodeFillOpacity(d))
            .attr("stroke", (d) => getNodeStroke(d, currentUserIdStr))
            .attr("stroke-opacity", 0.6)
            .attr("stroke-width", 1.5)
            .style("cursor", "pointer");

        enter
            .call(simulation.drag) // Use Cola.js drag behavior
            .on("mouseenter", function (event, d) {
                if (isMobile || d.id === currentUserIdStr) return;
                showLabel(d);
                d3.select(this)
                    .attr("r", 10)
                    .style("fill-opacity", d.avatar_url ? 1 : 0.4)
                    .attr("stroke-opacity", 0.8);
            })
            .on("mouseleave", function (event, d) {
                if (isMobile || d.id === currentUserIdStr) return;
                hideLabel(d);
                d3.select(this)
                    .attr("r", 8)
                    .style("fill-opacity", d.avatar_url ? 1 : 0.3)
                    .attr("stroke-opacity", 0.6);
            })
            .on("click", handleNodeClick)
            .transition()
            .duration(500)
            .attr("r", 8); // Uniform size

        nodes.exit().transition().duration(300).attr("r", 0).remove();

        // Update cached selection
        nodeSelection = nodeGroup.selectAll("circle");
    }

    function updateLinks() {
        const links = linkGroup
            .selectAll("line")
            .data(linksData, (d) => `${d.source.id}-${d.target.id}`);

        // Enter new links with animation
        links
            .enter()
            .append("line")
            .attr("stroke", "#ffffff")
            .attr("stroke-opacity", 0)
            .attr("stroke-width", 0.5)
            .attr("x1", (d) => d.source.x)
            .attr("y1", (d) => d.source.y)
            .attr("x2", (d) => d.target.x)
            .attr("y2", (d) => d.target.y)
            .transition()
            .duration(500)
            .attr("stroke-opacity", 0.15);

        links
            .exit()
            .transition()
            .duration(300)
            .attr("stroke-opacity", 0)
            .remove();

        // Update cached selection
        linkSelection = linkGroup.selectAll("line");
    }

    function initGraph() {
        if (!container || !graphData) return;

        const rect = container.getBoundingClientRect();
        width = rect.width || window.innerWidth;
        height = rect.height || window.innerHeight;

        // Clear existing
        d3.select(container).selectAll("*").remove();

        // Build node/link data
        const data = buildData(graphData);

        // Create SVG
        svg = d3
            .select(container)
            .append("svg")
            .attr("width", width)
            .attr("height", height)
            .style("background", "transparent");

        // Definitions for filters
        const defs = svg.append("defs");
        // No filters needed for glassy style

        // Main group with zoom
        const mainGroup = svg.append("g").attr("class", "main");

        const zoom = d3
            .zoom()
            .scaleExtent([0.5, 3])
            .on("zoom", (event) => {
                mainGroup.attr("transform", event.transform);
            });
        svg.call(zoom);

        isMobile = width < 600;

        if (hideControls) {
            zoom.filter((event) => event.type !== "wheel");
        }

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
        svg.call(zoom.transform, initialTransform);

        // Create groups
        linkGroup = mainGroup.append("g").attr("class", "links");
        nodeGroup = mainGroup.append("g").attr("class", "nodes");
        labelGroup = mainGroup.append("g").attr("class", "labels");

        nodesData = data.nodes;
        linksData = data.links;
        nodeMap.clear();
        nodesData.forEach((n) => nodeMap.set(n.id, n));

        // Create patterns for avatars
        updatePatterns();

        // Cola.js simulation - stable constraint-based layout
        // Much smoother than D3 force, especially for dynamic updates
        const linkDistance = isMobile ? 50 : 80;
        const nodeRadius = isMobile ? 12 : 15;

        // Convert links to use node indices (Cola.js requirement)
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

        // Cola.js simulation - simplified setup like TMDB example
        // Simple config without expensive algorithms
        simulation = cola
            .d3adaptor(d3)
            .linkDistance(linkDistance)
            .size([width, height])
            .nodes(nodesData)
            .links(colaLinks)
            .handleDisconnected(true)
            .start(); // Simple start, no iteration counts

        // Initialize cached selections - use colaLinks since they have resolved node refs
        linkSelection = linkGroup
            .selectAll("line")
            .data(colaLinks)
            .join("line")
            .attr("stroke", "#ffffff")
            .attr("stroke-opacity", 0.15)
            .attr("stroke-width", 0.5);

        const currentUserIdStr = currentUserId ? String(currentUserId) : null;

        // Initialize nodes via updateNodes to attach behaviors and cache selection
        updateNodes();

        // Add current user's label
        if (currentUserIdStr) {
            const currentUserNode = data.nodes.find(
                (n) => n.id === currentUserIdStr,
            );
            if (currentUserNode) {
                labelGroup
                    .append("text")
                    .attr("class", "current-user-label")
                    .attr("data-node-id", currentUserIdStr)
                    .attr("x", currentUserNode.x)
                    .attr("y", currentUserNode.y - 15) // Above node
                    .attr("text-anchor", "middle")
                    .attr("fill", "#FFFFFF") // White text for You
                    .attr("font-size", "11px")
                    .attr("font-family", "Inter, sans-serif")
                    .attr("font-weight", "600")
                    .attr("letter-spacing", "0.02em")
                    .style("opacity", 1)
                    .style("pointer-events", "none")
                    .text(
                        currentUserNode.username ||
                            currentUserNode.name ||
                            "You",
                    );
            }
        }

        // Initial cache of label selection
        labelSelection = labelGroup.selectAll("text");

        // Tick counter for mobile frame skipping
        let tickCount = 0;
        const MOBILE_TICK_SKIP = 2; // Skip every 2 of 3 ticks on mobile for performance

        // Tick handler - Optimized to use cached selections + mobile frame skipping
        simulation.on("tick", () => {
            // On mobile, skip frames to reduce CPU load
            if (isMobile) {
                tickCount++;
                if (tickCount % (MOBILE_TICK_SKIP + 1) !== 0) {
                    return; // Skip this frame on mobile
                }
            }

            if (linkSelection) {
                linkSelection
                    .attr("x1", (d) => {
                        const src =
                            typeof d.source === "number"
                                ? nodesData[d.source]
                                : d.source;
                        return src ? src.x : 0;
                    })
                    .attr("y1", (d) => {
                        const src =
                            typeof d.source === "number"
                                ? nodesData[d.source]
                                : d.source;
                        return src ? src.y : 0;
                    })
                    .attr("x2", (d) => {
                        const tgt =
                            typeof d.target === "number"
                                ? nodesData[d.target]
                                : d.target;
                        return tgt ? tgt.x : 0;
                    })
                    .attr("y2", (d) => {
                        const tgt =
                            typeof d.target === "number"
                                ? nodesData[d.target]
                                : d.target;
                        return tgt ? tgt.y : 0;
                    });
            }

            if (nodeSelection) {
                nodeSelection.attr("cx", (d) => d.x).attr("cy", (d) => d.y);
            }

            if (labelSelection) {
                labelSelection
                    .attr("x", function (d) {
                        // For data-bound labels created by updateNodes/showLabel
                        if (d && d.x !== undefined) return d.x;

                        // For manually created labels (like current user label)
                        const nodeId = this.getAttribute("data-node-id");
                        if (nodeId) {
                            const node = nodeMap.get(nodeId);
                            return node ? node.x : 0;
                        }
                        return 0;
                    })
                    .attr("y", function (d) {
                        // For data-bound labels
                        if (d && d.y !== undefined) return d.y - 15;

                        // For manually created labels
                        const nodeId = this.getAttribute("data-node-id");
                        if (nodeId) {
                            const node = nodeMap.get(nodeId);
                            return node ? node.y - 15 : 0;
                        }
                        return 0;
                    });
            }
        });
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
    <div bind:this={container} class="w-full h-full relative z-10"></div>

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
