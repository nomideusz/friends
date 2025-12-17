<script>
    import { onMount, onDestroy } from "svelte";
    import * as d3 from "d3";

    // Props from Phoenix LiveView
    export let graphData = null;
    export let live = null;
    export let onSkip = null;
    // Whether to show the "Don't show again" checkbox (false for new users)
    export let showOptOut = true;
    // Whether to hide controls and fixed positioning (for background usage)
    export let hideControls = false;

    let container;
    let svg;
    let simulation;
    let width = 800;
    let height = 600;
    let animationFrame;
    let dontShowAgain = false;
    
    // Live update state
    let nodesData = [];
    let linksData = [];
    let nodeGroup;
    let linkGroup;
    let nodeMap = new Map();
    
    // Function to add a new user node dynamically
    export function addNode(userData) {
        if (!simulation || !nodeGroup) return;
        
        const id = String(userData.id || userData.user_id);
        if (nodeMap.has(id)) return; // Already exists
        
        const newNode = {
            ...userData,
            id,
            x: width / 2 + (Math.random() - 0.5) * 200,
            y: height / 2 + (Math.random() - 0.5) * 200
        };
        
        nodesData.push(newNode);
        nodeMap.set(id, newNode);
        
        // Update simulation
        simulation.nodes(nodesData);
        simulation.alpha(0.3).restart();
        
        // Redraw nodes with animation
        updateNodes();
    }
    
    // Function to remove a user node dynamically (when account is deleted)
    export function removeNode(userId) {
        if (!simulation || !nodeGroup) return;
        
        const id = String(userId);
        if (!nodeMap.has(id)) return; // Doesn't exist
        
        // Remove from nodeMap
        nodeMap.delete(id);
        
        // Remove from nodesData
        const nodeIndex = nodesData.findIndex(n => n.id === id);
        if (nodeIndex !== -1) {
            nodesData.splice(nodeIndex, 1);
        }
        
        // Remove any links connected to this node
        linksData = linksData.filter(l => 
            l.source.id !== id && l.target.id !== id
        );
        
        // Update simulation
        simulation.nodes(nodesData);
        simulation.force("link").links(linksData);
        simulation.alpha(0.3).restart();
        
        // Redraw with animation
        updateNodes();
        updateLinks();
    }
    
    // Function to add a new connection dynamically
    export function addLink(fromId, toId) {
        if (!simulation || !linkGroup) return;
        
        const source = nodeMap.get(String(fromId));
        const target = nodeMap.get(String(toId));
        if (!source || !target) return;
        
        // Check if link already exists
        const exists = linksData.some(l => 
            (l.source.id === source.id && l.target.id === target.id) ||
            (l.source.id === target.id && l.target.id === source.id)
        );
        if (exists) return;
        
        linksData.push({ source, target });
        
        // Update simulation
        simulation.force("link").links(linksData);
        simulation.alpha(0.3).restart();
        
        // Redraw links with animation
        updateLinks();
    }
    
    function updateNodes() {
        const nodes = nodeGroup
            .selectAll("circle")
            .data(nodesData, d => d.id);
            
        // Enter new nodes with animation
        nodes.enter()
            .append("circle")
            .attr("r", 0)
            .attr("cx", d => d.x)
            .attr("cy", d => d.y)
            .style("fill", "#ffffff")
            .style("fill-opacity", 0.8)
            .attr("filter", "url(#node-glow)")
            .call(d3.drag()
                .on("start", (event, d) => {
                    if (!event.active) simulation.alphaTarget(0.3).restart();
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
                })
            )
            .transition()
            .duration(500)
            .attr("r", 6);
            
        nodes.exit().transition().duration(300).attr("r", 0).remove();
    }
    
    function updateLinks() {
        const links = linkGroup
            .selectAll("line")
            .data(linksData, d => `${d.source.id}-${d.target.id}`);
            
        // Enter new links with animation
        links.enter()
            .append("line")
            .attr("stroke", "#ffffff")
            .attr("stroke-opacity", 0)
            .attr("stroke-width", 1)
            .attr("x1", d => d.source.x)
            .attr("y1", d => d.source.y)
            .attr("x2", d => d.target.x)
            .attr("y2", d => d.target.y)
            .transition()
            .duration(500)
            .attr("stroke-opacity", 0.08);
            
        links.exit().transition().duration(300).attr("stroke-opacity", 0).remove();
    }
    
    // Function to remove a connection dynamically
    export function removeLink(fromId, toId) {
        if (!simulation || !linkGroup) return;
        
        const srcId = String(fromId);
        const tgtId = String(toId);
        
        // Find and remove the link
        const linkIndex = linksData.findIndex(l => 
            (l.source.id === srcId && l.target.id === tgtId) ||
            (l.source.id === tgtId && l.target.id === srcId)
        );
        
        if (linkIndex === -1) return;
        
        linksData.splice(linkIndex, 1);
        
        // Update simulation
        simulation.force("link").links(linksData);
        simulation.alpha(0.3).restart();
        
        // Redraw links with animation
        updateLinks();
    }
    
    // Function to pulse a node (visualize a signal/post)
    export function pulseNode(id) {
        if (!nodeGroup) return;
        
        const nodeId = String(id);
        const circle = nodeGroup.selectAll("circle").filter(d => d.id === nodeId);
        
        if (!circle.empty()) {
             circle
                .transition()
                .duration(200)
                .attr("r", 15)
                .style("fill-opacity", 1)
                .attr("filter", null) // Remove glow temporarily to avoid artifact? Or keep it.
                .transition()
                .duration(600)
                .attr("r", width < 600 ? 8 : 5)
                .style("fill-opacity", 0.8)
                .attr("filter", "url(#node-glow)");
        }
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

        // Subtle glow filter
        const defs = svg.append("defs");
        const filter = defs
            .append("filter")
            .attr("id", "node-glow")
            .attr("x", "-100%")
            .attr("y", "-100%")
            .attr("width", "300%")
            .attr("height", "300%");

        filter
            .append("feGaussianBlur")
            .attr("stdDeviation", "2")
            .attr("result", "blur");

        filter
            .append("feFlood")
            .attr("flood-color", "#ffffff")
            .attr("flood-opacity", "0.8")
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

        // Main group with zoom
        const mainGroup = svg.append("g").attr("class", "main");

        const zoom = d3
            .zoom()
            .scaleExtent([0.5, 3])
            .on("zoom", (event) => {
                mainGroup.attr("transform", event.transform);
            });
        svg.call(zoom);

        // Initial zoom to center with dynamic scale
        // Calculate based on actual data bounds for better mobile fit
        const isMobile = width < 600;
        
        // For background mode, disable wheel zoom to allow page scrolling
        if (hideControls) {
             zoom.filter((event) => {
                // Allow interactions, just not wheel
                return event.type !== 'wheel';
             });
        }
        
        // For mobile, zoom out significantly more to show all nodes
        // For desktop, use a slightly tighter view
        const contentSize = isMobile ? 600 : 350;
        const minDimension = Math.min(width, height);
        const padding = isMobile ? 80 : 20;
        
        let initialScale = (minDimension - padding) / contentSize;
        // Cap max zoom, allow zooming out more for mobile
        initialScale = Math.min(initialScale, isMobile ? 0.6 : 1.2);
        // Ensure minimum zoom for very small screens
        initialScale = Math.max(initialScale, 0.2);

        const initialTransform = d3.zoomIdentity
            .translate(width / 2, height / 2)
            .scale(initialScale)
            .translate(-width / 2, -height / 2);
        svg.call(zoom.transform, initialTransform);

        // Create groups - store references for live updates
        linkGroup = mainGroup.append("g").attr("class", "links");
        nodeGroup = mainGroup.append("g").attr("class", "nodes");
        
        // Store data for live updates
        nodesData = data.nodes;
        linksData = data.links;
        // Build nodeMap for fast lookup
        nodeMap.clear();
        nodesData.forEach(n => nodeMap.set(n.id, n));

        // Simulation - use smaller forces on mobile to keep nodes closer
        const linkDistance = isMobile ? 40 : 80;
        const chargeStrength = isMobile ? -50 : -100;
        const collideRadius = isMobile ? 12 : 15;
        
        simulation = d3
            .forceSimulation(nodesData)
            .force(
                "link",
                d3
                    .forceLink(linksData)
                    .id((d) => d.id)
                    .distance(linkDistance),
            )
            .force("charge", d3.forceManyBody().strength(chargeStrength))
            .force("center", d3.forceCenter(width / 2, height / 2))
            .force("collide", d3.forceCollide().radius(collideRadius));

        // Draw edges - monochrome
        const links = linkGroup
            .selectAll("line")
            .data(data.links)
            .join("line")
            .attr("stroke", "#ffffff")
            .attr("stroke-opacity", 0.08)
            .attr("stroke-width", 1);

        // Draw nodes - larger on mobile for better touch interaction
        const nodeRadius = isMobile ? 8 : 5;
        const nodes = nodeGroup
            .selectAll("circle")
            .data(data.nodes)
            .join("circle")
            .attr("r", nodeRadius)
            .attr("fill", "#ffffff")
            .attr("stroke", "#ffffff")
            .attr("stroke-opacity", 0.2)
            .attr("stroke-width", 1)
            .attr("filter", "url(#node-glow)")
            // Reduced opacity for background mode
            .style("fill-opacity", hideControls ? 0.4 : 0.8)
            .style("cursor", "default")
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

        // Tick handler - uses selectAll to include dynamically added elements
        simulation.on("tick", () => {
            // Query all current links from the group (includes dynamically added ones)
            linkGroup.selectAll("line")
                .attr("x1", (d) => d.source.x)
                .attr("y1", (d) => d.source.y)
                .attr("x2", (d) => d.target.x)
                .attr("y2", (d) => d.target.y);

            // Query all current nodes from the group (includes dynamically added ones)
            nodeGroup.selectAll("circle")
                .attr("cx", (d) => d.x)
                .attr("cy", (d) => d.y);
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

    onMount(() => {
        initGraph();

        // Handle resize
        const handleResize = () => {
            initGraph();
        };
        window.addEventListener("resize", handleResize);
        
        return () => {
            window.removeEventListener("resize", handleResize);
        };
    });

    onDestroy(() => {
        if (simulation) simulation.stop();
        if (animationFrame) cancelAnimationFrame(animationFrame);
    });
</script>

<div class={hideControls ? "w-full h-full" : "fixed inset-0 z-50 bg-black"}>
    <!-- Subtle Gradient Background - Always Visible -->
    <div class="absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(255,255,255,0.03)_0%,transparent_70%)] pointer-events-none"></div>

    <!-- Graph Container -->
    <div bind:this={container} class="w-full h-full relative z-10"></div>


    <!-- Controls (bottom-right) -->
    {#if !hideControls}
        <div class="absolute bottom-10 right-10 flex flex-col items-end gap-3 z-20">
            <button
                on:click={handleSkip}
                class="text-white/40 hover:text-white/90 text-xs font-mono tracking-[0.2em] uppercase transition-all duration-300 cursor-pointer flex items-center gap-2 group"
            >
                Proceed <span class="group-hover:translate-x-1 transition-transform">→</span>
            </button>

            {#if showOptOut}
                <label
                    class="group flex items-center gap-3 cursor-pointer select-none mt-2"
                >
                    <div class="relative w-3 h-3 border border-white/10 rounded-sm group-hover:border-white/30 transition-colors">
                        {#if dontShowAgain}
                            <div class="absolute inset-0 bg-white/60 m-0.5 rounded-[1px]"></div>
                        {/if}
                    </div>
                    <input
                        type="checkbox"
                        bind:checked={dontShowAgain}
                        class="hidden"
                    />
                    <span class="text-[9px] text-white/20 font-mono uppercase tracking-widest group-hover:text-white/40 transition-colors">
                        Don't show again
                    </span>
                </label>
            {/if}
        </div>
    {/if}
</div>
