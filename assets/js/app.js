// Phoenix imports
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import {getHooks} from "live_svelte"
import FriendsMap from "../svelte/FriendsMap.svelte"
import { cryptoIdentity } from "./crypto-identity"
import { deviceLinkManager } from "./device-link"

const Components = { FriendsMap }

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
    
    FriendsApp: {
        async mounted() {
            this.browserId = getBrowserId()
            this.fingerprint = generateFingerprint()

            // Initialize crypto identity
            const { isNew, publicKey } = await cryptoIdentity.init()
            this.publicKey = publicKey
            this.identityPayload = {
                browser_id: this.browserId,
                fingerprint: this.fingerprint,
                public_key: this.publicKey,
                is_new_key: isNew
            }

            // If already connected, send immediately
            this.maybeSendIdentity()

            // Server can request identity when it knows the socket is ready
            this.handleEvent("request_identity", () => this.maybeSendIdentity())
            
            // Handle challenge-response authentication
            this.handleEvent("auth_challenge", async ({ challenge }) => {
                const signature = await cryptoIdentity.sign(challenge)
                this.pushEvent("auth_response", { 
                    signature,
                    challenge 
                })
            })
            
            // Handle registration success
            this.handleEvent("registration_complete", ({ user }) => {
                console.log("Registration complete:", user)
            })
            
            // Setup image optimization
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
            const form = this.el.querySelector('#upload-form')
            if (!form) return
            
            const fileInput = form.querySelector('input[type="file"]')
            if (!fileInput) return
            
            this.pendingThumbnail = null
            
            this.handleEvent("photo_uploaded", ({ photo_id }) => {
                if (this.pendingThumbnail && photo_id) {
                    this.pushEvent("set_thumbnail", {
                        photo_id: photo_id,
                        thumbnail: this.pendingThumbnail
                    })
                    this.pendingThumbnail = null
                }
            })
            
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
            this.observeImages()
        },
        updated() {
            this.observeImages()
        },
        observeImages() {
            const images = this.el.querySelectorAll('img:not(.observed)')
            images.forEach(img => {
                img.classList.add('observed')
                if (img.complete) {
                    img.classList.add('loaded')
                } else {
                    img.addEventListener('load', () => img.classList.add('loaded'), { once: true })
                }
            })
        }
    },
    
    RegisterApp: {
        async mounted() {
            // Initialize crypto identity and send public key to server
            const { isNew, publicKey } = await cryptoIdentity.init()
            
            this.pushEvent("set_public_key", {
                public_key: publicKey
            })
            
            // Handle clear identity request
            this.handleEvent("clear_identity", async () => {
                await cryptoIdentity.clear()
                localStorage.removeItem('friends_browser_id')
                alert("Identity cleared. Refreshing page...")
                window.location.reload()
            })
        }
    },
    
    RecoverApp: {
        async mounted() {
            // Listen for when user confirms recovery - then generate new key
            this.handleEvent("generate_recovery_key", async () => {
                // Clear existing identity and generate a new one for recovery
                await cryptoIdentity.clear()
                const { isNew, publicKey } = await cryptoIdentity.init()
                
                // Send the new public key to server
                this.pushEvent("set_public_key", {
                    public_key: publicKey
                })
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
            // Check if we have an identity to export
            const hasIdentity = await cryptoIdentity.hasIdentity()
            this.pushEvent("check_identity", { has_identity: hasIdentity })
            
            // Handle export request
            this.handleEvent("generate_transfer_code", async () => {
                try {
                    console.log("Generating transfer code...")
                    const result = await deviceLinkManager.generateTransferCode()
                    console.log("Transfer code generated:", result.pin, "QR length:", result.qrDataUrl?.length)
                    
                    // First push the text data
                    this.pushEvent("transfer_code_generated", {
                        pin: result.pin,
                        code: result.code,
                        qr_data_url: "pending"
                    })
                    
                    // Then render QR directly into DOM after LiveView patches
                    const renderQR = () => {
                        const container = document.getElementById('qr-container')
                        if (container && result.qrDataUrl) {
                            const img = document.createElement('img')
                            img.src = result.qrDataUrl
                            img.alt = 'QR Code'
                            img.className = 'w-48 h-48 loaded'
                            container.innerHTML = ''
                            container.appendChild(img)
                            console.log("QR code rendered!")
                        } else {
                            console.log("Container not found, retrying...")
                            setTimeout(renderQR, 200)
                        }
                    }
                    setTimeout(renderQR, 300)
                } catch (e) {
                    console.error("Failed to generate transfer code:", e)
                    this.pushEvent("transfer_code_generated", {
                        pin: "ERROR",
                        code: e.message,
                        qr_data_url: null
                    })
                }
            })
            
            // Handle import request
            this.handleEvent("import_identity", async ({ code, pin }) => {
                try {
                    const publicKey = await deviceLinkManager.importFromCode(code, pin)
                    if (publicKey) {
                        this.pushEvent("import_result", {
                            success: true,
                            public_key: publicKey
                        })
                    } else {
                        this.pushEvent("import_result", { success: false })
                    }
                } catch (e) {
                    console.error("Failed to import identity:", e)
                    this.pushEvent("import_result", { success: false })
                }
            })
        }
    }
}

// Setup LiveSocket
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
    hooks: Hooks,
    params: {_csrf_token: csrfToken},
    reconnectAfterMs: tries => [100, 200, 500, 1000, 2000, 5000][tries - 1] || 5000,
    longPollFallbackMs: 2500
})

// Progress bar
topbar.config({barColors: {0: "#fff"}, shadowColor: "rgba(0, 0, 0, .3)"})
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

