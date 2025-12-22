/**
 * Graph-related LiveView hooks
 * Handles: FriendGraph, ChordDiagram, WelcomeGraph
 */

import { mount, unmount } from 'svelte'
import FriendGraph from '../../svelte/FriendGraph.svelte'
import ChordDiagram from '../../svelte/ChordDiagram.svelte'
import WelcomeGraph from '../../svelte/WelcomeGraph.svelte'

export const WelcomeGraphHook = {
    mounted() {
        const alwaysShow = this.el.dataset.alwaysShow === 'true'

        if (!alwaysShow && (localStorage.getItem('hideWelcomeGraph') === 'true' || sessionStorage.getItem('graphViewed') === 'true')) {
            this.pushEvent('skip_welcome_graph', {})
            this.el.style.display = 'none'
            return
        }

        const graphData = JSON.parse(this.el.dataset.graphData || 'null')
        const isNewUser = this.el.dataset.isNewUser === 'true'
        const hideControls = this.el.dataset.hideControls === 'true'
        const currentUserId = this.el.dataset.currentUserId || null

        this.component = mount(WelcomeGraph, {
            target: this.el,
            props: {
                graphData,
                live: this,
                showOptOut: !isNewUser,
                hideControls,
                currentUserId
            }
        })

        this.handleEvent("welcome_new_user", (userData) => {
            if (this.component && this.component.addNode) {
                this.component.addNode(userData)
            }
        })

        this.handleEvent("welcome_new_connection", ({ from_id, to_id }) => {
            if (this.component && this.component.addLink) {
                this.component.addLink(from_id, to_id)
            }
        })

        this.handleEvent("welcome_connection_removed", ({ from_id, to_id }) => {
            if (this.component && this.component.removeLink) {
                this.component.removeLink(from_id, to_id)
            }
        })

        this.handleEvent("welcome_signal", ({ user_id }) => {
            if (this.component && this.component.pulseNode) {
                this.component.pulseNode(user_id)
            }
        })

        this.handleEvent("welcome_user_deleted", ({ user_id }) => {
            if (this.component && this.component.removeNode) {
                this.component.removeNode(user_id)
            }
        })
    },
    destroyed() {
        if (this.component) {
            unmount(this.component)
        }
    }
}

export const FriendGraphHook = {
    mounted() {
        const graphData = JSON.parse(this.el.dataset.graph || 'null')

        this.component = mount(FriendGraph, {
            target: this.el,
            props: {
                graphData,
                live: this
            }
        })

        this.handleEvent("graph-updated", ({ graph_data }) => {
            if (this.component) {
                unmount(this.component)
            }
            this.component = mount(FriendGraph, {
                target: this.el,
                props: {
                    graphData: graph_data,
                    live: this
                }
            })
        })
    },
    updated() {
        if (this.component) {
            unmount(this.component)
        }
        const graphData = JSON.parse(this.el.dataset.graph || 'null')
        this.component = mount(FriendGraph, {
            target: this.el,
            props: {
                graphData,
                live: this
            }
        })
    },
    destroyed() {
        if (this.component) {
            unmount(this.component)
        }
    }
}

export const ChordDiagramHook = {
    mounted() {
        const chordData = JSON.parse(this.el.dataset.chord || 'null')

        this.component = mount(ChordDiagram, {
            target: this.el,
            props: {
                chordData,
                live: this
            }
        })

        this.handleEvent("chord-updated", ({ chord_data }) => {
            if (this.component) {
                unmount(this.component)
            }
            this.component = mount(ChordDiagram, {
                target: this.el,
                props: {
                    chordData: chord_data,
                    live: this
                }
            })
        })
    },
    updated() {
        if (this.component) {
            unmount(this.component)
        }
        const chordData = JSON.parse(this.el.dataset.chord || 'null')
        this.component = mount(ChordDiagram, {
            target: this.el,
            props: {
                chordData,
                live: this
            }
        })
    },
    destroyed() {
        if (this.component) {
            unmount(this.component)
        }
    }
}

export default {
    WelcomeGraph: WelcomeGraphHook,
    FriendGraph: FriendGraphHook,
    ChordDiagram: ChordDiagramHook
}
