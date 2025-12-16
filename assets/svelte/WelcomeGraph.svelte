<script>
    import { onMount, onDestroy } from "svelte";
    import * as d3 from "d3";

    // Props from Phoenix LiveView
    export let graphData = null;
    export let live = null;
    export let onSkip = null;

    let container;
    let svg;
    let simulation;
    let width = 800;
    let height = 600;
    let animationFrame;
    let dontShowAgain = false;

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
            .attr("flood-opacity", "0.3")
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

        // Initial zoom to center
        const initialScale = 1.5;
        const initialTransform = d3.zoomIdentity
            .translate(width / 2, height / 2)
            .scale(initialScale)
            .translate(-width / 2, -height / 2);
        svg.call(zoom.transform, initialTransform);

        // Create groups
        const linkGroup = mainGroup.append("g").attr("class", "links");
        const nodeGroup = mainGroup.append("g").attr("class", "nodes");

        // Simulation
        simulation = d3
            .forceSimulation(data.nodes)
            .force(
                "link",
                d3
                    .forceLink(data.links)
                    .id((d) => d.id)
                    .distance(80),
            )
            .force("charge", d3.forceManyBody().strength(-100))
            .force("center", d3.forceCenter(width / 2, height / 2))
            .force("collide", d3.forceCollide().radius(15));

        // Draw edges - monochrome
        const links = linkGroup
            .selectAll("line")
            .data(data.links)
            .join("line")
            .attr("stroke", "#ffffff")
            .attr("stroke-opacity", 0.08)
            .attr("stroke-width", 1);

        // Draw nodes - all same size, monochrome
        const nodes = nodeGroup
            .selectAll("circle")
            .data(data.nodes)
            .join("circle")
            .attr("r", 5)
            .attr("fill", "#0a0a0a")
            .attr("stroke", "#ffffff")
            .attr("stroke-opacity", 0.4)
            .attr("stroke-width", 1)
            .attr("filter", "url(#node-glow)")
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

        // Tick handler
        simulation.on("tick", () => {
            links
                .attr("x1", (d) => d.source.x)
                .attr("y1", (d) => d.source.y)
                .attr("x2", (d) => d.target.x)
                .attr("y2", (d) => d.target.y);

            nodes.attr("cx", (d) => d.x).attr("cy", (d) => d.y);
        });
    }

    function buildData(data) {
        if (!data || !data.nodes) return { nodes: [], links: [] };

        const nodes = [];
        const links = [];
        const nodeMap = new Map();

        // Process nodes
        data.nodes.forEach((node) => {
            const n = {
                id: String(node.id),
                x: width / 2 + (Math.random() - 0.5) * 300,
                y: height / 2 + (Math.random() - 0.5) * 300,
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

<div class="fixed inset-0 z-50 bg-black">
    <!-- Graph Container -->
    <div bind:this={container} class="w-full h-full"></div>

    <!-- Skip Button (top-right) -->
    <button
        on:click={handleSkip}
        class="absolute top-6 right-6 text-white/40 hover:text-white text-sm font-medium transition-colors cursor-pointer"
    >
        Enter →
    </button>

    <!-- Don't show again (bottom-right) -->
    <label
        class="absolute bottom-6 right-6 text-white/30 text-xs flex items-center gap-2 cursor-pointer hover:text-white/50 transition-colors"
    >
        <input
            type="checkbox"
            bind:checked={dontShowAgain}
            class="w-3 h-3 rounded border-white/30 bg-transparent"
        />
        Don't show this again
    </label>
</div>
