/**
 * WebAuthn Module
 *
 * Provides optional hardware-backed authentication using WebAuthn/FIDO2.
 * This allows users to use fingerprint, Face ID, hardware keys, etc.
 */

/**
 * Check if WebAuthn is supported in this browser
 * @returns {boolean}
 */
export function isWebAuthnSupported() {
    return window.PublicKeyCredential !== undefined &&
           navigator.credentials !== undefined
}

/**
 * Convert base64url to ArrayBuffer
 */
function base64urlToBuffer(base64url) {
    const base64 = base64url.replace(/-/g, '+').replace(/_/g, '/')
    const binary = atob(base64)
    const bytes = new Uint8Array(binary.length)
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i)
    }
    return bytes.buffer
}

/**
 * Convert ArrayBuffer to base64url
 */
function bufferToBase64url(buffer) {
    const bytes = new Uint8Array(buffer)
    let binary = ''
    for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i])
    }
    return btoa(binary)
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=/g, '')
}

/**
 * Register a new WebAuthn credential
 * @param {Object} options - Challenge options from server
 * @returns {Promise<Object>} - Credential response
 */
export async function registerCredential(options) {
    if (!isWebAuthnSupported()) {
        throw new Error('WebAuthn is not supported in this browser')
    }

    try {
        // Convert challenge from base64url to ArrayBuffer
        const publicKeyOptions = {
            ...options,
            challenge: base64urlToBuffer(options.challenge),
            user: {
                ...options.user,
                id: new TextEncoder().encode(options.user.id)
            }
        }

        // Create credential
        const credential = await navigator.credentials.create({
            publicKey: publicKeyOptions
        })

        if (!credential) {
            throw new Error('Failed to create credential')
        }

        // Get transports from credential response (critical for iOS Safari Face ID)
        // This tells the browser what type of authenticator was used
        const transports = credential.response.getTransports 
            ? credential.response.getTransports() 
            : []

        // Convert response to JSON-serializable format
        return {
            id: credential.id,
            rawId: bufferToBase64url(credential.rawId),
            type: credential.type,
            transports: transports,
            response: {
                clientDataJSON: bufferToBase64url(credential.response.clientDataJSON),
                attestationObject: bufferToBase64url(credential.response.attestationObject)
            }
        }
    } catch (error) {
        console.error('WebAuthn registration error:', error)
        throw error
    }
}

/**
 * Authenticate with a WebAuthn credential
 * @param {Object} options - Challenge options from server
 * @returns {Promise<Object>} - Authentication response
 */
export async function authenticateWithCredential(options) {
    if (!isWebAuthnSupported()) {
        throw new Error('WebAuthn is not supported in this browser')
    }

    try {
        // Convert challenge and credential IDs
        const publicKeyOptions = {
            ...options,
            challenge: base64urlToBuffer(options.challenge),
            allowCredentials: options.allowCredentials?.map(cred => ({
                ...cred,
                id: base64urlToBuffer(cred.id)
            }))
        }

        // Get credential
        const credential = await navigator.credentials.get({
            publicKey: publicKeyOptions
        })

        if (!credential) {
            throw new Error('Authentication failed')
        }

        // Convert response to JSON-serializable format
        return {
            id: credential.id,
            rawId: bufferToBase64url(credential.rawId),
            type: credential.type,
            response: {
                clientDataJSON: bufferToBase64url(credential.response.clientDataJSON),
                authenticatorData: bufferToBase64url(credential.response.authenticatorData),
                signature: bufferToBase64url(credential.response.signature),
                userHandle: credential.response.userHandle ?
                    bufferToBase64url(credential.response.userHandle) : null
            }
        }
    } catch (error) {
        console.error('WebAuthn authentication error:', error)
        throw error
    }
}

/**
 * Check platform authenticator availability (e.g., Touch ID, Face ID)
 * @returns {Promise<boolean>}
 */
export async function isPlatformAuthenticatorAvailable() {
    if (!isWebAuthnSupported()) {
        return false
    }

    try {
        return await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()
    } catch {
        return false
    }
}
