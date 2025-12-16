// Phoenix imports
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import { getHooks } from "live_svelte"
import FriendsMap from "../svelte/FriendsMap.svelte"
import FriendGraph from "../svelte/FriendGraph.svelte"
import { mount, unmount } from 'svelte'
import { isWebAuthnSupported, isPlatformAuthenticatorAvailable, registerCredential, authenticateWithCredential } from "./webauthn"
import * as messageEncryption from "./message-encryption"
import { VoiceRecorder, VoicePlayer } from "./voice-recorder"
import QRCode from "qrcode"

const Components = { FriendsMap, FriendGraph }

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

// Hooks
const Hooks = {
    ...getHooks(Components),

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

    // Feed voice recording for public feed
    FeedVoiceRecorder: {
        mounted() {
            this.recorder = null
            this.isRecording = false

            this.el.addEventListener('click', async () => {
                if (this.isRecording) {
                    // Stop recording - the onStop callback handles the result
                    if (this.recorder) {
                        this.recorder.stop()
                    }
                    this.isRecording = false
                } else {
                    // Start recording
                    try {
                        this.recorder = new VoiceRecorder()

                        // Setup callback for when recording stops
                        this.recorder.onStop = async (audioBlob, durationMs) => {
                            try {
                                // Convert blob to base64 for sending to server
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
                            this.pushEvent("start_voice_recording", {})
                        }
                    } catch (err) {
                        console.error("Failed to start recording:", err)
                    }
                }
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
                        this.el.style.transform = ''
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

            const sendBtn = this.el.querySelector('button')
            const input = this.el.querySelector('input')

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

                        try {
                            playBtn.textContent = '...'

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
                                    if (this.audio) {
                                        this.audio.pause()
                                        URL.revokeObjectURL(this.audio.src)
                                    }

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
                                playBtn.textContent = '❌'
                            }
                        } catch (e) {
                            console.error("Failed to decrypt grid voice note:", e)
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

window.liveSocket = liveSocket

