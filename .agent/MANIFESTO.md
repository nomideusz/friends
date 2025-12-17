# New Internet — Project Manifesto

> *Fresh, clean, people-oriented, network-oriented. Almost Buddhist.*

---

## Core Philosophy

**New Internet** is an innovative project challenging old-school patterns. We propose something new—possibly better—while remaining intuitive for users accustomed to existing patterns.

New Internet is:
- **Friendly** — against violence, welcoming to all
- **People-oriented** — humans first, technology serves them
- **Network-oriented** — connections and communities at the center
- **Minimal** — as simple as possible, but not simpler

---

## Primary Focus: Groups

Groups are the main feature. Our priorities:
1. **Creating groups** — seamless, intuitive group creation (Spaces)
2. **Adding members** — frictionless invitations
3. **Building connections** — nurturing the network effect

---

## Design Principles

### Fluid Design
- **Organic Depth** — Use high-blur glass layering and subtle inner highlights to create realistic depth.
- **Physical Interaction** — Transitions and hovers use **spring-based easing** to feel responsive and alive.
- **Organic Corners** — Forget the grid-rigid past; use large, organic radii (`--radius-fluid`) for a softer human touch.
- **Constraint as Clarity** — No visual clutter. No banners, big headers, or traditional footers.

### Navigation Hub
- **Unified Controls** — Consolidate fragmented actions into a central **Fluid Toolbar** or Dynamic Island.
- **Responsive Surfaces** — 
  - **Mobile**: Surfaces emerge from the bottom as **Sheet Drawers** to prioritize thumb-reachability and natural physical flow.
  - **Desktop**: Surfaces appear as centered **Floating Islands** (Modals) to maintain focus and respect the wider canvas.
- **Context-Aware** — The interface adapts to the current focus (Space vs. Network) without layout shifts.
- **Gesture-Ready** — Design for touch-first fluidity across all devices.

### Content Philosophy
- **No helping texts** — we don't treat users like babies.
- **Trust user intelligence** — guide through design, not words.
- **Let the interface speak for itself.**

---

## Values

| Principle | What it means |
|-----------|---------------|
| Friendly | Welcoming, safe, against violence |
| Fresh | Modern, innovative, forward-thinking |
| Fluid | Organic motion, springy interactions, and depth |
| People-first | Human connections over engagement metrics |
| Network-first | Groups (Spaces) and connections are the product |

---

## Visual Identity — The Fluid Palette

### Depth & Surfaces
| Token | Purpose |
|-------|---------|
| `--color-void` | Pure Black background (#000000) for OLED depth |
| `--color-glass` | Semi-transparent layered surfaces |
| `--radius-fluid` | Large organic radius (32px) for structural elements |

### The Light
| Token | Purpose |
|-------|---------|
| `--color-light` | iOS-style clean white text (#F5F5F7) |
| `--color-dim` | iOS-style subtle secondary text (#8E8E93) |
| `--blur-glass` | High-quality 24px backdrop blur |

### Interactions
| Token | Purpose |
|-------|---------|
| `--color-energy` | Apple Blue (#007AFF) for focuses and primary actions |
| `--ease-spring` | The physical signature of our motion system |

---

## Anti-Patterns — What We Are NOT

| ❌ We avoid | Why |
|-------------|-----|
| **No "likes"** | Vanity metrics breed toxicity |
| **No marketing speak** | Authenticity over engagement |
| **No bullshit** | Honesty and clarity always |
| **No legacy patterns** | We break free from sidebars and static headers |
| **No dark patterns** | Respect user agency |

---

## Technical Principles

| Principle | Implementation |
|-----------|----------------|
| **Performance-first** | Fast, responsive, optimized (OLED optimized) |
| **Live by default** | Phoenix LiveView for real-time updates |
| **Everything is live** | No page reloads, seamless state transitions |
| **Server-driven UI** | LiveView pushes state, client follows the flow |

> 💡 If it can be live, it should be live.

---

*This manifesto guides all design and development decisions.*
