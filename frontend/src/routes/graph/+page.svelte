<script lang="ts">
    import { onMount, onDestroy } from "svelte";
    import * as d3 from "d3";
    import { api, joinGraph } from "$lib/phoenix";
    import { user as currentUser } from "$lib/stores/auth";

    // State
    let container: HTMLDivElement;
    let loading = true;
    let error: string | null = null;
    let stats = { total_users: 0, total_connections: 0 };

    // D3 refs
    let svg: d3.Selection<SVGSVGElement, unknown, null, undefined>;
    let simulation: d3.Simulation<any, any>;
    let nodesData: any[] = [];
    let linksData: any[] = [];
    let nodeMap = new Map<string, any>();
    let width = 800;
    let height = 600;

    // Groups for D3 elements
    let linkGroup: d3.Selection<SVGGElement, unknown, null, undefined>;
    let nodeGroup: d3.Selection<SVGGElement, unknown, null, undefined>;
    let labelGroup: d3.Selection<SVGGElement, unknown, null, undefined>;

    // Channel for cleanup
    let graphChannel: { leave: () => void } | null = null;

    onMount(async () => {
        try {
            const data = await api.getGraph();

            if (data.nodes && data.nodes.length > 0) {
                // Transform API data format
                nodesData = data.nodes.map((n: any) => ({
                    id: String(n.id),
                    username: n.username || n.label,
                    display_name: n.label || n.username,
                    type: n.type,
                }));

                // Build node map
                nodeMap = new Map(nodesData.map((n) => [n.id, n]));

                linksData = (data.links || [])
                    .map((l: any) => ({
                        source: String(
                            typeof l.source === "object"
                                ? l.source.id
                                : l.source,
                        ),
                        target: String(
                            typeof l.target === "object"
                                ? l.target.id
                                : l.target,
                        ),
                    }))
                    .filter(
                        (l: any) =>
                            nodeMap.has(l.source) && nodeMap.has(l.target),
                    );

                stats = {
                    total_users: nodesData.length,
                    total_connections: linksData.length,
                };

                initGraph();

                // Subscribe to live updates
                graphChannel = joinGraph({
                    onNewUser: addNode,
                    onNewConnection: addLink,
                    onConnectionRemoved: removeLink,
                    onUserDeleted: removeNode,
                    onSignal: pulseNode,
                });
            }
            loading = false;
        } catch (e) {
            error = "Failed to load graph data";
            loading = false;
            console.error(e);
        }
    });

    // === Live Update Functions ===

    function addNode(userData: {
        id: number;
        username: string;
        display_name?: string;
    }) {
        if (!simulation || !nodeGroup) return;

        const id = String(userData.id);
        if (nodeMap.has(id)) return;

        const newNode = {
            id,
            username: userData.username,
            display_name: userData.display_name || userData.username,
            x: width / 2 + (Math.random() - 0.5) * 100,
            y: height / 2 + (Math.random() - 0.5) * 100,
        };

        nodesData.push(newNode);
        nodeMap.set(id, newNode);
        stats.total_users++;

        simulation.nodes(nodesData);
        simulation.alpha(0.3).restart();

        updateNodes();
    }

    function removeNode(data: { user_id: number }) {
        if (!simulation || !nodeGroup) return;

        const id = String(data.user_id);
        const nodeIndex = nodesData.findIndex((n) => n.id === id);
        if (nodeIndex === -1) return;

        // Remove associated links
        linksData = linksData.filter(
            (l) =>
                String(l.source.id || l.source) !== id &&
                String(l.target.id || l.target) !== id,
        );

        nodesData.splice(nodeIndex, 1);
        nodeMap.delete(id);
        stats.total_users--;

        simulation.nodes(nodesData);
        simulation.force(
            "link",
            d3.forceLink(linksData).id((d: any) => d.id),
        );
        simulation.alpha(0.3).restart();

        updateNodes();
        updateLinks();
    }

    function addLink(data: { from_id: number; to_id: number }) {
        if (!simulation || !linkGroup) return;

        const sourceId = String(data.from_id);
        const targetId = String(data.to_id);

        const sourceNode = nodeMap.get(sourceId);
        const targetNode = nodeMap.get(targetId);

        if (!sourceNode || !targetNode) return;

        // Check if link exists
        const exists = linksData.some(
            (l) =>
                (String(l.source.id || l.source) === sourceId &&
                    String(l.target.id || l.target) === targetId) ||
                (String(l.source.id || l.source) === targetId &&
                    String(l.target.id || l.target) === sourceId),
        );
        if (exists) return;

        linksData.push({ source: sourceNode, target: targetNode });
        stats.total_connections++;

        simulation.force(
            "link",
            d3.forceLink(linksData).id((d: any) => d.id),
        );
        simulation.alpha(0.3).restart();

        updateLinks();
    }

    function removeLink(data: { from_id: number; to_id: number }) {
        if (!simulation || !linkGroup) return;

        const sourceId = String(data.from_id);
        const targetId = String(data.to_id);

        const prevLength = linksData.length;
        linksData = linksData.filter((l) => {
            const sId = String(l.source.id || l.source);
            const tId = String(l.target.id || l.target);
            return !(
                (sId === sourceId && tId === targetId) ||
                (sId === targetId && tId === sourceId)
            );
        });

        if (linksData.length < prevLength) {
            stats.total_connections--;
        }

        simulation.force(
            "link",
            d3.forceLink(linksData).id((d: any) => d.id),
        );
        simulation.alpha(0.1).restart();

        updateLinks();
    }

    function pulseNode(data: { user_id: number }) {
        if (!nodeGroup) return;

        const id = String(data.user_id);
        nodeGroup
            .selectAll("circle")
            .filter((d: any) => d.id === id)
            .transition()
            .duration(200)
            .attr("r", 14)
            .style("fill-opacity", 0.6)
            .transition()
            .duration(400)
            .attr("r", 8)
            .style("fill-opacity", 0.3);
    }

    function initGraph() {
        if (!container) return;

        const rect = container.getBoundingClientRect();
        width = rect.width || 800;
        height = rect.height || 600;

        // Clear existing
        d3.select(container).selectAll("*").remove();

        // Create SVG
        svg = d3
            .select(container)
            .append("svg")
            .attr("width", width)
            .attr("height", height)
            .style("background", "transparent");

        // Main group with zoom
        const mainGroup = svg.append("g").attr("class", "main");

        const zoom = d3
            .zoom<SVGSVGElement, unknown>()
            .scaleExtent([0.3, 3])
            .on("zoom", (event) => {
                mainGroup.attr("transform", event.transform);
            });
        svg.call(zoom);

        // Initial scale
        const isMobile = width < 600;
        const contentSize = isMobile ? 400 : 350;
        const minDimension = Math.min(width, height);
        let initialScale = (minDimension - 40) / contentSize;
        initialScale = Math.min(Math.max(initialScale, 0.4), 1.2);

        const initialTransform = d3.zoomIdentity
            .translate(width / 2, height / 2)
            .scale(initialScale)
            .translate(-width / 2, -height / 2);
        svg.call(zoom.transform, initialTransform);

        // Create groups
        linkGroup = mainGroup.append("g").attr("class", "links");
        nodeGroup = mainGroup.append("g").attr("class", "nodes");
        labelGroup = mainGroup.append("g").attr("class", "labels");

        // Initialize node positions
        const scatterRange = isMobile ? 150 : 250;
        nodesData.forEach((n) => {
            if (n.x === undefined) {
                n.x = width / 2 + (Math.random() - 0.5) * scatterRange;
                n.y = height / 2 + (Math.random() - 0.5) * scatterRange;
            }
        });

        // Force simulation
        const linkDistance = isMobile ? 60 : 90;
        const chargeStrength = isMobile ? -60 : -100;

        simulation = d3
            .forceSimulation(nodesData)
            .force(
                "link",
                d3
                    .forceLink(linksData)
                    .id((d: any) => d.id)
                    .distance(linkDistance),
            )
            .force("charge", d3.forceManyBody().strength(chargeStrength))
            .force("center", d3.forceCenter(width / 2, height / 2))
            .force("x", d3.forceX(width / 2).strength(0.05))
            .force("y", d3.forceY(height / 2).strength(0.05))
            .force("collide", d3.forceCollide().radius(20));

        // Current user ID
        const currentUserId = $currentUser?.id ? String($currentUser.id) : null;

        // Draw initial elements
        updateLinks();
        updateNodes();

        // Add current user label if exists
        const currentUserNode = nodesData.find(
            (n) => n.id === currentUserId || n.type === "current_user",
        );
        if (currentUserNode) {
            labelGroup
                .append("text")
                .attr("class", "current-user-label")
                .attr("data-node-id", currentUserNode.id)
                .attr("x", currentUserNode.x)
                .attr("y", currentUserNode.y - 15)
                .attr("text-anchor", "middle")
                .attr("fill", "#FFFFFF")
                .attr("font-size", "11px")
                .attr("font-family", "Inter, sans-serif")
                .attr("font-weight", "600")
                .style("pointer-events", "none")
                .text(currentUserNode.display_name || "You");
        }

        // Tick handler
        simulation.on("tick", () => {
            linkGroup
                .selectAll("line")
                .attr("x1", (d: any) => d.source.x)
                .attr("y1", (d: any) => d.source.y)
                .attr("x2", (d: any) => d.target.x)
                .attr("y2", (d: any) => d.target.y);

            nodeGroup
                .selectAll("circle")
                .attr("cx", (d: any) => d.x)
                .attr("cy", (d: any) => d.y);

            labelGroup
                .selectAll("text")
                .attr("x", function () {
                    const nodeId = d3.select(this).attr("data-node-id");
                    const node = nodesData.find((n) => n.id === nodeId);
                    return node ? node.x : 0;
                })
                .attr("y", function () {
                    const nodeId = d3.select(this).attr("data-node-id");
                    const node = nodesData.find((n) => n.id === nodeId);
                    return node ? node.y - 15 : 0;
                });
        });
    }

    function updateLinks() {
        if (!linkGroup) return;

        const links = linkGroup
            .selectAll("line")
            .data(
                linksData,
                (d: any) =>
                    `${d.source.id || d.source}-${d.target.id || d.target}`,
            );

        // Enter new links with thicker, more visible lines
        links
            .enter()
            .append("line")
            .attr("stroke", "#60A5FA") // Brighter blue
            .attr("stroke-opacity", 0)
            .attr("stroke-width", 1.5) // Thicker lines
            .attr("x1", (d: any) => d.source.x || width / 2)
            .attr("y1", (d: any) => d.source.y || height / 2)
            .attr("x2", (d: any) => d.target.x || width / 2)
            .attr("y2", (d: any) => d.target.y || height / 2)
            .transition()
            .duration(500)
            .attr("stroke-opacity", 0.4); // More visible opacity

        links
            .exit()
            .transition()
            .duration(300)
            .attr("stroke-opacity", 0)
            .remove();
    }

    function updateNodes() {
        if (!nodeGroup) return;

        const currentUserId = $currentUser?.id ? String($currentUser.id) : null;

        const nodes = nodeGroup
            .selectAll("circle")
            .data(nodesData, (d: any) => d.id);

        nodes
            .enter()
            .append("circle")
            .attr("r", 0)
            .attr("cx", (d: any) => d.x)
            .attr("cy", (d: any) => d.y)
            .style("fill", (d: any) =>
                d.id === currentUserId || d.type === "current_user"
                    ? "#60A5FA"
                    : "#3B82F6",
            )
            .style("fill-opacity", 0.3)
            .attr("stroke", (d: any) =>
                d.id === currentUserId || d.type === "current_user"
                    ? "#FFFFFF"
                    : "#93C5FD",
            )
            .attr("stroke-opacity", 0.6)
            .attr("stroke-width", 1.5)
            .style("cursor", "pointer")
            .on("mouseenter", function (event, d: any) {
                if (d.id === currentUserId || d.type === "current_user") return;
                showLabel(d);
                d3.select(this)
                    .transition()
                    .duration(200)
                    .attr("r", 10)
                    .style("fill-opacity", 0.4)
                    .attr("stroke-opacity", 0.8);
            })
            .on("mouseleave", function (event, d: any) {
                if (d.id === currentUserId || d.type === "current_user") return;
                hideLabel(d);
                d3.select(this)
                    .transition()
                    .duration(200)
                    .attr("r", 8)
                    .style("fill-opacity", 0.3)
                    .attr("stroke-opacity", 0.6);
            })
            .call(
                d3
                    .drag<SVGCircleElement, any>()
                    .on("start", (event, d) => {
                        if (!event.active)
                            simulation.alphaTarget(0.3).restart();
                        d.fx = d.x;
                        d.fy = d.y;
                    })
                    .on("drag", (event, d) => {
                        d.fx = event.x;
                        d.fy = event.y;
                    })
                    .on("end", (event, d) => {
                        if (!event.active) simulation.alphaTarget(0);
                        d.fx = null;
                        d.fy = null;
                    }),
            )
            .transition()
            .duration(500)
            .attr("r", 8);

        nodes.exit().transition().duration(300).attr("r", 0).remove();
    }

    function showLabel(d: any) {
        if (!labelGroup) return;
        if (labelGroup.select(`text[data-node-id="${d.id}"]`).empty()) {
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
        }
    }

    function hideLabel(d: any) {
        if (!labelGroup) return;
        labelGroup
            .select(`text[data-node-id="${d.id}"]:not(.current-user-label)`)
            .transition()
            .duration(200)
            .style("opacity", 0)
            .remove();
    }

    onDestroy(() => {
        if (simulation) simulation.stop();
        if (graphChannel) graphChannel.leave();
    });

    // Handle resize
    function handleResize() {
        if (nodesData.length > 0) {
            initGraph();
        }
    }
