/**
 * Authentication-related LiveView hooks
 * Handles: WebAuthnAuth, WebAuthnLogin, WebAuthnManager, RegisterApp, RecoverApp, LinkDeviceApp
 */

import { isWebAuthnSupported, isPlatformAuthenticatorAvailable, registerCredential, authenticateWithCredential } from '../webauthn'
import QRCode from 'qrcode'

export const WebAuthnAuthHook = {
    mounted() {
        const webauthnAvailable = isWebAuthnSupported()
        this.pushEvent("webauthn_available", { available: webauthnAvailable })

        this.handleEvent("webauthn_auth_challenge", async ({ mode, options }) => {
            try {
                if (mode === "login") {
                    const credential = await authenticateWithCredential(options)
                    this.pushEvent("webauthn_login_response", { credential })
                } else {
                    const credential = await registerCredential(options)
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

        this.handleEvent("auth_success", ({ user_id }) => {
            document.cookie = `friends_user_id=${user_id}; path=/; max-age=${60 * 60 * 24 * 365}; SameSite=Lax`
            window.location.href = '/'
        })
    }
}

export const WebAuthnLoginHook = {
    mounted() {
        this.handleEvent("webauthn_login_challenge", async ({ options }) => {
            try {
                const credential = await authenticateWithCredential(options)
                this.pushEvent("webauthn_login_response", { credential: credential })
            } catch (error) {
                console.error('[WebAuthnLogin] Error:', error)
                this.pushEvent("webauthn_login_error", {
                    error: error.name === 'NotAllowedError'
                        ? 'Authentication cancelled'
                        : error.message || 'Unknown error'
                })
            }
        })

        this.handleEvent("login_success", ({ user_id }) => {
            document.cookie = `friends_user_id=${user_id}; path=/; max-age=${60 * 60 * 24 * 365}; SameSite=Lax`
            window.location.href = '/'
        })
    }
}

export const WebAuthnManagerHook = {
    mounted() {
        const registerBtn = this.el.querySelector('[data-action="register-passkey"]')
        if (registerBtn) {
            registerBtn.onclick = async () => {
                try {
                    const hasExisting = this.el.dataset.hasCredential === 'true'
                    if (hasExisting) {
                        if (!confirm('You already have a passkey. Register a new one? (Your existing passkey will remain valid)')) {
                            return
                        }
                    }
                    this.pushEvent("start_passkey_registration", {})
                } catch (error) {
                    console.error('[WebAuthnManager] Error:', error)
                }
            }
        }

        this.handleEvent("webauthn_register_challenge", async ({ options }) => {
            try {
                const credential = await registerCredential(options)
                this.pushEvent("webauthn_register_response", { credential })
            } catch (error) {
                console.error('[WebAuthnManager] Registration error:', error)
                this.pushEvent("webauthn_register_error", {
                    error: error.name === 'NotAllowedError'
                        ? 'Registration cancelled'
                        : error.message || 'Unknown error'
                })
            }
        })
    }
}

export const RegisterAppHook = {
    mounted() {
        const webauthnAvailable = isWebAuthnSupported()
        this.pushEvent("webauthn_available", { available: webauthnAvailable })

        this.handleEvent("webauthn_register_challenge", async ({ options }) => {
            try {
                const credential = await registerCredential(options)
                this.pushEvent("webauthn_register_response", { credential })
            } catch (error) {
                console.error('[RegisterApp] Error:', error)
                this.pushEvent("webauthn_register_error", {
                    error: error.name === 'NotAllowedError'
                        ? 'Registration cancelled'
                        : error.message || 'Unknown error'
                })
            }
        })

        this.handleEvent("registration_success", ({ user_id }) => {
            document.cookie = `friends_user_id=${user_id}; path=/; max-age=${60 * 60 * 24 * 365}; SameSite=Lax`
            window.location.href = '/'
        })
    }
}

export const RecoverAppHook = {
    mounted() {
        const webauthnAvailable = isWebAuthnSupported()
        this.pushEvent("webauthn_available", { available: webauthnAvailable })

        this.handleEvent("webauthn_register_challenge", async ({ options }) => {
            try {
                const credential = await registerCredential(options)
                this.pushEvent("webauthn_register_response", { credential })
            } catch (error) {
                console.error('[RecoverApp] Error:', error)
                this.pushEvent("webauthn_register_error", {
                    error: error.name === 'NotAllowedError'
                        ? 'Registration cancelled'
                        : error.message || 'Unknown error'
                })
            }
        })
    }
}

export const QRDisplayHook = {
    mounted() {
        this.updateQR()
    },
    updated() {
        this.updateQR()
    },
    updateQR() {
        const data = this.el.dataset.qr
        if (data) {
            QRCode.toCanvas(this.el.querySelector('canvas') || this.el, data, {
                width: 200,
                margin: 2,
                color: { dark: '#000', light: '#fff' }
            })
        }
    }
}

export const LinkDeviceAppHook = {
    mounted() {
        const webauthnAvailable = isWebAuthnSupported()
        this.pushEvent("webauthn_available", { available: webauthnAvailable })

        this.handleEvent("webauthn_register_challenge", async ({ options }) => {
            try {
                const credential = await registerCredential(options)
                this.pushEvent("webauthn_register_response", { credential })
            } catch (error) {
                console.error('[LinkDeviceApp] Error:', error)
                this.pushEvent("webauthn_register_error", {
                    error: error.name === 'NotAllowedError'
                        ? 'Registration cancelled'
                        : error.message || 'Unknown error'
                })
            }
        })
    }
}

export const WebAuthnPairingHook = {
    mounted() {
        // Get the challenge from data attribute
        const challengeData = this.el.dataset.challenge
        if (!challengeData) {
            console.error('[WebAuthnPairing] No challenge data found')
            return
        }

        const challenge = JSON.parse(challengeData)

        // Set up the registration button
        const registerBtn = this.el.querySelector('#start-registration')
        if (registerBtn) {
            registerBtn.onclick = async () => {
                registerBtn.disabled = true
                registerBtn.innerHTML = `
                    <svg class="w-5 h-5 animate-spin" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    Registering...
                `

                try {
                    const credential = await registerCredential(challenge)
                    this.pushEvent("complete_registration", { attestation: credential })
                } catch (error) {
                    console.error('[WebAuthnPairing] Error:', error)
                    registerBtn.disabled = false
                    registerBtn.innerHTML = `
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 11c0 3.517-1.009 6.799-2.753 9.571m-3.44-2.04l.054-.09A13.916 13.916 0 008 11a4 4 0 118 0c0 1.017-.07 2.019-.203 3m-2.118 6.844A21.88 21.88 0 0015.171 17m3.839 1.132c.645-2.266.99-4.659.99-7.132A8 8 0 008 4.07M3 15.364c.64-1.319 1-2.8 1-4.364 0-1.457.39-2.823 1.07-4" />
                        </svg>
                        Try Again
                    `

                    const errorMsg = error.name === 'NotAllowedError'
                        ? 'Registration cancelled'
                        : error.message || 'Unknown error'
                    alert(errorMsg)
                }
            }
        }
    }
}

export default {
    WebAuthnAuth: WebAuthnAuthHook,
    WebAuthnLogin: WebAuthnLoginHook,
    WebAuthnManager: WebAuthnManagerHook,
    RegisterApp: RegisterAppHook,
    RecoverApp: RecoverAppHook,
    QRDisplay: QRDisplayHook,
    LinkDeviceApp: LinkDeviceAppHook,
    WebAuthnPairing: WebAuthnPairingHook
}
