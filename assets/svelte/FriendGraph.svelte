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
      nodes.push({
        id: node.id,
        label: node.display_name || node.username,
        color: {
          background: node.color || '#888888',
          border: isSelf ? '#ffffff' : 'rgba(255,255,255,0.5)',
          highlight: { background: node.color || '#888888', border: '#ffffff' },
          hover: { background: node.color || '#888888', border: 'rgba(255,255,255,0.8)' }
        },
        title: `@${node.username}`,
        size: isSelf ? 35 : 25,
        font: isSelf ? { size: 16, bold: true, color: '#ffffff' } : { size: 14, color: '#ffffff' }
      })
    })

    // Build edges
    if (graphData.edges) {
      graphData.edges.forEach((edge, index) => {
        const pairKey = `${Math.min(edge.from, edge.to)}-${Math.max(edge.from, edge.to)}`
        const isMutual = mutualPairs.has(pairKey) && (edge.type === 'trusted' || edge.type === 'trusts_me')

        if (edge.type === 'trusts_me' && mutualPairs.has(pairKey)) {
          return
        }

        const isPending = edge.type === 'pending_outgoing' || edge.type === 'pending_incoming'
        const color = isMutual ? edgeColors.mutual : edgeColors[edge.type] || 'rgba(255,255,255,0.3)'

        edges.push({
          id: `edge-${index}`,
          from: edge.from,
          to: edge.to,
          color: { color, highlight: '#ffffff', hover: color },
          dashes: isPending ? [5, 5] : false,
          width: isMutual ? 3 : 2,
          arrows: isMutual ? undefined : { to: { enabled: true, scaleFactor: 0.5 } }
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
