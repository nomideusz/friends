/**
 * WebAuthn Module for SvelteKit
 *
 * Provides hardware-backed authentication using WebAuthn/FIDO2.
 * This allows users to use fingerprint, Face ID, hardware keys, etc.
 */

export interface RegistrationOptions {
    challenge: string;
    rp: { name: string; id: string };
    user: { id: string; name: string; displayName: string };
    pubKeyCredParams: { type: string; alg: number }[];
    timeout: number;
    attestation: string;
    excludeCredentials?: { type: string; id: string; transports?: string[] }[];
    authenticatorSelection?: {
        residentKey?: string;
        userVerification?: string;
    };
}

export interface AuthenticationOptions {
    challenge: string;
    timeout: number;
    rpId: string;
    userVerification: string;
    allowCredentials?: { type: string; id: string; transports?: string[] }[];
}

export interface CredentialResponse {
    id: string;
    rawId: string;
    type: string;
    transports?: string[];
    response: {
        clientDataJSON: string;
        attestationObject?: string;
        authenticatorData?: string;
        signature?: string;
        userHandle?: string | null;
    };
}

/**
 * Check if WebAuthn is supported in this browser
 */
export function isWebAuthnSupported(): boolean {
    return window.PublicKeyCredential !== undefined &&
        navigator.credentials !== undefined;
}

/**
 * Convert base64url to ArrayBuffer
 */
function base64urlToBuffer(base64url: string): ArrayBuffer {
    const base64 = base64url.replace(/-/g, '+').replace(/_/g, '/');
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes.buffer;
}

/**
 * Convert ArrayBuffer to base64url
 */
function bufferToBase64url(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary)
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=/g, '');
}

/**
 * Register a new WebAuthn credential
 */
export async function registerCredential(options: RegistrationOptions): Promise<CredentialResponse> {
    if (!isWebAuthnSupported()) {
        throw new Error('WebAuthn is not supported in this browser');
    }

    // Convert challenge from base64url to ArrayBuffer
    const publicKeyOptions: PublicKeyCredentialCreationOptions = {
        challenge: base64urlToBuffer(options.challenge),
        rp: options.rp,
        user: {
            ...options.user,
            id: new TextEncoder().encode(options.user.id)
        },
        pubKeyCredParams: options.pubKeyCredParams as PublicKeyCredentialParameters[],
        timeout: options.timeout,
        attestation: options.attestation as AttestationConveyancePreference,
        authenticatorSelection: options.authenticatorSelection as AuthenticatorSelectionCriteria,
        excludeCredentials: options.excludeCredentials?.map(cred => ({
            id: base64urlToBuffer(cred.id),
            type: 'public-key' as const,
            transports: cred.transports as AuthenticatorTransport[] | undefined
        }))
    };

    // Create credential
    const credential = await navigator.credentials.create({
        publicKey: publicKeyOptions
    }) as PublicKeyCredential;

    if (!credential) {
        throw new Error('Failed to create credential');
    }

    const response = credential.response as AuthenticatorAttestationResponse;

    // Get transports from credential response (critical for iOS Safari Face ID)
    const transports = response.getTransports
        ? response.getTransports()
        : [];

    // Convert response to JSON-serializable format
    return {
        id: credential.id,
        rawId: bufferToBase64url(credential.rawId),
        type: credential.type,
        transports,
        response: {
            clientDataJSON: bufferToBase64url(response.clientDataJSON),
            attestationObject: bufferToBase64url(response.attestationObject)
        }
    };
}

/**
 * Authenticate with a WebAuthn credential
 */
export async function authenticateWithCredential(options: AuthenticationOptions): Promise<CredentialResponse> {
    if (!isWebAuthnSupported()) {
        throw new Error('WebAuthn is not supported in this browser');
    }

    // Convert challenge and credential IDs
    const publicKeyOptions: PublicKeyCredentialRequestOptions = {
        challenge: base64urlToBuffer(options.challenge),
        timeout: options.timeout,
        rpId: options.rpId,
        userVerification: options.userVerification as UserVerificationRequirement,
        allowCredentials: options.allowCredentials?.map(cred => ({
            id: base64urlToBuffer(cred.id),
            type: 'public-key' as const,
            transports: cred.transports as AuthenticatorTransport[] | undefined
        }))
    };

    // Get credential
    const credential = await navigator.credentials.get({
        publicKey: publicKeyOptions
    }) as PublicKeyCredential;

    if (!credential) {
        throw new Error('Authentication failed');
    }

    const response = credential.response as AuthenticatorAssertionResponse;

    // Convert response to JSON-serializable format
    return {
        id: credential.id,
        rawId: bufferToBase64url(credential.rawId),
        type: credential.type,
        response: {
            clientDataJSON: bufferToBase64url(response.clientDataJSON),
            authenticatorData: bufferToBase64url(response.authenticatorData),
            signature: bufferToBase64url(response.signature),
            userHandle: response.userHandle
                ? bufferToBase64url(response.userHandle)
                : null
        }
    };
}

/**
 * Check platform authenticator availability (e.g., Touch ID, Face ID)
 */
export async function isPlatformAuthenticatorAvailable(): Promise<boolean> {
    if (!isWebAuthnSupported()) {
        return false;
    }

    try {
        return await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
    } catch {
        return false;
    }
}
