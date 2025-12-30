/**
 * Friends App - Main JavaScript Entry Point
 * 
 * This file has been modularized. Hooks are now organized in:
 * - hooks/graph-hooks.js   - Graph visualization hooks
 * - hooks/auth-hooks.js    - WebAuthn authentication hooks
 * - hooks/media-hooks.js   - Voice recording/playback hooks
 * - hooks/ui-hooks.js      - UI interaction hooks
 * - hooks/chat-hooks.js    - Chat/messaging hooks
 */

// Phoenix imports
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import { getHooks } from "live_svelte"

// Svelte components (remaining after cleanup)
import FriendGraph from "../svelte/FriendGraph.svelte"
import WelcomeGraph from "../svelte/WelcomeGraph.svelte"
import ChordDiagram from "../svelte/ChordDiagram.svelte"

// Modular hooks
import ModularHooks from "./hooks"

// Image optimization utilities
import { generateThumbnail, optimizeImage, generateFingerprint, getBrowserId } from "./utils"

const Components = { FriendGraph, WelcomeGraph, ChordDiagram }

// Main application hook (kept here as it's the core app hook)
const FriendsAppHook = {
    async mounted() {
        this.browserId = bootstrapBrowserId
        this.fingerprint = bootstrapFingerprint

        this.identityPayload = {
            browser_id: this.browserId,
            fingerprint: this.fingerprint
        }

        this.maybeSendIdentity()

        this.handleEvent("request_identity", () => this.maybeSendIdentity())

        this.handleEvent("set_user_cookie", ({ user_id }) => {
            if (user_id) {
                document.cookie = `friends_user_id=${user_id}; path=/; max-age=${60 * 60 * 24 * 365}; SameSite=Lax`
            }
        })

        this.handleEvent("set_session_token", ({ token }) => {
            if (token) {
                document.cookie = `friends_session_token=${token}; path=/; max-age=${60 * 60 * 24 * 30}; SameSite=Lax`
            }
        })

        const skipBtn = document.getElementById('skip-constellation-btn')
        if (skipBtn) {
            skipBtn.addEventListener('click', () => {
                const optOutCheckbox = document.getElementById('constellation-opt-out')
                if (optOutCheckbox && optOutCheckbox.checked) {
                    localStorage.setItem('constellation_opt_out', 'true')
                }
            })
        }

        this.handleEvent("sign_out", async () => {
            localStorage.removeItem('friends_browser_id')
            document.cookie = 'friends_user_id=; path=/; max-age=0'
            document.cookie = 'friends_session_token=; path=/; max-age=0'
            window.location.href = '/'
        })

        this.handleEvent("photo_uploaded", ({ photo_id }) => {
            if (this.pendingThumbnail && photo_id) {
                this.pushEvent("set_thumbnail", {
                    photo_id: photo_id,
                    thumbnail: this.pendingThumbnail
                })
                this.pendingThumbnail = null
            }
        })


        this.pendingThumbnail = null
        this.setupImageOptimization()
    },

    updated() {
        this.setupImageOptimization()
    },

    reconnected() {
        this.maybeSendIdentity()
    },

    maybeSendIdentity(retryCount = 0) {
        const maxRetries = 10
        const baseDelay = 300

        if (!this.identityPayload) return

        try {
            this.pushEvent("set_user_id", this.identityPayload)
        } catch (error) {
            if (retryCount < maxRetries) {
                const delay = baseDelay * Math.pow(2, retryCount)
                setTimeout(() => this.maybeSendIdentity(retryCount + 1), delay)
            }
        }
    },

    setupImageOptimization() {
        const fileInput = this.el.querySelector('input[type="file"][name*="photo"]') ||
            this.el.querySelector('input[type="file"]')

        if (!fileInput) return
        if (fileInput.dataset.optimized) return
        fileInput.dataset.optimized = 'true'

        fileInput.addEventListener('change', async (e) => {
            const files = e.target.files
            if (!files || files.length === 0) return

            const file = files[0]

            if (file.type.startsWith('image/') && file.type !== 'image/gif') {
                const thumbnail = await generateThumbnail(file, 600)
                if (thumbnail) {
                    this.pendingThumbnail = thumbnail
                }
            }
        })
    }
}

