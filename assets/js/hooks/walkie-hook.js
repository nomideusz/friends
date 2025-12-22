/**
 * Walkie-Talkie Hook
 * Hold-to-speak live audio streaming for private rooms
 * Audio is encrypted and streamed in chunks via PubSub
 */

import * as messageEncryption from '../message-encryption'

export const WalkieTalkieHook = {
    mounted() {
        this.isTransmitting = false
        this.mediaRecorder = null
        this.audioContext = null
        this.audioQueue = []
        this.isPlaying = false
        this.roomId = this.el.dataset.roomId
        this.encryptionKey = null

        // Get the talk button
        const talkBtn = this.el.querySelector('.walkie-talk-btn')
        if (!talkBtn) {
            console.warn('WalkieTalkie: No talk button found')
            return
        }

        // Load encryption key on mount
        this.loadKey()

        // Hold-to-talk: mouse events
        talkBtn.addEventListener('mousedown', (e) => this.startTransmit(e))
        talkBtn.addEventListener('mouseup', () => this.stopTransmit())
        talkBtn.addEventListener('mouseleave', () => this.stopTransmit())

        // Hold-to-talk: touch events for mobile
        talkBtn.addEventListener('touchstart', (e) => {
            e.preventDefault()
            this.startTransmit(e)
        })
        talkBtn.addEventListener('touchend', () => this.stopTransmit())
        talkBtn.addEventListener('touchcancel', () => this.stopTransmit())

        // Handle incoming audio chunks from other users
        this.handleEvent('walkie_chunk', async (payload) => {
            await this.playChunk(payload)
        })

        // Handle transmission state from other users
        this.handleEvent('walkie_start', (payload) => {
            this.showTransmitting(payload.username)
        })

        this.handleEvent('walkie_stop', () => {
            this.hideTransmitting()
        })
    },

    async loadKey() {
        try {
            const conversationId = `room:${this.roomId}`
            this.encryptionKey = await messageEncryption.loadOrCreateConversationKey(conversationId)
        } catch (err) {
            console.error('WalkieTalkie: Failed to load encryption key', err)
        }
    },

    async startTransmit(e) {
        if (this.isTransmitting) return
        if (!this.encryptionKey) {
            await this.loadKey()
            if (!this.encryptionKey) return
        }

        try {
            const stream = await navigator.mediaDevices.getUserMedia({
                audio: {
                    echoCancellation: true,
                    noiseSuppression: true,
                    autoGainControl: true
                }
            })

            // Use timeslice for chunked recording (200ms chunks)
            this.mediaRecorder = new MediaRecorder(stream, {
                mimeType: 'audio/webm;codecs=opus'
            })

            this.mediaRecorder.ondataavailable = async (e) => {
                if (e.data.size > 0 && this.isTransmitting) {
                    await this.sendChunk(e.data)
                }
            }

            this.mediaRecorder.onstop = () => {
                stream.getTracks().forEach(track => track.stop())
            }

            // Start recording with 200ms timeslice
            this.mediaRecorder.start(200)
            this.isTransmitting = true

            // Visual feedback
            this.el.classList.add('walkie-active')

            // Notify server
            this.pushEvent('walkie_start', {})

        } catch (err) {
            console.error('WalkieTalkie: Failed to start', err)
        }
    },

    stopTransmit() {
        if (!this.isTransmitting) return

        this.isTransmitting = false

        if (this.mediaRecorder && this.mediaRecorder.state !== 'inactive') {
            this.mediaRecorder.stop()
        }

        // Visual feedback
        this.el.classList.remove('walkie-active')

        // Notify server
        this.pushEvent('walkie_stop', {})
    },

    async sendChunk(blob) {
        try {
            const arrayBuffer = await blob.arrayBuffer()
            const audioBytes = new Uint8Array(arrayBuffer)

            // Encrypt the chunk
            const { encrypted, nonce } = await messageEncryption.encryptBytesWithKey(
                audioBytes,
                this.encryptionKey
            )

            // Send via LiveView
            this.pushEvent('walkie_chunk', {
                encrypted_audio: messageEncryption.arrayToBase64(encrypted),
                nonce: messageEncryption.arrayToBase64(nonce)
            })
        } catch (err) {
            console.error('WalkieTalkie: Failed to send chunk', err)
        }
    },

    async playChunk(payload) {
        try {
            if (!this.encryptionKey) {
                await this.loadKey()
            }

            const encryptedBytes = messageEncryption.base64ToArray(payload.encrypted_audio)
            const nonceBytes = messageEncryption.base64ToArray(payload.nonce)

            // Decrypt
            const decryptedBuffer = await window.crypto.subtle.decrypt(
                { name: "AES-GCM", iv: nonceBytes },
                this.encryptionKey,
                encryptedBytes
            )

            // Queue for playback
            this.audioQueue.push(decryptedBuffer)
            this.processQueue()

        } catch (err) {
            console.error('WalkieTalkie: Failed to play chunk', err)
        }
    },

    async processQueue() {
        if (this.isPlaying || this.audioQueue.length === 0) return

        this.isPlaying = true

        while (this.audioQueue.length > 0) {
            const buffer = this.audioQueue.shift()
            await this.playBuffer(buffer)
        }

        this.isPlaying = false
    },

    async playBuffer(arrayBuffer) {
        return new Promise((resolve) => {
            try {
                if (!this.audioContext) {
                    this.audioContext = new (window.AudioContext || window.webkitAudioContext)()
                }

                // Create blob and play via Audio element (more reliable for webm)
                const blob = new Blob([arrayBuffer], { type: 'audio/webm' })
                const url = URL.createObjectURL(blob)
                const audio = new Audio(url)

                audio.onended = () => {
                    URL.revokeObjectURL(url)
                    resolve()
                }

                audio.onerror = () => {
                    URL.revokeObjectURL(url)
                    resolve()
                }

                audio.play().catch(() => resolve())

            } catch (err) {
                console.error('WalkieTalkie: Playback error', err)
                resolve()
            }
        })
    },

    showTransmitting(username) {
        const indicator = this.el.querySelector('.walkie-indicator')
        if (indicator) {
            indicator.textContent = `${username} is talking...`
            indicator.classList.remove('hidden')
        }
    },

    hideTransmitting() {
        const indicator = this.el.querySelector('.walkie-indicator')
        if (indicator) {
            indicator.classList.add('hidden')
        }
    },

    destroyed() {
        this.stopTransmit()
        if (this.audioContext) {
            this.audioContext.close()
        }
    }
}

export default { WalkieTalkie: WalkieTalkieHook }
