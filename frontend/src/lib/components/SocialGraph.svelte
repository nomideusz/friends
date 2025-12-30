<script lang="ts">
    import { Canvas } from "@threlte/core";
    import { OrbitControls, Text } from "@threlte/extras";
    import { T, useThrelte } from "@threlte/core";
    import * as THREE from "three";
    import GraphEffects from "./GraphEffects.svelte";
    import {
        forceSimulation,
        forceLink,
        forceManyBody,
        forceCenter,
        forceCollide,
    } from "d3-force-3d";
    import { onMount, onDestroy } from "svelte";
    import { api } from "$lib/phoenix";

    // Graph data types
    interface GraphNode {
        id: string;
        label: string;
        username: string;
        avatar?: string;
        type: "current_user" | "friend" | "discoverable";
        x?: number;
        y?: number;
        z?: number;
        online?: boolean;
    }

    interface GraphLink {
        source: string | GraphNode;
        target: string | GraphNode;
        strength: number;
    }

    // Props
    export let width = 800;
    export let height = 600;

    // State
    let nodes: GraphNode[] = [];
    let links: GraphLink[] = [];
    let simulation: any = null;
    let selectedNode: GraphNode | null = null;
    let hoveredNode: GraphNode | null = null;
    let loading = true;
    let error: string | null = null;

    // Load graph data
    onMount(async () => {
        try {
            const data = await api.getGraph();
            nodes = data.nodes || [];
            links = data.links || [];

            if (nodes.length > 0) {
                initSimulation();
            }
            loading = false;
        } catch (e) {
            error = "Failed to load graph data";
            loading = false;
            console.error(e);
        }
    });

    // Initialize force simulation
    function initSimulation() {
        simulation = forceSimulation(nodes)
            .force("charge", forceManyBody().strength(-150))
            .force(
                "link",
                forceLink(links)
                    .id((d: any) => d.id)
                    .distance(60)
                    .strength((l: any) => l.strength),
            )
            .force("center", forceCenter(0, 0, 0))
            .force("collide", forceCollide(15))
            .alphaDecay(0.02)
            .on("tick", () => {
                nodes = [...nodes]; // Trigger reactivity
                links = [...links]; // Also update links (source/target become objects)
            });
    }

    // Helper to get node by ID (for links that haven't been processed by simulation yet)
    function getNodeById(id: string | GraphNode): GraphNode | null {
        if (typeof id === "object") return id;
        return nodes.find((n) => n.id === id) || null;
    }

    // Calculate rotation to orient a Y-up cylinder between two 3D points
    function getCylinderRotation(
        sx: number,
        sy: number,
        sz: number,
        tx: number,
        ty: number,
        tz: number,
    ): [number, number, number] {
        const dx = tx - sx;
        const dy = ty - sy;
        const dz = tz - sz;
        const length = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (length === 0) return [0, 0, 0];

        // Use Three.js quaternion for proper rotation
        const upY = new THREE.Vector3(0, 1, 0);
        const dir = new THREE.Vector3(dx / length, dy / length, dz / length);
        const quaternion = new THREE.Quaternion().setFromUnitVectors(upY, dir);
        const euler = new THREE.Euler().setFromQuaternion(quaternion);
        return [euler.x, euler.y, euler.z];
    }

    onDestroy(() => {
        if (simulation) {
            simulation.stop();
        }
    });

    // Node interactions
    function handleNodeClick(node: GraphNode) {
        selectedNode = node;
        // Could dispatch event or navigate
        console.log("Selected node:", node);
    }

    function handleNodeHover(node: GraphNode | null) {
        hoveredNode = node;
    }

    // Get node color based on type and state
    function getNodeColor(node: GraphNode): string {
        if (selectedNode?.id === node.id) return "#ffd700"; // Gold for selected
        if (hoveredNode?.id === node.id) return "#00d4ff"; // Cyan for hover

        switch (node.type) {
            case "current_user":
                return "#ff6b9d"; // Pink for current user
            case "friend":
                return node.online ? "#00ff88" : "#4a5568"; // Green if online
            default:
                return "#718096"; // Gray for discoverable
        }
    }

    // Get node size
    function getNodeSize(node: GraphNode): number {
        if (node.type === "current_user") return 4;
        if (selectedNode?.id === node.id) return 3.5;
        return 2.5;
    }
</script>

