<script>
  import { onMount, onDestroy } from 'svelte'
  import { Network } from 'vis-network'
  import { DataSet } from 'vis-data'

  // Props from Phoenix LiveView
  export let currentUser = null
  export let friends = []
  export let live = null

  let container
  let network = null
  let nodesDataSet = null
  let edgesDataSet = null

  // Network options for a beautiful social graph
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
      color: {
        color: 'rgba(255,255,255,0.3)',
        highlight: 'rgba(255,255,255,0.8)',
        hover: 'rgba(255,255,255,0.6)'
      },
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
    const nodes = []
    const edges = []

    // Add current user as the central node
    if (currentUser) {
      nodes.push({
        id: currentUser.id,
        label: currentUser.display_name || currentUser.username,
        color: {
          background: currentUser.color || '#ffffff',
          border: '#ffffff',
          highlight: {
            background: currentUser.color || '#ffffff',
            border: '#ffffff'
          },
          hover: {
            background: currentUser.color || '#ffffff',
            border: '#ffffff'
          }
        },
        size: 35, // Larger size for current user
        font: {
          size: 16,
          bold: true
        },
        title: `@${currentUser.username}` // Tooltip
      })
    }

    // Add friends as nodes
    friends.forEach(friend => {
      nodes.push({
        id: friend.id,
        label: friend.display_name || friend.username,
        color: {
          background: friend.color || '#888888',
          border: 'rgba(255,255,255,0.5)',
          highlight: {
            background: friend.color || '#888888',
            border: '#ffffff'
          },
          hover: {
            background: friend.color || '#888888',
            border: 'rgba(255,255,255,0.8)'
          }
        },
        title: `@${friend.username}`, // Tooltip
        size: 25
      })

      // Create edge from current user to friend
      if (currentUser) {
        edges.push({
          from: currentUser.id,
          to: friend.id,
          id: `${currentUser.id}-${friend.id}`
        })
      }
    })

    return { nodes, edges }
  }

  function initNetwork() {
    if (!container) return

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
        if (live && nodeId !== currentUser?.id) {
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

    // Remove nodes that no longer exist
    const nodesToRemove = currentNodeIds.filter(id => !newNodeIds.includes(id))
    nodesDataSet.remove(nodesToRemove)

    // Add or update nodes
    nodesDataSet.update(nodes)

    // Update edges
    const currentEdgeIds = edgesDataSet.getIds()
    const newEdgeIds = edges.map(e => e.id)

    // Remove edges that no longer exist
    const edgesToRemove = currentEdgeIds.filter(id => !newEdgeIds.includes(id))
    edgesDataSet.remove(edgesToRemove)

    // Add or update edges
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

  // Reactive updates when friends change
  $: if (container && (friends || currentUser)) {
    updateNetwork()
  }
</script>

<div
  bind:this={container}
  class="w-full h-full min-h-[500px] bg-transparent"
></div>

<style>
  /* Ensure the container takes full height */
  div {
    position: relative;
  }
</style>
