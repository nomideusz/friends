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
    (graphData.nodes || []).forEach((node) => {
      // For 2nd degree nodes, we calculate visibility from edges.
      // Initialize to Infinity so we can find the EARLIEST connection.
      // Other nodes (Self, Friends) use their intrinsic connectedAt.
      const initialTime =
        node.type === "second_degree"
          ? Infinity
          : node.connected_at
            ? new Date(node.connected_at).getTime()
            : Date.now();

      let label = node.display_name || node.username;
      if (node.mutual_count && node.mutual_count > 0 && node.type !== "self") {
        label += ` (${node.mutual_count})`;
      }

      const n = {
        id: String(node.id),
        label: label,
        group: node.type === "self" ? 1 : 2,
        displayName: node.display_name || node.username,
        username: node.username,
        type: node.type,
        color: colors[node.type] || colors.second_degree,
        mutual_count: node.mutual_count || 0,
        connectedAt: initialTime,
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
          // LOGIC UPDATE: Smart Ego-Centric Visibility (Shortest Path)
          // A 2nd degree node (Target) becomes visible when a valid path (Me->Source->Target) completes.
          // Path completion time = max(Me->Source time, Source->Target time).
          // We take the MINIMUM of all path completion times (earliest discovery).

          if (source.type === "self" && target.type !== "self") {
            // Direct connection: Visible at edge time (which is Me->Target time)
            target.connectedAt = Math.min(target.connectedAt, edgeTime);
          } else if (target.type === "self" && source.type !== "self") {
            source.connectedAt = Math.min(source.connectedAt, edgeTime);
          } else if (
            source.type !== "second_degree" &&
            target.type === "second_degree"
          ) {
            // 1st -> 2nd
            const pathCompleteAt = Math.max(source.connectedAt, edgeTime);
            target.connectedAt = Math.min(target.connectedAt, pathCompleteAt);
          } else if (
            target.type !== "second_degree" &&
            source.type === "second_degree"
          ) {
            // 1st -> 2nd (Reverse)
            const pathCompleteAt = Math.max(target.connectedAt, edgeTime);
            source.connectedAt = Math.min(source.connectedAt, pathCompleteAt);
          }

          // Edge appears when BOTH connected nodes are visible AND the edge itself exists
          const effectiveTime = Math.max(
            source.connectedAt,
            target.connectedAt,
            edgeTime,
          );
          links.push({
            source: source.id,
            target: target.id,
            type: edge.type,
            color: colors[edge.type] || "#ffffff",
            connectedAt: effectiveTime, // Use later of: node A, node B, or the connection itself
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

  // ResizeObserver for robust responsiveness in modals/containers
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

    window.addEventListener("phx:graph-updated", (e) => {
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

  <!-- Legend -->

  <!-- Time Travel (Aether Design: Deep Void & Energy) -->
  <div
    class="absolute bottom-10 left-6 right-6 p-4 rounded-2xl border border-white/5 bg-black/30 backdrop-blur-md flex items-center gap-4 z-20"
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
      class="flex items-center gap-2 px-3 py-1 rounded-full bg-black/40 border border-white/5 shadow-inner"
    >
      <div
        class="w-1.5 h-1.5 rounded-full bg-blue-500 animate-pulse shadow-[0_0_8px_#3B82F6]"
      ></div>
      <div class="text-[10px] font-mono font-medium text-neutral-400">
        <span class="text-white text-base mr-1">{currentStats.nodes}</span> nodes
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
