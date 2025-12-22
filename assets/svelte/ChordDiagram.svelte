<script>
    import { onMount, onDestroy } from "svelte";
    import * as d3 from "d3";

    // Props from Phoenix LiveView
    export let chordData = null;
    export let live = null;

    let container;
    let svg;
    let width = 800;
    let height = 800;

    // Tooltip state
    let tooltip = { show: false, x: 0, y: 0, content: "" };

    // Color definitions
    const groupColors = {
        self: "#ffffff",
        recovery: "#34d399",
        recovers_me: "#a78bfa",
        friend: "#3b82f6",
        member: "#14b8a6",
    };

    function initChord() {
        if (!container || !chordData || !chordData.nodes || !chordData.matrix)
            return;

        const rect = container.getBoundingClientRect();
        width = rect.width || 800;
        height = rect.height || 800;
        const outerRadius = Math.min(width, height) * 0.4;
        const innerRadius = outerRadius - 25;

        // Clear previous
        d3.select(container).selectAll("*").remove();

        svg = d3
            .select(container)
            .append("svg")
            .attr("width", width)
            .attr("height", height)
            .style("background", "transparent");

        // Define glow filters
        const defs = svg.append("defs");

        // Arc glow filter
        const arcGlow = defs
            .append("filter")
            .attr("id", "arc-glow")
            .attr("x", "-50%")
            .attr("y", "-50%")
            .attr("width", "200%")
            .attr("height", "200%");

        arcGlow
            .append("feGaussianBlur")
            .attr("stdDeviation", "3")
            .attr("result", "blur");

        const arcMerge = arcGlow.append("feMerge");
        arcMerge.append("feMergeNode").attr("in", "blur");
        arcMerge.append("feMergeNode").attr("in", "SourceGraphic");

        // Node glow filter
        const nodeGlow = defs
            .append("filter")
            .attr("id", "node-glow")
            .attr("x", "-100%")
            .attr("y", "-100%")
            .attr("width", "300%")
            .attr("height", "300%");

        nodeGlow
            .append("feGaussianBlur")
            .attr("stdDeviation", "4")
            .attr("result", "blur");

        nodeGlow
            .append("feFlood")
            .attr("flood-color", "#ffffff")
            .attr("flood-opacity", "0.4")
            .attr("result", "color");

        nodeGlow
            .append("feComposite")
            .attr("in", "color")
            .attr("in2", "blur")
            .attr("operator", "in")
            .attr("result", "glow");

        const nodeMerge = nodeGlow.append("feMerge");
        nodeMerge.append("feMergeNode").attr("in", "glow");
        nodeMerge.append("feMergeNode").attr("in", "SourceGraphic");

        // Create main group centered
        const mainGroup = svg
            .append("g")
            .attr("transform", `translate(${width / 2}, ${height / 2})`);

        // Create chord layout
        const chord = d3.chord().padAngle(0.04).sortSubgroups(d3.descending);

        const chords = chord(chordData.matrix);

        // Arc generator for outer ring
        const arc = d3.arc().innerRadius(innerRadius).outerRadius(outerRadius);

        // Ribbon generator for connections
        const ribbon = d3.ribbon().radius(innerRadius - 5);

        // Draw outer arcs (groups/nodes)
        const groups = mainGroup
            .append("g")
            .attr("class", "groups")
            .selectAll("g")
            .data(chords.groups)
            .join("g")
            .attr("class", "group");

        groups
            .append("path")
            .attr("class", "arc")
            .attr("d", arc)
            .attr("fill", (d) => chordData.nodes[d.index]?.color || "#666")
            .attr("stroke", (d) => chordData.nodes[d.index]?.color || "#666")
            .attr("stroke-width", 1)
            .attr("opacity", 0.85)
            .attr("filter", "url(#arc-glow)")
            .style("cursor", "pointer")
            .on("mouseenter", function (event, d) {
                const node = chordData.nodes[d.index];

                // Highlight this arc
                d3.select(this)
                    .transition()
                    .duration(200)
                    .attr("opacity", 1)
                    .attr("stroke-width", 2);

                // Dim unrelated ribbons
                mainGroup.selectAll(".ribbon").each(function (r) {
                    const related =
                        r.source.index === d.index ||
                        r.target.index === d.index;
                    d3.select(this)
                        .transition()
                        .duration(200)
                        .attr("opacity", related ? 0.8 : 0.1);
                });

                // Show tooltip
                tooltip = {
                    show: true,
                    x: event.clientX,
                    y: event.clientY,
                    content: node ? `${node.name} (${node.group})` : "",
                };
            })
            .on("mouseleave", function () {
                // Reset arc
                d3.select(this)
                    .transition()
                    .duration(200)
                    .attr("opacity", 0.85)
                    .attr("stroke-width", 1);

                // Reset ribbons
                mainGroup
                    .selectAll(".ribbon")
                    .transition()
                    .duration(200)
                    .attr("opacity", 0.5);

                tooltip = { show: false, x: 0, y: 0, content: "" };
            })
            .on("click", (event, d) => {
                const node = chordData.nodes[d.index];
                if (node && node.group !== "self") {
                    live?.pushEvent("chord_node_clicked", { user_id: node.id });
                }
            });

        // Add labels around the circumference
        groups
            .append("text")
            .each((d) => {
                d.angle = (d.startAngle + d.endAngle) / 2;
            })
            .attr("dy", "0.35em")
            .attr(
                "transform",
                (d) =>
                    `rotate(${(d.angle * 180) / Math.PI - 90}) translate(${outerRadius + 12}) ${d.angle > Math.PI ? "rotate(180)" : ""}`,
            )
            .attr("text-anchor", (d) => (d.angle > Math.PI ? "end" : "start"))
            .attr("fill", "#ffffff")
            .attr("font-size", "11px")
            .attr("font-family", "Outfit, sans-serif")
            .attr("font-weight", "500")
            .attr("opacity", 0.9)
            .style("pointer-events", "none")
            .text((d) => {
                const node = chordData.nodes[d.index];
                return node ? node.name : "";
            });

        // Draw ribbons (connections)
        mainGroup
            .append("g")
            .attr("class", "ribbons")
            .selectAll("path")
            .data(chords)
            .join("path")
            .attr("class", "ribbon")
            .attr("d", ribbon)
            .attr("fill", (d) => {
                // Use source node color with transparency
                const sourceNode = chordData.nodes[d.source.index];
                return sourceNode?.color || "#ffffff";
            })
            .attr("stroke", (d) => {
                const sourceNode = chordData.nodes[d.source.index];
                return sourceNode?.color || "#ffffff";
            })
            .attr("stroke-width", 0.5)
            .attr("opacity", 0.5)
            .style("mix-blend-mode", "screen")
            .on("mouseenter", function (event, d) {
                d3.select(this).transition().duration(200).attr("opacity", 0.9);

                const source = chordData.nodes[d.source.index];
                const target = chordData.nodes[d.target.index];
                tooltip = {
                    show: true,
                    x: event.clientX,
                    y: event.clientY,
                    content: `${source?.name || "?"} ↔ ${target?.name || "?"}`,
                };
            })
            .on("mouseleave", function () {
                d3.select(this).transition().duration(200).attr("opacity", 0.5);
                tooltip = { show: false, x: 0, y: 0, content: "" };
            });

        // Add center label
        mainGroup
            .append("text")
            .attr("text-anchor", "middle")
            .attr("dy", "-0.5em")
            .attr("fill", "#ffffff")
            .attr("font-size", "16px")
            .attr("font-family", "Outfit, sans-serif")
            .attr("font-weight", "600")
            .attr("opacity", 0.6)
            .text("Network");

        mainGroup
            .append("text")
            .attr("text-anchor", "middle")
            .attr("dy", "1em")
            .attr("fill", "#ffffff")
            .attr("font-size", "12px")
            .attr("font-family", "Outfit, sans-serif")
            .attr("opacity", 0.4)
            .text(`${chordData.nodes.length} connections`);
    }

    // ResizeObserver for responsiveness
    let resizeObserver;

    onMount(() => {
        initChord();

        if (container) {
            resizeObserver = new ResizeObserver((entries) => {
                for (const entry of entries) {
                    const newWidth = entry.contentRect.width;
                    if (Math.abs(newWidth - width) > 50) {
                        initChord();
                    }
                }
            });
            resizeObserver.observe(container);
        }

        // Listen for data updates
        window.addEventListener("phx:chord-updated", (e) => {
            if (e.detail.chord_data) {
                chordData = e.detail.chord_data;
                initChord();
            }
        });
    });

    onDestroy(() => {
        if (resizeObserver) resizeObserver.disconnect();
    });

    // Reactivity for data changes
    $: if (container && chordData) {
        initChord();
    }
