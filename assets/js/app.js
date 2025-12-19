// Phoenix imports
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import { getHooks } from "live_svelte"
import FriendsMap from "../svelte/FriendsMap.svelte"
import FriendGraph from "../svelte/FriendGraph.svelte"
import GlobalGraph from "../svelte/GlobalGraph.svelte"
import ConstellationGraph from "../svelte/ConstellationGraph.svelte"
import WelcomeGraph from "../svelte/WelcomeGraph.svelte"
import CornerNavigation from "../svelte/CornerNavigation.svelte"
import { mount, unmount } from 'svelte'
import { isWebAuthnSupported, isPlatformAuthenticatorAvailable, registerCredential, authenticateWithCredential } from "./webauthn"
import * as messageEncryption from "./message-encryption"
import { VoiceRecorder, VoicePlayer } from "./voice-recorder"
import QRCode from "qrcode"

const Components = { FriendsMap, FriendGraph, GlobalGraph, ConstellationGraph, WelcomeGraph }

// Generate device fingerprint - hardware characteristics that are consistent across browsers
function generateFingerprint() {
    const components = [
        screen.width,
        screen.height,
        screen.colorDepth,
        new Date().getTimezoneOffset(),
        screen.availWidth,
        screen.availHeight,
        navigator.hardwareConcurrency || 0,
        navigator.maxTouchPoints || 0,
        navigator.language
    ]

    const fingerprint = components.join('|')

    // FNV-1a hash
    let hash = 2166136261
    for (let i = 0; i < fingerprint.length; i++) {
        hash ^= fingerprint.charCodeAt(i)
        hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24)
    }

    return (hash >>> 0).toString(16)
}

// Get or create browser ID (unique per browser)
function getBrowserId() {
    const key = 'friends_browser_id'
    let id = localStorage.getItem(key)

    if (!id) {
        id = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
            const r = Math.random() * 16 | 0
            const v = c === 'x' ? r : (r & 0x3 | 0x8)
            return v.toString(16)
        })
        localStorage.setItem(key, id)
    }

    return id
}

// Generate thumbnail from image file
function generateThumbnail(file, maxSize = 300) {
    return new Promise(resolve => {
        if (!file.type.startsWith('image/') || file.type === 'image/gif') {
            resolve(null)
            return
        }

        const img = new Image()
        const canvas = document.createElement('canvas')
        const ctx = canvas.getContext('2d')

        img.onload = () => {
            let { width, height } = img

            if (width > height) {
                height = Math.round((height * maxSize) / width)
                width = maxSize
            } else {
                width = Math.round((width * maxSize) / height)
                height = maxSize
            }

            canvas.width = width
            canvas.height = height
            ctx.imageSmoothingEnabled = true
            ctx.imageSmoothingQuality = 'high'
            ctx.drawImage(img, 0, 0, width, height)

            const dataUrl = canvas.toDataURL('image/jpeg', 0.7)
            URL.revokeObjectURL(img.src)
            resolve(dataUrl)
        }

        img.onerror = () => resolve(null)
        img.src = URL.createObjectURL(file)
    })
}

// Optimize image before upload
function optimizeImage(file, maxSize = 1200) {
    return new Promise(resolve => {
        if (!file.type.startsWith('image/') || file.type === 'image/gif') {
            resolve(file)
            return
        }

        const img = new Image()
        const canvas = document.createElement('canvas')
        const ctx = canvas.getContext('2d')

        img.onload = () => {
            let { width, height } = img

            if (width > maxSize || height > maxSize) {
                if (width > height) {
                    height = Math.round((height * maxSize) / width)
                    width = maxSize
                } else {
                    width = Math.round((width * maxSize) / height)
                    height = maxSize
                }
            }

            canvas.width = width
            canvas.height = height
            ctx.drawImage(img, 0, 0, width, height)

            canvas.toBlob(blob => {
                if (blob) {
                    const optimized = new File([blob], file.name, {
                        type: 'image/jpeg',
                        lastModified: Date.now()
                    })
                    resolve(optimized)
                } else {
                    resolve(file)
                }
            }, 'image/jpeg', 0.85)
        }

        img.onerror = () => resolve(file)
        img.src = URL.createObjectURL(file)
    })
}

// Shared Audio Context
let sharedAudioCtx = null
function getAudioContext() {
    if (!sharedAudioCtx) {
        const AudioContext = window.AudioContext || window.webkitAudioContext
        sharedAudioCtx = new AudioContext()
    }
    return sharedAudioCtx
}

