/**
 * WebAuthn Module
 *
 * Provides optional hardware-backed authentication using WebAuthn/FIDO2.
 * This allows users to use fingerprint, Face ID, hardware keys, etc.
 * 
 * Supports both:
 * - Browser WebAuthn API (Chrome, Safari, etc.)
 * - Native Capacitor passkeys (Android/iOS apps via capacitor-webauthn plugin)
 */

// Access Capacitor plugin through the global Capacitor.Plugins registry
// The capacitor-webauthn plugin registers as 'Webauthn'
function getNativePasskey() {
    try {
        if (typeof window !== 'undefined' &&
            window.Capacitor &&
            window.Capacitor.Plugins &&
            window.Capacitor.Plugins.Webauthn) {
            console.log('Native Webauthn plugin available via Capacitor.Plugins');
            return window.Capacitor.Plugins.Webauthn;
        }
    } catch (e) {
        console.log('Native Webauthn plugin not available:', e);
    }
    return null;
}

/**
 * Check if running in a Capacitor native app
 * @returns {boolean}
 */
export function isCapacitor() {
    return typeof window !== 'undefined' &&
        window.Capacitor !== undefined &&
        window.Capacitor.isNativePlatform();
}

/**
 * Check if WebAuthn is supported in this browser/environment
 * @returns {boolean}
 */
export function isWebAuthnSupported() {
    // In Capacitor native app, we use the native passkey plugin
    if (isCapacitor()) {
        return true; // Native plugin handles passkeys
    }

    // In browser, check for WebAuthn API
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
 * Convert a string to base64url encoding
 */
function stringToBase64url(str) {
    return btoa(unescape(encodeURIComponent(str)))
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=/g, '')
}

/**
 * Register a new WebAuthn credential (native or browser)
 * @param {Object} options - Challenge options from server
 * @returns {Promise<Object>} - Credential response
 */
export async function registerCredential(options) {
    // Use native passkey plugin in Capacitor
    const nativePlugin = getNativePasskey();
    if (isCapacitor() && nativePlugin) {
        return await registerCredentialNative(options, nativePlugin);
    }

    // Fall back to browser WebAuthn
    return await registerCredentialBrowser(options);
}

/**
 * Register credential using native Capacitor plugin
 */
async function registerCredentialNative(options, plugin) {
    try {
        console.log('Using native passkey registration');
        console.log('Options received:', JSON.stringify(options, null, 2));

        // The native plugin expects user.id as base64url encoded string
        // Always encode it since the server sends plain string (like "0")
        const userId = stringToBase64url(String(options.user.id));

        // The native plugin expects options in a specific format
        const nativeOptions = {
            challenge: options.challenge,
            rp: options.rp,
            user: {
                id: userId,
                name: options.user.name,
                displayName: options.user.displayName || options.user.name
            },
            pubKeyCredParams: options.pubKeyCredParams,
            timeout: options.timeout || 60000,
            authenticatorSelection: options.authenticatorSelection || {
                authenticatorAttachment: 'platform',
                userVerification: 'required',
                residentKey: 'required',
                requireResidentKey: true
            },
            attestation: options.attestation || 'none'
        };

        console.log('Native options:', JSON.stringify(nativeOptions, null, 2));
        const result = await plugin.startRegistration(nativeOptions);

        // Format response to match what the server expects
        return {
            id: result.id,
            rawId: result.rawId,
            type: 'public-key',
            transports: result.response?.transports || ['internal'],
            response: {
                clientDataJSON: result.response.clientDataJSON,
                attestationObject: result.response.attestationObject
            }
        };
    } catch (error) {
        console.error('Native passkey registration error:', error);
        throw error;
    }
}

/**
 * Register credential using browser WebAuthn API
 */
async function registerCredentialBrowser(options) {
    if (!window.PublicKeyCredential) {
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
 * Authenticate with a WebAuthn credential (native or browser)
 * @param {Object} options - Challenge options from server
 * @returns {Promise<Object>} - Authentication response
 */
export async function authenticateWithCredential(options) {
    // Use native passkey plugin in Capacitor
    const nativePlugin = getNativePasskey();
    if (isCapacitor() && nativePlugin) {
        return await authenticateCredentialNative(options, nativePlugin);
    }

    // Fall back to browser WebAuthn
    return await authenticateCredentialBrowser(options);
}

/**
 * Authenticate using native Capacitor plugin
 */
async function authenticateCredentialNative(options, plugin) {
    try {
        console.log('Using native passkey authentication');

        const nativeOptions = {
            challenge: options.challenge,
            rpId: options.rpId,
            timeout: options.timeout || 60000,
            userVerification: options.userVerification || 'required',
            allowCredentials: options.allowCredentials?.map(cred => ({
                id: cred.id,
                type: 'public-key',
                transports: cred.transports || ['internal']
            }))
        };

        const result = await plugin.startAuthentication(nativeOptions);

        // Format response to match what the server expects
        return {
            id: result.id,
            rawId: result.rawId,
            type: 'public-key',
            response: {
                clientDataJSON: result.response.clientDataJSON,
                authenticatorData: result.response.authenticatorData,
                signature: result.response.signature,
                userHandle: result.response.userHandle || null
            }
        };
    } catch (error) {
        console.error('Native passkey authentication error:', error);
        throw error;
    }
}

/**
 * Authenticate using browser WebAuthn API
 */
async function authenticateCredentialBrowser(options) {
    if (!window.PublicKeyCredential) {
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
    // In Capacitor, native passkeys are always available on modern devices
    if (isCapacitor()) {
        return true;
    }

    if (!window.PublicKeyCredential) {
        return false
    }

    try {
        return await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()
    } catch {
        return false
    }
}
