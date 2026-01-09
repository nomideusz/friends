/**
 * Chat and messaging-related LiveView hooks
 * Handles: Message encryption, chat scroll, room chat
 */

import * as messageEncryption from '../message-encryption'
import { VoiceRecorder } from '../voice-recorder'

export const MessageEncryptionHook = {
    async mounted() {
        const conversationId = this.el.dataset.conversationId
        if (!conversationId) return

        this.key = await messageEncryption.loadOrCreateConversationKey(conversationId)
        this.recorder = null
        this.isRecording = false

        // Decrypt visible messages on mount
        this.decryptVisibleMessages()

        // Handle send message
        const form = this.el.querySelector('form')
        if (form) {
            form.addEventListener('submit', async (e) => {
                e.preventDefault()
                const input = form.querySelector('input[name="message"]')
                if (!input || !input.value.trim()) return

                const { encrypted, nonce } = await messageEncryption.encryptWithKey(input.value, this.key)
                const encryptedBase64 = btoa(String.fromCharCode(...encrypted))
                const nonceBase64 = btoa(String.fromCharCode(...nonce))

                this.pushEvent("send_message", {
                    encrypted_content: encryptedBase64,
                    nonce: nonceBase64,
                    content_type: "text"
                })

                input.value = ''
            })
        }

        // Handle voice recording
        const voiceBtn = this.el.querySelector('[data-action="record-voice"]')
        if (voiceBtn) {
            voiceBtn.addEventListener('click', async () => {
                if (this.isRecording) {
                    if (this.recorder) this.recorder.stop()
                    this.isRecording = false
                } else {
                    this.recorder = new VoiceRecorder()
                    this.recorder.onStop = async (blob, durationMs) => {
                        const arrayBuffer = await blob.arrayBuffer()
                        const audioBytes = new Uint8Array(arrayBuffer)
                        const { encrypted, nonce } = await messageEncryption.encryptBytesWithKey(audioBytes, this.key)

                        const encryptedBase64 = btoa(String.fromCharCode(...encrypted))
                        const nonceBase64 = btoa(String.fromCharCode(...nonce))

                        this.pushEvent("send_message", {
                            encrypted_content: encryptedBase64,
                            nonce: nonceBase64,
                            content_type: "audio",
                            metadata: { duration: durationMs }
                        })
                    }

                    const started = await this.recorder.start()
                    if (started) this.isRecording = true
                }
            })
        }
    },

    updated() {
        this.decryptVisibleMessages()
    },

    async decryptVisibleMessages() {
        const messages = this.el.querySelectorAll('[data-encrypted-content]:not([data-decrypted])')

        for (const msg of messages) {
            try {
                const encryptedData = msg.dataset.encryptedContent
                const nonce = msg.dataset.nonce

                if (!encryptedData || !nonce) continue

                const encryptedBytes = Uint8Array.from(atob(encryptedData), c => c.charCodeAt(0))
                const nonceBytes = Uint8Array.from(atob(nonce), c => c.charCodeAt(0))

                const decrypted = await messageEncryption.decryptWithKey(encryptedBytes, nonceBytes, this.key)
                const decoder = new TextDecoder()
                msg.textContent = decoder.decode(decrypted)
                msg.setAttribute('data-decrypted', 'true')
            } catch (err) {
                console.error('Decryption error:', err)
            }
        }
    }
}

export const MessagesScrollHook = {
    mounted() {
        this.scrollToBottom()
        this.decryptVisibleMessages()
    },

    updated() {
        // Check if we should scroll (new message added)
        const atBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 100
        if (atBottom) {
            this.scrollToBottom()
        }
        this.decryptVisibleMessages()
    },

    scrollToBottom() {
        this.el.scrollTop = this.el.scrollHeight
    },

    async decryptVisibleMessages() {
        const conversationId = this.el.dataset.conversationId
        if (!conversationId) return

        const key = await messageEncryption.loadOrCreateConversationKey(conversationId)
        const messages = this.el.querySelectorAll('[data-encrypted-content]:not([data-decrypted])')

        for (const msg of messages) {
            try {
                const encryptedData = msg.dataset.encryptedContent
                const nonce = msg.dataset.nonce

                if (!encryptedData || !nonce) continue

                const encryptedBytes = Uint8Array.from(atob(encryptedData), c => c.charCodeAt(0))
                const nonceBytes = Uint8Array.from(atob(nonce), c => c.charCodeAt(0))

                const decrypted = await messageEncryption.decryptWithKey(encryptedBytes, nonceBytes, key)
                const decoder = new TextDecoder()
                msg.textContent = decoder.decode(decrypted)
                msg.setAttribute('data-decrypted', 'true')
            } catch (err) {
                console.error('Decryption error:', err)
            }
        }
    }
}