</script>

<div class="relative w-full h-full">
    <!-- Chord Container -->
    <div bind:this={container} class="w-full h-full"></div>

    <!-- Tooltip -->
    {#if tooltip.show}
        <div
            class="fixed z-50 px-3 py-1.5 rounded-lg bg-black/80 backdrop-blur-md border border-white/10 text-white text-sm font-medium shadow-lg pointer-events-none"
            style="left: {tooltip.x + 10}px; top: {tooltip.y + 10}px;"
        >
            {tooltip.content}
        </div>
    {/if}

    <!-- Legend -->
    <div
        class="absolute bottom-4 left-4 p-3 rounded-xl bg-black/40 backdrop-blur-md border border-white/10"
    >
        <div
            class="text-[10px] uppercase tracking-widest text-neutral-400 mb-2"
        >
            Connection Types
        </div>
        <div class="flex flex-wrap gap-3">
            {#each Object.entries(groupColors) as [group, color]}
                <div class="flex items-center gap-1.5">
                    <div
                        class="w-2.5 h-2.5 rounded-full"
                        style="background: {color}; box-shadow: 0 0 8px {color};"
                    ></div>
                    <span class="text-xs text-neutral-300 capitalize"
                        >{group.replace("_", " ")}</span
                    >
                </div>
            {/each}
        </div>
    </div>

    <!-- Stats -->
    <div
        class="absolute top-4 right-4 px-3 py-2 rounded-xl bg-black/40 backdrop-blur-md border border-white/10"
    >
        <div class="flex items-center gap-3">
            <div class="text-[10px] font-mono font-medium text-neutral-400">
                <span class="text-white text-base mr-1"
                    >{chordData?.nodes?.length || 0}</span
                >nodes
            </div>
            <div class="w-px h-4 bg-white/10"></div>
            <div class="text-[10px] font-mono font-medium text-neutral-400">
                <span class="text-white text-base mr-1"
                    >{chordData?.matrix?.flat().filter((v) => v > 0).length /
                        2 || 0}</span
                >links
            </div>
        </div>
    </div>
</div>
