<script>
  import { onMount, onDestroy } from "svelte";
  import * as d3 from "d3";

  // Props from Phoenix LiveView
  export let data = null;
  export let live = null;

  let container;
  let svg;
  let width = 800;
  let height = 600;
  let animationFrame;

  // Context menu state
  let contextMenu = { show: false, x: 0, y: 0, user: null };

  // Empty state tracking
  let showEmptyState = false;
  let inviteCopied = false;

  // Animation time (for orbital motion)
  let time = 0;

  // Orbital layers configuration
  const orbitalLayers = [
    { radius: 0.25, speed: 0.0003, count: 5 },
    { radius: 0.35, speed: 0.0002, count: 8 },
    { radius: 0.45, speed: 0.00015, count: 10 },
    { radius: 0.55, speed: 0.0001, count: 7 },
  ];

  function initGraph() {
    if (!container || !data) return;

    const rect = container.getBoundingClientRect();
    width = rect.width || 800;
    height = rect.height || 600;
    const centerX = width / 2;
    const centerY = height / 2;
    const minDim = Math.min(width, height);

    // Clear previous content
    d3.select(container).selectAll("*").remove();

    svg = d3
      .select(container)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .style("background", "radial-gradient(ellipse at center, #0a0a0f 0%, #000000 100%)")
      .on("click", () => {
        contextMenu = { show: false, x: 0, y: 0, user: null };
      });

    // Create star field background
    const starsGroup = svg.append("g").attr("class", "stars");
    for (let i = 0; i < 100; i++) {
      starsGroup
        .append("circle")
        .attr("cx", Math.random() * width)
        .attr("cy", Math.random() * height)
        .attr("r", Math.random() * 1.5 + 0.5)
        .attr("fill", "#ffffff")
        .attr("opacity", Math.random() * 0.3 + 0.1);
    }

    // Glow filter for self
    const defs = svg.append("defs");

    const selfGlow = defs
      .append("filter")
      .attr("id", "self-glow")
      .attr("x", "-100%")
      .attr("y", "-100%")
      .attr("width", "300%")
      .attr("height", "300%");

    selfGlow
      .append("feGaussianBlur")
      .attr("stdDeviation", "8")
      .attr("result", "blur");

    selfGlow
      .append("feFlood")
      .attr("flood-color", "#ffffff")
      .attr("flood-opacity", "0.6")
      .attr("result", "color");

    selfGlow
      .append("feComposite")
      .attr("in", "color")
      .attr("in2", "blur")
      .attr("operator", "in")
      .attr("result", "glow");

    const selfMerge = selfGlow.append("feMerge");
    selfMerge.append("feMergeNode").attr("in", "glow");
    selfMerge.append("feMergeNode").attr("in", "glow");
    selfMerge.append("feMergeNode").attr("in", "SourceGraphic");

    // Orbital glow filter - larger, more visible
    const orbitalGlow = defs
      .append("filter")
      .attr("id", "orbital-glow")
      .attr("x", "-100%")
      .attr("y", "-100%")
      .attr("width", "300%")
      .attr("height", "300%");

    orbitalGlow
      .append("feGaussianBlur")
      .attr("in", "SourceGraphic")
      .attr("stdDeviation", "6")
      .attr("result", "blur");

    const orbitalMerge = orbitalGlow.append("feMerge");
    orbitalMerge.append("feMergeNode").attr("in", "blur");
    orbitalMerge.append("feMergeNode").attr("in", "blur");
    orbitalMerge.append("feMergeNode").attr("in", "SourceGraphic");

    // Create orbital rings (subtle guides)
    const ringsGroup = svg.append("g").attr("class", "rings");
    orbitalLayers.forEach((layer) => {
      ringsGroup
        .append("circle")
        .attr("cx", centerX)
        .attr("cy", centerY)
        .attr("r", layer.radius * minDim)
        .attr("fill", "none")
        .attr("stroke", "#ffffff")
        .attr("stroke-opacity", 0.03)
        .attr("stroke-width", 1);
    });

    // Create group for orbiting users
    const orbitingGroup = svg.append("g").attr("class", "orbiting");

    // Assign users to orbital layers
    const users = data.others || [];
    let currentIndex = 0;
    let globalUserIndex = 0; // For staggered reveal timing

    orbitalLayers.forEach((layer, layerIndex) => {
      const usersInLayer = users.slice(currentIndex, currentIndex + layer.count);
      currentIndex += layer.count;

      usersInLayer.forEach((user, i) => {
        const baseAngle = (2 * Math.PI * i) / usersInLayer.length;
        // Random delay: base timing plus random 0-600ms variation for organic feel
        const randomExtra = Math.random() * 600;
        const revealDelay = 5000 + globalUserIndex * 800 + randomExtra;
        globalUserIndex++;

        const userGroup = orbitingGroup
          .append("g")
          .attr("class", `orbiting-user orbiting-user-${user.id}`)
          .datum({ user, layer, baseAngle, layerIndex })
          .style("cursor", "pointer")
          .style("opacity", 0); // Start hidden

        // Click handler
        userGroup.on("click", (event) => {
          event.stopPropagation();
          const pos = d3.pointer(event, container);
          contextMenu = {
            show: true,
            x: pos[0],
            y: pos[1],
            user: user,
          };
        });

        // Staggered reveal animation using native DOM - slow fade in
        setTimeout(() => {
          const node = userGroup.node();
          if (node) {
            node.style.transition = "opacity 1.2s ease-out";
            node.style.opacity = "1";
          }
        }, revealDelay);

        // User dot - thinner border, filled with color for inner glow
        userGroup
          .append("circle")
          .attr("class", "user-dot")
          .attr("r", 8)
          .attr("fill", user.color || "#6366f1")
          .attr("stroke", user.color || "#6366f1")
          .attr("stroke-width", 1)
          .attr("filter", "url(#orbital-glow)")
          .style("opacity", 0.6);

        // Username label (hidden by default, shown on hover) - positioned ABOVE to avoid cursor
        userGroup
          .append("text")
          .attr("class", "user-label")
          .attr("dy", -18)
          .attr("text-anchor", "middle")
          .attr("fill", "#ffffff")
          .attr("font-size", "11px")
          .attr("font-weight", "500")
          .attr("font-family", "Outfit, sans-serif")
          .attr("opacity", 0)
          .attr("paint-order", "stroke")
          .attr("stroke", "#000000")
          .attr("stroke-width", "3px")
          .text(user.display_name || user.username);

        // Hover interactions - increase opacity and size on hover
        userGroup
          .on("mouseenter", function () {
            d3.select(this).select(".user-dot")
              .transition().duration(200)
              .attr("r", 12)
              .style("opacity", 1);
            d3.select(this).select(".user-label").transition().duration(200).attr("opacity", 1);
          })
          .on("mouseleave", function () {
            d3.select(this).select(".user-dot")
              .transition().duration(200)
              .attr("r", 8)
              .style("opacity", 0.6);
            d3.select(this).select(".user-label").transition().duration(200).attr("opacity", 0);
          });
      });
    });

    // Create central self node
    const selfGroup = svg.append("g").attr("class", "self");

    // Breathing animation circle (background pulse)
    selfGroup
      .append("circle")
      .attr("class", "self-pulse")
      .attr("cx", centerX)
      .attr("cy", centerY)
      .attr("r", 20)
      .attr("fill", "rgba(255, 255, 255, 0.1)")
      .attr("filter", "url(#self-glow)");

    // Main self dot
    selfGroup
      .append("circle")
      .attr("class", "self-dot")
      .attr("cx", centerX)
      .attr("cy", centerY)
      .attr("r", 16)
      .attr("fill", "#ffffff")
      .attr("filter", "url(#self-glow)");

    // Self label
    selfGroup
      .append("text")
      .attr("x", centerX)
      .attr("y", centerY + 35)
      .attr("text-anchor", "middle")
      .attr("fill", "#ffffff")
      .attr("font-size", "12px")
      .attr("font-weight", "600")
      .attr("font-family", "Outfit, sans-serif")
      .text(data.self?.display_name || data.self?.username || "You");

    // Show empty state message if no discoverable users
    if (users.length === 0) {
      showEmptyState = true;
      svg.append("text")
        .attr("class", "empty-message")
        .attr("x", centerX)
        .attr("y", centerY + 80)
        .attr("text-anchor", "middle")
        .attr("fill", "rgba(255, 255, 255, 0.5)")
        .attr("font-size", "14px")
        .attr("font-family", "Outfit, sans-serif")
        .text("You've connected with everyone here!");

      svg.append("text")
        .attr("class", "empty-submessage")
        .attr("x", centerX)
        .attr("y", centerY + 105)
        .attr("text-anchor", "middle")
        .attr("fill", "rgba(255, 255, 255, 0.3)")
        .attr("font-size", "12px")
        .attr("font-family", "Outfit, sans-serif")
        .text("New users will appear as they join.");
    }

    // Start animation loop
    animate();
  }

  function animate() {
    time += 1;
    const centerX = width / 2;
    const centerY = height / 2;
    const minDim = Math.min(width, height);

    // Animate orbiting users
    svg.selectAll(".orbiting-user").each(function (d) {
      const angle = d.baseAngle + time * d.layer.speed;
      const x = centerX + Math.cos(angle) * d.layer.radius * minDim;
      const y = centerY + Math.sin(angle) * d.layer.radius * minDim;
      d3.select(this).attr("transform", `translate(${x}, ${y})`);
    });

    // Animate breathing effect on self
    const breathScale = 1 + 0.1 * Math.sin(time * 0.02);
    svg.select(".self-pulse").attr("r", 20 * breathScale);

    animationFrame = requestAnimationFrame(animate);
  }

  function handleInvite() {
    if (contextMenu.user && live) {
      const userId = contextMenu.user.id;
      
      // Animate fade out the user's dot immediately
      const userGroup = svg.select(`.orbiting-user-${userId}`);
      if (userGroup.node()) {
        userGroup
          .transition()
          .duration(1000)
          .style("opacity", 0)
          .on("end", function() {
            d3.select(this).remove();
            // Check if all dots are gone and show empty message
            checkAndShowEmptyState();
          });
      }
      
      // Send the friend request
      live.pushEvent("constellation_invite", { user_id: String(userId) });
    }
    contextMenu = { show: false, x: 0, y: 0, user: null };
  }

  function checkAndShowEmptyState() {
    // Count only visible dots (opacity > 0.1)
    let visibleDots = 0;
    svg.selectAll(".orbiting-user").each(function() {
      const opacity = parseFloat(d3.select(this).style("opacity") || "1");
      if (opacity > 0.1) visibleDots++;
    });
    
    const existingMessage = svg.select(".empty-message");
    
    if (visibleDots === 0 && existingMessage.empty()) {
      showEmptyState = true;
      const centerX = width / 2;
      const centerY = height / 2;
      
      svg.append("text")
        .attr("class", "empty-message")
        .attr("x", centerX)
        .attr("y", centerY + 80)
        .attr("text-anchor", "middle")
        .attr("fill", "rgba(255, 255, 255, 0)")
        .attr("font-size", "14px")
        .attr("font-family", "Outfit, sans-serif")
        .text("You've connected with everyone here!")
        .transition()
        .duration(800)
        .attr("fill", "rgba(255, 255, 255, 0.5)");

      svg.append("text")
        .attr("class", "empty-submessage")
        .attr("x", centerX)
        .attr("y", centerY + 105)
        .attr("text-anchor", "middle")
        .attr("fill", "rgba(255, 255, 255, 0)")
        .attr("font-size", "12px")
        .attr("font-family", "Outfit, sans-serif")
        .text("New users will appear as they join.")
        .transition()
        .duration(800)
        .delay(200)
        .attr("fill", "rgba(255, 255, 255, 0.3)");
    }
  }

  async function shareInviteLink() {
    // Get personalized invite link with current user's username
    const username = data.self?.username || '';
    const inviteUrl = `${window.location.origin}/register?ref=${username}`;
    
    try {
      await navigator.clipboard.writeText(inviteUrl);
      inviteCopied = true;
      setTimeout(() => inviteCopied = false, 2000);
    } catch (err) {
      // Fallback for browsers that don't support clipboard API
      prompt('Copy this link:', inviteUrl);
    }
  }

  // Resize handler
  let resizeTimeout;
  function handleResize() {
    clearTimeout(resizeTimeout);
    resizeTimeout = setTimeout(() => {
      if (animationFrame) cancelAnimationFrame(animationFrame);
      initGraph();
    }, 250);
  }

  // Add a new user dot dynamically (for real-time updates)
  function addNewUser(user) {
    if (!svg) return;
    
    const centerX = width / 2;
    const centerY = height / 2;
    const minDim = Math.min(width, height);
    
    // Pick a random orbital layer
    const layerIndex = Math.floor(Math.random() * orbitalLayers.length);
    const layer = orbitalLayers[layerIndex];
    const baseAngle = Math.random() * 2 * Math.PI;
    
    const orbitingGroup = svg.select(".orbiting");
    
    const userGroup = orbitingGroup
      .append("g")
      .attr("class", `orbiting-user orbiting-user-${user.id}`)
      .datum({ user, layer, baseAngle, layerIndex })
      .style("cursor", "pointer")
      .style("opacity", 0);

    // Position immediately
    const angle = baseAngle;
    const x = centerX + Math.cos(angle) * layer.radius * minDim;
    const y = centerY + Math.sin(angle) * layer.radius * minDim;
    userGroup.attr("transform", `translate(${x}, ${y})`);

    // Click handler
    userGroup.on("click", (event) => {
      event.stopPropagation();
      const pos = d3.pointer(event, container);
      contextMenu = {
        show: true,
        x: pos[0],
        y: pos[1],
        user: user,
      };
    });

    // User dot - thinner border, filled with color for inner glow
    userGroup
      .append("circle")
      .attr("class", "user-dot")
      .attr("r", 8)
      .attr("fill", user.color || "#6366f1")
      .attr("stroke", user.color || "#6366f1")
      .attr("stroke-width", 1)
      .attr("filter", "url(#orbital-glow)")
      .style("opacity", 0.6);

    // Username label
    userGroup
      .append("text")
      .attr("class", "user-label")
      .attr("dy", -18)
      .attr("text-anchor", "middle")
      .attr("fill", "#ffffff")
      .attr("font-size", "11px")
      .attr("font-weight", "500")
      .attr("font-family", "Outfit, sans-serif")
      .attr("opacity", 0)
      .attr("paint-order", "stroke")
      .attr("stroke", "#000000")
      .attr("stroke-width", "3px")
      .text(user.display_name || user.username);

    // Hover interactions - increase opacity and size on hover
    userGroup
      .on("mouseenter", function () {
        d3.select(this).select(".user-dot")
          .transition().duration(200)
          .attr("r", 12)
          .style("opacity", 1);
        d3.select(this).select(".user-label").transition().duration(200).attr("opacity", 1);
      })
      .on("mouseleave", function () {
        d3.select(this).select(".user-dot")
          .transition().duration(200)
          .attr("r", 8)
          .style("opacity", 0.6);
        d3.select(this).select(".user-label").transition().duration(200).attr("opacity", 0);
      });

    // Fade in with delay
    setTimeout(() => {
      const node = userGroup.node();
      if (node) {
        node.style.transition = "opacity 1.2s ease-out";
        node.style.opacity = "1";
      }
    }, 100);
  }

  // Handle custom event from parent
  function handleAddNewUser(event) {
    addNewUser(event.detail);
  }

  onMount(() => {
    initGraph();
    window.addEventListener("resize", handleResize);
    // Listen for new user events from LiveView hook
    window.addEventListener("constellation:addNewUser", handleAddNewUser);
  });

  onDestroy(() => {
    if (animationFrame) cancelAnimationFrame(animationFrame);
    if (resizeTimeout) clearTimeout(resizeTimeout);
    window.removeEventListener("resize", handleResize);
    window.removeEventListener("constellation:addNewUser", handleAddNewUser);
  });