export const RoomChatScrollHook = {
    mounted() {
        console.log('RoomChatScrollHook mounted, roomId:', this.el.dataset.roomId)
        this.scrollToBottom()
        // Delay decryption to ensure DOM is fully rendered
        requestAnimationFrame(() => {
            this.decryptVisibleMessages()
        })

        // MutationObserver to detect new messages and force scroll
        this.observer = new MutationObserver((mutations) => {
            let hasNewMessages = false
            for (const mutation of mutations) {
                if (mutation.addedNodes.length > 0) {
                    hasNewMessages = true
                    break
                }
            }
            if (hasNewMessages) {
                // Small delay to ensure layout is complete
                setTimeout(() => this.scrollToBottom(), 50)
                this.decryptVisibleMessages()
            }
        })

        this.observer.observe(this.el, { childList: true, subtree: true })
    },

    updated() {
        // Always scroll on update, then check if we need to stay
        const wasAtBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 100

        // Force scroll with delay for layout completion
        setTimeout(() => {
            if (wasAtBottom || this._shouldForceScroll) {
                this.scrollToBottom()
                this._shouldForceScroll = false
            }
        }, 50)

        this.decryptVisibleMessages()
    },

    scrollToBottom() {
        this.el.scrollTop = this.el.scrollHeight
    },

    destroyed() {
        if (this.observer) {
            this.observer.disconnect()
        }
    },

    async decryptVisibleMessages() {
        // Use roomId to match how messages are encrypted (room:${roomId})
        const roomId = this.el.dataset.roomId
        console.log('decryptVisibleMessages called, roomId:', roomId)
        if (!roomId) {
            console.warn('No roomId found for decryption')
            return
        }

        const key = await messageEncryption.loadOrCreateConversationKey(`room:${roomId}`)
        const messages = this.el.querySelectorAll('[data-encrypted-content]:not([data-decrypted])')
        console.log('Found messages to decrypt:', messages.length)

        for (const msg of messages) {
            try {
                const encryptedData = msg.dataset.encryptedContent
                const nonce = msg.dataset.nonce

                if (!encryptedData || !nonce) continue

                const encryptedBytes = Uint8Array.from(atob(encryptedData), c => c.charCodeAt(0))
                const nonceBytes = Uint8Array.from(atob(nonce), c => c.charCodeAt(0))

                const decrypted = await messageEncryption.decryptWithKey(encryptedBytes, nonceBytes, key)
                // decryptWithKey already returns a string, use directly
                msg.textContent = decrypted
                msg.setAttribute('data-decrypted', 'true')
            } catch (err) {
                console.error('Decryption error:', err)
            }
        }
    }
}