// PhotoModal hook (complex interaction, kept in main file)
const PhotoModalHook = {
    mounted() {
        this.currentIndex = 0
        this.total = parseInt(this.el.dataset.total) || 1

        const img = this.el.querySelector('img')
        let startX = 0
        let startY = 0

        const handleLoad = () => {
            img.classList.remove('opacity-0')
            img.classList.add('opacity-100')
        }

        if (img) {
            if (img.complete) {
                handleLoad()
            } else {
                img.addEventListener('load', handleLoad)
            }
        }

        // Touch swipe
        this.el.addEventListener('touchstart', (e) => {
            startX = e.touches[0].clientX
            startY = e.touches[0].clientY
        }, { passive: true })

        this.el.addEventListener('touchend', (e) => {
            const diffX = e.changedTouches[0].clientX - startX
            const diffY = e.changedTouches[0].clientY - startY

            if (Math.abs(diffX) > Math.abs(diffY)) {
                if (diffX > 50) {
                    this.pushEvent("prev_photo", {})
                } else if (diffX < -50) {
                    this.pushEvent("next_photo", {})
                }
            } else if (diffY > 100) {
                this.pushEvent("close_modal", {})
            }
        }, { passive: true })

        // Keyboard navigation
        this.keyHandler = (e) => {
            if (e.key === 'ArrowLeft') this.pushEvent("prev_photo", {})
            else if (e.key === 'ArrowRight') this.pushEvent("next_photo", {})
            else if (e.key === 'Escape') this.pushEvent("close_modal", {})
        }
        document.addEventListener('keydown', this.keyHandler)
    },

    destroyed() {
        if (this.keyHandler) {
            document.removeEventListener('keydown', this.keyHandler)
        }
    }
}

// Combine all hooks
const Hooks = {
    ...getHooks(Components),
    ...ModularHooks,
    FriendsApp: FriendsAppHook,
    PhotoModal: PhotoModalHook
}

// Precompute identity signals
const bootstrapBrowserId = getBrowserId()
const bootstrapFingerprint = generateFingerprint()

// Setup LiveSocket
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
    hooks: Hooks,
    params: {
        _csrf_token: csrfToken,
        browser_id: bootstrapBrowserId,
        fingerprint: bootstrapFingerprint
    },
    reconnectAfterMs: tries => [100, 200, 500, 1000, 2000, 5000][tries - 1] || 5000,
    longPollFallbackMs: 2500
})

// Progress bar
topbar.config({ barColors: { 0: "#fff" }, shadowColor: "rgba(0, 0, 0, .3)" })
let initialLoad = true
window.addEventListener("phx:page-loading-start", info => {
    if (!initialLoad && info.detail.kind === "redirect") {
        topbar.show(200)
    }
})
window.addEventListener("phx:page-loading-stop", () => {
    initialLoad = false
    topbar.hide()
})

// Connect
liveSocket.connect()

// Handle visibility changes
document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && !liveSocket.isConnected()) {
        liveSocket.connect()
    }
})

// Handle global sign_out event
window.addEventListener("phx:sign_out", () => {
    document.cookie = "friends_user_id=; path=/; max-age=0; SameSite=Lax"
    window.location.href = '/'
})

// Handle trigger_file_input event globally
// Handle trigger_file_input event globally
window.addEventListener("phx:trigger_file_input", (e) => {
    const selector = e.detail.selector
    if (selector) {
        const input = document.querySelector(selector)
        if (input) {
            // Add a one-time listener to close the menu after file selection
            const closeMenuHandler = () => {
                if (window.liveSocket) {
                    const hook = document.querySelector('[phx-hook="FriendsApp"]')
                    // Only close if menu is actually open (optional check, but good for robustness)
                    if (hook && hook._liveSocket) {
                        window.liveSocket.execJS(hook, '[["push",{"event":"close_create_menu"}]]')
                    }
                }
            }

            input.addEventListener('change', closeMenuHandler, { once: true })

            // Small timeout to ensure DOM is ready and prevent potential race conditions with double-clicks
            setTimeout(() => input.click(), 0)
        }
    }
})

window.liveSocket = liveSocket