<div class="graph-container" style="width: {width}px; height: {height}px;">
    {#if loading}
        <div class="loading">
            <div class="spinner"></div>
            <p>Loading network...</p>
        </div>
    {:else if error}
        <div class="error">
            <p>{error}</p>
        </div>
    {:else}
        <Canvas>
            <T.PerspectiveCamera makeDefault position={[0, 0, 150]} fov={60}>
                <OrbitControls
                    enableDamping
                    dampingFactor={0.05}
                    minDistance={50}
                    maxDistance={300}
                    enablePan={false}
                />
            </T.PerspectiveCamera>

            <!-- Ambient light -->
            <T.AmbientLight intensity={0.4} />

            <!-- Point light for depth -->
            <T.PointLight position={[100, 100, 100]} intensity={0.8} />
            <T.PointLight position={[-100, -100, -100]} intensity={0.4} />

            <!-- Particle trails and bloom effects -->
            <GraphEffects {nodes} {links} />

            <!-- Render links as cylinders (more visible than thin lines) -->
            {#each links as link}
                {@const sourceNode = getNodeById(link.source)}
                {@const targetNode = getNodeById(link.target)}
                {#if sourceNode && targetNode && sourceNode.x !== undefined && targetNode.x !== undefined}
                    {@const sx = sourceNode.x ?? 0}
                    {@const sy = sourceNode.y ?? 0}
                    {@const sz = sourceNode.z ?? 0}
                    {@const tx = targetNode.x ?? 0}
                    {@const ty = targetNode.y ?? 0}
                    {@const tz = targetNode.z ?? 0}
                    {@const dx = tx - sx}
                    {@const dy = ty - sy}
                    {@const dz = tz - sz}
                    {@const length = Math.sqrt(dx * dx + dy * dy + dz * dz)}
                    {@const midX = (sx + tx) / 2}
                    {@const midY = (sy + ty) / 2}
                    {@const midZ = (sz + tz) / 2}
                    {@const rotation = getCylinderRotation(
                        sx,
                        sy,
                        sz,
                        tx,
                        ty,
                        tz,
                    )}
                    <T.Mesh position={[midX, midY, midZ]} {rotation}>
                        <T.CylinderGeometry args={[0.3, 0.3, length, 6]} />
                        <T.MeshBasicMaterial
                            color="#4a9eff"
                            transparent
                            opacity={0.6}
                        />
                    </T.Mesh>
                {/if}
            {/each}

            <!-- Render nodes as 3D glass marbles -->
            {#each nodes as node (node.id)}
                <T.Group
                    position={[node.x ?? 0, node.y ?? 0, node.z ?? 0]}
                    on:pointerenter={() => handleNodeHover(node)}
                    on:pointerleave={() => handleNodeHover(null)}
                    on:click={() => handleNodeClick(node)}
                >
                    <!-- Inner glowing core -->
                    <T.Mesh>
                        <T.SphereGeometry
                            args={[getNodeSize(node) * 0.6, 24, 24]}
                        />
                        <T.MeshBasicMaterial
                            color={getNodeColor(node)}
                            transparent
                            opacity={0.9}
                        />
                    </T.Mesh>

                    <!-- Glass marble outer shell -->
                    <T.Mesh>
                        <T.SphereGeometry args={[getNodeSize(node), 48, 48]} />
                        <T.MeshPhysicalMaterial
                            color={getNodeColor(node)}
                            metalness={0.1}
                            roughness={0.05}
                            transmission={0.6}
                            thickness={2}
                            clearcoat={1}
                            clearcoatRoughness={0}
                            ior={1.5}
                            envMapIntensity={1}
                            transparent
                            opacity={0.85}
                        />
                    </T.Mesh>

                    <!-- Specular highlight (fake reflection) -->
                    <T.Mesh
                        position={[
                            getNodeSize(node) * 0.3,
                            getNodeSize(node) * 0.3,
                            getNodeSize(node) * 0.6,
                        ]}
                    >
                        <T.SphereGeometry
                            args={[getNodeSize(node) * 0.15, 16, 16]}
                        />
                        <T.MeshBasicMaterial
                            color="#ffffff"
                            transparent
                            opacity={0.6}
                        />
                    </T.Mesh>

                    <!-- Outer glow for online/current users -->
                    {#if node.online || node.type === "current_user"}
                        <T.Mesh scale={1.4}>
                            <T.SphereGeometry
                                args={[getNodeSize(node), 16, 16]}
                            />
                            <T.MeshBasicMaterial
                                color={getNodeColor(node)}
                                transparent
                                opacity={0.12}
                            />
                        </T.Mesh>
                    {/if}

                    <!-- Label (shown on hover or for current user) -->
                    {#if hoveredNode?.id === node.id || node.type === "current_user"}
                        <Text
                            text={node.label}
                            fontSize={3}
                            color="white"
                            position={[0, getNodeSize(node) + 3, 0]}
                            anchorX="center"
                            anchorY="middle"
                        />
                    {/if}
                </T.Group>
            {/each}
        </Canvas>

        <!-- Info overlay -->
        {#if selectedNode}
            <div class="node-info">
                <h3>{selectedNode.label}</h3>
                <p>@{selectedNode.username}</p>
                <button on:click={() => (selectedNode = null)}>Close</button>
            </div>
        {/if}
    {/if}
</div>

<style>
    .graph-container {
        position: relative;
        background: linear-gradient(135deg, #0a0a0a 0%, #1a1a2e 100%);
        border-radius: 12px;
        overflow: hidden;
    }

    .loading,
    .error {
        position: absolute;
        inset: 0;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        color: white;
        gap: 1rem;
    }

    .spinner {
        width: 40px;
        height: 40px;
        border: 3px solid rgba(255, 255, 255, 0.1);
        border-top-color: #00d4ff;
        border-radius: 50%;
        animation: spin 1s linear infinite;
    }

    @keyframes spin {
        to {
            transform: rotate(360deg);
        }
    }

    .node-info {
        position: absolute;
        bottom: 20px;
        left: 20px;
        background: rgba(0, 0, 0, 0.8);
        backdrop-filter: blur(10px);
        padding: 1rem;
        border-radius: 8px;
        color: white;
        min-width: 150px;
    }

    .node-info h3 {
        margin: 0 0 0.25rem 0;
        font-size: 1.1rem;
    }

    .node-info p {
        margin: 0 0 0.75rem 0;
        opacity: 0.7;
        font-size: 0.9rem;
    }

    .node-info button {
        background: rgba(255, 255, 255, 0.1);
        border: none;
        padding: 0.5rem 1rem;
        border-radius: 4px;
        color: white;
        cursor: pointer;
        transition: background 0.2s;
    }

    .node-info button:hover {
        background: rgba(255, 255, 255, 0.2);
    }
</style>