export const RoomChatEncryptionHook = {
    async mounted() {
        const roomCode = this.el.dataset.roomCode
        if (!roomCode) {
            console.warn('RoomChatEncryption: No roomCode found')
            return
        }

        this.key = await messageEncryption.loadOrCreateConversationKey(`room:${roomCode}`)
        this.recorder = null
        this.isRecording = false
        this.typingTimer = null
        this.lastBroadcastText = ''
        this.TYPING_DELAY = 300 // 300ms delay for near-instant live typing

        // The element itself is a form now, or find form inside
        const form = this.el.tagName === 'FORM' ? this.el : this.el.querySelector('form')
        // Robust input finding: name, id, or just input tag
        const input = this.el.querySelector('input[name="message"]') ||
            this.el.querySelector('#unified-message-input') ||
            this.el.querySelector('input[type="text"]') ||
            this.el.querySelector('[contenteditable]')

        const sendBtn = this.el.querySelector('#send-unified-message-btn')
        const walkieContainer = this.el.querySelector('#walkie-talkie-container')

        // UI Update Helper - optimized to prevent flickering
        const updateUI = () => {
            if (!input || !sendBtn || !walkieContainer) return
            // Use value for inputs, textContent for contenteditable
            const val = input.value !== undefined ? input.value : input.textContent
            const hasText = val && val.trim().length > 0

            // Use requestAnimationFrame to batch DOM updates and prevent flickering
            requestAnimationFrame(() => {
                if (hasText) {
                    walkieContainer.style.display = 'none'
                    sendBtn.style.display = 'flex'
                    sendBtn.classList.remove('scale-90', 'bg-white/10', 'text-white/40')
                    sendBtn.classList.add('scale-100', 'bg-white', 'text-black')
                } else {
                    walkieContainer.style.display = 'block'
                    sendBtn.style.display = 'none'
                }
            })
        }

        // Initial check
        updateUI()

        // Broadcast typing with debounce (near-instant live typing)
        const broadcastTyping = (text) => {
            if (this.typingTimer) {
                clearTimeout(this.typingTimer)
            }

            this.typingTimer = setTimeout(() => {
                if (text && text.trim() && text !== this.lastBroadcastText) {
                    this.lastBroadcastText = text
                    this.pushEvent("typing", { text: text.trim() })
                }
            }, this.TYPING_DELAY)
        }

        // Stop typing broadcast
        const stopTyping = () => {
            if (this.typingTimer) {
                clearTimeout(this.typingTimer)
                this.typingTimer = null
            }
            if (this.lastBroadcastText) {
                this.lastBroadcastText = ''
                this.pushEvent("stop_typing", {})
            }
        }

        // Listen for typing on input
        if (input) {
            // Input event for immediate UI updates (higher priority)
            input.addEventListener('input', (e) => {
                // Update UI first for instant feedback
                updateUI()

                // Then handle typing broadcast
                const text = input.value || input.textContent || ''
                if (text.trim()) {
                    broadcastTyping(text)
                } else {
                    stopTyping()
                }
            })

            // Blur event to stop typing
            input.addEventListener('blur', () => {
                stopTyping()
            })
        }

        // Send message function
        const sendMessage = async () => {
            if (!input) return
            const text = input.textContent !== undefined ? input.textContent : input.value
            if (!text || !text.trim()) return

            try {
                // Stop typing indicator immediately
                stopTyping()

                const { encrypted, nonce } = await messageEncryption.encryptWithKey(text.trim(), this.key)
                const encryptedBase64 = btoa(String.fromCharCode(...encrypted))
                const nonceBase64 = btoa(String.fromCharCode(...nonce))

                this.pushEvent("send_room_message", {
                    encrypted_content: encryptedBase64,
                    nonce: nonceBase64,
                    content_type: "text"
                })

                // Clear input and update UI immediately
                if (input.textContent !== undefined) {
                    input.textContent = ''
                } else {
                    input.value = ''
                }
                // Update UI to show walkie-talkie again
                updateUI()
            } catch (err) {
                console.error('Failed to encrypt/send message:', err)
            }
        }

        // Handle form submit (if present)
        if (form) {
            form.addEventListener('submit', async (e) => {
                e.preventDefault()
                await sendMessage()
            })
        }

        // Handle Send Button click explicitly (if no form or as backup)
        if (sendBtn) {
            sendBtn.addEventListener('click', async (e) => {
                e.preventDefault()
                await sendMessage()
            })
        }

        // Handle Enter key on input as fallback
        if (input) {
            input.addEventListener('keydown', async (e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault()
                    await sendMessage()
                }
            })
        }

        // Handle voice recording
        const voiceBtn = this.el.querySelector('[data-action="record-room-voice"]')
        if (voiceBtn) {
            voiceBtn.addEventListener('click', async () => {
                if (this.isRecording) {
                    if (this.recorder) this.recorder.stop()
                    this.isRecording = false
                } else {
                    this.recorder = new VoiceRecorder()
                    this.recorder.onStop = async (blob, durationMs) => {
                        const arrayBuffer = await blob.arrayBuffer()
                        const audioBytes = new Uint8Array(arrayBuffer)
                        const { encrypted, nonce } = await messageEncryption.encryptBytesWithKey(audioBytes, this.key)

                        const encryptedBase64 = btoa(String.fromCharCode(...encrypted))
                        const nonceBase64 = btoa(String.fromCharCode(...nonce))

                        this.pushEvent("send_room_message", {
                            encrypted_content: encryptedBase64,
                            nonce: nonceBase64,
                            content_type: "audio",
                            metadata: { duration: durationMs }
                        })
                    }

                    const started = await this.recorder.start()
                    if (started) this.isRecording = true
                }
            })
        }

        // Walkie-talkie (hold to talk) - MediaRecorder implementation
        const walkieBtn = walkieContainer?.querySelector('.walkie-talk-btn')
        if (walkieBtn) {
            let mediaRecorder = null
            let mediaStream = null
            let isTransmitting = false
            // Fix race condition: if mouseup happens before start finishes
            this.shouldStopWalkie = false

            const startWalkie = async () => {
                if (isTransmitting) return // Already running

                this.shouldStopWalkie = false
                try {
                    // Visual feedback immediate with pulsing ring
                    walkieBtn.classList.add('bg-emerald-500', 'text-white', 'animate-pulse', 'scale-110', 'ring-2', 'ring-emerald-400')
                    walkieBtn.classList.remove('bg-white/10', 'text-white/60')

                    mediaStream = await navigator.mediaDevices.getUserMedia({
                        audio: {
                            echoCancellation: true,
                            noiseSuppression: true,
                            autoGainControl: true
                        }
                    })

                    // Race check
                    if (this.shouldStopWalkie) {
                        mediaStream.getTracks().forEach(t => t.stop())
                        stopWalkie()
                        return
                    }

                    // Use MediaRecorder with 200ms chunks
                    mediaRecorder = new MediaRecorder(mediaStream, {
                        mimeType: 'audio/webm;codecs=opus'
                    })

                    mediaRecorder.ondataavailable = async (e) => {
                        if (e.data.size > 0 && isTransmitting) {
                            const arrayBuffer = await e.data.arrayBuffer()
                            const audioBytes = new Uint8Array(arrayBuffer)

                            const key = await messageEncryption.loadOrCreateConversationKey(`room:${roomCode}`)
                            const { encrypted, nonce } = await messageEncryption.encryptBytesWithKey(audioBytes, key)

                            this.pushEvent("walkie_chunk", {
                                encrypted_audio: btoa(String.fromCharCode(...encrypted)),
                                nonce: btoa(String.fromCharCode(...nonce))
                            })
                        }
                    }

                    mediaRecorder.onstop = () => {
                        mediaStream.getTracks().forEach(track => track.stop())
                    }

                    // Start recording with 200ms timeslice
                    mediaRecorder.start(200)
                    isTransmitting = true

                    this.pushEvent("walkie_start", {})

                } catch (err) {
                    console.error('Walkie-talkie error:', err)
                    stopWalkie()
                }
            }

            const stopWalkie = () => {
                this.shouldStopWalkie = true
                isTransmitting = false

                if (mediaRecorder && mediaRecorder.state !== 'inactive') {
                    mediaRecorder.stop()
                }
                mediaRecorder = null

                if (mediaStream) {
                    mediaStream.getTracks().forEach(t => t.stop())
                    mediaStream = null
                }

                this.pushEvent("walkie_stop", {})

                // Reset button state
                walkieBtn.classList.remove('bg-emerald-500', 'text-white', 'animate-pulse', 'scale-110', 'ring-2', 'ring-emerald-400')
                walkieBtn.classList.add('bg-white/10', 'text-white/60')
            }

            // Touch events with touchmove prevention to keep recording during finger drift
            walkieBtn.addEventListener('touchstart', (e) => {
                e.preventDefault()
                e.stopPropagation()
                startWalkie()
            }, { passive: false })

            walkieBtn.addEventListener('touchmove', (e) => {
                // Prevent scroll and keep recording active during finger movement
                e.preventDefault()
            }, { passive: false })

            walkieBtn.addEventListener('touchend', (e) => {
                e.preventDefault()
                stopWalkie()
            })
            walkieBtn.addEventListener('touchcancel', stopWalkie)

            // Mouse events
            walkieBtn.addEventListener('mousedown', startWalkie)
            walkieBtn.addEventListener('mouseup', stopWalkie)
            walkieBtn.addEventListener('mouseleave', stopWalkie)
        }
    },

    destroyed() {
        if (this.typingTimer) {
            clearTimeout(this.typingTimer)
        }
    }
}

