<script>
    import { onMount, onDestroy } from "svelte";
    import * as d3 from "d3";

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
        light: '#EAE6DD',      // Primary text
        dim: '#888888',        // Secondary
        energy: '#3B82F6',     // Blue accent (connections)
        you: '#14B8A6',        // Teal/cyan (current user) - blue-green mix
    };

    let container;
    let svg;
    let simulation;
    let width = 800;
    let height = 600;
    let animationFrame;
    
    // Live update state
    let nodesData = [];
    let linksData = [];
    let nodeGroup;
    let labelGroup;
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
        
        // For mobile, zoom in a bit more for better visibility
        // For desktop, use a slightly tighter view
        const contentSize = isMobile ? 500 : 350;
        const minDimension = Math.min(width, height);
        const padding = isMobile ? 60 : 20;
        
        let initialScale = (minDimension - padding) / contentSize;
        // Cap max zoom - allow closer view on mobile
        initialScale = Math.min(initialScale, isMobile ? 0.85 : 1.2);
        // Ensure minimum zoom for very small screens
        initialScale = Math.max(initialScale, 0.3);

        const initialTransform = d3.zoomIdentity
            .translate(width / 2, height / 2)
            .scale(initialScale)
            .translate(-width / 2, -height / 2);
        svg.call(zoom.transform, initialTransform);

        // Create groups - store references for live updates
        linkGroup = mainGroup.append("g").attr("class", "links");
        nodeGroup = mainGroup.append("g").attr("class", "nodes");
        labelGroup = mainGroup.append("g").attr("class", "labels");
        
        // Store data for live updates
        nodesData = data.nodes;
        linksData = data.links;
        // Build nodeMap for fast lookup
        nodeMap.clear();
        nodesData.forEach(n => nodeMap.set(n.id, n));

        // Simulation - tighter clustering on mobile, lonely nodes pulled to center
        const linkDistance = isMobile ? 45 : 70;
        const chargeStrength = isMobile ? -45 : -80;
        const collideRadius = isMobile ? 10 : 12;
        const centerStrength = isMobile ? 0.06 : 0.03; // Pull lonely nodes to center
        
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
            .force("x", d3.forceX(width / 2).strength(centerStrength))
            .force("y", d3.forceY(height / 2).strength(centerStrength))
            .force("collide", d3.forceCollide().radius(collideRadius));

        // Draw edges - subtle energy blue
        const links = linkGroup
            .selectAll("line")
            .data(data.links)
            .join("line")
            .attr("stroke", COLORS.energy)
            .attr("stroke-opacity", isMobile ? 0.18 : 0.15)
            .attr("stroke-width", isMobile ? 1.5 : 1);

        // Draw nodes - same size for all, visually distinctive current user
        const nodeRadius = isMobile ? 5 : 5;
        const currentUserIdStr = currentUserId ? String(currentUserId) : null;
        
        // No outer ring - self node is just blue, others are white
        
        
        const nodes = nodeGroup
            .selectAll("circle")
            .data(data.nodes)
            .join("circle")
            .attr("r", nodeRadius)
            .attr("fill", d => d.id === currentUserIdStr ? COLORS.energy : "#ffffff")
            .attr("stroke", d => d.id === currentUserIdStr ? COLORS.energy : "#ffffff")
            .attr("stroke-opacity", 0.5)
            .attr("stroke-width", 1)
            .attr("filter", "url(#node-glow)")
            .style("fill-opacity", d => {
                if (d.id === currentUserIdStr) return 1;
                return hideControls ? 0.5 : 0.85;
            })
            .style("cursor", "pointer")
            .on("mouseenter", function(event, d) {
                if (d.id === currentUserIdStr) return;
                showLabel(d);
                // Highlight on hover
                d3.select(this)
                    .transition().duration(150)
                    .attr("r", nodeRadius + 1.5)
                    .style("fill-opacity", 1);
            })
            .on("mouseleave", function(event, d) {
                if (d.id === currentUserIdStr) return;
                hideLabel(d);
                // Return to normal
                d3.select(this)
                    .transition().duration(150)
                    .attr("r", nodeRadius)
                    .style("fill-opacity", hideControls ? 0.5 : 0.85);
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
        
        // Add current user's label (always visible)
        if (currentUserIdStr) {
            const currentUserNode = data.nodes.find(n => n.id === currentUserIdStr);
            if (currentUserNode) {
                labelGroup
                    .append("text")
                    .attr("class", "current-user-label")
                    .attr("data-node-id", currentUserIdStr)
                    .attr("x", currentUserNode.x)
                    .attr("y", currentUserNode.y - nodeRadius - 6)
                    .attr("text-anchor", "middle")
                    .attr("fill", COLORS.light)
                    .attr("font-size", "8px")
                    .attr("font-family", "'IBM Plex Mono', monospace")
                    .attr("font-weight", "400")
                    .attr("letter-spacing", "0.05em")
                    .style("opacity", 0.8)
                    .text(currentUserNode.username || currentUserNode.name || 'you');
            }
        }
        
        // Helper: show label on hover
        function showLabel(d) {
            const label = labelGroup.select(`text[data-node-id="${d.id}"]`);
            if (label.empty()) {
                labelGroup
                    .append("text")
                    .attr("data-node-id", d.id)
                    .attr("x", d.x)
                    .attr("y", d.y - nodeRadius - 6)
                    .attr("text-anchor", "middle")
                    .attr("fill", COLORS.dim)
                    .attr("font-size", "8px")
                    .attr("font-family", "'IBM Plex Mono', monospace")
                    .attr("font-weight", "400")
                    .attr("letter-spacing", "0.05em")
                    .style("opacity", 0)
                    .text(d.username || d.name || d.id)
                    .transition()
                    .duration(150)
                    .style("opacity", 0.8);
            }
        }
        
        // Helper: hide label on hover out
        function hideLabel(d) {
            labelGroup.select(`text[data-node-id="${d.id}"]:not(.current-user-label)`)
                .transition()
                .duration(150)
                .style("opacity", 0)
                .remove();
        }

        // Tick handler - uses selectAll to include dynamically added elements
        simulation.on("tick", () => {
            // Query all current links from the group (includes dynamically added ones)
            linkGroup.selectAll("line")
                .attr("x1", (d) => d.source.x)
                .attr("y1", (d) => d.source.y)
                .attr("x2", (d) => d.target.x)
                .attr("y2", (d) => d.target.y);

            // Query all current nodes
            nodeGroup.selectAll("circle")
                .attr("cx", (d) => d.x)
                .attr("cy", (d) => d.y);
            
            // Update label positions
            labelGroup.selectAll("text")
                .attr("x", function() {
                    const nodeId = d3.select(this).attr("data-node-id");
                    const node = nodesData.find(n => n.id === nodeId);
                    return node ? node.x : 0;
                })
                .attr("y", function() {
                    const nodeId = d3.select(this).attr("data-node-id");
                    const node = nodesData.find(n => n.id === nodeId);
                    const isCurrentUser = d3.select(this).classed("current-user-label");
                    const offset = isCurrentUser ? nodeRadius * 2 + 4 : nodeRadius + 6;
                    return node ? node.y - offset : 0;
                });
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
</div>
