# Cytoscape.js Migration Plan

## Goals
1. Migrate from vis.js to Cytoscape.js
2. Maintain all existing functionality
3. Add 3 new killer features

## Step-by-Step Plan

### Step 1: Install Cytoscape.js (15 min)
```bash
cd assets
npm install cytoscape
npm install cytoscape-cola  # For better layouts
npm install cytoscape-fcose # Alternative physics layout
```

### Step 2: Create New Component (2 hours)
**File:** `assets/svelte/NetworkGraph.svelte` (new name to avoid conflicts)

**Key differences from vis.js:**
- More explicit styling (CSS-like)
- Better programmatic control
- Easier to customize

**Data format:** (minimal changes needed)
```javascript
// Current format works! Just need to adapt:
{
  nodes: [
    { data: { id: 1, label: "Alice", type: "friend" } }
  ],
  edges: [
    { data: { source: 1, target: 2, type: "mutual" } }
  ]
}
```

### Step 3: Backend Changes (30 min)
**File:** `lib/friends_web/live/network_live.ex`

Change graph data format slightly:
```elixir
# Old (vis.js):
%{from: user.id, to: f.user.id}

# New (Cytoscape):
%{source: user.id, target: f.user.id}
```

### Step 4: Testing (1 hour)
- Verify all nodes render
- Check real-time updates
- Test click interactions
- Mobile responsiveness

### Step 5: Deploy (30 min)
- Swap component in network_live.html.heex
- Monitor for issues
- Rollback plan ready

---

## New Features to Add During Migration

### Feature 1: Visual Group Creation (2 hours)
**What:** Multi-select nodes → "Create Group" button appears

**Implementation:**
```javascript
// In NetworkGraph.svelte
let selectedNodes = []

cy.on('select', 'node', (evt) => {
  selectedNodes = cy.$('node:selected').map(n => n.id())
  if (selectedNodes.length >= 2) {
    showCreateGroupButton()
  }
})

function createGroup() {
  live.pushEvent('create_group_from_graph', {
    member_ids: selectedNodes
  })
}
```

**Backend:**
```elixir
# In network_live.ex
def handle_event("create_group_from_graph", %{"member_ids" => ids}, socket) do
  # Auto-generate group name from members
  # Create room
  # Add members
  # Redirect to new group
end
```

### Feature 2: Trust Path Highlighting (2 hours)
**What:** Hover any node → highlight shortest path to you

**Implementation:**
```javascript
cy.on('mouseover', 'node', (evt) => {
  const node = evt.target
  const currentUser = cy.$('#' + currentUserId)

  // Find shortest path using built-in algorithm
  const path = cy.elements()
    .aStar({
      root: currentUser,
      goal: node
    })

  if (path.found) {
    path.path.addClass('highlighted')
    showTrustScore(path.distance)
  }
})
```

**UI:**
- Glowing path animation
- Popup showing: "2 hops away, 3 mutual friends"
- Trust score: High/Medium/Low

### Feature 3: Community Detection (3 hours)
**What:** Auto-detect friend clusters → suggest group names

**Implementation:**
```javascript
// Use Cytoscape's built-in community detection
import cytoscapeCola from 'cytoscape-cola'

const clusters = cy.elements().markovClustering({
  attributes: ['mutual_count']
})

// Color nodes by cluster
clusters.forEach((cluster, index) => {
  cluster.style('background-color', clusterColors[index])
})

// Suggest groups
live.pushEvent('suggest_groups', {
  clusters: clusters.map(c => c.map(n => n.id()))
})
```

**Backend analyzes clusters:**
- "Your college friends" (if all went to same school)
- "Work connections" (if all in same company)
- "Local friends" (if all in same city)
- Generic: "Friend Group A" as fallback

---

## Migration Risks & Mitigations

### Risk 1: Breaking Changes
**Mitigation:** Keep both components during migration
- Deploy Cytoscape as opt-in beta
- Feature flag: `use_new_graph: true`
- Easy rollback

### Risk 2: Performance Regression
**Mitigation:** Benchmark before/after
- Test with large graphs (100+ nodes)
- Monitor render times
- Lazy load 2nd degree if needed

### Risk 3: Mobile Performance
**Mitigation:**
- Simplified mobile layout
- Reduce physics complexity on mobile
- Progressive enhancement

---

## Timeline

### Aggressive (1 week):
- Day 1-2: Migration + testing
- Day 3: Visual group creation
- Day 4: Trust path highlighting
- Day 5: Community detection
- Day 6-7: Polish + deploy

### Realistic (2 weeks):
- Week 1: Migration + one feature (group creation)
- Week 2: Trust paths + community detection + polish

### Conservative (3 weeks):
- Week 1: Migration thoroughly tested
- Week 2: Visual group creation
- Week 3: Trust paths OR community detection

---

## Success Metrics

**Graph engagement:**
- Track clicks on graph
- Time spent on /network page
- Groups created via graph

**Target:** 50% of groups created from graph within 1 month

**Trust awareness:**
- Users hovering nodes to see trust paths
- Trust scores influencing friend requests

**Target:** 30% of users check trust before adding

---

## Next Steps

**Option 1: Full Migration First**
- Migrate entire graph to Cytoscape
- Then add features
- Safer, but slower to ship features

**Option 2: Feature-First with Vis.js**
- Prototype visual group creation with current vis.js
- Validate concept
- Then migrate with features included
- Faster validation, technical debt

**Option 3: Parallel Development**
- Build Cytoscape version alongside vis.js
- Ship as beta/opt-in
- Migrate when confident
- Most flexible, more work

**Recommendation: Option 1**
- Migration is only 2-4 hours
- Better foundation for features
- Clean break, no technical debt