export const ContentEditableInputHook = {
    mounted() {
        this.lastValue = ''

        // Sync contenteditable with hidden input
        this.el.addEventListener('input', () => {
            const text = this.el.textContent
            if (text !== this.lastValue) {
                this.lastValue = text
                this.pushEvent("update_chat_message", { message: text })
            }
        })

        // Handle Enter key
        this.el.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault()
                const sendBtn = document.getElementById('send-unified-message-btn')
                if (sendBtn) sendBtn.click()
            }
        })

        // Handle paste - strip formatting
        this.el.addEventListener('paste', (e) => {
            e.preventDefault()
            const text = e.clipboardData.getData('text/plain')
            document.execCommand('insertText', false, text)
        })

        // Clear input after message sent
        this.handleEvent('clear_chat_input', () => {
            this.el.textContent = ''
            this.lastValue = ''
        })
    },

    updated() {
        if (this.el.dataset.shouldClear === 'true') {
            this.el.textContent = ''
            this.lastValue = ''
            this.el.removeAttribute('data-should-clear')
        }
    }
}

/**
 * ChatInputFocus Hook
 * Auto-focuses the chat input when the chat sheet opens
 */
export const ChatInputFocusHook = {
    mounted() {
        // Auto-focus the input with a small delay for animation
        setTimeout(() => {
            this.el.focus()
        }, 150)
    },

    updated() {
        // Re-focus if needed after updates
        if (document.activeElement !== this.el && this.el.closest('.fixed')) {
            this.el.focus()
        }
    }
}

/**
 * ChatRadialMenu Hook
 * Handles the expandable radial action menu for voice/walkie-talkie
 */
