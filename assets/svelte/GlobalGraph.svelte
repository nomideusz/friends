<script>
    import { onMount, onDestroy } from "svelte";
    import * as d3 from "d3";

    // Props from Phoenix LiveView
    export let graphData = null;
    export let live = null;
    export let currentUserId = null;

    let container;
    let svg;
    let simulation;
    let width = 800;
    let height = 600;

    // Time Travel State
    let timeValue = 100;
    let isPlaying = false;
    let animationFrame;
    let minTime = 0;
    let maxTime = Date.now();

    // Stats
    let currentStats = { nodes: 0, edges: 0 };

    // Current date display for timeline
    $: currentDate = (() => {
        if (!minTime || !maxTime) return "";
        const range = maxTime - minTime;
        const currentTime = minTime + range * (timeValue / 100);
        return new Date(currentTime).toLocaleDateString("en-US", {
            year: "numeric",
            month: "short",
            day: "numeric",
        });
    })();

    // Color palette for nodes (consistent hashing by ID)
    const colorPalette = [
        "#ef4444",
        "#f97316",
        "#eab308",
        "#22c55e",
        "#14b8a6",
        "#3b82f6",
        "#8b5cf6",
        "#ec4899",
    ];

    function getNodeColor(id) {
        const numId = typeof id === "string" ? parseInt(id) : id;
        return colorPalette[numId % colorPalette.length];
    }

    // Convert Phoenix data to D3 format - simple global view
    function buildAllData(data) {
        if (!data || !data.nodes) return { nodes: [], links: [] };

        const nodes = [];
        const links = [];
        const nodeMap = new Map();

        // Process ALL nodes - no special "self" treatment
        (data.nodes || []).forEach((node) => {
            const nodeTime = node.inserted_at
                ? new Date(node.inserted_at).getTime()
                : Date.now();

            const isCurrentUser =
                currentUserId && String(node.id) === String(currentUserId);

            const n = {
                id: String(node.id),
                label: node.display_name || node.username,
                displayName: node.display_name || node.username,
                username: node.username,
                color: getNodeColor(node.id),
                connectedAt: nodeTime,
                isCurrentUser: isCurrentUser,
                // Initialize position randomly
                x: width / 2 + (Math.random() - 0.5) * 200,
                y: height / 2 + (Math.random() - 0.5) * 200,
            };
            nodes.push(n);
            nodeMap.set(n.id, n);
        });

        // Process ALL edges - straightforward timestamps
        if (data.edges) {
            data.edges.forEach((edge) => {
                const edgeTime = edge.connected_at
                    ? new Date(edge.connected_at).getTime()
                    : Date.now();

                const source = nodeMap.get(String(edge.from));
                const target = nodeMap.get(String(edge.to));

                if (source && target) {
                    links.push({
                        source: source.id,
                        target: target.id,
                        connectedAt: edgeTime,
                    });
                }
            });
        }

        return { nodes, links };
    }

    function initGraph() {
        if (!container || !graphData) return;

        // Get container dimensions
        const rect = container.getBoundingClientRect();
        width = rect.width || 800;
        height = rect.height || 600;

        // Calculate time range from all data
        const dates = [];
        (graphData.nodes || []).forEach((n) => {
            if (n.inserted_at) dates.push(new Date(n.inserted_at).getTime());
        });
        (graphData.edges || []).forEach((e) => {
            if (e.connected_at) dates.push(new Date(e.connected_at).getTime());
        });
        if (dates.length > 0) {
            minTime = Math.min(...dates) - 1000 * 60 * 60 * 24 * 7;
            maxTime = Math.max(...dates);
        }

        // Build graph data
        const data = buildAllData(graphData);
        currentStats = { nodes: data.nodes.length, edges: data.links.length };

        // Create SVG
        d3.select(container).selectAll("*").remove();
        svg = d3
            .select(container)
            .append("svg")
            .attr("width", width)
            .attr("height", height)
            .style("background", "transparent");

        // Define glow filter
        const defs = svg.append("defs");
        const filter = defs
            .append("filter")
            .attr("id", "glow-node")
            .attr("x", "-100%")
            .attr("y", "-100%")
            .attr("width", "300%")
            .attr("height", "300%");

        filter
            .append("feGaussianBlur")
            .attr("stdDeviation", "3")
            .attr("result", "blur");

        filter
            .append("feFlood")
            .attr("flood-color", "#ffffff")
            .attr("flood-opacity", "0.4")
            .attr("result", "color");

        filter
            .append("feComposite")
            .attr("in", "color")
            .attr("in2", "blur")
            .attr("operator", "in")
            .attr("result", "glow");

        const merge = filter.append("feMerge");
        merge.append("feMergeNode").attr("in", "glow");
        merge.append("feMergeNode").attr("in", "SourceGraphic");

        // Create main group for zoom/pan
        const mainGroup = svg.append("g").attr("class", "main");

        // Add zoom behavior
        const zoom = d3
            .zoom()
            .scaleExtent([0.2, 4])
            .on("zoom", (event) => {
                mainGroup.attr("transform", event.transform);
            });
        svg.call(zoom);

        // Apply initial zoom to fit content
        const initialScale = 0.8;
        const initialTransform = d3.zoomIdentity
            .translate(width / 2, height / 2)
            .scale(initialScale)
            .translate(-width / 2, -height / 2);
        svg.call(zoom.transform, initialTransform);

        // Create groups
        const linkGroup = mainGroup.append("g").attr("class", "links");
        const nodeGroup = mainGroup.append("g").attr("class", "nodes");
        const labelGroup = mainGroup.append("g").attr("class", "labels");

        // Create simulation - no fixed center node
        simulation = d3
            .forceSimulation(data.nodes)
            .force(
                "link",
                d3
                    .forceLink(data.links)
                    .id((d) => d.id)
                    .distance(80),
            )
            .force("charge", d3.forceManyBody().strength(-150))
            .force("x", d3.forceX(width / 2).strength(0.03))
            .force("y", d3.forceY(height / 2).strength(0.03))
            .force("collide", d3.forceCollide().radius(25));

        // Draw links
        const links = linkGroup
            .selectAll("line")
            .data(data.links)
            .join("line")
            .attr("stroke", "#ffffff")
            .attr("stroke-opacity", 0)
            .attr("stroke-width", 1)
            .style("transition", "stroke-opacity 0.3s ease");

        // Draw nodes
        const nodes = nodeGroup
            .selectAll("circle")
            .data(data.nodes)
            .join("circle")
            .attr("r", (d) => (d.isCurrentUser ? 12 : 8))
            .attr("fill", "#111")
            .attr("stroke", (d) => d.color)
            .attr("stroke-width", (d) => (d.isCurrentUser ? 2.5 : 1.5))
            .attr("filter", "url(#glow-node)")
            .style("opacity", 0)
            .style("transition", "opacity 0.3s ease")
            .style("cursor", "pointer")
            .on("click", (event, d) => {
                live?.pushEvent("node_clicked", { user_id: d.id });
            })
            .call(
                d3
                    .drag()
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
            );

        // Draw labels
        const labels = labelGroup
            .selectAll("text")
            .data(data.nodes)
            .join("text")
            .text((d) => d.label)
            .attr("font-size", (d) => (d.isCurrentUser ? "11px" : "9px"))
            .attr("font-family", "Outfit, sans-serif")
            .attr("fill", "#ffffff")
            .attr("text-anchor", "middle")
            .attr("dy", 20)
            .style("opacity", 0)
            .style("transition", "opacity 0.3s ease")
            .style("pointer-events", "none");

        // Update positions on tick
        simulation.on("tick", () => {
            links
                .attr("x1", (d) => d.source.x)
                .attr("y1", (d) => d.source.y)
                .attr("x2", (d) => d.target.x)
                .attr("y2", (d) => d.target.y);

            nodes.attr("cx", (d) => d.x).attr("cy", (d) => d.y);

            labels.attr("x", (d) => d.x).attr("y", (d) => d.y);
        });
    }

    function updateGraph(percent) {
        if (!svg || !graphData) return;

        const range = maxTime - minTime;
        const cutoffTime = minTime + range * (percent / 100);

        const mainGroup = svg.select(".main");

        // Toggle visibility of nodes based on timestamp
        let visibleNodeCount = 0;
        mainGroup.selectAll("circle").each(function (d) {
            const visible = d.connectedAt <= cutoffTime;
            if (visible) visibleNodeCount++;
            d3.select(this).style("opacity", visible ? 1 : 0);
        });

        // Toggle visibility of labels
        mainGroup.selectAll("text").each(function (d) {
            const visible = d.connectedAt <= cutoffTime;
            d3.select(this).style("opacity", visible ? 1 : 0);
        });

        // Toggle visibility of links
        let visibleEdgeCount = 0;
        mainGroup.selectAll("line").each(function (d) {
            const sourceVisible = d.source.connectedAt <= cutoffTime;
            const targetVisible = d.target.connectedAt <= cutoffTime;
            const visible =
                sourceVisible && targetVisible && d.connectedAt <= cutoffTime;
            if (visible) visibleEdgeCount++;
            d3.select(this).attr("stroke-opacity", visible ? 0.4 : 0);
        });

        currentStats = { nodes: visibleNodeCount, edges: visibleEdgeCount };
    }

    // Time Travel reactivity
    $: if (svg && graphData) {
        updateGraph(timeValue);
    }

    function togglePlay() {
        isPlaying = !isPlaying;
        if (isPlaying) {
            if (timeValue >= 100) timeValue = 0;
            animate();
        } else {
            cancelAnimationFrame(animationFrame);
        }
    }

    function animate() {
        if (!isPlaying) return;
        timeValue += 0.5;
        if (timeValue >= 100) {
            timeValue = 100;
            isPlaying = false;
            return;
        }
        animationFrame = requestAnimationFrame(animate);
    }

    // ResizeObserver for responsiveness
    let resizeObserver;

    onMount(() => {
        initGraph();

        if (container) {
            resizeObserver = new ResizeObserver((entries) => {
                for (const entry of entries) {
                    const newWidth = entry.contentRect.width;
                    if (Math.abs(newWidth - width) > 50) {
                        initGraph();
                    }
                }
            });
            resizeObserver.observe(container);
        }

        window.addEventListener("phx:global-graph-updated", (e) => {
            if (e.detail.graph_data) {
                graphData = e.detail.graph_data;
                initGraph();
            }
        });
    });

    onDestroy(() => {
        if (simulation) simulation.stop();
        if (animationFrame) cancelAnimationFrame(animationFrame);
        if (resizeObserver) resizeObserver.disconnect();
    });
