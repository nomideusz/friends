<script>
  import { onMount, onDestroy } from 'svelte'
  import { Network } from 'vis-network'
  import { DataSet } from 'vis-data'

  // Props from Phoenix LiveView (new structure)
  export let graphData = null
  export let live = null

  let container
  let network = null
  let nodesDataSet = null
  let edgesDataSet = null

  // Edge colors by type
  const edgeColors = {
    trusted: '#60a5fa',      // blue - I trust them
    trusts_me: '#a78bfa',    // purple - they trust me
    mutual: '#ffffff',       // white - mutual trust
    pending_outgoing: '#fbbf24', // yellow - pending I sent
    pending_incoming: '#fbbf24', // yellow - pending they sent
    invited: '#f472b6'       // pink - invite relationship
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
        size: 10,
        x: 0,
        y: 0
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
    },
    layout: {
      improvedLayout: true
    }
  }

  function buildGraphData() {
    if (!graphData) return { nodes: [], edges: [] }

    const nodes = []
    const edges = []

    // Track which edges are mutual
    const mutualPairs = new Set()

    // Find mutual relationships
    graphData.edges.forEach(edge => {
      if (edge.type === 'trusted') {
        // Check if there's a reverse trusts_me edge
        const hasMutual = graphData.edges.some(e =>
          e.type === 'trusts_me' && e.from === edge.to && e.to === edge.from
        )
        if (hasMutual) {
          mutualPairs.add(`${Math.min(edge.from, edge.to)}-${Math.max(edge.from, edge.to)}`)
        }
      }
    })

    // Build nodes
    graphData.nodes.forEach(node => {
      const isSelf = node.type === 'self'
      nodes.push({
        id: node.id,
        label: node.display_name || node.username,
        color: {
          background: node.color || '#888888',
          border: isSelf ? '#ffffff' : 'rgba(255,255,255,0.5)',
          highlight: {
            background: node.color || '#888888',
            border: '#ffffff'
          },
          hover: {
            background: node.color || '#888888',
            border: 'rgba(255,255,255,0.8)'
          }
        },
        title: `@${node.username}`,
        size: isSelf ? 35 : 25,
        font: isSelf ? { size: 16, bold: true, color: '#ffffff' } : { size: 14, color: '#ffffff' }
      })
    })

    // Build edges
    graphData.edges.forEach((edge, index) => {
      const pairKey = `${Math.min(edge.from, edge.to)}-${Math.max(edge.from, edge.to)}`
      const isMutual = mutualPairs.has(pairKey) && (edge.type === 'trusted' || edge.type === 'trusts_me')

      // Skip trusts_me edges for mutual relationships (we'll use the trusted edge)
      if (edge.type === 'trusts_me' && mutualPairs.has(pairKey)) {
        return
      }

      const isPending = edge.type === 'pending_outgoing' || edge.type === 'pending_incoming'
      const color = isMutual ? edgeColors.mutual : edgeColors[edge.type] || 'rgba(255,255,255,0.3)'

      edges.push({
        id: `edge-${index}`,
        from: edge.from,
        to: edge.to,
        color: {
          color: color,
          highlight: '#ffffff',
          hover: color
        },
        dashes: isPending ? [5, 5] : false,
        width: isMutual ? 3 : 2,
        arrows: isMutual ? undefined : {
          to: {
            enabled: true,
            scaleFactor: 0.5
          }
        }
      })
    })

    return { nodes, edges }
  }

  function initNetwork() {
    if (!container || !graphData) return

    const { nodes, edges } = buildGraphData()

    nodesDataSet = new DataSet(nodes)
    edgesDataSet = new DataSet(edges)

    const data = {
      nodes: nodesDataSet,
      edges: edgesDataSet
    }

    network = new Network(container, data, options)

    // Handle node click events
    network.on('click', params => {
      if (params.nodes.length > 0) {
        const nodeId = params.nodes[0]
        const currentUserId = graphData?.current_user?.id
        if (live && nodeId !== currentUserId) {
          live.pushEvent('node_clicked', { user_id: nodeId })
        }
      }
    })

    // Handle double-click to focus on a node
    network.on('doubleClick', params => {
      if (params.nodes.length > 0) {
        network.focus(params.nodes[0], {
          scale: 1.5,
          animation: {
            duration: 500,
            easingFunction: 'easeInOutQuad'
          }
        })
      }
    })

    // Fit the network to view once stabilized
    network.once('stabilizationIterationsDone', () => {
      network.fit({
        animation: {
          duration: 500,
          easingFunction: 'easeInOutQuad'
        }
      })
    })
  }

  function updateNetwork() {
    if (!network || !nodesDataSet || !edgesDataSet) {
      initNetwork()
      return
    }

    const { nodes, edges } = buildGraphData()

    // Update nodes
    const currentNodeIds = nodesDataSet.getIds()
    const newNodeIds = nodes.map(n => n.id)

    const nodesToRemove = currentNodeIds.filter(id => !newNodeIds.includes(id))
    nodesDataSet.remove(nodesToRemove)
    nodesDataSet.update(nodes)

    // Update edges
    const currentEdgeIds = edgesDataSet.getIds()
    const newEdgeIds = edges.map(e => e.id)

    const edgesToRemove = currentEdgeIds.filter(id => !newEdgeIds.includes(id))
    edgesDataSet.remove(edgesToRemove)
    edgesDataSet.update(edges)
  }

  onMount(() => {
    initNetwork()
  })

  onDestroy(() => {
    if (network) {
      network.destroy()
      network = null
    }
  })

  // Reactive updates when graphData changes
  $: if (container && graphData) {
    updateNetwork()
  }
</script>

<div
  bind:this={container}
  class="w-full h-full min-h-[500px] bg-transparent"
></div>

<style>
  div {
    position: relative;
  }
</style>