export const ChatRadialMenuHook = {
    mounted() {
        this.isOpen = false
        this.isRecording = false
        this.recorder = null

        const roomId = this.el.dataset.roomId
        const radialOptions = this.el.querySelector('.radial-options')
        const toggleBtn = this.el.querySelector('.radial-toggle')
        const defaultIcon = this.el.querySelector('.radial-icon-default')
        const closeIcon = this.el.querySelector('.radial-icon-close')
        const photoBtn = this.el.querySelector('.radial-photo-btn')
        const noteBtn = this.el.querySelector('.radial-note-btn')
        const voiceBtn = this.el.querySelector('.radial-voice-btn')
        const walkieBtn = this.el.querySelector('.radial-walkie-btn')
        const backdrop = this.el.querySelector('.radial-backdrop')

        // Toggle radial menu
        const toggleMenu = (open) => {
            this.isOpen = open !== undefined ? open : !this.isOpen

            if (this.isOpen) {
                radialOptions.classList.remove('hidden')
                defaultIcon.classList.add('hidden')
                closeIcon.classList.remove('hidden')
                toggleBtn.classList.add('bg-white/20', 'text-white')
            } else {
                radialOptions.classList.add('hidden')
                defaultIcon.classList.remove('hidden')
                closeIcon.classList.add('hidden')
                toggleBtn.classList.remove('bg-white/20', 'text-white')
            }
        }

        // Toggle button click
        toggleBtn.addEventListener('click', () => toggleMenu())

        // Close on backdrop click
        if (backdrop) {
            backdrop.addEventListener('click', () => toggleMenu(false))
        }

        // Photo button - trigger the hidden file input
        if (photoBtn) {
            photoBtn.addEventListener('click', () => {
                // Find the global hidden upload form and trigger it
                const fileInput = document.querySelector('#global-upload-form input[type="file"]')
                if (fileInput) {
                    fileInput.click()
                }
                toggleMenu(false)
            })
        }

        // Note button - open the note modal via LiveView
        if (noteBtn) {
            noteBtn.addEventListener('click', () => {
                this.pushEvent("open_room_note_modal", {})
                toggleMenu(false)
            })
        }


        // Voice recording
        if (voiceBtn) {
            voiceBtn.addEventListener('click', async () => {
                if (this.isRecording) {
                    // Stop recording
                    if (this.recorder) this.recorder.stop()
                    this.isRecording = false
                    voiceBtn.classList.remove('animate-pulse', 'ring-2', 'ring-red-500')
                } else {
                    // Start recording
                    const { VoiceRecorder } = await import('../voice-recorder')
                    this.recorder = new VoiceRecorder()

                    this.recorder.onStop = async (blob, durationMs) => {
                        const arrayBuffer = await blob.arrayBuffer()
                        const audioBytes = new Uint8Array(arrayBuffer)

                        // Get encryption key
                        const messageEncryption = await import('../message-encryption')
                        const key = await messageEncryption.loadOrCreateConversationKey(`room:${roomId}`)
                        const { encrypted, nonce } = await messageEncryption.encryptBytesWithKey(audioBytes, key)

                        const encryptedBase64 = btoa(String.fromCharCode(...encrypted))
                        const nonceBase64 = btoa(String.fromCharCode(...nonce))

                        this.pushEvent("send_room_voice_note", {
                            encrypted_content: encryptedBase64,
                            nonce: nonceBase64,
                            duration_ms: durationMs
                        })

                        toggleMenu(false)
                    }

                    const started = await this.recorder.start()
                    if (started) {
                        this.isRecording = true
                        voiceBtn.classList.add('animate-pulse', 'ring-2', 'ring-red-500')
                    }
                }
            })
        }

        // Walkie-talkie (hold to talk)
        if (walkieBtn) {
            let audioContext = null
            let mediaStream = null
            let processor = null

            const startWalkie = async () => {
                try {
                    mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true })
                    audioContext = new AudioContext()
                    const source = audioContext.createMediaStreamSource(mediaStream)

                    // Create processor for live audio
                    processor = audioContext.createScriptProcessor(4096, 1, 1)
                    source.connect(processor)
                    processor.connect(audioContext.destination)

                    this.pushEvent("walkie_start", {})
                    walkieBtn.classList.add('bg-emerald-500', 'scale-110')

                    processor.onaudioprocess = async (e) => {
                        const audioData = e.inputBuffer.getChannelData(0)
                        const bytes = new Uint8Array(audioData.buffer)

                        // Get encryption key and encrypt
                        const messageEncryption = await import('../message-encryption')
                        const key = await messageEncryption.loadOrCreateConversationKey(`room:${roomId}`)
                        const { encrypted, nonce } = await messageEncryption.encryptBytesWithKey(bytes, key)

                        const encryptedBase64 = btoa(String.fromCharCode(...encrypted))
                        const nonceBase64 = btoa(String.fromCharCode(...nonce))

                        this.pushEvent("walkie_chunk", {
                            encrypted_audio: encryptedBase64,
                            nonce: nonceBase64
                        })
                    }
                } catch (err) {
                    console.error('Walkie-talkie error:', err)
                }
            }

            const stopWalkie = () => {
                if (processor) {
                    processor.disconnect()
                    processor = null
                }
                if (audioContext) {
                    audioContext.close()
                    audioContext = null
                }
                if (mediaStream) {
                    mediaStream.getTracks().forEach(t => t.stop())
                    mediaStream = null
                }
                this.pushEvent("walkie_stop", {})
                walkieBtn.classList.remove('bg-emerald-500', 'scale-110')
            }

            // Touch events for mobile
            walkieBtn.addEventListener('touchstart', (e) => {
                e.preventDefault()
                startWalkie()
            })
            walkieBtn.addEventListener('touchend', stopWalkie)
            walkieBtn.addEventListener('touchcancel', stopWalkie)

            // Mouse events for desktop
            walkieBtn.addEventListener('mousedown', startWalkie)
            walkieBtn.addEventListener('mouseup', stopWalkie)
            walkieBtn.addEventListener('mouseleave', stopWalkie)
        }

        // Close menu on escape
        this.escHandler = (e) => {
            if (e.key === 'Escape' && this.isOpen) {
                toggleMenu(false)
            }
        }
        document.addEventListener('keydown', this.escHandler)
    },

    destroyed() {
        if (this.escHandler) {
            document.removeEventListener('keydown', this.escHandler)
        }
    }
}

/**
 * InlineChatInput Hook
 * Handles the inline chat panel at the bottom of the room
 */
