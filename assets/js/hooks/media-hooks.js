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
                        const arrayBuffer = await blob.arrayBuffer()
                        const bytes = new Uint8Array(arrayBuffer)
                        let binary = ''
                        for (let i = 0; i < bytes.length; i++) {
                            binary += String.fromCharCode(bytes[i])
                        }
                        const base64 = btoa(binary)

                        this.pushEvent("room_voice_recorded", {
                            audio_data: base64,
                            duration_ms: durationMs
                        })
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

function formatTime(seconds) {
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins}:${secs.toString().padStart(2, '0')}`
}

export default {
    VoiceWaveform: VoiceWaveformHook,
    FeedVoiceRecorder: FeedVoiceRecorderHook,
    GridVoiceRecorder: GridVoiceRecorderHook,
    RoomVoiceRecorder: RoomVoiceRecorderHook,
    VoicePlayer: VoicePlayerHook
}
