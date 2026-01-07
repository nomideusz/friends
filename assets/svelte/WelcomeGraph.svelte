<script>
    import { onMount, onDestroy } from "svelte";
    import * as d3 from "d3";

    // Props from Phoenix LiveView
    export let graphData = null;
    export let live = null;
    export let onSkip = null;
    // Current user ID for highlighting
    export let currentUserId = null;

    // Titanium / iOS 18 inspired palette
    const COLORS = {
        white: "#F5F5F7",
        dim: "rgba(235, 235, 245, 0.3)", // Glassy white/gray
        energy: "#0A84FF", // System Blue
        you: "#30D158", // System Green
        friend: "#5E5CE6", // System Indigo
        aura: "rgba(10, 132, 255, 0.05)", // Extremely subtle
        link: "rgba(120, 120, 128, 0.2)", // Static, subtle gray
        label: "rgba(255, 255, 255, 0.85)",
    };
    let container;
    let canvas;
    let ctx;
    let width = 800;
    let height = 600;
    let transform = d3.zoomIdentity;

    let simulation;
    let zoomBehavior;

    // Canvas optimization
    const dpi =
        typeof window !== "undefined" ? window.devicePixelRatio || 1 : 1;
    let animationFrame;

    // Image cache for avatars
    const imageCache = new Map();
    const placeholderImage = new Image();
    placeholderImage.src = "/images/icon-192.png"; // Use existing icon as fallback

    // State for interactions
    let draggedSubject = null;
    let hoverSubject = null;

    // Data storage
    let nodesData = [];
    let linksData = [];
    let nodeMap = new Map();

    // Queue for batched updates
    let pendingUpdates = { nodes: [], links: [], removals: [] };
    let updateTimeout = null;
    const UPDATE_THROTTLE_MS = 1000;

    // Context menu state
    let showContextMenu = false;
    let contextMenuX = 0;
    let contextMenuY = 0;
    let contextMenuUser = null;

    let isMobile = false;
    let hasTouch = false;
    let isDragging = false; // Declared here!
    if (typeof window !== "undefined") {
        hasTouch = "ontouchstart" in window || navigator.maxTouchPoints > 0;
    }
    let contextMenuStatus = "none"; // 'connected', 'pending', or 'none'

    // === Exported functions for live updates from LiveView ===

    // Process batched updates (called after throttle delay)
    function processPendingUpdates() {
        if (!simulation) return;

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
                width: 32, // For overlap avoidance
                height: 32,
            };

            // Preload image
            if (newNode.avatar_url && !imageCache.has(newNode.avatar_url)) {
                const img = new Image();
                img.src = newNode.avatar_url;
                imageCache.set(newNode.avatar_url, img);
            }

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
            // Restart simulation
            simulation.nodes(nodesData);
            simulation.force("link").links(linksData);
            simulation.alpha(1).restart();
        }
    }

    // Schedule batched update
    function scheduleUpdate() {
        if (updateTimeout) return; // Already scheduled
        updateTimeout = setTimeout(() => {
            processPendingUpdates();
            updateTimeout = null;
        }, UPDATE_THROTTLE_MS);
    }

    // Add a new node (user joined) - throttled
    export function addNode(userData) {
        if (!simulation) return;
        pendingUpdates.nodes.push(userData);
        scheduleUpdate();
    }

    // Remove a node (user left/removed) - immediate
    export function removeNode(userId) {
        if (!simulation) return;

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

        simulation.nodes(nodesData);
        simulation.force("link").links(linksData);
        simulation.alpha(1).restart();
    }

    // Add a connection between two nodes with animation (throttled)
    export function addLink(fromId, toId) {
        if (!simulation) return;
        pendingUpdates.links.push({ fromId, toId });
        scheduleUpdate();
    }

    // Remove a connection between two nodes with animation
    export function removeLink(fromId, toId) {
        if (!simulation) return;

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

        simulation.force("link").links(linksData);
        simulation.alpha(1).restart();
    }

    // Pulse a node to indicate activity (e.g., new post)
    export function pulseNode(userId) {
        // Todo: Implement canvas-based pulse animation (e.g. set a 'pulse' property on node)
        // For now, no-op to avoid errors
    }

    // Handle node click - show context menu at node position
    function handleNodeClick(event, d) {
        // D3 event propagation is different in Canvas manual handling
        // event.stopPropagation() might not work if it's a native event, but check dispatch

        const currentUserIdStr = currentUserId ? String(currentUserId) : null;

        // Don't trigger on self
        if (d.id === currentUserIdStr) return;

        // Get mouse position relative to container
        // Event clientX/Y are global
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

    // showLabel and hideLabel are removed - handled in draw() loop

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

    // Context menu state

    // Animation loop
    function animate() {
        draw();
        animationFrame = requestAnimationFrame(animate);
    }

    // Main draw function
    function draw() {
        if (!ctx) return;

        ctx.save();
        ctx.clearRect(0, 0, width, height);

        // Apply zoom transform
        ctx.translate(transform.x, transform.y);
        ctx.scale(transform.k, transform.k);

        // Draw Links
        ctx.beginPath();
        linksData.forEach((d) => {
            const src = getObj(d.source);
            const tgt = getObj(d.target);
            if (src && tgt) {
                ctx.moveTo(src.x, src.y);
                ctx.lineTo(tgt.x, tgt.y);
            }
        });
        ctx.strokeStyle = COLORS.link;
        ctx.lineWidth = 0.5; // hairline
        ctx.stroke();

        // Draw Nodes
        nodesData.forEach((d) => drawNode(d));

        // Draw Labels (only on hover, drag, or for current user)
        const currentIdStr = String(currentUserId);
        nodesData.forEach((d) => {
            if (
                String(d.id) === currentIdStr ||
                d === hoverSubject ||
                d === draggedSubject
            ) {
                drawLabel(d);
            }
        });

        ctx.restore();
    }

    // Helper to resolve Cola's index vs object refs
    function getObj(ref) {
        return typeof ref === "number" ? nodesData[ref] : ref;
    }

    function drawNode(d) {
        // Slightly smaller, more refined nodes
        const r = isMobile ? 11 : 14;
        const currentIdStr = String(currentUserId);
        const isSelf = String(d.id) === currentIdStr;

        // Subtle Aura for active/self only, or very minimal for others
        if (isSelf) {
            const auraGradient = ctx.createRadialGradient(
                d.x,
                d.y,
                r * 0.8,
                d.x,
                d.y,
                r * 2.0,
            );
            auraGradient.addColorStop(0, COLORS.aura);
            auraGradient.addColorStop(1, "transparent");
            ctx.fillStyle = auraGradient;
            ctx.beginPath();
            ctx.arc(d.x, d.y, r * 2.0, 0, 2 * Math.PI);
            ctx.fill();
        }

        ctx.beginPath();
        ctx.arc(d.x, d.y, r, 0, 2 * Math.PI);

        // Draw avatar if available
        if (d.avatar_url && imageCache.has(d.avatar_url)) {
            const img = imageCache.get(d.avatar_url);
            if (img.complete && img.naturalWidth > 0) {
                ctx.save();
                ctx.clip();
                // Draw image centered
                ctx.drawImage(img, d.x - r, d.y - r, r * 2, r * 2);
                ctx.restore();

                // Border for avatar
                ctx.strokeStyle = "#FFFFFF";
                ctx.lineWidth = 1.5;
                ctx.stroke();
                return;
            }
        }

        // Flat, transparent design
        const baseColor = isSelf ? COLORS.you : COLORS.friend;
        const colorWithOpacity = d3.color(baseColor);
        colorWithOpacity.opacity = 0.6; // 60% opacity

        ctx.fillStyle = colorWithOpacity.toString();
        ctx.beginPath();
        ctx.arc(d.x, d.y, r, 0, 2 * Math.PI);
        ctx.fill();

        // Thicker, solid border
        ctx.strokeStyle = "rgba(255,255,255,0.8)";
        ctx.lineWidth = 2.5;
        ctx.stroke();
    }

    function drawLabel(d) {
        ctx.font = "600 11px Inter, sans-serif";
        ctx.fillStyle = COLORS.label;
        const label = d.username || d.display_name || "User";

        // Slightly offset if dragging to avoid finger occlusion
        const offsetY = d === draggedSubject ? -35 : -25;
        ctx.fillText(label, d.x, d.y + offsetY);
    }

    // --- Interaction Handlers ---

    // Helper to find subject for interaction (sharing logic between drag and zoom filter)
    function findInteractionSubject(event) {
        if (!canvas || !nodesData.length) return null;

        const t = d3.zoomTransform(canvas);
        const sourceEvent = event.sourceEvent || event;

        // Get coordinates relative to canvas
        // Handle touch events specially - d3.pointer doesn't work well with TouchEvent
        let px, py;
        if (sourceEvent.touches && sourceEvent.touches.length > 0) {
            // Touch event - use first touch
            const touch = sourceEvent.touches[0];
            const rect = canvas.getBoundingClientRect();
            px = touch.clientX - rect.left;
            py = touch.clientY - rect.top;
        } else if (
            sourceEvent.changedTouches &&
            sourceEvent.changedTouches.length > 0
        ) {
            // Touch end event - use changedTouches
            const touch = sourceEvent.changedTouches[0];
            const rect = canvas.getBoundingClientRect();
            px = touch.clientX - rect.left;
            py = touch.clientY - rect.top;
        } else {
            // Mouse event - use d3.pointer
            [px, py] = d3.pointer(sourceEvent, canvas);
        }

        // Invert transform to get world coordinates
        const mx = t.invertX(px);
        const my = t.invertY(py);

        // Adaptive hit radius (screen pixels)
        // Fingers are less precise; use a larger hit area on touch devices
        // This radius is in screen pixels, then converted to world distance squared
        const baseRadius = hasTouch || isMobile ? 120 : 40;
        const worldRadius = baseRadius / t.k;
        const maxDist2 = worldRadius * worldRadius;

        // Use d3.least to find the closest node within range
        return d3.least(nodesData, (d) => {
            const dx = d.x - mx;
            const dy = d.y - my;
            const dist2 = dx * dx + dy * dy;
            return dist2 < maxDist2 ? dist2 : NaN;
        });
    }

    function dragStarted(event) {
        // Pin the node at its current position
        event.subject.fx = event.subject.x;
        event.subject.fy = event.subject.y;
        // NOTE: Don't set isDragging or draggedSubject yet
        // We'll set them on first actual movement to allow clicks through

        // Stop propagation to prevent zoom behavior from catching this
        if (event.sourceEvent) {
            event.sourceEvent.stopPropagation();
        }
    }

    function dragged(event) {
        // Now we're actually dragging - set flags
        if (!isDragging) {
            isDragging = true;
            draggedSubject = event.subject;
            // Use lower alpha to reduce "dancing" of other nodes
            simulation.alphaTarget(0.1).restart();
        }

        // Update position using D3's event coordinates
        const sourceEvent = event.sourceEvent || event;
        const [px, py] = d3.pointer(sourceEvent, canvas);
        const t = d3.zoomTransform(canvas);

        // Set both x/y and fx/fy for immediate visual update
        const worldX = t.invertX(px);
        const worldY = t.invertY(py);
        if (isFinite(worldX) && isFinite(worldY)) {
            event.subject.x = worldX;
            event.subject.y = worldY;
            event.subject.fx = worldX;
            event.subject.fy = worldY;
        }
    }

    function dragEnded(event) {
        simulation.alphaTarget(0);
        event.subject.fx = null;
        event.subject.fy = null;
        draggedSubject = null;

        // Brief delay to prevent immediate click from firing on the node after drag
        if (isDragging) {
            setTimeout(() => {
                isDragging = false;
            }, 50);
        }
    }

    function handleCanvasMouseMove(event) {
        if (isDragging) return;

        const subject = findInteractionSubject(event);
        if (subject !== hoverSubject) {
            hoverSubject = subject;
            canvas.style.cursor = subject ? "pointer" : "default";
        }
    }

    function handleCanvasClick(event) {
        // Stop bubbling to prevent parent's handleBackdropClick from firing
        event.stopPropagation();

        if (isDragging) return;

        const subject = findInteractionSubject(event);
        if (subject) {
            handleNodeClick(event, subject);
        } else {
            handleBackdropClick(event);
        }
    }

    // Cached selections for performance
    let nodeSelection;
    let linkSelection;
    let labelSelection;

    // Clean up empty SVG functions
    function ticked() {
        // Empty - drawing handled by animate loop
    }
    function updatePatterns() {}
    function updateNodes() {}
    function updateLinks() {}

    function initGraph() {
        if (!container || !graphData || !canvas) return;

        const rect = container.getBoundingClientRect();
        width = rect.width || window.innerWidth;
        height = rect.height || window.innerHeight;
        isMobile = width < 600;

        // Set canvas size with DPI scaling
        canvas.width = width * dpi;
        canvas.height = height * dpi;
        canvas.style.width = `${width}px`;
        canvas.style.height = `${height}px`;

        // Build initial data
        const data = buildData(graphData);
        nodesData = data.nodes;
        linksData = data.links;
        nodeMap.clear();

        ctx = canvas.getContext("2d");
        // Crucial: Reset transform before scaling to avoid cumulative drift
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.scale(dpi, dpi);
        ctx.textBaseline = "middle";
        ctx.textAlign = "center";

        // Prepare image cache
        nodesData.forEach((n) => {
            nodeMap.set(n.id, n);
            if (n.avatar_url && !imageCache.has(n.avatar_url)) {
                const img = new Image();
                img.src = n.avatar_url;
                imageCache.set(n.avatar_url, img);
            }
        });

        // D3 Force Simulation setup - matching standard D3 example
        // Nodes are positioned around origin (0,0), canvas transform centers them
        simulation = d3
            .forceSimulation(nodesData)
            .force(
                "link",
                d3.forceLink(linksData).id((d) => d.id),
            )
            .force("charge", d3.forceManyBody().strength(-150))
            .force("collide", d3.forceCollide().radius(20))
            .force("x", d3.forceX())
            .force("y", d3.forceY())
            .on("tick", ticked);

        // Zoom behavior
        zoomBehavior = d3
            .zoom()
            .scaleExtent([0.1, 4])
            .filter((event) => {
                const sourceEvent = event.sourceEvent || event;

                // If we are already dragging, block zoom
                if (isDragging) return false;

                // Handle multi-touch: always allow zoom for pinches
                if (sourceEvent.touches && sourceEvent.touches.length > 1)
                    return true;

                // For single touches or mouse downs, check if we are over a node
                const filteredTypes = [
                    "mousedown",
                    "touchstart",
                    "pointerdown",
                ];
                if (filteredTypes.includes(event.type)) {
                    const subject = findInteractionSubject(event);
                    if (subject) return false; // Block zoom, let drag take it
                }

                // Default D3 filter logic for zoom
                return (
                    (!event.ctrlKey || event.type === "wheel") && !event.button
                );
            })
            .on("zoom", (event) => {
                transform = event.transform;
            });

        // Track touch state for manual touch handling
        let touchStartTime = 0;
        let touchStartX = 0;
        let touchStartY = 0;
        let touchedNode = null;
        let isTouchDragging = false;

        // D3 drag for MOUSE only (desktop)
        const drag = d3
            .drag()
            .container(canvas)
            .filter((event) => {
                // Only mouse events, not touch
                if (
                    event.sourceEvent &&
                    event.sourceEvent.type.startsWith("touch")
                ) {
                    return false;
                }
                const subject = findInteractionSubject(event);
                return !!subject;
            })
            .subject((event) => findInteractionSubject(event))
            .on("start", dragStarted)
            .on("drag", dragged)
            .on("end", dragEnded);

        const canvasSelection = d3.select(canvas);

        // Zoom filter: block zoom for single-touch on nodes
        zoomBehavior.filter((event) => {
            const sourceEvent = event.sourceEvent || event;

            // Always block if currently dragging
            if (isDragging || isTouchDragging) return false;

            // Allow pinch-to-zoom (multi-touch)
            if (sourceEvent.touches && sourceEvent.touches.length > 1)
                return true;

            // For single touch, block if over a node
            if (sourceEvent.touches && sourceEvent.touches.length === 1) {
                const subject = findInteractionSubject(event);
                if (subject) return false;
            }

            // For mouse/pointer, check if over a node
            const filteredTypes = ["mousedown", "touchstart", "pointerdown"];
            if (filteredTypes.includes(event.type)) {
                const subject = findInteractionSubject(event);
                if (subject) return false;
            }

            // Default D3 filter logic
            return (!event.ctrlKey || event.type === "wheel") && !event.button;
        });

        canvasSelection
            .call(zoomBehavior)
            .call(drag)
            .on("click", handleCanvasClick)
            .on("mousemove", handleCanvasMouseMove);

        // === FULLY MANUAL TOUCH HANDLING ===
        // This bypasses D3 entirely for touch events

        canvas.addEventListener(
            "touchstart",
            (event) => {
                if (event.touches.length !== 1) return; // Only single touch

                const touch = event.touches[0];
                touchStartTime = Date.now();
                touchStartX = touch.clientX;
                touchStartY = touch.clientY;
                touchedNode = findInteractionSubject(event);

                if (touchedNode) {
                    // We're touching a node - prepare for potential drag
                    // Pin the node at its current position
                    touchedNode.fx = touchedNode.x;
                    touchedNode.fy = touchedNode.y;
                    // NOTE: Don't set draggedSubject yet - only when actually dragging
                    // This prevents the label from jumping on tap

                    // Prevent zoom from taking this event
                    event.preventDefault();
                }
            },
            { passive: false },
        );

        canvas.addEventListener(
            "touchmove",
            (event) => {
                if (!touchedNode || event.touches.length !== 1) return;

                const touch = event.touches[0];
                const dx = Math.abs(touch.clientX - touchStartX);
                const dy = Math.abs(touch.clientY - touchStartY);

                // Start dragging after moving more than 10px
                if (!isTouchDragging && (dx > 10 || dy > 10)) {
                    isTouchDragging = true;
                    isDragging = true;
                    draggedSubject = touchedNode; // NOW set draggedSubject
                    // Gently reheat simulation (lower alpha for less dancing)
                    simulation.alphaTarget(0.1).restart();
                }

                if (isTouchDragging && touchedNode) {
                    // Get canvas-relative coordinates
                    const rect = canvas.getBoundingClientRect();
                    const px = touch.clientX - rect.left;
                    const py = touch.clientY - rect.top;
                    const t = d3.zoomTransform(canvas);

                    // Update node position - set BOTH x/y and fx/fy
                    // fx/fy pins the node, x/y is the actual drawn position
                    const worldX = t.invertX(px);
                    const worldY = t.invertY(py);

                    // Only update if coordinates are valid
                    if (isFinite(worldX) && isFinite(worldY)) {
                        touchedNode.x = worldX;
                        touchedNode.y = worldY;
                        touchedNode.fx = worldX;
                        touchedNode.fy = worldY;
                    }

                    event.preventDefault();
                }
            },
            { passive: false },
        );

        canvas.addEventListener(
            "touchend",
            (event) => {
                const elapsed = Date.now() - touchStartTime;
                const TAP_THRESHOLD_MS = 250;
                const TAP_DISTANCE_PX = 10;

                if (
                    touchedNode &&
                    !isTouchDragging &&
                    elapsed < TAP_THRESHOLD_MS
                ) {
                    const touch = event.changedTouches[0];
                    const dx = Math.abs(touch.clientX - touchStartX);
                    const dy = Math.abs(touch.clientY - touchStartY);

                    if (dx < TAP_DISTANCE_PX && dy < TAP_DISTANCE_PX) {
                        // This is a tap on a node - trigger context menu
                        handleNodeClick(
                            { clientX: touch.clientX, clientY: touch.clientY },
                            touchedNode,
                        );
                    }
                }

                // Clean up
                if (touchedNode) {
                    touchedNode.fx = null;
                    touchedNode.fy = null;
                }
                simulation.alphaTarget(0);

                touchedNode = null;
                draggedSubject = null;
                touchStartTime = 0;

                setTimeout(() => {
                    isDragging = false;
                    isTouchDragging = false;
                }, 50);
            },
            { passive: true },
        );

        canvas.addEventListener(
            "touchcancel",
            () => {
                // Clean up on cancel
                if (touchedNode) {
                    touchedNode.fx = null;
                    touchedNode.fy = null;
                }
                simulation.alphaTarget(0);
                touchedNode = null;
                draggedSubject = null;
                isDragging = false;
                isTouchDragging = false;
            },
            { passive: true },
        );

        // Pre-warm the simulation to stabilize layout
        // Run about 300 ticks synchronously
        simulation.stop();
        for (let i = 0; i < 300; ++i) simulation.tick();
        ticked(); // Run one tick handler just in case

        // Initial Zoom to Fit
        zoomToFit();

        // Start animation loop
        if (animationFrame) cancelAnimationFrame(animationFrame);
        animate();
    }

    function zoomToFit() {
        if (!nodesData.length || !canvas) return;

        // Calculate bounding box
        let minX = Infinity,
            maxX = -Infinity,
            minY = Infinity,
            maxY = -Infinity;

        nodesData.forEach((d) => {
            if (d.x < minX) minX = d.x;
            if (d.x > maxX) maxX = d.x;
            if (d.y < minY) minY = d.y;
            if (d.y > maxY) maxY = d.y;
        });

        // Add some padding to the bounding box
        const padding = 50;
        const width = canvas.offsetWidth;
        const height = canvas.offsetHeight;

        // Calculate the width and height of the graph
        const graphWidth = maxX - minX + padding * 2;
        const graphHeight = maxY - minY + padding * 2;

        // Calculate the scale to fit the graph into the canvas
        const scaleX = width / graphWidth;
        const scaleY = height / graphHeight;
        let scale = Math.min(scaleX, scaleY);

        // Clamp scale to reasonable limits
        scale = Math.min(Math.max(scale, 0.1), 2.0);

        // Calculate translation to center the graph
        const midX = (minX + maxX) / 2;
        const midY = (minY + maxY) / 2;

        // Create the new transform
        const newTransform = d3.zoomIdentity
            .translate(width / 2, height / 2)
            .scale(scale)
            .translate(-midX, -midY);

        // Apply transform with transition
        d3.select(canvas)
            .transition()
            .duration(750)
            .call(zoomBehavior.transform, newTransform);
    }

    function buildData(data) {
        if (!data || !data.nodes) return { nodes: [], links: [] };

        const nodes = [];
        const links = [];
        const nodeMap = new Map();

        // Process nodes - scatter around origin (0,0)
        // The viewBox/transform will center them in the canvas
        const scatterRange = isMobile ? 50 : 100;
        data.nodes.forEach((node) => {
            const n = {
                ...node,
                id: String(node.id),
                x: (Math.random() - 0.5) * scatterRange,
                y: (Math.random() - 0.5) * scatterRange,
                width: 32,
                height: 32,
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
    <div bind:this={container} class="w-full h-full relative z-10">
        <canvas
            bind:this={canvas}
            class="block w-full h-full cursor-grab active:cursor-grabbing"
            style="touch-action: none;"
            data-is-dragging={isDragging}
            data-has-subject={!!draggedSubject}
        ></canvas>
    </div>

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
    /* Apple Fluid Style Context Menu */
    .context-menu {
        position: absolute;
        z-index: 100;
        min-width: 150px;
        transform: translate(-50%, 10px);
        transform-origin: top center;

        /* High-quality Glassmorphism */
        background: rgba(35, 35, 40, 0.75);
        backdrop-filter: blur(25px) saturate(180%);
        -webkit-backdrop-filter: blur(25px) saturate(180%);
        border: 1px solid rgba(255, 255, 255, 0.12);
        box-shadow:
            0 12px 32px rgba(0, 0, 0, 0.4),
            0 4px 8px rgba(0, 0, 0, 0.2),
            inset 0 0 0 1px rgba(255, 255, 255, 0.05);

        border-radius: 14px;
        padding: 6px;

        /* Typography */
        font-family:
            "SF Pro Text",
            "Inter",
            -apple-system,
            BlinkMacSystemFont,
            system-ui,
            sans-serif;
        color: rgba(255, 255, 255, 0.95);

        /* Animation */
        animation: menu-enter 0.25s cubic-bezier(0.16, 1, 0.3, 1) forwards;
    }

    @keyframes menu-enter {
        0% {
            opacity: 0;
            transform: translate(-50%, 0px) scale(0.92);
        }
        100% {
            opacity: 1;
            transform: translate(-50%, 10px) scale(1);
        }
    }

    .menu-header {
        padding: 6px 10px 8px;
        text-align: left;
        border-bottom: 1px solid rgba(255, 255, 255, 0.1);
        margin-bottom: 4px;
        margin-left: 4px;
        margin-right: 4px;
    }

    .menu-username {
        display: block;
        font-size: 13px;
        font-weight: 500;
        color: rgba(255, 255, 255, 0.6);
        letter-spacing: -0.01em;
    }

    .menu-actions {
        display: flex;
        flex-direction: column;
        gap: 2px;
    }

    .menu-item {
        appearance: none;
        border: none;
        background: transparent;
        width: 100%;
        text-align: left;
        padding: 10px 12px;
        border-radius: 8px;
        font-size: 15px;
        font-weight: 400;
        color: inherit;
        cursor: pointer;
        transition: all 0.15s ease-out;
        display: flex;
        align-items: center;
        justify-content: flex-start;
    }

    .menu-item:not([disabled]):hover {
        background: rgba(255, 255, 255, 0.1);
        transform: scale(1.02);
    }

    .menu-item:not([disabled]):active {
        background: rgba(255, 255, 255, 0.15);
        transform: scale(0.98);
    }

    .menu-item span {
        position: relative;
    }

    .menu-item-pending {
        opacity: 0.5;
        cursor: default;
        font-style: italic;
    }
</style>