// Hooks
const Hooks = {
    VoiceWaveform: {
        mounted() {
            this.src = this.el.dataset.src
            this.canvas = this.el
            this.ctx = this.canvas.getContext('2d')
            this.analyze()
        },

        updated() {
            if (this.el.dataset.src !== this.src) {
                this.src = this.el.dataset.src
                this.analyze()
            }
        },

        async analyze() {
            if (!this.src) return

            try {
                const response = await fetch(this.src)
                const arrayBuffer = await response.arrayBuffer()

                const audioCtx = getAudioContext()
                const audioBuffer = await audioCtx.decodeAudioData(arrayBuffer)

                const rawData = audioBuffer.getChannelData(0)
                const samples = 40
                const blockSize = Math.floor(rawData.length / samples)
                const peaks = []

                for (let i = 0; i < samples; i++) {
                    let sum = 0
                    for (let j = 0; j < blockSize; j++) {
                        sum += Math.abs(rawData[i * blockSize + j])
                    }
                    peaks.push(sum / blockSize)
                }

                const max = Math.max(...peaks) || 1
                const normalized = peaks.map(p => p / max)

                this.draw(normalized)
            } catch (e) {
                console.error("Waveform error", e)
            }
        },

        draw(data) {
            const width = this.canvas.width
            const height = this.canvas.height
            const ctx = this.ctx
            const barWidth = width / data.length
            const gap = 2

            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = getComputedStyle(this.canvas).color || '#fdba74'

            data.forEach((val, i) => {
                const barHeight = Math.max(3, val * height * 0.8)
                const x = i * barWidth
                const y = (height - barHeight) / 2

                // Draw rounded bars (manual radius for compatibility)
                this.roundRect(ctx, x, y, barWidth - gap, barHeight, 2)
                ctx.fill()
            })
        },

        roundRect(ctx, x, y, w, h, r) {
            if (w < 2 * r) r = w / 2
            if (h < 2 * r) r = h / 2
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.arcTo(x + w, y, x + w, y + h, r)
            ctx.arcTo(x + w, y + h, x, y + h, r)
            ctx.arcTo(x, y + h, x, y, r)
            ctx.arcTo(x, y, x + w, y, r)
            ctx.closePath()
        }
    },

    ...getHooks(Components),

    WelcomeGraph: {
        mounted() {
            // Check if we should always show (e.g. for empty feed background)
            const alwaysShow = this.el.dataset.alwaysShow === 'true'

            // Check localStorage for permanent opt-out OR sessionStorage for already viewed this session
            // BUT only if not set to always show
            if (!alwaysShow && (localStorage.getItem('hideWelcomeGraph') === 'true' || sessionStorage.getItem('graphViewed') === 'true')) {
                // User opted out or already viewed - trigger skip
                this.pushEvent('skip_welcome_graph', {})
                this.el.style.display = 'none'
                return
            }

            const graphData = JSON.parse(this.el.dataset.graphData || 'null')
            // If user is new, don't show opt-out checkbox
            const isNewUser = this.el.dataset.isNewUser === 'true'
            const hideControls = this.el.dataset.hideControls === 'true'
            const currentUserId = this.el.dataset.currentUserId || null

            // Svelte 5 mount
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

            // Listen for live network updates from server
            this.handleEvent("welcome_new_user", (userData) => {
                console.log('[WelcomeGraph] New user joined:', userData)
                if (this.component && this.component.addNode) {
                    this.component.addNode(userData)
                }
            })

            this.handleEvent("welcome_new_connection", ({ from_id, to_id }) => {
                console.log('[WelcomeGraph] New connection:', from_id, '->', to_id)
                if (this.component && this.component.addLink) {
                    this.component.addLink(from_id, to_id)
                }
            })

            this.handleEvent("welcome_connection_removed", ({ from_id, to_id }) => {
                console.log('[WelcomeGraph] Connection removed:', from_id, '->', to_id)
                if (this.component && this.component.removeLink) {
                    this.component.removeLink(from_id, to_id)
                }
            })

            // Pulse on signal (post)
            this.handleEvent("welcome_signal", ({ user_id }) => {
                if (this.component && this.component.pulseNode) {
                    this.component.pulseNode(user_id)
                }
            })

            this.handleEvent("welcome_user_deleted", ({ user_id }) => {
                console.log('[WelcomeGraph] User deleted:', user_id)
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
    },

    CornerNavigation: {
        mounted() {
            const currentUser = JSON.parse(this.el.dataset.currentUser || 'null')
            const pendingCount = parseInt(this.el.dataset.pendingCount || '0', 10)
            const currentRoute = this.el.dataset.currentRoute || '/'
            const rooms = JSON.parse(this.el.dataset.rooms || '[]')

            this.component = mount(CornerNavigation, {
                target: this.el,
                props: {
                    live: this,
                    currentUser,
                    pendingCount,
                    currentRoute,
                    rooms
                }
            })
        },
        updated() {
            if (!this.component) return;

            const currentUser = JSON.parse(this.el.dataset.currentUser || 'null')
            const pendingCount = parseInt(this.el.dataset.pendingCount || '0', 10)
            const currentRoute = this.el.dataset.currentRoute || '/'
            const rooms = JSON.parse(this.el.dataset.rooms || '[]')

            // Update props directly on the component instance if supported by Svelte 5 mount return
            // For Svelte 5, the return value of mount is the exports object.
            // But we can't easily update props on the instance created by `mount` unless we use state/store or specific framework methods.
            // A common pattern with svelte and liveview hooks is to unmount and remount or use a store signal.
            // However, with Svelte 5, if we want reactivity, we can wrap the props in a Rune or use a wrapper.
            // Let's try simple unmount/remount for now as it's robust, or see if we can set props on the component.
            // Actually, Svelte 5 `mount` interaction is different. 
            // Let's stick to the robust unmount/remount for this "ignore" block pattern if attributes change, 
            // OR simpler: since the container has phx-update="ignore", the `updated` hook MIGHT NOT BE CALLED by LiveView 
            // UNLESS the attributes on the container itself changes.
            // Wait, if phx-update="ignore" is present, LiveView patches the attributes of the container 
            // but ignores the content. So `updated()` IS called.

            unmount(this.component)
            this.component = mount(CornerNavigation, {
                target: this.el,
                props: {
                    live: this,
                    currentUser,
                    pendingCount,
                    currentRoute,
                    rooms
                }
            })
        },
        destroyed() {
            if (this.component) {
                unmount(this.component)
            }
        }
    },

    FriendGraph: {
        mounted() {
            const graphData = JSON.parse(this.el.dataset.graph || 'null')

            // Svelte 5 uses mount() instead of new Component()
            this.component = mount(FriendGraph, {
                target: this.el,
                props: {
                    graphData,
                    live: this
                }
            })

            // Listen for graph updates from the server (since phx-update="ignore")
            this.handleEvent("graph-updated", ({ graph_data }) => {
                console.log('[FriendGraph] Received graph update', graph_data)
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
            // Svelte 5: remount component with new props
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
    },

    GlobalGraph: {
        mounted() {
            const graphData = JSON.parse(this.el.dataset.graph || 'null')
            const currentUserId = this.el.dataset.currentUserId || null

            this.component = mount(GlobalGraph, {
                target: this.el,
                props: {
                    graphData,
                    currentUserId,
                    live: this
                }
            })
        },
        updated() {
            if (this.component) {
                unmount(this.component)
            }
            const graphData = JSON.parse(this.el.dataset.graph || 'null')
            const currentUserId = this.el.dataset.currentUserId || null
            this.component = mount(GlobalGraph, {
                target: this.el,
                props: {
                    graphData,
                    currentUserId,
                    live: this
                }
            })
        },
        destroyed() {
            if (this.component) {
                unmount(this.component)
            }
        }
    },



    ConstellationGraph: {
        mounted() {
            // Check localStorage for opt-out preference
            if (localStorage.getItem('constellation_opt_out') === 'true') {
                // User opted out - trigger skip and hide constellation
                this.pushEvent('skip_constellation', {})
                this.el.style.display = 'none'
                // Also hide the skip button container
                const skipContainer = document.querySelector('[class*="fixed bottom-24"]')
                if (skipContainer) skipContainer.style.display = 'none'
                return
            }

            const constellationData = JSON.parse(this.el.dataset.constellation || 'null')

            this.component = mount(ConstellationGraph, {
                target: this.el,
                props: {
                    data: constellationData,
                    live: this
                }
            })

            // Handle server event to fade out invited user
            this.handleEvent("constellation_user_invited", ({ user_id }) => {
                const svg = this.el.querySelector('svg')
                if (svg) {
                    const userGroup = svg.querySelector(`.orbiting-user-${user_id}`)
                    if (userGroup) {
                        // Animate smooth fade out
                        userGroup.style.transition = 'opacity 1s ease-out'
                        userGroup.style.opacity = '0'
                        // Remove after animation
                        setTimeout(() => userGroup.remove(), 1000)
                    }
                }
            })

            // Handle server event for new user joining
            this.handleEvent("constellation_new_user", (user) => {
                // Dispatch custom event on window for reliable cross-component communication
                window.dispatchEvent(new CustomEvent('constellation:addNewUser', { detail: user }))
            })
        },
        updated() {
            // Don't rebuild on updates - we handle changes via push_event
        },
        destroyed() {
            try {
                if (this.component) {
                    unmount(this.component)
                }
            } catch (e) {
                console.error("ConstellationGraph unmount error:", e)
            }
            // Robust cleanup: ensure container is empty
            this.el.innerHTML = ''

            // If the svelte component mounted to body or portal, we might need more aggressive cleanup
            // ensuring this element is hidden immediately
            this.el.style.display = 'none'
        }
    },

    HomeOrb: {
        mounted() {
            this.timer = null
            this.held = false
            this.hovered = false

            const startPress = (e) => {
                // Only left click or touch
                if (e.type === 'mousedown' && e.button !== 0) return

                this.held = false
                this.timer = setTimeout(() => {
                    this.held = true
                    // Provide haptic feedback if available
                    if (navigator.vibrate) navigator.vibrate(10)
                    this.pushEvent("show_breadcrumbs", {})
                }, 500)
            }

            const endPress = (e) => {
                if (this.timer) {
                    clearTimeout(this.timer)
                    this.timer = null
                }

                // If we held it, prevent the click navigation
                if (this.held) {
                    e.preventDefault()
                    e.stopPropagation()
                }
            }

            // Hover behavior for desktop - show breadcrumbs on hover
            const handleMouseEnter = () => {
                if (!this.hovered) {
                    this.hovered = true
                    this.pushEvent("show_breadcrumbs", {})
                }
            }

            const handleMouseLeave = () => {
                if (this.hovered) {
                    this.hovered = false
                    // Hide breadcrumbs after a short delay (allows moving to breadcrumbs)
                    setTimeout(() => {
                        if (!this.hovered) {
                            this.pushEvent("show_breadcrumbs", {})  // Toggle off
                        }
                    }, 300)
                }
            }

            // Long-press events (mobile)
            this.el.addEventListener('mousedown', startPress)
            this.el.addEventListener('touchstart', startPress, { passive: false })
            this.el.addEventListener('mouseup', endPress)
            this.el.addEventListener('mouseleave', endPress)
            this.el.addEventListener('touchend', endPress)
            this.el.addEventListener('touchcancel', endPress)

            // Hover events (desktop)
            this.el.addEventListener('mouseenter', handleMouseEnter)
            this.el.addEventListener('mouseleave', handleMouseLeave)
        }
    },

    // Long-press nav orb for 3s to reveal fullscreen graph (hidden feature)
    NavOrbLongPress: {
        mounted() {
            this.timer = null
            this.held = false

            const startPress = (e) => {
                if (e.type === 'mousedown' && e.button !== 0) return
                e.preventDefault()

                this.held = false
                this.timer = setTimeout(() => {
                    this.held = true
                    // Haptic feedback
                    if (navigator.vibrate) navigator.vibrate([50, 50, 50])
                    // Show fullscreen graph
                    this.pushEvent("show_fullscreen_graph", {})
                }, 3000) // 3 seconds
            }

            const endPress = (e) => {
                if (this.timer) {
                    clearTimeout(this.timer)
                    this.timer = null
                }

                if (this.held) {
                    e.preventDefault()
                    e.stopPropagation()
                    this.held = false
                }
            }

            this.el.addEventListener('mousedown', startPress)
            this.el.addEventListener('touchstart', startPress, { passive: false })
            this.el.addEventListener('mouseup', endPress)
            this.el.addEventListener('mouseleave', endPress)
            this.el.addEventListener('touchend', endPress)
            this.el.addEventListener('touchcancel', endPress)
        },
        destroyed() {
            if (this.timer) clearTimeout(this.timer)
        }
    },

    // Progressive sign out - hold for 3s with visual ring progress
    ProgressiveSignOut: {
        mounted() {
            this.timer = null
            this.morphTimer = null
            this.pressing = false
            this.duration = 3000 // 3 seconds
            
            // Prevent text selection on mobile
            this.el.style.userSelect = 'none'
            this.el.style.webkitUserSelect = 'none'
            this.el.style.touchAction = 'manipulation'
            
            // Create progress ring overlay
            this.createProgressRing()
            
            // Store original icon
            this.originalIcon = this.el.querySelector('svg')?.outerHTML
            this.iconContainer = this.el.querySelector('div.w-7')
            
            const startPress = (e) => {
                if (e.type === 'mousedown' && e.button !== 0) return
                e.preventDefault()
                
                this.pressing = true
                
                // Show and animate ring after 500ms
                setTimeout(() => {
                    if (!this.pressing) return
                    this.progressSvg.style.opacity = '1'
                    this.progressRing.style.strokeDashoffset = '0'
                    
                    // Haptic start
                    if (navigator.vibrate) navigator.vibrate(10)
                }, 500)
                
                // Morph icon at 1.5s
                this.morphTimer = setTimeout(() => {
                    if (!this.pressing) return
                    if (this.iconContainer) {
                        this.iconContainer.innerHTML = `
                            <svg class="w-4 h-4 animate-pulse" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
                            </svg>
                        `
                    }
                    // Stronger haptic
                    if (navigator.vibrate) navigator.vibrate([30, 30, 30])
                }, 1500)
                
                // Fire sign out at 3s
                this.timer = setTimeout(() => {
                    if (this.pressing) {
                        // Success haptic
                        if (navigator.vibrate) navigator.vibrate([50, 50, 100])
                        this.pushEvent("sign_out", {})
                        this.pressing = false
                        this.resetVisuals()
                    }
                }, this.duration)
            }
            
            const endPress = (e) => {
                if (!this.pressing) return
                
                this.pressing = false
                
                if (this.timer) {
                    clearTimeout(this.timer)
                    this.timer = null
                }
                if (this.morphTimer) {
                    clearTimeout(this.morphTimer)
                    this.morphTimer = null
                }
                
                this.resetVisuals()
            }
            
            this.el.addEventListener('mousedown', startPress)
            this.el.addEventListener('touchstart', startPress, { passive: false })
            this.el.addEventListener('mouseup', endPress)
            this.el.addEventListener('mouseleave', endPress)
            this.el.addEventListener('touchend', endPress)
            this.el.addEventListener('touchcancel', endPress)
            
            // Prevent click from firing regular event
            this.el.addEventListener('click', (e) => {
                e.preventDefault()
                e.stopPropagation()
            })
        },
        
        createProgressRing() {
            const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
            svg.setAttribute('class', 'progressive-sign-out-ring')
            svg.setAttribute('viewBox', '0 0 50 50')
            svg.style.cssText = 'position: absolute; inset: -4px; width: calc(100% + 8px); height: calc(100% + 8px); pointer-events: none; opacity: 0; transition: opacity 0.3s; z-index: 10;'

            const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle')
            circle.setAttribute('cx', '25')
            circle.setAttribute('cy', '25')
            circle.setAttribute('r', '22')
            circle.setAttribute('fill', 'none')
            circle.setAttribute('stroke', 'rgba(239, 68, 68, 0.8)') // red-500
            circle.setAttribute('stroke-width', '3')
            circle.setAttribute('stroke-linecap', 'round')
            circle.setAttribute('stroke-dasharray', '138.23') // 2*PI*22
            circle.setAttribute('stroke-dashoffset', '138.23')
            circle.setAttribute('transform', 'rotate(-90 25 25)')
            circle.style.transition = `stroke-dashoffset ${this.duration - 500}ms linear` // -500ms for delay

            svg.appendChild(circle)
            this.el.style.position = 'relative'
            this.el.appendChild(svg)
            this.progressRing = circle
            this.progressSvg = svg
        },
        
        resetVisuals() {
            // Reset ring
            this.progressSvg.style.opacity = '0'
            this.progressRing.style.transition = 'none'
            this.progressRing.style.strokeDashoffset = '138.23'
            // Force reflow
            this.progressRing.offsetHeight
            this.progressRing.style.transition = `stroke-dashoffset ${this.duration - 500}ms linear`
            
            // Reset icon
            if (this.iconContainer && this.originalIcon) {
                this.iconContainer.innerHTML = this.originalIcon
            }
        },
        
        destroyed() {
            if (this.timer) clearTimeout(this.timer)
            if (this.morphTimer) clearTimeout(this.morphTimer)
        }
    },


    // Unified WebAuthn hook for /auth page (handles both login and registration)
    WebAuthnAuth: {
        mounted() {
            // Check WebAuthn availability on mount
            const webauthnAvailable = isWebAuthnSupported()
            console.log('[WebAuthnAuth] WebAuthn available:', webauthnAvailable)
            this.pushEvent("webauthn_available", { available: webauthnAvailable })

            // Handle WebAuthn challenge (works for both login and register)
            this.handleEvent("webauthn_auth_challenge", async ({ mode, options }) => {
                try {
                    console.log(`[WebAuthnAuth] ${mode} challenge received`)

                    if (mode === "login") {
                        // Authentication flow
                        const credential = await authenticateWithCredential(options)
                        console.log('[WebAuthnAuth] Login credential obtained')
                        this.pushEvent("webauthn_login_response", { credential })
                    } else {
                        // Registration flow
                        const credential = await registerCredential(options)
                        console.log('[WebAuthnAuth] Register credential created')
                        this.pushEvent("webauthn_register_response", { credential })
                    }
                } catch (error) {
                    console.error('[WebAuthnAuth] Error:', error)
                    this.pushEvent("webauthn_error", {
                        error: error.name === 'NotAllowedError'
                            ? (mode === 'login' ? 'Authentication cancelled' : 'Registration cancelled')
                            : error.message || 'Unknown error'
                    })
                }
            })

            // Handle auth success - set cookie and redirect
            this.handleEvent("auth_success", ({ user_id }) => {
                console.log('[WebAuthnAuth] Success for user:', user_id)
                document.cookie = `friends_user_id=${user_id}; path=/; max-age=${60 * 60 * 24 * 365}; SameSite=Lax`
                window.location.href = '/'
            })
        }
    },

    // Feed voice recording for public feed
    FeedVoiceRecorder: {
        mounted() {
            this.recorder = null
            this.isRecording = false

            this.handleEvent("start_js_recording", async () => {
                if (this.isRecording) return

                try {
                    this.recorder = new VoiceRecorder()

                    this.recorder.onStop = async (audioBlob, durationMs) => {
                        try {
                            const arrayBuffer = await audioBlob.arrayBuffer()
                            const bytes = new Uint8Array(arrayBuffer)
                            let binary = ''
                            for (let i = 0; i < bytes.length; i++) {
                                binary += String.fromCharCode(bytes[i])
                            }
                            const base64 = btoa(binary)

                            this.pushEvent("post_public_voice", {
                                audio_data: base64,
                                duration_ms: durationMs
                            })
                        } catch (err) {
                            console.error("Failed to process audio:", err)
                        }
                    }

                    const started = await this.recorder.start()
                    if (started) {
                        this.isRecording = true
                        // No need to push start_voice_recording as server triggered this
                    }
                } catch (err) {
                    console.error("Failed to start recording:", err)
                    this.pushEvent("cancel_voice_recording", {})
                }
            })

            this.el.addEventListener('click', async () => {
                if (this.isRecording) {
                    // Stop recording - the onStop callback handles the result
                    if (this.recorder) {
                        this.recorder.stop()
                    }
                    this.isRecording = false
                }
                // Click only handles STOP because button is hidden when not recording
            })
        },
        destroyed() {
            if (this.recorder && this.isRecording) {
                this.recorder.stop()
            }
        }
    },

    FriendsApp: {
        async mounted() {
            this.browserId = bootstrapBrowserId
            this.fingerprint = bootstrapFingerprint

            // Simple identity payload - just device info, no crypto keys
            // Authentication is handled via WebAuthn on the login page
            this.identityPayload = {
                browser_id: this.browserId,
                fingerprint: this.fingerprint
            }

            // Send device identity for presence tracking
            this.maybeSendIdentity()

            // Server can request identity when it knows the socket is ready
            this.handleEvent("request_identity", () => this.maybeSendIdentity())

            // Handle user cookie set (for instant username display on reload)
            this.handleEvent("set_user_cookie", ({ user_id }) => {
                if (user_id) {
                    document.cookie = `friends_user_id=${user_id}; path=/; max-age=${60 * 60 * 24 * 365}; SameSite=Lax`
                }
            })

            // Handle session token for authenticated requests
            this.handleEvent("set_session_token", ({ token }) => {
                if (token) {
                    // 30-day session token cookie
                    document.cookie = `friends_session_token=${token}; path=/; max-age=${60 * 60 * 24 * 30}; SameSite=Lax`
                }
            })

            // Handle constellation opt-out - save to localStorage when skip is clicked
            const skipBtn = document.getElementById('skip-constellation-btn')
            if (skipBtn) {
                skipBtn.addEventListener('click', () => {
                    const optOutCheckbox = document.getElementById('constellation-opt-out')
                    if (optOutCheckbox && optOutCheckbox.checked) {
                        localStorage.setItem('constellation_opt_out', 'true')
                    }
                })
            }

            // Handle sign out
            this.handleEvent("sign_out", async () => {
                // Clear browser ID
                localStorage.removeItem('friends_browser_id')

                // Clear cookies
                document.cookie = 'friends_user_id=; path=/; max-age=0'
                document.cookie = 'friends_session_token=; path=/; max-age=0'

                // Refresh page to show logged out state
                window.location.href = '/'
            })

            // Handle photo_uploaded event - send pending thumbnail
            this.handleEvent("photo_uploaded", ({ photo_id }) => {
                if (this.pendingThumbnail && photo_id) {
                    this.pushEvent("set_thumbnail", {
                        photo_id: photo_id,
                        thumbnail: this.pendingThumbnail
                    })
                    this.pendingThumbnail = null
                }
            })

            // Handle server-triggered file input click
            this.handleEvent("trigger_file_input", ({ selector }) => {
                const input = document.querySelector(selector)
                if (input) {
                    input.click()
                } else {
                    console.error("File input not found:", selector)
                }
            })

            // Setup image optimization (may need to retry after DOM updates)
            this.pendingThumbnail = null
            this.setupImageOptimization()
        },
        updated() {
            // Re-setup image optimization when DOM updates (e.g., after user auth)
            this.setupImageOptimization()
        },
        reconnected() {
            // On LiveView reconnect, re-send identity so header shows the user immediately
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
                } else {
                    console.error("Failed to send user identity after retries:", error)
                }
            }
        },

        setupImageOptimization() {
            // Find any file input for photo uploads (feed or room)
            const fileInput = this.el.querySelector('input[type="file"][name*="photo"]') ||
                this.el.querySelector('input[type="file"]')

            if (!fileInput) return

            // Avoid setting up duplicate listeners
            if (fileInput.dataset.optimized) return
            fileInput.dataset.optimized = 'true'

            fileInput.addEventListener('change', async (e) => {
                const files = e.target.files
                if (!files || files.length === 0) return

                const file = files[0]

                if (file.type.startsWith('image/') && file.type !== 'image/gif') {
                    const [thumbnail, optimized] = await Promise.all([
                        generateThumbnail(file, 600),
                        optimizeImage(file, 1200)
                    ])

                    this.pendingThumbnail = thumbnail

                    if (optimized.size < file.size) {
                        const dt = new DataTransfer()
                        dt.items.add(optimized)
                        fileInput.files = dt.files
                    }
                }
            })
        }
    },

    PhotoGrid: {
        mounted() {
            // Initial check
            this.observeImages()

            // Polling backup for Streams/Dynamic content
            // This is safer than MutationObserver for preventing crashes
            this.interval = setInterval(() => {
                this.observeImages()
            }, 500)
        },
        updated() {
            this.observeImages()
        },
        destroyed() {
            if (this.interval) {
                clearInterval(this.interval)
            }
        },
        observeImages() {
            try {
                if (!this.el) return
                const images = this.el.querySelectorAll('img:not(.observed)')
                images.forEach(img => {
                    img.classList.add('observed')
                    if (img.complete) {
                        img.classList.add('loaded')
                    } else {
                        img.addEventListener('load', () => img.classList.add('loaded'), { once: true })
                    }
                })
            } catch (e) {
                console.error("PhotoGrid error:", e)
            }
        }
    },

    // Swipeable drawer for mobile - enables drag-down-to-close
    SwipeableDrawer: {
        mounted() {
            this.startY = 0
            this.currentY = 0
            this.isDragging = false
            this.closeEvent = this.el.dataset.closeEvent || "toggle_mobile_chat"

            // Touch start
            this.el.addEventListener('touchstart', (e) => {
                // Only track if touching the handle area (top 60px)
                const touch = e.touches[0]
                const rect = this.el.getBoundingClientRect()
                if (touch.clientY - rect.top < 60) {
                    this.startY = touch.clientY
                    this.isDragging = true
                    this.el.style.transition = 'none'
                }
            }, { passive: true })

            // Touch move
            this.el.addEventListener('touchmove', (e) => {
                if (!this.isDragging) return

                this.currentY = e.touches[0].clientY
                const deltaY = this.currentY - this.startY

                // Only allow dragging down
                if (deltaY > 0) {
                    this.el.style.transform = `translateY(${deltaY}px)`
                }
            }, { passive: true })

            // Touch end
            this.el.addEventListener('touchend', () => {
                if (!this.isDragging) return

                this.isDragging = false
                this.el.style.transition = 'transform 0.3s ease-out'

                const deltaY = this.currentY - this.startY

                // If dragged more than 100px down, close the drawer
                if (deltaY > 100) {
                    this.el.style.transform = 'translateY(100%)'
                    setTimeout(() => {
                        this.pushEvent(this.closeEvent, {})
                        // Do not reset transform here, let LiveView remove the element
                    }, 300)
                } else {
                    // Snap back
                    this.el.style.transform = 'translateY(0)'
                }

                this.startY = 0
                this.currentY = 0
            }, { passive: true })
        }
    },

    RegisterApp: {
        async mounted() {
            // Check WebAuthn availability
            const webauthnAvailable = isWebAuthnSupported()
            console.log('[RegisterApp] WebAuthn available:', webauthnAvailable)
            this.pushEvent("webauthn_available", { available: webauthnAvailable })

            // Handle WebAuthn registration challenge
            this.handleEvent("webauthn_register_challenge", async ({ options }) => {
                try {
                    console.log('[RegisterApp] WebAuthn challenge received, creating credential...')
                    const credential = await registerCredential(options)
                    console.log('[RegisterApp] WebAuthn credential created, sending to server...')
                    this.pushEvent("webauthn_register_response", { credential })
                } catch (error) {
                    console.error('[RegisterApp] WebAuthn registration failed:', error)
                    this.pushEvent("webauthn_register_error", {
                        error: error.name === 'NotAllowedError'
                            ? 'Registration cancelled'
                            : error.message || 'Unknown error'
                    })
                }
            })

            // Handle registration success
            this.handleEvent("registration_complete", ({ user }) => {
                console.log("Registration complete:", user)
                // Set cookie for fast initial render on next page load
                if (user && user.id) {
                    document.cookie = `friends_user_id=${user.id}; path=/; max-age=${60 * 60 * 24 * 365}; SameSite=Lax`
                }
            })
        }
    },

    RecoverApp: {
        async mounted() {
            // Check WebAuthn availability
            const webauthnAvailable = isWebAuthnSupported()
            this.pushEvent("webauthn_available", { available: webauthnAvailable })

            // Handle WebAuthn registration challenge for recovery
            this.handleEvent("webauthn_recovery_challenge", async ({ options }) => {
                try {
                    console.log('[RecoverApp] WebAuthn challenge received, creating credential...')
                    const credential = await registerCredential(options)
                    console.log('[RecoverApp] WebAuthn credential created, sending to server...')
                    this.pushEvent("webauthn_recovery_response", { credential })
                } catch (error) {
                    console.error('[RecoverApp] WebAuthn registration failed:', error)
                    this.pushEvent("webauthn_recovery_error", {
                        error: error.name === 'NotAllowedError'
                            ? 'Registration cancelled'
                            : error.message || 'Unknown error'
                    })
                }
            })

            // Handle recovery success
            this.handleEvent("recovery_complete", ({ user }) => {
                console.log("Recovery complete:", user)
                if (user && user.id) {
                    document.cookie = `friends_user_id=${user.id}; path=/; max-age=${60 * 60 * 24 * 365}; SameSite=Lax`
                }
            })
        }
    },

    QRDisplay: {
        mounted() {
            this.updateQR()
        },
        updated() {
            this.updateQR()
        },
        updateQR() {
            const qrData = this.el.dataset.qr
            if (qrData && qrData.startsWith('data:')) {
                const img = document.createElement('img')
                img.src = qrData
                img.alt = 'QR Code'
                img.className = 'w-48 h-48 loaded'
                this.el.innerHTML = ''
                this.el.appendChild(img)
            }
        }
    },

    LinkDeviceApp: {
        async mounted() {
            // Check WebAuthn availability
            const webauthnAvailable = isWebAuthnSupported()
            this.pushEvent("webauthn_available", { available: webauthnAvailable })

            // Handle WebAuthn registration challenge for linking a new device
            this.handleEvent("webauthn_link_challenge", async ({ options }) => {
                try {
                    console.log('[LinkDeviceApp] WebAuthn challenge received, creating credential...')
                    const credential = await registerCredential(options)
                    console.log('[LinkDeviceApp] WebAuthn credential created, sending to server...')
                    this.pushEvent("webauthn_link_response", { credential })
                } catch (error) {
                    console.error('[LinkDeviceApp] WebAuthn registration failed:', error)
                    this.pushEvent("webauthn_link_error", {
                        error: error.name === 'NotAllowedError'
                            ? 'Registration cancelled'
                            : error.message || 'Unknown error'
                    })
                }
            })

            // Handle successful device linking
            this.handleEvent("link_complete", ({ user }) => {
                console.log("Device linked:", user)
                if (user && user.id) {
                    document.cookie = `friends_user_id=${user.id}; path=/; max-age=${60 * 60 * 24 * 365}; SameSite=Lax`
                }
            })
        }
    },

    // Locks body scroll while a modal overlay is mounted
    LockScroll: {
        mounted() {
            this._original = document.body.style.overflow
            document.body.style.overflow = 'hidden'
        },
        destroyed() {
            document.body.style.overflow = this._original || ''
        }
    },

    // Long-press handler for orb navigation (hidden power-user feature)
    LongPressOrb: {
        mounted() {
            this.pressTimer = null
            this.pressing = false
            this.duration = parseInt(this.el.dataset.longPressDuration) || 3000
            this.event = this.el.dataset.longPressEvent

            // Create visual feedback element (progress ring)
            this.createProgressRing()

            // Mouse events
            this.el.addEventListener('mousedown', (e) => this.startPress(e))
            this.el.addEventListener('mouseup', () => this.endPress())
            this.el.addEventListener('mouseleave', () => this.endPress())

            // Touch events
            this.el.addEventListener('touchstart', (e) => this.startPress(e), { passive: false })
            this.el.addEventListener('touchend', () => this.endPress())
            this.el.addEventListener('touchcancel', () => this.endPress())
        },

        createProgressRing() {
            // Add SVG progress ring that fills during long press
            const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
            svg.setAttribute('class', 'long-press-ring')
            svg.setAttribute('viewBox', '0 0 50 50')
            svg.style.cssText = 'position: absolute; inset: -4px; width: calc(100% + 8px); height: calc(100% + 8px); pointer-events: none; opacity: 0; transition: opacity 0.2s;'

            const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle')
            circle.setAttribute('cx', '25')
            circle.setAttribute('cy', '25')
            circle.setAttribute('r', '22')
            circle.setAttribute('fill', 'none')
            circle.setAttribute('stroke', 'rgba(255,255,255,0.5)')
            circle.setAttribute('stroke-width', '2')
            circle.setAttribute('stroke-dasharray', '138.23') // 2*PI*22
            circle.setAttribute('stroke-dashoffset', '138.23')
            circle.setAttribute('transform', 'rotate(-90 25 25)')
            circle.style.transition = `stroke-dashoffset ${this.duration}ms linear`

            svg.appendChild(circle)
            this.el.style.position = 'relative'
            this.el.appendChild(svg)
            this.progressRing = circle
            this.progressSvg = svg
        },

        startPress(e) {
            this.pressing = true

            // Show progress ring
            this.progressSvg.style.opacity = '1'
            this.progressRing.style.strokeDashoffset = '0'

            // Set timer for long press
            this.pressTimer = setTimeout(() => {
                if (this.pressing && this.event) {
                    this.pushEvent(this.event, {})
                    this.endPress()
                }
            }, this.duration)
        },

        endPress() {
            this.pressing = false
            if (this.pressTimer) {
                clearTimeout(this.pressTimer)
                this.pressTimer = null
            }

            // Reset progress ring
            if (this.progressSvg) {
                this.progressSvg.style.opacity = '0'
                // Reset without transition
                this.progressRing.style.transition = 'none'
                this.progressRing.style.strokeDashoffset = '138.23'
                // Re-enable transition after a frame
                setTimeout(() => {
                    this.progressRing.style.transition = `stroke-dashoffset ${this.duration}ms linear`
                }, 10)
            }
        },

        destroyed() {
            if (this.pressTimer) {
                clearTimeout(this.pressTimer)
            }
        }
    },

    // Message encryption and sending hook
    MessageEncryption: {
        mounted() {
            this.conversationId = parseInt(this.el.dataset.conversationId)

            // Handle send button click
            const sendBtn = this.el.querySelector('#send-message-btn')
            const input = this.el.querySelector('#message-input')

            if (sendBtn && input) {
                sendBtn.addEventListener('click', async () => {
                    const message = input.value.trim()
                    if (!message) return

                    try {
                        const { encryptedContent, nonce } = await messageEncryption.encryptMessage(message, this.conversationId)
                        this.pushEvent("send_message", {
                            encrypted_content: messageEncryption.arrayToBase64(encryptedContent),
                            nonce: messageEncryption.arrayToBase64(nonce)
                        })
                        input.value = ''
                    } catch (e) {
                        console.error("Failed to encrypt message:", e)
                    }
                })

                // Enter key to send
                input.addEventListener('keydown', async (e) => {
                    if (e.key === 'Enter' && !e.shiftKey) {
                        e.preventDefault()
                        sendBtn.click()
                    }
                })
            }

            // Handle start/stop voice recording events
            this.handleEvent("start_voice_recording", async () => {
                this.voiceRecorder = new VoiceRecorder()
                this.voiceRecorder.onStop = async (blob, durationMs) => {
                    try {
                        const { encryptedContent, nonce } = await messageEncryption.encryptVoiceNote(blob, this.conversationId)
                        this.pushEvent("send_voice_note", {
                            encrypted_content: messageEncryption.arrayToBase64(encryptedContent),
                            nonce: messageEncryption.arrayToBase64(nonce),
                            duration_ms: durationMs
                        })
                    } catch (e) {
                        console.error("Failed to encrypt voice note:", e)
                    }
                }
                await this.voiceRecorder.start()
            })

            this.handleEvent("stop_voice_recording", () => {
                if (this.voiceRecorder) {
                    this.voiceRecorder.stop()
                }
            })

            // Handle scroll to bottom event
            this.handleEvent("scroll_to_bottom", () => {
                const container = document.getElementById('messages-container')
                if (container) {
                    container.scrollTop = container.scrollHeight
                }
            })

            // Decrypt existing messages on mount
            this.decryptVisibleMessages()
        },

        updated() {
            this.decryptVisibleMessages()
        },

        decryptVisibleMessages() {
            const messages = this.el.querySelectorAll('.decrypted-content')
            messages.forEach(async (el) => {
                if (el.dataset.decrypted) return

                const encrypted = el.dataset.encrypted
                const nonce = el.dataset.nonce

                if (encrypted && nonce) {
                    try {
                        const encryptedData = messageEncryption.base64ToArray(encrypted)
                        const nonceData = messageEncryption.base64ToArray(nonce)
                        const decrypted = await messageEncryption.decryptMessage(encryptedData, nonceData, this.conversationId)
                        el.textContent = decrypted
                        el.dataset.decrypted = 'true'
                    } catch (e) {
                        console.error("Failed to decrypt message:", e)
                        el.textContent = "[Unable to decrypt]"
                    }
                }
            })
        }
    },

    // Messages container scroll hook - also handles decryption
    MessagesScroll: {
        mounted() {
            // Get conversation ID from the parent input area
            const inputArea = document.getElementById('message-input-area')
            this.conversationId = inputArea ? parseInt(inputArea.dataset.conversationId) : null

            // Scroll to bottom on mount
            this.el.scrollTop = this.el.scrollHeight

            // Decrypt visible messages
            this.decryptVisibleMessages()
        },
        updated() {
            // Auto-scroll when new messages arrive (if already at bottom)
            const isAtBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 100
            if (isAtBottom) {
                this.el.scrollTop = this.el.scrollHeight
            }

            // Decrypt any new messages
            this.decryptVisibleMessages()
        },

        async decryptVisibleMessages() {
            if (!this.conversationId) {
                console.warn("No conversation ID for decryption")
                return
            }

            const messages = this.el.querySelectorAll('.decrypted-content')
            for (const el of messages) {
                if (el.dataset.decrypted === 'true') continue

                const encrypted = el.dataset.encrypted
                const nonce = el.dataset.nonce

                if (encrypted && nonce) {
                    try {
                        const encryptedData = messageEncryption.base64ToArray(encrypted)
                        const nonceData = messageEncryption.base64ToArray(nonce)
                        const decrypted = await messageEncryption.decryptMessage(encryptedData, nonceData, this.conversationId)
                        el.textContent = decrypted
                        el.dataset.decrypted = 'true'
                    } catch (e) {
                        console.error("Failed to decrypt message:", e)
                        el.textContent = "[Unable to decrypt]"
                        el.dataset.decrypted = 'true'  // Mark as processed to avoid retry loop
                    }
                }
            }
        }
    },

    // Voice message player hook
    VoicePlayer: {
        mounted() {
            this.messageId = this.el.dataset.messageId
            const playBtn = this.el.querySelector('.voice-play-btn')
            const progressBar = this.el.querySelector('.voice-progress')

            // Get conversation ID from parent
            const inputArea = document.getElementById('message-input-area')
            this.conversationId = inputArea ? parseInt(inputArea.dataset.conversationId) : null

            // Get encrypted data from the message element in DOM
            // We need to find the message data - it's passed as data attributes on the parent
            const messageContainer = this.el.closest('[data-encrypted]') || this.el
            this.encryptedData = messageContainer.dataset.encrypted
            this.nonceData = messageContainer.dataset.nonce

            this.audio = null
            this.isPlaying = false

            if (playBtn) {
                playBtn.addEventListener('click', async () => {
                    if (this.isPlaying && this.audio) {
                        this.audio.pause()
                        playBtn.textContent = '▶'
                        this.isPlaying = false
                    } else if (this.audio) {
                        this.audio.play()
                        playBtn.textContent = '⏸'
                        this.isPlaying = true
                    } else {
                        // First play - need to decrypt and create player
                        playBtn.textContent = '...'

                        try {
                            // Find the voice message element and get its encrypted content
                            // The server sends the binary data that we need to fetch
                            const msgEl = document.getElementById(`msg-${this.messageId}`)
                            const encrypted = msgEl?.dataset.encrypted
                            const nonce = msgEl?.dataset.nonce

                            if (encrypted && nonce && this.conversationId) {
                                const encryptedArray = messageEncryption.base64ToArray(encrypted)
                                const nonceArray = messageEncryption.base64ToArray(nonce)

                                const audioBlob = await messageEncryption.decryptVoiceNote(
                                    encryptedArray,
                                    nonceArray,
                                    this.conversationId
                                )

                                if (audioBlob) {
                                    this.audio = new Audio(URL.createObjectURL(audioBlob))

                                    this.audio.ontimeupdate = () => {
                                        if (progressBar && this.audio.duration) {
                                            const percent = (this.audio.currentTime / this.audio.duration) * 100
                                            progressBar.style.width = `${percent}%`
                                        }
                                    }

                                    this.audio.onended = () => {
                                        playBtn.textContent = '▶'
                                        this.isPlaying = false
                                        if (progressBar) progressBar.style.width = '0%'
                                    }

                                    this.audio.play()
                                    playBtn.textContent = '⏸'
                                    this.isPlaying = true
                                } else {
                                    playBtn.textContent = '❌'
                                }
                            } else {
                                console.warn("Missing encrypted data for voice message")
                                playBtn.textContent = '❌'
                            }
                        } catch (e) {
                            console.error("Failed to decrypt voice note:", e)
                            playBtn.textContent = '❌'
                        }
                    }
                })
            }
        },
        destroyed() {
            if (this.audio) {
                this.audio.pause()
                URL.revokeObjectURL(this.audio.src)
            }
        }
    },

    // Room chat scroll and decryption hook
    RoomChatScroll: {
        mounted() {
            this.roomId = this.el.dataset.roomId

            // Scroll to bottom on mount
            this.el.scrollTop = this.el.scrollHeight

            // Decrypt visible messages
            this.decryptVisibleMessages()
        },
        updated() {
            // Auto-scroll when new messages arrive
            const isAtBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 100
            if (isAtBottom) {
                this.el.scrollTop = this.el.scrollHeight
            }

            // Decrypt any new messages
            this.decryptVisibleMessages()
        },

        async decryptVisibleMessages() {
            if (!this.roomId) return

            const messages = this.el.querySelectorAll('.room-decrypted-content')
            for (const el of messages) {
                if (el.dataset.decrypted === 'true') continue

                const encrypted = el.dataset.encrypted
                const nonce = el.dataset.nonce

                if (encrypted && nonce) {
                    try {
                        const encryptedData = messageEncryption.base64ToArray(encrypted)
                        const nonceData = messageEncryption.base64ToArray(nonce)
                        // Use room ID as the conversation ID for key derivation
                        const decrypted = await messageEncryption.decryptMessage(encryptedData, nonceData, `room-${this.roomId}`)
                        el.textContent = decrypted
                        el.dataset.decrypted = 'true'
                    } catch (e) {
                        console.error("Failed to decrypt room message:", e)
                        el.textContent = "[Unable to decrypt]"
                        el.dataset.decrypted = 'true'
                    }
                }
            }
        }
    },

    // Room chat encryption hook for sending messages
    RoomChatEncryption: {
        mounted() {
            this.roomId = this.el.dataset.roomId
            this.voiceRecorder = null

            // Find by ID for fluid layout compatibility
            const sendBtn = this.el.querySelector('#send-unified-message-btn') || this.el.querySelector('button')
            const input = this.el.querySelector('#unified-message-input') || this.el.querySelector('input[type="text"]')

            if (sendBtn && input) {
                sendBtn.addEventListener('click', async () => {
                    const message = input.value.trim()
                    if (!message) return

                    try {
                        // Use room ID as the conversation ID for encryption
                        const { encryptedContent, nonce } = await messageEncryption.encryptMessage(message, `room-${this.roomId}`)
                        this.pushEvent("send_room_message", {
                            encrypted_content: messageEncryption.arrayToBase64(encryptedContent),
                            nonce: messageEncryption.arrayToBase64(nonce)
                        })
                        input.value = ''
                    } catch (e) {
                        console.error("Failed to encrypt room message:", e)
                    }
                })

                // Enter key to send
                input.addEventListener('keydown', async (e) => {
                    if (e.key === 'Enter' && !e.shiftKey) {
                        e.preventDefault()
                        sendBtn.click()
                    }
                })
            }

            // Handle voice recording events from LiveView
            this.handleEvent("start_room_voice_recording", async () => {
                this.voiceRecorder = new VoiceRecorder()
                this.voiceRecorder.onStop = async (blob, durationMs) => {
                    try {
                        const { encryptedContent, nonce } = await messageEncryption.encryptVoiceNote(blob, `room-${this.roomId}`)
                        this.pushEvent("send_room_voice_note", {
                            encrypted_content: messageEncryption.arrayToBase64(encryptedContent),
                            nonce: messageEncryption.arrayToBase64(nonce),
                            duration_ms: durationMs
                        })
                    } catch (e) {
                        console.error("Failed to encrypt room voice note:", e)
                    }
                }
                await this.voiceRecorder.start()
            })

            this.handleEvent("stop_room_voice_recording", () => {
                if (this.voiceRecorder) {
                    this.voiceRecorder.stop()
                }
            })
        }
    },

    // Room voice player hook for space chat
    RoomVoicePlayer: {
        mounted() {
            this.messageId = this.el.dataset.messageId
            this.roomId = this.el.dataset.roomId
            const playBtn = this.el.querySelector('.room-voice-play-btn')
            const progressBar = this.el.querySelector('.room-voice-progress')

            this.audio = null
            this.isPlaying = false

            if (playBtn) {
                playBtn.addEventListener('click', async () => {
                    if (this.isPlaying && this.audio) {
                        this.audio.pause()
                        playBtn.textContent = '▶'
                        this.isPlaying = false
                    } else if (this.audio) {
                        this.audio.play()
                        playBtn.textContent = '⏸'
                        this.isPlaying = true
                    } else {
                        // First play - need to decrypt and create player
                        playBtn.textContent = '...'

                        try {
                            const msgEl = this.el.querySelector('.room-voice-data')
                            const encrypted = msgEl?.dataset.encrypted
                            const nonce = msgEl?.dataset.nonce

                            if (encrypted && nonce && this.roomId) {
                                const encryptedArray = messageEncryption.base64ToArray(encrypted)
                                const nonceArray = messageEncryption.base64ToArray(nonce)

                                const audioBlob = await messageEncryption.decryptVoiceNote(
                                    encryptedArray,
                                    nonceArray,
                                    `room-${this.roomId}`
                                )

                                if (audioBlob) {
                                    this.audio = new Audio(URL.createObjectURL(audioBlob))

                                    this.audio.ontimeupdate = () => {
                                        if (progressBar && this.audio.duration) {
                                            const percent = (this.audio.currentTime / this.audio.duration) * 100
                                            progressBar.style.width = `${percent}%`
                                        }
                                    }

                                    this.audio.onended = () => {
                                        playBtn.textContent = '▶'
                                        this.isPlaying = false
                                        if (progressBar) progressBar.style.width = '0%'
                                    }

                                    this.audio.play()
                                    playBtn.textContent = '⏸'
                                    this.isPlaying = true
                                } else {
                                    playBtn.textContent = '❌'
                                }
                            } else {
                                console.warn("Missing encrypted data for room voice message")
                                playBtn.textContent = '❌'
                            }
                        } catch (e) {
                            console.error("Failed to decrypt room voice note:", e)
                            playBtn.textContent = '❌'
                        }
                    }
                })
            }
        },
        destroyed() {
            if (this.audio) {
                this.audio.pause()
                URL.revokeObjectURL(this.audio.src)
            }
        }
    },

    // Grid voice recorder - click to toggle recording from the photo/note grid
    GridVoiceRecorder: {
        mounted() {
            this.roomId = this.el.dataset.roomId
            this.voiceRecorder = null
            this.isRecording = false

            this.el.addEventListener('click', async () => {
                if (this.isRecording) {
                    // Stop recording
                    if (this.voiceRecorder) {
                        this.voiceRecorder.stop()
                    }
                    this.isRecording = false
                    this.pushEvent("stop_room_recording", {})
                } else {
                    // Start recording
                    try {
                        this.voiceRecorder = new VoiceRecorder()
                        this.voiceRecorder.onStop = async (blob, durationMs) => {
                            try {
                                const { encryptedContent, nonce } = await messageEncryption.encryptVoiceNote(blob, `room-${this.roomId}`)
                                this.pushEvent("save_grid_voice_note", {
                                    encrypted_content: messageEncryption.arrayToBase64(encryptedContent),
                                    nonce: messageEncryption.arrayToBase64(nonce),
                                    duration_ms: durationMs
                                })
                            } catch (e) {
                                console.error("Failed to encrypt grid voice note:", e)
                            }
                        }
                        await this.voiceRecorder.start()
                        this.isRecording = true
                        this.pushEvent("start_voice_recording", {})
                    } catch (e) {
                        console.error("Failed to start recording:", e)
                        this.pushEvent("recording_error", { error: e.message })
                    }
                }
            })
        }
    },

    GridVoicePlayer: {
        mounted() {
            this.itemId = this.el.dataset.itemId
            this.roomId = this.el.dataset.roomId
            this.audio = null
            this.isPlaying = false

            const playBtn = this.el.querySelector('.grid-voice-play-btn')
            const progressBar = this.el.querySelector('.grid-voice-progress')
            const canvas = this.el.querySelector('canvas.visualizer-canvas')

            // Auto-decrypt and visualize
            this.decryptAndVisualize(canvas)

            if (playBtn) {
                this.el.addEventListener('click', async (e) => {
                    if (e.target.closest('.grid-voice-play-btn')) {
                        e.stopPropagation()
                        e.preventDefault()

                        if (this.isPlaying && this.audio) {
                            this.audio.pause()
                            this.isPlaying = false
                            playBtn.textContent = '▶'
                            return
                        }

                        // If audio is already prepared (from visualization step), just play
                        if (this.audio) {
                            this.audio.play()
                            playBtn.textContent = '⏸'
                            this.isPlaying = true
                            return
                        }

                        // Fallback: Decrypt if not yet ready
                        playBtn.textContent = '...'
                        if (await this.decryptAndVisualize(canvas)) {
                            this.audio.play()
                            playBtn.textContent = '⏸'
                            this.isPlaying = true
                        } else {
                            playBtn.textContent = '❌'
                        }
                    }
                })
            }
        },

        async decryptAndVisualize(canvas) {
            // Check if already decrypted
            if (this.audio) return true

            try {
                const dataEl = document.getElementById(`grid-voice-data-${this.itemId}`)
                if (dataEl && dataEl.dataset.encrypted) {
                    const encryptedArray = messageEncryption.base64ToArray(dataEl.dataset.encrypted)
                    const nonceArray = messageEncryption.base64ToArray(dataEl.dataset.nonce)

                    const audioBlob = await messageEncryption.decryptVoiceNote(
                        encryptedArray,
                        nonceArray,
                        `room-${this.roomId}`
                    )

                    if (audioBlob) {
                        this.audio = new Audio(URL.createObjectURL(audioBlob))

                        // Setup visualizer if canvas exists
                        if (canvas) {
                            this.drawWaveform(canvas, audioBlob)
                        }

                        // Setup audio events
                        if (this.el.querySelector('.grid-voice-progress')) {
                            const progressBar = this.el.querySelector('.grid-voice-progress')
                            const playBtn = this.el.querySelector('.grid-voice-play-btn')

                            this.audio.ontimeupdate = () => {
                                if (this.audio.duration) {
                                    const percent = (this.audio.currentTime / this.audio.duration) * 100
                                    progressBar.style.width = `${percent}%`
                                }
                            }

                            this.audio.onended = () => {
                                if (playBtn) playBtn.textContent = '▶'
                                this.isPlaying = false
                                progressBar.style.width = '0%'
                            }
                        }
                        return true
                    }
                }
            } catch (e) {
                console.error("Failed to decrypt grid voice note:", e)
            }
            return false
        },

        async drawWaveform(canvas, audioBlob) {
            try {
                const audioCtx = new (window.AudioContext || window.webkitAudioContext)()
                const arrayBuffer = await audioBlob.arrayBuffer()
                const audioBuffer = await audioCtx.decodeAudioData(arrayBuffer)

                const width = canvas.width
                const height = canvas.height
                const ctx = canvas.getContext('2d')
                const data = audioBuffer.getChannelData(0)
                const step = Math.ceil(data.length / width)
                const amp = height / 2

                ctx.clearRect(0, 0, width, height)
                ctx.beginPath()

                // Draw centered waveform
                for (let i = 0; i < width; i++) {
                    let min = 1.0
                    let max = -1.0

                    // Get chunk of data for this pixel
                    for (let j = 0; j < step; j++) {
                        const datum = data[(i * step) + j]
                        if (datum < min) min = datum
                        if (datum > max) max = datum
                    }

                    if (min === 1.0) min = 0
                    if (max === -1.0) max = 0

                    // Smooth data slightly
                    const high = Math.abs(max)
                    const low = Math.abs(min)
                    const avg = (high + low) / 2

                    // Draw line
                    const y = (1 + min) * amp
                    const h = Math.max(1, (max - min) * amp)

                    ctx.fillStyle = '#fbbf24' // warm amber
                    ctx.fillRect(i, height / 2 - h / 2 * 1.5, 1, h * 1.5) // scaled up slightly
                }

            } catch (e) {
                console.error("Waveform visualization failed:", e)
            }
        },

        destroyed() {
            if (this.audio) {
                this.audio.pause()
                URL.revokeObjectURL(this.audio.src)
            }
        }
    },

    CopyToClipboard: {
        mounted() {
            this.handleClick = async (event) => {
                event.preventDefault()
                const text = this.el.dataset.copy || this.el.getAttribute('data-copy')
                if (!text) return
                try {
                    await navigator.clipboard.writeText(text)
                    // Visual feedback
                    const originalText = this.el.textContent
                    this.el.textContent = "Copied!"

                    // Temporary styles for success state
                    const originalClasses = this.el.className
                    if (!this.el.classList.contains('text-green-500')) {
                        // Assuming simple buttons, we might want to just rely on text
                        // but let's try to add a subtle pop
                        this.el.style.transition = 'all 0.2s'
                        this.el.style.transform = 'scale(1.05)'
                    }

                    if (this.timeout) clearTimeout(this.timeout)
                    this.timeout = setTimeout(() => {
                        this.el.textContent = originalText
                        this.el.style.transform = ''
                        this.el.className = originalClasses
                    }, 2000)

                    console.log('[CopyToClipboard] copied', text)
                } catch (e) {
                    console.error('[CopyToClipboard] failed to copy', e)
                }
            }
            this.el.addEventListener('click', this.handleClick)
        },
        destroyed() {
            if (this.handleClick) {
                this.el.removeEventListener('click', this.handleClick)
            }
            if (this.timeout) clearTimeout(this.timeout)
        }
    },

    AutoFocus: {
        mounted() {
            setTimeout(() => this.el.focus(), 50)
        }
    },

    // ExportKeys hook removed - WebAuthn passkeys are stored securely on your device
    // and synced via your platform's passkey provider (iCloud Keychain, Google Password Manager, etc.)

    WebAuthnManager: {
        async mounted() {
            const statusDiv = document.getElementById('webauthn-status')
            const registerBtn = document.getElementById('register-webauthn-btn')

            // Check WebAuthn support
            const supported = isWebAuthnSupported()
            const platformAvailable = supported && await isPlatformAuthenticatorAvailable()

            if (!supported) {
                statusDiv.textContent = 'Not supported'
                statusDiv.className = 'text-xs text-red-500'
                return
            }

            if (platformAvailable) {
                statusDiv.textContent = 'Platform ready'
                statusDiv.className = 'text-xs text-green-500 hidden md:block'
            } else {
                statusDiv.textContent = 'Key supported'
                statusDiv.className = 'text-xs text-neutral-500 hidden md:block'
            }

            // Show register button
            registerBtn.classList.remove('hidden')

            // Handle challenge response from server
            this.handleEvent("webauthn_challenge_generated", async ({ options }) => {
                try {
                    console.log('[WebAuthn] Challenge received, creating credential...')

                    // Create credential with the challenge from server
                    const credential = await registerCredential(options)

                    console.log('[WebAuthn] Credential created, sending to server...')

                    // Send credential back to server for verification
                    this.pushEvent("register_webauthn_credential", {
                        credential: credential
                    })
                } catch (error) {
                    console.error('[WebAuthn] Registration failed:', error)
                    registerBtn.disabled = false
                    registerBtn.textContent = 'Register Hardware Key'

                    if (error.name === 'NotAllowedError') {
                        alert('Registration cancelled or not allowed')
                    } else {
                        alert('Registration failed: ' + error.message)
                    }
                }
            })

            // Handle registration complete
            this.handleEvent("webauthn_registration_complete", () => {
                registerBtn.disabled = false
                registerBtn.textContent = 'Register Hardware Key'
                console.log('[WebAuthn] Registration complete!')
            })

            // Handle registration failed
            this.handleEvent("webauthn_registration_failed", () => {
                registerBtn.disabled = false
                registerBtn.textContent = 'Register Hardware Key'
            })

            // Handle register button click
            registerBtn.onclick = async () => {
                try {
                    registerBtn.disabled = true
                    registerBtn.textContent = 'Preparing...'

                    // Request challenge from server
                    this.pushEvent("request_webauthn_challenge", {})
                } catch (error) {
                    console.error('[WebAuthn] Failed to request challenge:', error)
                    registerBtn.disabled = false
                    registerBtn.textContent = 'Register Hardware Key'
                    alert('Failed to start registration: ' + error.message)
                }
            }
        }
    },

    WebAuthnLogin: {
        async mounted() {
            // Handle WebAuthn login challenge from server
            this.handleEvent("webauthn_login_challenge", async ({ options }) => {
                try {
                    console.log('[WebAuthn Login] Challenge received, authenticating...')

                    // Authenticate with credential
                    const credential = await authenticateWithCredential(options)

                    console.log('[WebAuthn Login] Authentication successful, sending to server...')

                    // Send credential back to server for verification
                    this.pushEvent("webauthn_login_response", {
                        credential: credential
                    })
                } catch (error) {
                    console.error('[WebAuthn Login] Authentication failed:', error)

                    let errorMsg = error.message
                    if (error.name === 'NotAllowedError') {
                        errorMsg = 'Authentication cancelled or not allowed'
                    } else if (error.name === 'InvalidStateError') {
                        errorMsg = 'No matching credential found'
                    }

                    this.pushEvent("webauthn_login_error", { error: errorMsg })
                }
            })

            // Handle successful login
            this.handleEvent("login_success", ({ user_id, token }) => {
                // Detect if we're on HTTPS for Secure flag
                const isSecure = window.location.protocol === 'https:'
                const secureSuffix = isSecure ? '; Secure' : ''

                // Set cookies for session
                document.cookie = `friends_user_id=${user_id}; path=/; max-age=${60 * 60 * 24 * 365}; SameSite=Lax${secureSuffix}`
                if (token) {
                    document.cookie = `friends_session_token=${token}; path=/; max-age=${60 * 60 * 24 * 30}; SameSite=Lax${secureSuffix}`
                }

                // Redirect to home
                setTimeout(() => {
                    window.location.href = '/'
                }, 500)
            })
        }
    },

    PhotoModal: {
        mounted() {
            // Lock body scrolling when modal opens
            document.body.style.overflow = 'hidden'

            // Handle image loading state
            const img = this.el.querySelector('img')
            if (img) {
                // Show loading state initially
                img.style.opacity = '0'

                // Create and add loading spinner
                const spinner = document.createElement('div')
                spinner.className = 'absolute inset-0 flex items-center justify-center'
                spinner.innerHTML = '<div class="spinner"></div>'
                spinner.id = 'photo-loading-spinner'
                img.parentElement.appendChild(spinner)

                // Handle image load
                const handleLoad = () => {
                    img.style.transition = 'opacity 0.3s ease-in-out'
                    img.style.opacity = '1'
                    spinner.remove()
                }

                // Handle image error
                const handleError = () => {
                    spinner.innerHTML = '<div class="text-white text-sm">Failed to load image</div>'
                }

                if (img.complete) {
                    handleLoad()
                } else {
                    img.addEventListener('load', handleLoad, { once: true })
                    img.addEventListener('error', handleError, { once: true })
                }
            }

            // Add touch swipe gesture support
            let touchStartX = 0
            let touchEndX = 0
            let touchStartY = 0
            let touchEndY = 0

            const handleTouchStart = (e) => {
                touchStartX = e.changedTouches[0].screenX
                touchStartY = e.changedTouches[0].screenY
            }

            const handleTouchEnd = (e) => {
                touchEndX = e.changedTouches[0].screenX
                touchEndY = e.changedTouches[0].screenY
                handleGesture()
            }

            const handleGesture = () => {
                const diffX = touchEndX - touchStartX
                const diffY = touchEndY - touchStartY

                // Only trigger if horizontal swipe is dominant
                if (Math.abs(diffX) > Math.abs(diffY)) {
                    // Minimum swipe distance (50px)
                    if (Math.abs(diffX) > 50) {
                        if (diffX > 0) {
                            // Swipe right - previous photo
                            this.pushEvent("prev_photo", {})
                        } else {
                            // Swipe left - next photo
                            this.pushEvent("next_photo", {})
                        }
                    }
                }
            }

            // Add keyboard navigation
            const handleKeyDown = (e) => {
                if (e.key === 'ArrowLeft') {
                    e.preventDefault()
                    this.pushEvent("prev_photo", {})
                } else if (e.key === 'ArrowRight') {
                    e.preventDefault()
                    this.pushEvent("next_photo", {})
                } else if (e.key === 'Escape') {
                    e.preventDefault()
                    this.pushEvent("close_image_modal", {})
                }
            }

            // Attach listeners
            this.el.addEventListener('touchstart', handleTouchStart, { passive: true })
            this.el.addEventListener('touchend', handleTouchEnd, { passive: true })
            document.addEventListener('keydown', handleKeyDown)

            // Store for cleanup
            this.handleKeyDown = handleKeyDown
        },

        updated() {
            // Handle loading state when photo changes (prev/next navigation)
            const img = this.el.querySelector('img')
            if (img) {
                // Remove old spinner if it exists
                const oldSpinner = this.el.querySelector('#photo-loading-spinner')
                if (oldSpinner) {
                    oldSpinner.remove()
                }

                // Show loading state initially
                img.style.opacity = '0'

                // Create and add loading spinner
                const spinner = document.createElement('div')
                spinner.className = 'absolute inset-0 flex items-center justify-center'
                spinner.innerHTML = '<div class="spinner"></div>'
                spinner.id = 'photo-loading-spinner'
                img.parentElement.appendChild(spinner)

                // Handle image load
                const handleLoad = () => {
                    img.style.transition = 'opacity 0.3s ease-in-out'
                    img.style.opacity = '1'
                    spinner.remove()
                }

                // Handle image error
                const handleError = () => {
                    spinner.innerHTML = '<div class="text-white text-sm">Failed to load image</div>'
                }

                if (img.complete) {
                    handleLoad()
                } else {
                    img.addEventListener('load', handleLoad, { once: true })
                    img.addEventListener('error', handleError, { once: true })
                }
            }
        },

        destroyed() {
            // Unlock body scrolling when modal closes
            document.body.style.overflow = ''

            // Remove keyboard listener
            if (this.handleKeyDown) {
                document.removeEventListener('keydown', this.handleKeyDown)
            }
        }
    }
}

// Precompute lightweight identity signals for instant server bootstrap
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

// Handle global sign_out event (works on all pages)
window.addEventListener("phx:sign_out", () => {
    console.log('[SignOut] Clearing session and redirecting...')
    // Clear the session cookie
    document.cookie = "friends_user_id=; path=/; max-age=0; SameSite=Lax"
    // Redirect to home
    window.location.href = '/'
})

window.liveSocket = liveSocket

