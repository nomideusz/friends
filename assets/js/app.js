// Phoenix imports
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import {getHooks} from "live_svelte"
import FriendsMap from "../svelte/FriendsMap.svelte"
import { cryptoIdentity } from "./crypto-identity"
import { deviceLinkManager } from "./device-link"
import { deviceAttestation } from "./device-attestation"
import { isWebAuthnSupported, isPlatformAuthenticatorAvailable, registerCredential } from "./webauthn"
import QRCode from "qrcode"

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
            this.browserId = bootstrapBrowserId
            this.fingerprint = bootstrapFingerprint

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
                const deviceInfo = await deviceAttestation.init()

                this.pushEvent("auth_response", {
                    signature,
                    challenge,
                    device_fingerprint: deviceInfo.fingerprint,
                    device_name: deviceInfo.deviceName,
                    key_fingerprint: cryptoIdentity.getKeyFingerprint()
                })
            })

            // Handle registration success
            this.handleEvent("registration_complete", ({ user }) => {
                console.log("Registration complete:", user)
                // Set cookie for fast initial render on next page load
                if (user && user.id) {
                    document.cookie = `friends_user_id=${user.id}; path=/; max-age=${60 * 60 * 24 * 365}; SameSite=Lax`
                }
            })

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
                // Clear crypto identity
                await cryptoIdentity.clear()

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
            const form = this.el.querySelector('#upload-form')
            if (!form) return

            const fileInput = form.querySelector('input[type="file"]')
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

            // Handle registration success
            this.handleEvent("registration_complete", ({ user }) => {
                console.log("Registration complete:", user)
                // Set cookie for fast initial render on next page load
                if (user && user.id) {
                    document.cookie = `friends_user_id=${user.id}; path=/; max-age=${60 * 60 * 24 * 365}; SameSite=Lax`
                }
            })

            // Handle clear identity request
            this.handleEvent("clear_identity", async () => {
                await cryptoIdentity.clear()
                localStorage.removeItem('friends_browser_id')
                // Clear user cookie
                document.cookie = 'friends_user_id=; path=/; max-age=0'
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
    },

    ExportKeys: {
        async mounted() {
            this.handleEvent("export_backup", async () => {
                try {
                    // Export backup as JSON string
                    const backup = await cryptoIdentity.exportBackup()

                    // Generate QR code
                    const qrContainer = document.getElementById('export-qr-code')
                    if (qrContainer) {
                        qrContainer.innerHTML = '<p class="text-xs text-neutral-500 mb-2">QR Code (for mobile import)</p>'
                        const canvas = document.createElement('canvas')
                        await QRCode.toCanvas(canvas, backup, {
                            width: 256,
                            margin: 2,
                            color: {
                                dark: '#ffffff',
                                light: '#000000'
                            }
                        })
                        qrContainer.appendChild(canvas)

                        // Add download button
                        const btnContainer = document.createElement('div')
                        btnContainer.className = 'mt-4 space-y-2'

                        const downloadBtn = document.createElement('button')
                        downloadBtn.textContent = 'Download Backup File'
                        downloadBtn.className = 'w-full px-4 py-2 bg-white text-black font-medium hover:bg-neutral-200'
                        downloadBtn.onclick = () => cryptoIdentity.downloadBackup()

                        const copyBtn = document.createElement('button')
                        copyBtn.textContent = 'Copy to Clipboard'
                        copyBtn.className = 'w-full px-4 py-2 bg-neutral-800 text-white hover:bg-neutral-700'
                        copyBtn.onclick = async () => {
                            await navigator.clipboard.writeText(backup)
                            copyBtn.textContent = 'Copied!'
                            setTimeout(() => {
                                copyBtn.textContent = 'Copy to Clipboard'
                            }, 2000)
                        }

                        btnContainer.appendChild(downloadBtn)
                        btnContainer.appendChild(copyBtn)
                        qrContainer.appendChild(btnContainer)
                    }
                } catch (e) {
                    console.error("Failed to export backup:", e)
                    alert("Failed to export backup: " + e.message)
                }
            })
        }
    },

    WebAuthnManager: {
        async mounted() {
            const statusDiv = document.getElementById('webauthn-status')
            const registerBtn = document.getElementById('register-webauthn-btn')

            // Check WebAuthn support
            const supported = isWebAuthnSupported()
            const platformAvailable = supported && await isPlatformAuthenticatorAvailable()

            if (!supported) {
                statusDiv.textContent = '❌ WebAuthn not supported in this browser'
                statusDiv.className = 'text-sm text-red-500 mb-4'
                return
            }

            if (platformAvailable) {
                statusDiv.textContent = '✅ Platform authenticator available (Touch ID, Face ID, Windows Hello)'
                statusDiv.className = 'text-sm text-green-500 mb-4'
            } else {
                statusDiv.textContent = '⚠️ WebAuthn supported, but no platform authenticator detected. You can still use USB security keys.'
                statusDiv.className = 'text-sm text-yellow-500 mb-4'
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

