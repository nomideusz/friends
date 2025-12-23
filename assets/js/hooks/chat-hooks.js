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
        this.scrollToBottom()
        this.decryptVisibleMessages()
    },

    updated() {
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
        const roomCode = this.el.dataset.roomCode
        if (!roomCode) return

        const key = await messageEncryption.loadOrCreateConversationKey(`room:${roomCode}`)
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

        // The element itself is a form now, or find form inside
        const form = this.el.tagName === 'FORM' ? this.el : this.el.querySelector('form')
        const input = this.el.querySelector('input[name="message"]') || this.el.querySelector('[contenteditable]')
        
        // Send message function
        const sendMessage = async () => {
            if (!input) return
            const text = input.textContent !== undefined ? input.textContent : input.value
            if (!text || !text.trim()) return

            try {
                const { encrypted, nonce } = await messageEncryption.encryptWithKey(text.trim(), this.key)
                const encryptedBase64 = btoa(String.fromCharCode(...encrypted))
                const nonceBase64 = btoa(String.fromCharCode(...nonce))

                this.pushEvent("send_room_message", {
                    encrypted_content: encryptedBase64,
                    nonce: nonceBase64,
                    content_type: "text"
                })

                // Clear input
                if (input.textContent !== undefined) {
                    input.textContent = ''
                } else {
                    input.value = ''
                }
            } catch (err) {
                console.error('Failed to encrypt/send message:', err)
            }
        }

        // Handle form submit
        if (form) {
            form.addEventListener('submit', async (e) => {
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

export default {
    MessageEncryption: MessageEncryptionHook,
    MessagesScroll: MessagesScrollHook,
    RoomChatScroll: RoomChatScrollHook,
    RoomChatEncryption: RoomChatEncryptionHook,
    ContentEditableInput: ContentEditableInputHook
}
