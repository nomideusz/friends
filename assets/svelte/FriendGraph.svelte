<script>
  import { onMount, onDestroy } from "svelte";
  import * as d3 from "d3";

  // Props from Phoenix LiveView
  export let graphData = null;
  export let live = null;

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

  // Aether Design Tokens
  const colors = {
    self: "#ffffff",
    trusted: "#34d399",
    trusts_me: "#a78bfa",
    friend: "#3b82f6",
    second_degree: "#6b7280",
  };

  // Convert Phoenix data to D3 format - includes ALL data with timestamps
  function buildAllData(data) {
    if (!data || !data.nodes) return { nodes: [], links: [] };

    const nodes = [];
    const links = [];
    const nodeMap = new Map();

    // Process ALL nodes
    data.nodes.forEach((node) => {
      // Default to maxTime if no timestamp, so node appears at the end
      const nodeTime = node.connected_at
        ? new Date(node.connected_at).getTime()
        : Date.now(); // Default to present time

      let label = node.display_name || node.username;
      if (node.mutual_count && node.mutual_count > 0 && node.type !== "self") {
        label += ` (${node.mutual_count})`;
      }

      const n = {
        id: String(node.id),
        label: label,
        type: node.type,
        color: colors[node.type] || colors.second_degree,
        mutual_count: node.mutual_count || 0,
        connectedAt: nodeTime, // Store timestamp for visibility filtering
        // Initialize position at center
        x: width / 2 + (Math.random() - 0.5) * 50,
        y: height / 2 + (Math.random() - 0.5) * 50,
        // Fix self at center
        fx: node.type === "self" ? width / 2 : null,
        fy: node.type === "self" ? height / 2 : null,
      };
      nodes.push(n);
      nodeMap.set(n.id, n);
    });

    // Process ALL edges
    if (data.edges) {
      data.edges.forEach((edge) => {
        // Default to present time if no timestamp
        const edgeTime = edge.connected_at
          ? new Date(edge.connected_at).getTime()
          : Date.now();

        const source = nodeMap.get(String(edge.from));
        const target = nodeMap.get(String(edge.to));
        if (source && target) {
          links.push({
            source: source.id,
            target: target.id,
            type: edge.type,
            color: colors[edge.type] || "#ffffff",
            connectedAt: edgeTime, // Store timestamp for visibility filtering
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

    // Calculate time range
    const dates = [];
    (graphData.nodes || []).forEach((n) => {
      if (n.connected_at) dates.push(new Date(n.connected_at).getTime());
    });
    (graphData.edges || []).forEach((e) => {
      if (e.connected_at) dates.push(new Date(e.connected_at).getTime());
    });
    if (dates.length > 0) {
      minTime = Math.min(...dates) - 1000 * 60 * 60 * 24 * 7;
      maxTime = Math.max(...dates);
    }

    // Build ALL data once (visibility controlled by updateGraph)
    const data = buildAllData(graphData);
    currentStats = { nodes: data.nodes.length, edges: data.links.length };

    // Create SVG - no viewBox for proper scaling
    d3.select(container).selectAll("*").remove();
    svg = d3
      .select(container)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .style("background", "transparent");

    // Define glow filters
    const defs = svg.append("defs");

    // Create glow filters for ALL node types
    const allColors = { ...colors };
    Object.entries(allColors).forEach(([type, color]) => {
      const filter = defs
        .append("filter")
        .attr("id", `glow-${type}`)
        .attr("x", "-100%")
        .attr("y", "-100%")
        .attr("width", "300%")
        .attr("height", "300%");

      filter
        .append("feGaussianBlur")
        .attr("stdDeviation", type === "self" ? "4" : "3")
        .attr("result", "blur");

      filter
        .append("feFlood")
        .attr("flood-color", color)
        .attr("flood-opacity", type === "self" ? "0.5" : "0.6")
        .attr("result", "color");

      filter
        .append("feComposite")
        .attr("in", "color")
        .attr("in2", "blur")
        .attr("operator", "in")
        .attr("result", "glow");

      const merge = filter.append("feMerge");
      merge.append("feMergeNode").attr("in", "glow");
      merge.append("feMergeNode").attr("in", "glow");
      merge.append("feMergeNode").attr("in", "SourceGraphic");
    });

    // Create main group for zoom/pan
    const mainGroup = svg.append("g").attr("class", "main");

    // Add zoom behavior
    const zoom = d3
      .zoom()
      .scaleExtent([0.3, 3])
      .on("zoom", (event) => {
        mainGroup.attr("transform", event.transform);
      });
    svg.call(zoom);

    // Apply initial zoom to scale up and center the graph
    const initialScale = 1.8;
    const initialTransform = d3.zoomIdentity
      .translate(width / 2, height / 2)
      .scale(initialScale)
      .translate(-width / 2, -height / 2);
    svg.call(zoom.transform, initialTransform);

    // Create groups inside main group
    const linkGroup = mainGroup.append("g").attr("class", "links");
    const nodeGroup = mainGroup.append("g").attr("class", "nodes");
    const labelGroup = mainGroup.append("g").attr("class", "labels");

    // Create simulation with variable link distances
    simulation = d3
      .forceSimulation(data.nodes)
      .force(
        "link",
        d3
          .forceLink(data.links)
          .id((d) => d.id)
          .distance((d) => {
            // 2nd degree connections should be longer to push them outward
            const sourceType =
              typeof d.source === "object"
                ? d.source.type
                : data.nodes.find((n) => n.id === d.source)?.type;
            const targetType =
              typeof d.target === "object"
                ? d.target.type
                : data.nodes.find((n) => n.id === d.target)?.type;
            if (
              sourceType === "second_degree" ||
              targetType === "second_degree"
            ) {
              return 120; // Longer distance for 2nd degree
            }
            return 70; // Shorter for direct connections
          }),
      )
      .force("charge", d3.forceManyBody().strength(-200))
      // Only apply center force to non-2nd-degree nodes
      .force(
        "x",
        d3
          .forceX(width / 2)
          .strength((d) => (d.type === "second_degree" ? 0.01 : 0.05)),
      )
      .force(
        "y",
        d3
          .forceY(height / 2)
          .strength((d) => (d.type === "second_degree" ? 0.01 : 0.05)),
      )
      .force("collide", d3.forceCollide().radius(20));

    // Draw links - start all invisible, visibility controlled by updateGraph
    const links = linkGroup
      .selectAll("line")
      .data(data.links)
      .join("line")
      .attr("stroke", (d) => d.color)
      .attr("stroke-opacity", 0) // Start invisible - updateGraph will control
      .attr("stroke-width", (d) => (d.type === "mutual" ? 0.8 : 1.2))
      .style("transition", "stroke-opacity 0.3s ease"); // CSS transition for smooth animation

    // Draw nodes - start non-self invisible, visibility controlled by updateGraph
    const nodes = nodeGroup
      .selectAll("circle")
      .data(data.nodes)
      .join("circle")
      .attr("r", (d) =>
        d.type === "self" ? 12 : d.type === "second_degree" ? 7 : 10,
      )
      .attr("fill", (d) => (d.type === "self" ? "#ffffff" : "#111"))
      .attr("stroke", (d) => d.color)
      .attr("stroke-width", (d) => (d.type === "self" ? 0 : 1.5))
      .attr("filter", (d) => `url(#glow-${d.type})`)
      .style("opacity", (d) => (d.type === "self" ? 1 : 0)) // Non-self start invisible
      .style("transition", "opacity 0.3s ease") // CSS transition for smooth animation
      .style("cursor", "pointer")
      .on("click", (event, d) => {
        if (d.type !== "self") {
          if (d.type === "second_degree") {
            live?.pushEvent("add_friend_from_graph", { user_id: d.id });
          } else {
            live?.pushEvent("node_clicked", { user_id: d.id });
          }
        }
      })
      .call(
        d3
          .drag()
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
            // Keep self fixed, release others
            if (d.type !== "self") {
              d.fx = null;
              d.fy = null;
            }
          }),
      );

    // Draw labels - start non-self invisible, visibility controlled by updateGraph
    const labels = labelGroup
      .selectAll("text")
      .data(data.nodes)
      .join("text")
      .text((d) => d.label)
      .attr("font-size", (d) => (d.type === "self" ? "11px" : "9px"))
      .attr("font-family", "Outfit, sans-serif")
      .attr("fill", (d) => (d.type === "second_degree" ? "#6b7280" : "#ffffff"))
      .attr("text-anchor", "middle")
      .attr("dy", (d) => (d.type === "self" ? 22 : 16))
      .style("opacity", (d) => (d.type === "self" ? 1 : 0)) // Non-self start invisible
      .style("transition", "opacity 0.3s ease") // CSS transition for smooth animation
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

    // Select all elements from the main group
    const mainGroup = svg.select(".main");

    // Toggle visibility of nodes based on timestamp - no transition for rapid updates
    mainGroup.selectAll("circle").each(function (d) {
      const visible = d.type === "self" || d.connectedAt <= cutoffTime;
      d3.select(this).style("opacity", visible ? 1 : 0);
    });

    // Toggle visibility of labels based on timestamp
    mainGroup.selectAll("text").each(function (d) {
      const visible = d.type === "self" || d.connectedAt <= cutoffTime;
      d3.select(this).style("opacity", visible ? 1 : 0);
    });

    // Toggle visibility of links based on timestamp
    mainGroup.selectAll("line").each(function (d) {
      const sourceVisible =
        d.source.type === "self" || d.source.connectedAt <= cutoffTime;
      const targetVisible =
        d.target.type === "self" || d.target.connectedAt <= cutoffTime;
      const visible =
        sourceVisible && targetVisible && d.connectedAt <= cutoffTime;
      const baseOpacity = d.type === "mutual" ? 0.2 : 0.5;
      d3.select(this).attr("stroke-opacity", visible ? baseOpacity : 0);
    });

    // Update stats for visible nodes
    const visibleNodes = mainGroup
      .selectAll("circle")
      .filter(function (d) {
        return d.type === "self" || d.connectedAt <= cutoffTime;
      })
      .size();
    currentStats = { nodes: visibleNodes, edges: 0 };
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

  onMount(() => {
    initGraph();
    window.addEventListener("phx:graph-updated", (e) => {
      if (e.detail.graph_data) {
        graphData = e.detail.graph_data;
        initGraph();
      }
    });
    window.addEventListener("resize", initGraph);
  });

  onDestroy(() => {
    if (simulation) simulation.stop();
    if (animationFrame) cancelAnimationFrame(animationFrame);
    window.removeEventListener("resize", initGraph);
  });
</script>

<div class="relative w-full h-full">
  <!-- Graph Container -->
  <div bind:this={container} class="w-full h-full"></div>

  <!-- Legend -->
  <div
    class="absolute top-4 right-4 p-3 bg-black/70 backdrop-blur-md rounded-lg border border-white/10 text-xs text-white space-y-2 pointer-events-none z-10"
  >
    <div
      class="font-semibold border-b border-white/10 pb-1 uppercase tracking-wider text-[10px] text-neutral-400"
    >
      Legend
    </div>
    <div class="flex items-center gap-2">
      <div class="w-3 h-3 rounded-full bg-white"></div>
      <span>You</span>
    </div>
    <div class="flex items-center gap-2">
      <div
        class="w-2.5 h-2.5 rounded-full border-2"
        style="border-color: {colors.trusted}; box-shadow: 0 0 6px {colors.trusted}"
      ></div>
      <span>Trusted</span>
    </div>
    <div class="flex items-center gap-2">
      <div
        class="w-2.5 h-2.5 rounded-full border-2"
        style="border-color: {colors.trusts_me}; box-shadow: 0 0 6px {colors.trusts_me}"
      ></div>
      <span>Trusts You</span>
    </div>
    <div class="flex items-center gap-2">
      <div
        class="w-2.5 h-2.5 rounded-full border-2"
        style="border-color: {colors.friend}; box-shadow: 0 0 6px {colors.friend}"
      ></div>
      <span>Friend</span>
    </div>
    <div class="flex items-center gap-2">
      <div class="w-2 h-2 rounded-full border border-gray-500/50"></div>
      <span class="text-neutral-400">2nd Degree</span>
    </div>
  </div>

  <!-- Time Travel -->
  <div
    class="absolute bottom-0 left-0 right-0 px-4 py-2 bg-gradient-to-t from-black via-black/80 to-transparent"
  >
    <div class="flex items-center gap-4 max-w-2xl mx-auto">
      <button
        class="flex items-center justify-center w-10 h-10 rounded-full bg-white/10 hover:bg-white/20 text-white transition-all active:scale-95"
        on:click={togglePlay}
      >
        {#if isPlaying}
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="w-4 h-4"
            viewBox="0 0 24 24"
            fill="currentColor"><path d="M6 4h4v16H6V4zm8 0h4v16h-4V4z" /></svg
          >
        {:else}
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="w-4 h-4 ml-0.5"
            viewBox="0 0 24 24"
            fill="currentColor"><path d="M8 5v14l11-7z" /></svg
          >
        {/if}
      </button>

      <div class="flex-1 flex flex-col gap-1">
        <div
          class="flex justify-between text-[10px] text-neutral-500 font-mono uppercase tracking-widest"
        >
          <span
            >{new Date(minTime).toLocaleDateString("en-US", {
              month: "short",
              year: "2-digit",
            })}</span
          >
          <span class="text-white font-semibold">{currentDate}</span>
          <span>Now</span>
        </div>
        <input
          type="range"
          min="0"
          max="100"
          step="0.1"
          bind:value={timeValue}
          on:change={() => (isPlaying = false)}
          class="w-full h-1.5 bg-white/10 rounded-lg appearance-none cursor-pointer accent-blue-500"
        />
      </div>

      <div class="text-right min-w-[70px]">
        <div
          class="text-[10px] text-neutral-500 uppercase tracking-widest font-mono"
        >
          Network
        </div>
        <div class="text-xl font-bold text-white leading-none">
          {currentStats.nodes}
          <span class="text-xs font-normal text-neutral-600">nodes</span>
        </div>
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