</script>

<svelte:window on:resize={handleResize} />

<svelte:head>
    <title>Network | New Internet</title>
</svelte:head>

<div class="graph-page">
    <!-- Header -->
    <header class="graph-header fluid-glass">
        <div class="header-left">
            <a href="/" class="back-link">
                <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="icon"
                >
                    <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="M10.5 19.5L3 12m0 0l7.5-7.5M3 12h18"
                    />
                </svg>
            </a>
            <h1>Global Network</h1>
        </div>

        <div class="header-stats">
            <div class="stat">
                <span
                    class="presence-dot presence-dot-online"
                    style="color: var(--color-energy)"
                ></span>
                <span><strong>{stats.total_users}</strong> users</span>
            </div>
            <div class="divider"></div>
            <div class="stat">
                <strong>{stats.total_connections}</strong> connections
            </div>
        </div>
    </header>

    <!-- Graph Container -->
    <div class="graph-container">
        {#if loading}
            <div class="loading-state">
                <div class="spinner"></div>
                <p class="text-muted">Loading network...</p>
            </div>
        {:else if error}
            <div class="error-state">
                <p>{error}</p>
                <a href="/" class="btn-aether">Go Home</a>
            </div>
        {:else if nodesData.length === 0}
            <div class="empty-state">
                <p class="text-muted">
                    No network data yet. Connect with friends to see the graph!
                </p>
                <a href="/" class="btn-aether btn-aether-primary">Go Home</a>
            </div>
        {:else}
            <div bind:this={container} class="graph-canvas"></div>
        {/if}
    </div>

    <!-- Instructions -->
    <aside class="instructions aether-card">
        <h3 class="fluid-label">Navigation</h3>
        <ul>
            <li><strong>Drag</strong> — Rotate the view</li>
            <li><strong>Scroll</strong> — Zoom in/out</li>
            <li><strong>Hover node</strong> — See username</li>
            <li><strong>Drag node</strong> — Move it around</li>
        </ul>
    </aside>
</div>

<style>
    .graph-page {
        display: flex;
        flex-direction: column;
        min-height: calc(100vh - 80px);
        gap: 1rem;
    }

    .graph-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 0.75rem 1rem;
        border-radius: var(--radius-button);
    }

    .header-left {
        display: flex;
        align-items: center;
        gap: 1rem;
    }

    .back-link {
        color: var(--color-dim);
        transition: color 0.2s;
    }

    .back-link:hover {
        color: var(--color-photon);
    }

    .icon {
        width: 24px;
        height: 24px;
    }

    .graph-header h1 {
        font-size: 1.25rem;
        margin: 0;
    }

    .header-stats {
        display: flex;
        align-items: center;
        gap: 1rem;
        font-size: 0.875rem;
        color: var(--color-dim);
    }

    .stat {
        display: flex;
        align-items: center;
        gap: 0.5rem;
    }

    .stat strong {
        color: var(--color-photon);
    }

    .divider {
        width: 1px;
        height: 16px;
        background: rgba(255, 255, 255, 0.1);
    }

    .graph-container {
        flex: 1;
        position: relative;
        min-height: 400px;
        border-radius: var(--radius-fluid);
        overflow: hidden;
        background: linear-gradient(135deg, #0a0a0a 0%, #1a1a2e 100%);
    }

    .graph-canvas {
        width: 100%;
        height: 100%;
        position: absolute;
        inset: 0;
    }

    .loading-state,
    .error-state,
    .empty-state {
        position: absolute;
        inset: 0;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 1rem;
    }

    .spinner {
        width: 40px;
        height: 40px;
        border: 3px solid rgba(255, 255, 255, 0.1);
        border-top-color: var(--color-accent);
        border-radius: 50%;
        animation: spin 1s linear infinite;
    }

    @keyframes spin {
        to {
            transform: rotate(360deg);
        }
    }

    .instructions {
        padding: 1rem 1.5rem;
        max-width: 100%;
    }

    .instructions h3 {
        margin-bottom: 0.75rem;
    }

    .instructions ul {
        list-style: none;
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
        gap: 0.5rem;
    }

    .instructions li {
        font-size: 0.875rem;
        color: var(--color-dim);
    }

    .instructions strong {
        color: var(--color-accent);
    }

    @media (max-width: 640px) {
        .header-stats {
            display: none;
        }

        .graph-container {
            min-height: 300px;
        }

        .instructions ul {
            grid-template-columns: 1fr 1fr;
        }
    }
</style>
