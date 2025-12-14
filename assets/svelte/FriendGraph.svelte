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
      
      // Aether Colors
      let color = '#888888'
      if (isSelf) color = '#ffffff' // Photon
      else if (node.type === 'trusted') color = '#34d399' // Emerald
      else if (node.type === 'trusts_me') color = '#a78bfa' // Amethyst
      else if (node.type === 'friend') color = '#3b82f6' // Sapphire

      nodes.push({
        id: node.id,
        label: node.display_name || node.username,
        color: {
          background: isSelf ? '#ffffff' : 'rgba(0,0,0,0.8)', // Self is solid light, others are dark void orbs
          border: color,
          highlight: { background: isSelf ? '#ffffff' : color, border: '#ffffff' },
          hover: { background: isSelf ? '#ffffff' : color, border: '#ffffff' }
        },
        shadow: {
          enabled: true,
          color: color,
          size: isSelf ? 25 : 15,
          x: 0,
          y: 0
        },
        title: `@${node.username}`,
        size: isSelf ? 20 : 12,
        borderWidth: isSelf ? 0 : 2,
        font: { 
          size: isSelf ? 16 : 14, 
          color: '#ffffff',
          face: 'Outfit, sans-serif',
          strokeWidth: 3,
          strokeColor: '#000000'
        }
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
        
        // Edge Colors (Aether Light Beams)
        let baseColor = 'rgba(255,255,255,0.15)'
        if (edge.type === 'trusted') baseColor = 'rgba(52, 211, 153, 0.4)'
        if (edge.type === 'friend') baseColor = 'rgba(59, 130, 246, 0.3)'
        
        const color = isMutualTrust ? '#ffffff' : baseColor

        edges.push({
          id: `edge-${index}`,
          from: edge.from,
          to: edge.to,
          color: { 
            color: isFriendToFriend ? 'rgba(255,255,255,0.05)' : color, 
            highlight: '#ffffff', 
            hover: '#ffffff'
          },
          dashes: isPending || isFriendToFriend ? [5, 5] : false,
          width: isMutualTrust ? 2 : (isFriendToFriend ? 1 : 1),
          arrows: isMutualTrust || isFriendToFriend ? undefined : { to: { enabled: true, scaleFactor: 0.5, type: 'arrow' } },
          smooth: { type: 'continuous', roundness: 0.3 }
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
            live.pushEvent('node_clicked', { user_id: nodeId })
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

  onMount(() => {
    // Small delay to ensure container is rendered
    setTimeout(initNetwork, 50)
  })

  onDestroy(() => {
    if (network) {
      network.destroy()
      network = null
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