export const InlineChatInputHook = {
    async mounted() {
        this.isMenuOpen = false
        this.isRecording = false
        this.recorder = null

        const roomId = this.el.dataset.roomId
        const actionToggle = this.el.querySelector('.action-toggle')
        const actionMenu = this.el.querySelector('.action-menu')
        const plusIcon = this.el.querySelector('.action-icon-plus')
        const closeIcon = this.el.querySelector('.action-icon-close')
        const photoBtn = this.el.querySelector('.action-photo')
        const noteBtn = this.el.querySelector('.action-note')
        const voiceBtn = this.el.querySelector('.action-voice')
        const walkieBtn = this.el.querySelector('.walkie-btn')  // Dedicated button outside menu
        const chatInput = this.el.querySelector('.chat-input')
        const sendBtn = this.el.querySelector('.send-btn')

        // Auto-focus input when chat opens
        setTimeout(() => {
            if (chatInput) chatInput.focus()
        }, 100)

        // Click outside to collapse chat - listen on the content area above
        this.clickOutsideHandler = (e) => {
            const chatPanel = this.el.closest('[class*="fixed bottom-0"]')
            if (chatPanel && !chatPanel.contains(e.target)) {
                // Check if chat is expanded (has h-[50vh] class)
                if (chatPanel.classList.contains('h-[50vh]') || chatPanel.className.includes('h-[50vh]')) {
                    this.pushEvent("toggle_chat_expanded", {})
                }
            }
        }
        document.addEventListener('click', this.clickOutsideHandler)

        // Toggle action menu
        const toggleMenu = (open) => {
            this.isMenuOpen = open !== undefined ? open : !this.isMenuOpen
            if (this.isMenuOpen) {
                actionMenu.classList.remove('hidden')
                plusIcon.classList.add('hidden')
                closeIcon.classList.remove('hidden')
            } else {
                actionMenu.classList.add('hidden')
                plusIcon.classList.remove('hidden')
                closeIcon.classList.add('hidden')
            }
        }

        if (actionToggle) {
            actionToggle.addEventListener('click', () => toggleMenu())
        }

        // Close menu on click outside
        document.addEventListener('click', (e) => {
            if (this.isMenuOpen && !this.el.contains(e.target)) {
                toggleMenu(false)
            }
        })

        // Photo action
        if (photoBtn) {
            photoBtn.addEventListener('click', () => {
                const fileInput = document.querySelector('#global-upload-form input[type="file"]')
                if (fileInput) fileInput.click()
                toggleMenu(false)
            })
        }

        // Note action
        if (noteBtn) {
            noteBtn.addEventListener('click', () => {
                this.pushEvent("open_room_note_modal", {})
                toggleMenu(false)
            })
        }

        // Voice recording
        if (voiceBtn) {
            voiceBtn.addEventListener('click', async () => {
                if (this.isRecording) {
                    if (this.recorder) this.recorder.stop()
                    this.isRecording = false
                    voiceBtn.classList.remove('bg-red-500/20', 'text-red-400')
                } else {
                    const { VoiceRecorder } = await import('../voice-recorder')
                    this.recorder = new VoiceRecorder()

                    this.recorder.onStop = async (blob, durationMs) => {
                        const arrayBuffer = await blob.arrayBuffer()
                        const audioBytes = new Uint8Array(arrayBuffer)

                        const messageEncryption = await import('../message-encryption')
                        const key = await messageEncryption.loadOrCreateConversationKey(`room:${roomId}`)
                        const { encrypted, nonce } = await messageEncryption.encryptBytesWithKey(audioBytes, key)

                        const encryptedBase64 = btoa(String.fromCharCode(...encrypted))
                        const nonceBase64 = btoa(String.fromCharCode(...nonce))

                        this.pushEvent("send_room_voice_note", {
                            encrypted_content: encryptedBase64,
                            nonce: nonceBase64,
                            duration_ms: durationMs
                        })

                        toggleMenu(false)
                    }

                    const started = await this.recorder.start()
                    if (started) {
                        this.isRecording = true
                        voiceBtn.classList.add('bg-red-500/20', 'text-red-400')
                    }
                }
            })
        }

        // Walkie-talkie (hold to talk) - MediaRecorder implementation
        if (walkieBtn) {
            let mediaRecorder = null
            let mediaStream = null
            let isTransmitting = false
            // Fix race condition: if mouseup happens before start finishes
            this.shouldStopWalkie = false

            const startWalkie = async () => {
                if (isTransmitting) return // Already running

                this.shouldStopWalkie = false
                try {
                    // Visual feedback immediate with pulsing ring
                    walkieBtn.classList.add('bg-emerald-500', 'text-white', 'animate-pulse', 'scale-110', 'ring-2', 'ring-emerald-400')
                    walkieBtn.classList.remove('bg-white/10', 'text-white/60')

                    mediaStream = await navigator.mediaDevices.getUserMedia({
                        audio: {
                            echoCancellation: true,
                            noiseSuppression: true,
                            autoGainControl: true
                        }
                    })

                    // Race check
                    if (this.shouldStopWalkie) {
                        mediaStream.getTracks().forEach(t => t.stop())
                        stopWalkie()
                        return
                    }

                    // Use MediaRecorder with 200ms chunks
                    mediaRecorder = new MediaRecorder(mediaStream, {
                        mimeType: 'audio/webm;codecs=opus'
                    })

                    mediaRecorder.ondataavailable = async (e) => {
                        if (e.data.size > 0 && isTransmitting) {
                            const arrayBuffer = await e.data.arrayBuffer()
                            const audioBytes = new Uint8Array(arrayBuffer)

                            const messageEncryption = await import('../message-encryption')
                            const key = await messageEncryption.loadOrCreateConversationKey(`room:${roomId}`)
                            const { encrypted, nonce } = await messageEncryption.encryptBytesWithKey(audioBytes, key)

                            this.pushEvent("walkie_chunk", {
                                encrypted_audio: btoa(String.fromCharCode(...encrypted)),
                                nonce: btoa(String.fromCharCode(...nonce))
                            })
                        }
                    }

                    mediaRecorder.onstop = () => {
                        mediaStream.getTracks().forEach(track => track.stop())
                    }

                    // Start recording with 200ms timeslice
                    mediaRecorder.start(200)
                    isTransmitting = true

                    this.pushEvent("walkie_start", {})

                } catch (err) {
                    console.error('Walkie-talkie error:', err)
                    stopWalkie()
                }
            }

            const stopWalkie = () => {
                this.shouldStopWalkie = true
                isTransmitting = false

                if (mediaRecorder && mediaRecorder.state !== 'inactive') {
                    mediaRecorder.stop()
                }
                mediaRecorder = null

                if (mediaStream) {
                    mediaStream.getTracks().forEach(t => t.stop())
                    mediaStream = null
                }

                this.pushEvent("walkie_stop", {})

                // Reset button state
                walkieBtn.classList.remove('bg-emerald-500', 'text-white', 'animate-pulse', 'scale-110', 'ring-2', 'ring-emerald-400')
                walkieBtn.classList.add('bg-white/10', 'text-white/60')
            }

            // Touch events with touchmove prevention to keep recording during finger drift
            walkieBtn.addEventListener('touchstart', (e) => {
                e.preventDefault()
                e.stopPropagation()
                startWalkie()
            }, { passive: false })

            walkieBtn.addEventListener('touchmove', (e) => {
                // Prevent scroll and keep recording active during finger movement
                e.preventDefault()
            }, { passive: false })

            walkieBtn.addEventListener('touchend', (e) => {
                e.preventDefault()
                stopWalkie()
            })
            walkieBtn.addEventListener('touchcancel', stopWalkie)

            // Mouse events
            walkieBtn.addEventListener('mousedown', startWalkie)
            walkieBtn.addEventListener('mouseup', stopWalkie)
            walkieBtn.addEventListener('mouseleave', stopWalkie)

            // Unified pointer events for better cross-platform support
            walkieBtn.addEventListener('pointerdown', (e) => {
                if (e.pointerType === 'touch') return // Already handled by touch events
                startWalkie()
            })
            walkieBtn.addEventListener('pointerup', (e) => {
                if (e.pointerType === 'touch') return
                stopWalkie()
            })
        }


        // Send message
        const sendMessage = async () => {
            const text = chatInput.value.trim()
            if (!text) return

            try {
                const messageEncryption = await import('../message-encryption')
                const key = await messageEncryption.loadOrCreateConversationKey(`room:${roomId}`)
                const { encrypted, nonce } = await messageEncryption.encryptWithKey(text, key)

                this.pushEvent("send_room_message", {
                    encrypted_content: btoa(String.fromCharCode(...encrypted)),
                    nonce: btoa(String.fromCharCode(...nonce)),
                    content_type: "text"
                })

                chatInput.value = ''
            } catch (err) {
                console.error('Failed to send message:', err)
            }
        }

        if (sendBtn) {
            sendBtn.addEventListener('click', sendMessage)
        }

        if (chatInput) {
            chatInput.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault()
                    sendMessage()
                }
            })

            // Typing indicator + auto-expand chat on first input
            chatInput.addEventListener('input', () => {
                // Auto-expand chat when user starts typing (if not already expanded)
                if (chatInput.value.length === 1) {
                    // Check if chat panel is collapsed by checking the container height
                    const panel = this.el.closest('[class*="h-auto"]')
                    if (panel) {
                        this.pushEvent("expand_chat", {})
                    }
                }
            })
        }

        // === Walkie-Talkie Audio Reception ===
        this.audioQueue = []
        this.isPlaying = false
        this.encryptionKey = null

        // Load encryption key for receiving walkie audio
        const loadWalkieKey = async () => {
            try {
                const messageEncryption = await import('../message-encryption')
                this.encryptionKey = await messageEncryption.loadOrCreateConversationKey(`room:${roomId}`)
            } catch (err) {
                console.error('Failed to load walkie encryption key', err)
            }
        }
        loadWalkieKey()

        // Handle incoming walkie audio chunks
        this.handleEvent('walkie_chunk', async (payload) => {
            try {
                if (!this.encryptionKey) {
                    await loadWalkieKey()
                }

                const messageEncryption = await import('../message-encryption')
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
                this.processAudioQueue()
            } catch (err) {
                console.error('Walkie playback error:', err)
            }
        })

        // Handle walkie start - show indicator
        this.handleEvent('walkie_start', (payload) => {
            const indicator = document.createElement('div')
            indicator.id = 'walkie-live-indicator'
            indicator.className = 'fixed top-4 left-1/2 -translate-x-1/2 px-3 py-1.5 bg-emerald-500/90 text-white text-xs rounded-full flex items-center gap-2 z-[200] animate-pulse'
            indicator.innerHTML = `<span class="w-2 h-2 bg-white rounded-full"></span> ${payload.username} is talking...`
            document.body.appendChild(indicator)
        })

        // Handle walkie stop - hide indicator
        this.handleEvent('walkie_stop', () => {
            const indicator = document.getElementById('walkie-live-indicator')
            if (indicator) indicator.remove()
        })
    },

    async processAudioQueue() {
        if (this.isPlaying || this.audioQueue.length === 0) return

        this.isPlaying = true

        while (this.audioQueue.length > 0) {
            const buffer = this.audioQueue.shift()
            await this.playAudioBuffer(buffer)
        }

        this.isPlaying = false
    },

    playAudioBuffer(arrayBuffer) {
        return new Promise((resolve) => {
            try {
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
                console.error('Audio playback error:', err)
                resolve()
            }
        })
    },

    destroyed() {
        // Clean up click-outside listener
        if (this.clickOutsideHandler) {
            document.removeEventListener('click', this.clickOutsideHandler)
        }
    }
}

