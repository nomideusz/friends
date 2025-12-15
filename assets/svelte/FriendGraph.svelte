<script>
  import { onMount, onDestroy, tick } from 'svelte'
  import { Network } from 'vis-network'
  import { DataSet } from 'vis-data'

  // Props from Phoenix LiveView
  export let graphData = null
  export let live = null

  let container
  let network = null
  let nodesDataSet = null
  let edgesDataSet = null
  let error = null

  // Edge colors by type
  const edgeColors = {
    friend: '#3b82f6',
    trusted: '#60a5fa',
    trusts_me: '#a78bfa',
    mutual: '#ffffff',
    pending_outgoing: '#fbbf24',
    pending_incoming: '#fbbf24',
    invited: '#f472b6'
  }

  // Network options
  const options = {
    nodes: {
      shape: 'dot',
      size: 25,
      font: {
        size: 14,
        color: '#ffffff',
        face: 'monospace'
      },
      borderWidth: 3,
      shadow: {
        enabled: true,
        color: 'rgba(0,0,0,0.5)',
        size: 10
      }
    },
    edges: {
      width: 2,
      smooth: {
        type: 'continuous',
        roundness: 0.5
      },
      shadow: {
        enabled: true,
        color: 'rgba(0,0,0,0.3)',
        size: 5
      }
    },
    physics: {
      enabled: true,
      solver: 'forceAtlas2Based',
      forceAtlas2Based: {
        gravitationalConstant: -50,
        centralGravity: 0.01,
        springLength: 150,
        springConstant: 0.08,
        damping: 0.4
      },
      stabilization: {
        enabled: true,
        iterations: 200,
        updateInterval: 25
      }
    },
    interaction: {
      hover: true,
      tooltipDelay: 200,
      hideEdgesOnDrag: true,
      zoomView: true,
      dragView: true
    }
  }

  function buildGraphData() {
    if (!graphData || !graphData.nodes) return { nodes: [], edges: [] }

    const nodes = []
    const edges = []
    const mutualPairs = new Set()

    // Find mutual relationships
    if (graphData.edges) {
      graphData.edges.forEach(edge => {
        if (edge.type === 'trusted') {
          const hasMutual = graphData.edges.some(e =>
            e.type === 'trusts_me' && e.from === edge.to && e.to === edge.from
          )
          if (hasMutual) {
            mutualPairs.add(`${Math.min(edge.from, edge.to)}-${Math.max(edge.from, edge.to)}`)
          }
        }
      })
    }

    // Build nodes
    graphData.nodes.forEach(node => {
      const isSelf = node.type === 'self'
      const isSecondDegree = node.type === 'second_degree'

      // Aether Colors
      let color = '#888888'
      if (isSelf) color = '#ffffff' // Photon
      else if (node.type === 'trusted') color = '#34d399' // Emerald
      else if (node.type === 'trusts_me') color = '#a78bfa' // Amethyst
      else if (node.type === 'friend') color = '#3b82f6' // Sapphire
      else if (isSecondDegree) color = '#6b7280' // Gray for 2nd degree

      // Build title (tooltip) with mutual count if available
      let title = `@${node.username}`
      if (node.mutual_count && node.mutual_count > 0) {
        title += `\n${node.mutual_count} mutual friend${node.mutual_count > 1 ? 's' : ''}`
      }

      nodes.push({
        id: node.id,
        label: node.display_name || node.username,
        color: {
          background: isSelf ? '#ffffff' : (isSecondDegree ? 'rgba(0,0,0,0.5)' : 'rgba(0,0,0,0.8)'),
          border: color,
          highlight: { background: isSelf ? '#ffffff' : color, border: '#ffffff' },
          hover: { background: isSelf ? '#ffffff' : color, border: '#ffffff' }
        },
        shadow: {
          enabled: true,
          color: color,
          size: isSelf ? 25 : (isSecondDegree ? 8 : 15),
          x: 0,
          y: 0
        },
        title: title,
        size: isSelf ? 20 : (isSecondDegree ? 8 : 12),
        borderWidth: isSelf ? 0 : 2,
        font: {
          size: isSelf ? 16 : (isSecondDegree ? 11 : 14),
          color: isSecondDegree ? '#9ca3af' : '#ffffff',
          face: 'Outfit, sans-serif',
          strokeWidth: 3,
          strokeColor: '#000000'
        },
        opacity: isSecondDegree ? 0.6 : 1.0
      })
    })

    // Build edges
    if (graphData.edges) {
      graphData.edges.forEach((edge, index) => {
        const pairKey = `${Math.min(edge.from, edge.to)}-${Math.max(edge.from, edge.to)}`
        const isMutualTrust = mutualPairs.has(pairKey) && (edge.type === 'trusted' || edge.type === 'trusts_me')

        if (edge.type === 'trusts_me' && mutualPairs.has(pairKey)) {
          return
        }

        const isPending = edge.type === 'pending_outgoing' || edge.type === 'pending_incoming'
        const isFriendToFriend = edge.type === 'mutual'
        const isSecondDegree = edge.type === 'second_degree'

        // Edge Colors (Aether Light Beams)
        let baseColor = 'rgba(255,255,255,0.15)'
        if (edge.type === 'trusted') baseColor = 'rgba(52, 211, 153, 0.4)'
        if (edge.type === 'friend') baseColor = 'rgba(59, 130, 246, 0.3)'
        if (isSecondDegree) baseColor = 'rgba(107, 114, 128, 0.15)' // Faded gray

        const color = isMutualTrust ? '#ffffff' : baseColor

        // Build edge label for mutual count
        let label = undefined
        if (edge.mutual_count && edge.mutual_count > 0) {
          label = `${edge.mutual_count}`
        }

        edges.push({
          id: `edge-${index}`,
          from: edge.from,
          to: edge.to,
          color: {
            color: isFriendToFriend ? 'rgba(255,255,255,0.05)' : color,
            highlight: '#ffffff',
            hover: '#ffffff'
          },
          dashes: isPending || isFriendToFriend || isSecondDegree ? [5, 5] : false,
          width: isMutualTrust ? 2 : (isFriendToFriend || isSecondDegree ? 1 : 1),
          arrows: isMutualTrust || isFriendToFriend || isSecondDegree ? undefined : { to: { enabled: true, scaleFactor: 0.5, type: 'arrow' } },
          smooth: { type: 'continuous', roundness: 0.3 },
          label: label,
          font: {
            size: 10,
            color: '#60a5fa',
            background: 'rgba(0,0,0,0.8)',
            strokeWidth: 0,
            face: 'Outfit, sans-serif'
          }
        })
      })
    }

    return { nodes, edges }
  }

  async function initNetwork() {
    if (!container) {
      console.error('[FriendGraph] No container')
      return
    }

    if (!graphData) {
      console.error('[FriendGraph] No graphData')
      return
    }

    try {
      // Wait for DOM to be ready
      await tick()

      // Ensure container has dimensions
      if (container.offsetWidth === 0 || container.offsetHeight === 0) {
        console.warn('[FriendGraph] Container has no dimensions, retrying...')
        setTimeout(initNetwork, 100)
        return
      }

      const { nodes, edges } = buildGraphData()

      console.log('[FriendGraph] Initializing with', nodes.length, 'nodes and', edges.length, 'edges')

      if (nodes.length === 0) {
        error = 'No nodes to display'
        return
      }

      nodesDataSet = new DataSet(nodes)
      edgesDataSet = new DataSet(edges)

      const data = { nodes: nodesDataSet, edges: edgesDataSet }

      // Destroy existing network if any
      if (network) {
        network.destroy()
      }

      network = new Network(container, data, options)

      network.on('click', params => {
        if (params.nodes.length > 0) {
          const nodeId = params.nodes[0]
          const currentUserId = graphData?.current_user?.id

          if (live && nodeId !== currentUserId) {
            // Find the clicked node to check its type
            const clickedNode = graphData.nodes.find(n => n.id === nodeId)

            if (clickedNode && clickedNode.type === 'second_degree') {
              // Second degree node clicked - send friend request
              live.pushEvent('add_friend_from_graph', { user_id: String(nodeId) })
            } else {
              // Regular node clicked - just notify
              live.pushEvent('node_clicked', { user_id: nodeId })
            }
          }
        }
      })

      network.on('doubleClick', params => {
        if (params.nodes.length > 0) {
          network.focus(params.nodes[0], {
            scale: 1.5,
            animation: { duration: 500, easingFunction: 'easeInOutQuad' }
          })
        }
      })

      network.once('stabilizationIterationsDone', () => {
        network.fit({
          animation: { duration: 500, easingFunction: 'easeInOutQuad' }
        })
      })

      error = null
    } catch (e) {
      console.error('[FriendGraph] Error initializing network:', e)
      error = e.message
    }
  }

  // Handle real-time graph updates from LiveView
  function handleGraphUpdate(event) {
    if (!nodesDataSet || !edgesDataSet || !event.detail || !event.detail.graph_data) {
      console.warn('[FriendGraph] No DataSets or graph_data in update event')
      return
    }

    const newGraphData = event.detail.graph_data
    const { nodes: newNodes, edges: newEdges } = buildGraphData(newGraphData)

    // Get current IDs
    const currentNodeIds = new Set(nodesDataSet.getIds())
    const currentEdgeIds = new Set(edgesDataSet.getIds())
    const newNodeIds = new Set(newNodes.map(n => n.id))
    const newEdgeIds = new Set(newEdges.map(e => e.id))

    // Find nodes to add, update, and remove
    const nodesToAdd = newNodes.filter(n => !currentNodeIds.has(n.id))
    const nodesToUpdate = newNodes.filter(n => currentNodeIds.has(n.id))
    const nodesToRemove = Array.from(currentNodeIds).filter(id => !newNodeIds.has(id))

    // Find edges to add, update, and remove
    const edgesToAdd = newEdges.filter(e => !currentEdgeIds.has(e.id))
    const edgesToUpdate = newEdges.filter(e => currentEdgeIds.has(e.id))
    const edgesToRemove = Array.from(currentEdgeIds).filter(id => !newEdgeIds.has(id))

    console.log('[FriendGraph] Update:', {
      nodesToAdd: nodesToAdd.length,
      nodesToUpdate: nodesToUpdate.length,
      nodesToRemove: nodesToRemove.length,
      edgesToAdd: edgesToAdd.length,
      edgesToUpdate: edgesToUpdate.length,
      edgesToRemove: edgesToRemove.length
    })

    // Apply updates (order matters: remove first, then update, then add)
    if (nodesToRemove.length > 0) nodesDataSet.remove(nodesToRemove)
    if (edgesToRemove.length > 0) edgesDataSet.remove(edgesToRemove)
    if (nodesToUpdate.length > 0) nodesDataSet.update(nodesToUpdate)
    if (edgesToUpdate.length > 0) edgesDataSet.update(edgesToUpdate)
    if (nodesToAdd.length > 0) nodesDataSet.add(nodesToAdd)
    if (edgesToAdd.length > 0) edgesDataSet.add(edgesToAdd)

    // Smooth re-fit if significant changes
    if (nodesToAdd.length > 0 || nodesToRemove.length > 0) {
      setTimeout(() => {
        if (network) {
          network.fit({
            animation: { duration: 300, easingFunction: 'easeInOutQuad' }
          })
        }
      }, 500)
    }
  }

  onMount(() => {
    // Small delay to ensure container is rendered
    setTimeout(initNetwork, 50)

    // Listen for real-time graph updates from LiveView
    if (live) {
      window.addEventListener('phx:graph-updated', handleGraphUpdate)
    }
  })

  onDestroy(() => {
    if (network) {
      network.destroy()
      network = null
    }

    // Clean up event listener
    if (live) {
      window.removeEventListener('phx:graph-updated', handleGraphUpdate)
    }
  })

  // Reactive updates
  $: if (container && graphData && !network) {
    initNetwork()
  }
</script>

<div
  bind:this={container}
  style="width: 100%; height: 500px; min-height: 500px;"
></div>

{#if error}
  <div class="absolute inset-0 flex items-center justify-center text-red-400 text-sm">
    Error: {error}
  </div>
{/if}
