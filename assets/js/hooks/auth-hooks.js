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

export default {
    WebAuthnAuth: WebAuthnAuthHook,
    WebAuthnLogin: WebAuthnLoginHook,
    WebAuthnManager: WebAuthnManagerHook,
    RegisterApp: RegisterAppHook,
    RecoverApp: RecoverAppHook,
    QRDisplay: QRDisplayHook,
    LinkDeviceApp: LinkDeviceAppHook
}
