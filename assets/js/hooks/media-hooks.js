/**
 * Media-related LiveView hooks
 * Handles: Voice recording, playback, waveform visualization
 */

import { VoiceRecorder, VoicePlayer } from '../voice-recorder'
import * as messageEncryption from '../message-encryption'

// Shared Audio Context for all audio hooks
let sharedAudioCtx = null
export function getAudioContext() {
    if (!sharedAudioCtx) {
        const AudioContext = window.AudioContext || window.webkitAudioContext
        sharedAudioCtx = new AudioContext()
    }
    return sharedAudioCtx
}

export const VoiceWaveformHook = {
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
}

export const FeedVoiceRecorderHook = {
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
                }
            } catch (err) {
                console.error("Failed to start recording:", err)
                this.pushEvent("cancel_voice_recording", {})
            }
        })

        this.el.addEventListener('click', async () => {
            if (this.isRecording) {
                if (this.recorder) {
                    this.recorder.stop()
                }
                this.isRecording = false
            }
        })
    },
    destroyed() {
        if (this.recorder && this.isRecording) {
            this.recorder.stop()
        }
    }
}

export const GridVoiceRecorderHook = {
    mounted() {
        this.recorder = null
        this.isRecording = false

        this.el.addEventListener('click', async () => {
            if (this.isRecording) {
                if (this.recorder) {
                    this.recorder.stop()
                }
                this.isRecording = false
                this.pushEvent("stop_voice_recording", {})
            } else {
                try {
                    this.recorder = new VoiceRecorder()

                    this.recorder.onStop = async (blob, durationMs) => {
                        const arrayBuffer = await blob.arrayBuffer()
                        const bytes = new Uint8Array(arrayBuffer)
                        let binary = ''
                        for (let i = 0; i < bytes.length; i++) {
                            binary += String.fromCharCode(bytes[i])
                        }
                        const base64 = btoa(binary)

                        this.pushEvent("voice_note_recorded", {
                            audio_data: base64,
                            duration_ms: durationMs
                        })
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
    }
}

export const RoomVoiceRecorderHook = {
    mounted() {
        this.recorder = null
        this.isRecording = false
        this.roomId = this.el.dataset.roomId

        this.el.addEventListener('click', async () => {
            if (this.isRecording) {
                if (this.recorder) {
                    this.recorder.stop()
                }
                this.isRecording = false
                this.pushEvent("stop_room_voice_recording", {})
            } else {
                try {
                    this.recorder = new VoiceRecorder()

                    this.recorder.onStop = async (blob, durationMs) => {
                        try {
                            // Get room encryption key
                            const conversationId = `room:${this.roomId}`
                            const key = await messageEncryption.loadOrCreateConversationKey(conversationId)

                            // Read audio as bytes
                            const arrayBuffer = await blob.arrayBuffer()
                            const audioBytes = new Uint8Array(arrayBuffer)

                            // Encrypt the audio
                            const { encrypted, nonce } = await messageEncryption.encryptBytesWithKey(audioBytes, key)

                            // Send encrypted voice note
                            this.pushEvent("send_room_voice_note", {
                                encrypted_content: messageEncryption.arrayToBase64(encrypted),
                                nonce: messageEncryption.arrayToBase64(nonce),
                                duration_ms: durationMs
                            })
                        } catch (err) {
                            console.error("Failed to encrypt voice:", err)
                        }
                    }

                    const started = await this.recorder.start()
                    if (started) {
                        this.isRecording = true
                        this.pushEvent("start_room_voice_recording", {})
                    }
                } catch (err) {
                    console.error("Failed to start recording:", err)
                    this.pushEvent("room_voice_recording_error", { error: err.message })
                }
            }
        })
    },
    destroyed() {
        if (this.recorder && this.isRecording) {
            this.recorder.stop()
        }
    }
}

export const VoicePlayerHook = {
    async mounted() {
        const encryptedData = this.el.dataset.encrypted
        const nonce = this.el.dataset.nonce
        const conversationId = this.el.dataset.conversationId
        const duration = parseFloat(this.el.dataset.duration) || 0

        if (!encryptedData || !nonce) {
            console.error("VoicePlayer missing encrypted data or nonce")
            return
        }

        try {
            const key = await messageEncryption.loadOrCreateConversationKey(conversationId)
            const encryptedBytes = Uint8Array.from(atob(encryptedData), c => c.charCodeAt(0))
            const nonceBytes = Uint8Array.from(atob(nonce), c => c.charCodeAt(0))

            const decrypted = await messageEncryption.decryptWithKey(encryptedBytes, nonceBytes, key)
            const blob = new Blob([decrypted], { type: 'audio/webm' })
            const url = URL.createObjectURL(blob)

            this.audio = new Audio(url)

            const playButton = this.el.querySelector('[data-action="play"]')
            const progressBar = this.el.querySelector('[data-progress]')
            const timeDisplay = this.el.querySelector('[data-time]')

            if (playButton) {
                playButton.addEventListener('click', () => {
                    if (this.audio.paused) {
                        this.audio.play()
                        playButton.textContent = '⏸'
                    } else {
                        this.audio.pause()
                        playButton.textContent = '▶'
                    }
                })
            }

            this.audio.ontimeupdate = () => {
                if (progressBar && duration > 0) {
                    progressBar.style.width = `${(this.audio.currentTime / duration) * 100}%`
                }
                if (timeDisplay) {
                    timeDisplay.textContent = formatTime(this.audio.currentTime)
                }
            }

            this.audio.onended = () => {
                if (playButton) playButton.textContent = '▶'
                if (progressBar) progressBar.style.width = '0%'
            }
        } catch (err) {
            console.error("VoicePlayer decryption error:", err)
        }
    },
    destroyed() {
        if (this.audio) {
            this.audio.pause()
            URL.revokeObjectURL(this.audio.src)
        }
    }
}

// FeedVoicePlayer - Simple voice player for public feed grid items
export const FeedVoicePlayerHook = {
    mounted() {
        this.audio = null
        this.isPlaying = false

        const itemId = this.el.dataset.itemId

        // Find the play button
        const playBtn = this.el.querySelector('.feed-voice-play-btn')
        if (!playBtn) return

        playBtn.addEventListener('click', async (e) => {
            e.stopPropagation()

            if (this.isPlaying && this.audio) {
                this.audio.pause()
                this.audio.currentTime = 0
                this.isPlaying = false
                playBtn.innerHTML = `<svg class="w-5 h-5 ml-0.5" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>`
                return
            }

            // Get audio source on click (deferred lookup)
            const dataEl = document.getElementById(`feed-voice-data-${itemId}`)
            if (!dataEl) {
                console.warn('FeedVoicePlayer: Data element not found for item', itemId)
                return
            }

            const audioSrc = dataEl.dataset.src
            if (!audioSrc) {
                console.warn('FeedVoicePlayer: No audio source for item', itemId)
                return
            }

            try {
                this.audio = new Audio(audioSrc)

                this.audio.onplay = () => {
                    this.isPlaying = true
                    playBtn.innerHTML = `<svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg>`
                }

                this.audio.onended = () => {
                    this.isPlaying = false
                    playBtn.innerHTML = `<svg class="w-5 h-5 ml-0.5" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>`
                }

                this.audio.onerror = (err) => {
                    console.error('FeedVoicePlayer: Audio error', err)
                    this.isPlaying = false
                }

                await this.audio.play()
            } catch (err) {
                console.error('FeedVoicePlayer: Playback error', err)
            }
        })
    },

    destroyed() {
        if (this.audio) {
            this.audio.pause()
            this.audio = null
        }
    }
}

// RoomVoicePlayer - Voice player for encrypted room chat messages
export const RoomVoicePlayerHook = {
    async mounted() {
        this.audio = null
        this.isPlaying = false

        const messageId = this.el.dataset.messageId
        const roomId = this.el.dataset.roomId

        // Get encrypted data from hidden element
        const dataEl = this.el.querySelector('.room-voice-data')
        if (!dataEl) {
            console.warn('RoomVoicePlayer: No data element for message', messageId)
            return
        }

        const encryptedBase64 = dataEl.dataset.encrypted
        const nonceBase64 = dataEl.dataset.nonce

        if (!encryptedBase64 || !nonceBase64) {
            console.warn('RoomVoicePlayer: Missing encrypted data')
            return
        }

        // Get UI elements
        const playBtn = this.el.querySelector('.room-voice-play-btn')
        const timeDisplay = this.el.querySelector('.room-voice-time')
        const waveformBars = this.el.querySelectorAll('.room-voice-bar')

        if (!playBtn) return

        // Decrypt audio on first play
        let audioBlob = null

        playBtn.addEventListener('click', async (e) => {
            e.stopPropagation()

            if (this.isPlaying && this.audio) {
                this.audio.pause()
                this.audio.currentTime = 0
                this.isPlaying = false
                playBtn.innerHTML = `<svg class="w-4 h-4 ml-0.5" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>`
                return
            }

            try {
                // Decrypt if not already done
                if (!audioBlob) {
                    const conversationId = `room:${roomId}`
                    console.log("[RoomVoicePlayer] Decrypting for:", conversationId)
                    const key = await messageEncryption.loadOrCreateConversationKey(conversationId)

                    let encryptedBytes = messageEncryption.base64ToArray(encryptedBase64)
                    let nonceBytes = messageEncryption.base64ToArray(nonceBase64)

                    // Debug: Log sizes to diagnose decryption issues
                    console.log("[RoomVoicePlayer] encryptedBase64 length:", encryptedBase64.length)
                    console.log("[RoomVoicePlayer] encryptedBytes length:", encryptedBytes.length)
                    console.log("[RoomVoicePlayer] nonceBytes length:", nonceBytes.length)

                    // Fix for potentially double-encoded data (DB storing Base64 string as bytes)
                    // Only attempt fix if nonce length is exactly 16 (base64 of 12 bytes) AND
                    // the encrypted content size is unreasonably small after decoding (< 100 bytes suggests corruption)
                    if (nonceBytes.length === 16 && encryptedBytes.length < 100) {
                        try {
                            const str = Array.from(nonceBytes).map(b => String.fromCharCode(b)).join('')
                            // Check if it looks like Base64 (alphanumeric + +/ = )
                            if (/^[A-Za-z0-9+/=]+$/.test(str)) {
                                const decoded = atob(str)
                                if (decoded.length === 12) {
                                    console.warn("[RoomVoicePlayer] Detected double-encoded nonce, fixing.")
                                    nonceBytes = new Uint8Array(decoded.length)
                                    for (let i = 0; i < decoded.length; i++) nonceBytes[i] = decoded.charCodeAt(i)

                                    // If nonce was double encoded, likely encrypted content was too
                                    const encStr = Array.from(encryptedBytes).map(b => String.fromCharCode(b)).join('')
                                    const encDecoded = atob(encStr)
                                    encryptedBytes = new Uint8Array(encDecoded.length)
                                    for (let i = 0; i < encDecoded.length; i++) encryptedBytes[i] = encDecoded.charCodeAt(i)
                                    console.warn("[RoomVoicePlayer] Fixed encrypted content size:", encryptedBytes.length)
                                }
                            }
                        } catch (e) {
                            console.warn("Failed to fix double-encoding:", e)
                        }
                    }

                    // decryptWithKey returns string for text, we need raw bytes for audio
                    const decryptedBytes = await window.crypto.subtle.decrypt(
                        { name: "AES-GCM", iv: nonceBytes },
                        key,
                        encryptedBytes
                    )
                    audioBlob = new Blob([decryptedBytes], { type: 'audio/webm' })
                }

                const audioUrl = URL.createObjectURL(audioBlob)
                this.audio = new Audio(audioUrl)

                this.audio.onplay = () => {
                    this.isPlaying = true
                    playBtn.innerHTML = `<svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg>`
                }

                this.audio.onended = () => {
                    this.isPlaying = false
                    playBtn.innerHTML = `<svg class="w-4 h-4 ml-0.5" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>`
                }

                this.audio.onerror = (e) => {
                    console.error("Audio playback error", e)
                    this.isPlaying = false
                    playBtn.innerHTML = `<svg class="w-4 h-4 ml-0.5" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>`
                }

                await this.audio.play()

                this.audio.ontimeupdate = () => {
                    if (timeDisplay) {
                        timeDisplay.textContent = formatTime(this.audio.currentTime)
                    }
                    // Animate waveform bars based on playback progress
                    if (waveformBars.length > 0 && this.audio.duration) {
                        const progress = this.audio.currentTime / this.audio.duration
                        const activeBar = Math.floor(progress * waveformBars.length)
                        waveformBars.forEach((bar, i) => {
                            if (i <= activeBar) {
                                bar.style.opacity = '1'
                            } else {
                                bar.style.opacity = '0.5'
                            }
                        })
                    }
                }

                this.audio.onended = () => {
                    this.isPlaying = false
                    playBtn.innerHTML = `<svg class="w-4 h-4 ml-0.5" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>`
                    if (timeDisplay) timeDisplay.textContent = '0:00'
                    waveformBars.forEach(bar => bar.style.opacity = '0.5')
                }

                this.audio.onerror = (err) => {
                    console.error('RoomVoicePlayer: Audio error', err)
                    this.isPlaying = false
                }

                await this.audio.play()
            } catch (err) {
                console.error('RoomVoicePlayer: Playback/decryption error', err)
            }
        })
    },

    destroyed() {
        if (this.audio) {
            this.audio.pause()
            this.audio = null
        }
    }
}

function formatTime(seconds) {
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins}:${secs.toString().padStart(2, '0')}`
}

export default {
    VoiceWaveform: VoiceWaveformHook,
    FeedVoiceRecorder: FeedVoiceRecorderHook,
    FeedVoicePlayer: FeedVoicePlayerHook,
    GridVoiceRecorder: GridVoiceRecorderHook,
    RoomVoiceRecorder: RoomVoiceRecorderHook,
    RoomVoicePlayer: RoomVoicePlayerHook,
    VoicePlayer: VoicePlayerHook
}