/**
 * DecryptedPreview Hook
 * Decrypts a single message preview (used for collapsed chat state)
 */
export const DecryptedPreviewHook = {
    async mounted() {
        const roomId = this.el.dataset.roomId
        const encryptedContent = this.el.dataset.encryptedContent
        const nonce = this.el.dataset.nonce

        if (!roomId || !encryptedContent || !nonce) return

        try {
            const messageEncryption = await import('../message-encryption')
            const key = await messageEncryption.loadOrCreateConversationKey(`room:${roomId}`)

            const encryptedBytes = Uint8Array.from(atob(encryptedContent), c => c.charCodeAt(0))
            const nonceBytes = Uint8Array.from(atob(nonce), c => c.charCodeAt(0))

            const decrypted = await messageEncryption.decryptWithKey(encryptedBytes, nonceBytes, key)

            // Truncate to avoid huge previews
            const text = decrypted.length > 30 ? decrypted.substring(0, 30) + '...' : decrypted
            this.el.textContent = text
            this.el.classList.remove('text-white/30') // Remove placeholder style
            this.el.classList.add('text-white')
        } catch (err) {
            console.error('Preview decryption error:', err)
            this.el.textContent = 'Error decrypting'
        }
    }
}

/**
 * UnifiedChatUIHook
 * Handles dynamic UI updates for the unified input area:
 * 1. Toggles between Walkie Talkie and Send button based on input content
 * 2. Handles Enter key on mobile/desktop to submit form reliably
 */