</script>

<div class="relative w-full h-full overflow-hidden bg-black">
  <!-- Graph Container -->
  <div bind:this={container} class="w-full h-full"></div>

  <!-- Context Menu -->
  {#if contextMenu.show && contextMenu.user}
    <div
      class="absolute z-50 bg-black/90 border border-white/20 rounded-xl shadow-2xl backdrop-blur-md p-3 min-w-[180px]"
      style="left: {contextMenu.x}px; top: {contextMenu.y}px; transform: translate(-50%, -100%) translateY(-10px);"
    >
      <div class="text-center mb-3">
        <div
          class="w-10 h-10 mx-auto rounded-full flex items-center justify-center text-sm font-bold text-white border border-white/20"
          style="background-color: {contextMenu.user.color || '#6366f1'}"
        >
          {contextMenu.user.username?.charAt(0).toUpperCase() || "?"}
        </div>
        <p class="text-white font-medium text-sm mt-2">
          {contextMenu.user.display_name || contextMenu.user.username}
        </p>
        <p class="text-neutral-500 text-xs">@{contextMenu.user.username}</p>
      </div>
      <button
        class="w-full px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium rounded-lg transition-colors"
        on:click={handleInvite}
      >
        Send Friend Request
      </button>
    </div>
  {/if}

  <!-- Bottom hint -->
  <div class="absolute bottom-6 left-0 right-0 text-center">
    {#if showEmptyState}
      <button
        on:click={shareInviteLink}
        class="px-6 py-2 bg-white/10 hover:bg-white/20 backdrop-blur-md border border-white/20 rounded-full text-white text-sm transition-all cursor-pointer"
      >
        {inviteCopied ? '✓ Link Copied!' : 'Share Invite Link'}
      </button>
    {:else}
      <p class="text-neutral-500 text-xs pointer-events-none">
        Click on a dot to connect
      </p>
    {/if}
  </div>
</div>

<style>
  :global(.orbiting-user) {
    transition: opacity 0.3s ease;
  }
</style>