</script>

<div class="relative w-full h-full">
    <!-- Graph Container -->
    <div bind:this={container} class="w-full h-full"></div>

    <!-- Time Travel Controls -->
    <div
        class="absolute bottom-6 left-6 right-6 p-4 rounded-2xl border border-white/5 bg-black/30 backdrop-blur-md flex items-center gap-4 z-20"
    >
        <button
            class="w-8 h-8 flex items-center justify-center rounded-full bg-white/5 hover:bg-white/10 border border-white/10 hover:border-blue-500/50 text-white hover:text-blue-400 transition-all active:scale-95 shadow-[0_0_10px_rgba(0,0,0,0.5)] hover:shadow-[0_0_15px_rgba(59,130,246,0.3)] cursor-pointer"
            on:click|stopPropagation={togglePlay}
        >
            {#if isPlaying}
                <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="w-3 h-3"
                    viewBox="0 0 24 24"
                    fill="currentColor"
                >
                    <path d="M6 4h4v16H6V4zm8 0h4v16h-4V4z" />
                </svg>
            {:else}
                <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="w-3 h-3 ml-0.5"
                    viewBox="0 0 24 24"
                    fill="currentColor"
                >
                    <path d="M8 5v14l11-7z" />
                </svg>
            {/if}
        </button>

        <div class="flex-1 flex flex-col gap-1">
            <div
                class="flex justify-between text-[10px] text-neutral-400 font-mono uppercase tracking-widest"
            >
                <span
                    >{new Date(minTime).toLocaleDateString("en-US", {
                        month: "short",
                        day: "numeric",
                    })}</span
                >
                <span class="text-white font-semibold flex items-center gap-2">
                    {currentDate}
                    {#if isPlaying}
                        <span
                            class="w-1.5 h-1.5 rounded-full bg-blue-500 animate-pulse shadow-[0_0_5px_#3B82F6]"
                        ></span>
                    {/if}
                </span>
            </div>
            <input
                type="range"
                min="0"
                max="100"
                step="0.1"
                bind:value={timeValue}
                on:change={() => (isPlaying = false)}
                on:input|stopPropagation
                on:click|stopPropagation
                class="w-full h-1 bg-white/10 rounded-lg appearance-none cursor-pointer [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:w-3 [&::-webkit-slider-thumb]:h-3 [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:bg-white [&::-webkit-slider-thumb]:shadow-[0_0_15px_#3B82F6] [&::-webkit-slider-thumb]:border-[1px] [&::-webkit-slider-thumb]:border-blue-200"
            />
        </div>

        <div
            class="flex items-center gap-3 px-3 py-1 rounded-full bg-black/40 border border-white/5 shadow-inner"
        >
            <div class="flex items-center gap-2">
                <div
                    class="w-1.5 h-1.5 rounded-full bg-blue-500 animate-pulse shadow-[0_0_8px_#3B82F6]"
                ></div>
                <div class="text-[10px] font-mono font-medium text-neutral-400">
                    <span class="text-white text-base mr-1"
                        >{currentStats.nodes}</span
                    >users
                </div>
            </div>
            <div class="w-px h-4 bg-white/10"></div>
            <div class="text-[10px] font-mono font-medium text-neutral-400">
                <span class="text-white text-base mr-1"
                    >{currentStats.edges}</span
                >connections
            </div>
        </div>
    </div>
</div>

<style>
    input[type="range"]::-webkit-slider-thumb {
        -webkit-appearance: none;
        height: 14px;
        width: 14px;
        border-radius: 50%;
        background: #ffffff;
        box-shadow: 0 0 10px rgba(255, 255, 255, 0.6);
        cursor: pointer;
        margin-top: -5px;
    }
</style>