export const UnifiedChatUIHook = {
    mounted() {
        console.log('UnifiedChatUIHook mounted')
        this.form = this.el.tagName === 'FORM' ? this.el : this.el.querySelector('form')
        if (!this.form) {
            console.error('UnifiedChatUIHook: Form not found')
            return
        }

        this.input = this.form.querySelector('#unified-message-input')
        this.sendBtn = this.form.querySelector('#send-unified-message-btn')
        this.walkieContainer = this.form.querySelector('#walkie-talkie-container')

        console.log('UnifiedChatUIHook found elements:', { input: !!this.input, sendBtn: !!this.sendBtn, walkieContainer: !!this.walkieContainer })

        // Initial state check
        this.updateUI()

        // Listen for input changes
        if (this.input) {
            this.input.addEventListener('input', () => this.updateUI())
            this.input.addEventListener('keyup', () => this.updateUI())

            // Handle Enter key (especially for mobile)
            this.input.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault()
                    // Force submit logic
                    const submitEvent = new Event('submit', { bubbles: true, cancelable: true })
                    if (this.form.dispatchEvent(submitEvent)) {
                        // If not prevented, try manual submission or let LiveView handle it via form submit
                    }

                    // For Phoenix LiveView, triggering submit on the form usually works if phx-submit is bound
                    // But if it relies on a button click being the trigger:
                    if (this.sendBtn) {
                        this.sendBtn.click()
                    }
                }
            })
        }
    },

    updated() {
        this.updateUI()
    },

    updateUI() {
        if (!this.input || !this.sendBtn || !this.walkieContainer) return

        const hasText = this.input.value && this.input.value.trim().length > 0

        // Use requestAnimationFrame to batch DOM updates and prevent flickering
        requestAnimationFrame(() => {
            if (hasText) {
                // Show Send, Hide Walkie
                this.walkieContainer.style.display = 'none'
                this.sendBtn.style.display = 'flex'
                this.sendBtn.classList.remove('scale-90', 'bg-white/10', 'text-white/40')
                this.sendBtn.classList.add('scale-100', 'bg-white', 'text-black')
            } else {
                // Show Walkie, Hide Send
                this.walkieContainer.style.display = 'block'
                this.sendBtn.style.display = 'none'
            }
        })
    }
}

export default {
    MessageEncryption: MessageEncryptionHook,
    MessagesScroll: MessagesScrollHook,
    RoomChatScroll: RoomChatScrollHook,
    RoomChatEncryption: RoomChatEncryptionHook,
    ChatRadialMenu: ChatRadialMenuHook,
    InlineChatInput: InlineChatInputHook,
    ContentEditableInput: ContentEditableInputHook,
    ChatInputFocus: ChatInputFocusHook,
    DecryptedPreview: DecryptedPreviewHook
}
