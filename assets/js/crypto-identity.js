/**
 * Crypto Identity Module
 * 
 * Generates and manages browser-based cryptographic keys for passwordless auth.
 * Keys are stored in IndexedDB (primary) with localStorage backup.
 */

const DB_NAME = 'FriendsIdentity'
const DB_VERSION = 1
const STORE_NAME = 'keys'
const KEY_ID = 'identity'
const LS_BACKUP_KEY = 'friends_identity_backup'

// Initialize IndexedDB
function openDB() {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open(DB_NAME, DB_VERSION)
        
        request.onerror = () => reject(request.error)
        request.onsuccess = () => resolve(request.result)
        
        request.onupgradeneeded = (event) => {
            const db = event.target.result
            if (!db.objectStoreNames.contains(STORE_NAME)) {
                db.createObjectStore(STORE_NAME, { keyPath: 'id' })
            }
        }
    })
}

// Generate ECDSA keypair using Web Crypto API
async function generateKeyPair() {
    const keyPair = await crypto.subtle.generateKey(
        {
            name: 'ECDSA',
            namedCurve: 'P-256'
        },
        true, // extractable - needed for export
        ['sign', 'verify']
    )
    
    return keyPair
}

// Export public key to JWK format (for sending to server)
async function exportPublicKey(publicKey) {
    const jwk = await crypto.subtle.exportKey('jwk', publicKey)
    return jwk
}

// Export private key for backup
async function exportPrivateKey(privateKey) {
    const jwk = await crypto.subtle.exportKey('jwk', privateKey)
    return jwk
}

// Import private key from JWK
async function importPrivateKey(jwk) {
    return await crypto.subtle.importKey(
        'jwk',
        jwk,
        { name: 'ECDSA', namedCurve: 'P-256' },
        true,
        ['sign']
    )
}

// Import public key from JWK
async function importPublicKey(jwk) {
    return await crypto.subtle.importKey(
        'jwk',
        jwk,
        { name: 'ECDSA', namedCurve: 'P-256' },
        true,
        ['verify']
    )
}

// Store identity in IndexedDB
async function storeInIndexedDB(identity) {
    const db = await openDB()
    return new Promise((resolve, reject) => {
        const tx = db.transaction(STORE_NAME, 'readwrite')
        const store = tx.objectStore(STORE_NAME)
        const request = store.put({ id: KEY_ID, ...identity })
        
        request.onsuccess = () => resolve()
        request.onerror = () => reject(request.error)
    })
}

// Retrieve identity from IndexedDB
async function getFromIndexedDB() {
    try {
        const db = await openDB()
        return new Promise((resolve, reject) => {
            const tx = db.transaction(STORE_NAME, 'readonly')
            const store = tx.objectStore(STORE_NAME)
            const request = store.get(KEY_ID)
            
            request.onsuccess = () => resolve(request.result)
            request.onerror = () => reject(request.error)
        })
    } catch (e) {
        console.warn('IndexedDB unavailable:', e)
        return null
    }
}

// Backup to localStorage (encrypted with a derived key from the private key)
function backupToLocalStorage(privateKeyJwk, publicKeyJwk) {
    try {
        const backup = JSON.stringify({ privateKey: privateKeyJwk, publicKey: publicKeyJwk })
        localStorage.setItem(LS_BACKUP_KEY, backup)
    } catch (e) {
        console.warn('localStorage backup failed:', e)
    }
}

// Restore from localStorage backup
function getFromLocalStorage() {
    try {
        const backup = localStorage.getItem(LS_BACKUP_KEY)
        if (backup) {
            return JSON.parse(backup)
        }
    } catch (e) {
        console.warn('localStorage restore failed:', e)
    }
    return null
}

// Sign a challenge/message with private key
async function signMessage(privateKey, message) {
    console.log('[Crypto] Signing message:', message.substring(0, 20) + '... (length: ' + message.length + ')')

    const encoder = new TextEncoder()
    const data = encoder.encode(message)

    console.log('[Crypto] Encoded data bytes:', data.byteLength)

    const signature = await crypto.subtle.sign(
        { name: 'ECDSA', hash: 'SHA-256' },
        privateKey,
        data
    )

    console.log('[Crypto] Signature bytes:', signature.byteLength)

    // Convert to base64 for transmission
    const base64Sig = btoa(String.fromCharCode(...new Uint8Array(signature)))
    console.log('[Crypto] Base64 signature length:', base64Sig.length)

    return base64Sig
}

// Verify a signature (for testing/debugging)
async function verifySignature(publicKey, message, signatureBase64) {
    const encoder = new TextEncoder()
    const data = encoder.encode(message)
    
    const signature = Uint8Array.from(atob(signatureBase64), c => c.charCodeAt(0))
    
    return await crypto.subtle.verify(
        { name: 'ECDSA', hash: 'SHA-256' },
        publicKey,
        signature,
        data
    )
}

/**
 * Main identity class
 */
class CryptoIdentity {
    constructor() {
        this.privateKey = null
        this.publicKey = null
        this.publicKeyJwk = null
        this.initialized = false
    }
    
    /**
     * Initialize identity - load existing or create new
     * @returns {Object} { isNew: boolean, publicKey: JWK }
     */
    async init() {
        console.log('[Crypto] init() called, initialized:', this.initialized)

        if (this.initialized) {
            console.log('[Crypto] Already initialized, returning cached key')
            return { isNew: false, publicKey: this.publicKeyJwk }
        }

        // Try to load from IndexedDB first
        console.log('[Crypto] Attempting to load from IndexedDB...')
        let stored = await getFromIndexedDB()

        // Fallback to localStorage
        if (!stored) {
            console.log('[Crypto] No keys in IndexedDB, trying localStorage...')
            stored = getFromLocalStorage()
        }

        if (stored && stored.privateKey && stored.publicKey) {
            console.log('[Crypto] Found stored keys, restoring identity')
            console.log('[Crypto] Public key x:', stored.publicKey.x?.substring(0, 10) + '...')

            // Restore existing identity
            try {
                this.privateKey = await importPrivateKey(stored.privateKey)
                this.publicKey = await importPublicKey(stored.publicKey)
                this.publicKeyJwk = stored.publicKey
                this.initialized = true

                // Ensure IndexedDB has the latest
                await storeInIndexedDB({
                    privateKey: stored.privateKey,
                    publicKey: stored.publicKey
                })

                console.log('[Crypto] Successfully restored existing identity')
                return { isNew: false, publicKey: this.publicKeyJwk }
            } catch (e) {
                console.error('[Crypto] Failed to restore keys, generating new:', e)
            }
        } else {
            console.log('[Crypto] No stored keys found')
        }

        // Generate new identity
        console.log('[Crypto] Generating new identity...')
        const keyPair = await generateKeyPair()
        this.privateKey = keyPair.privateKey
        this.publicKey = keyPair.publicKey

        const privateKeyJwk = await exportPrivateKey(this.privateKey)
        this.publicKeyJwk = await exportPublicKey(this.publicKey)

        console.log('[Crypto] New public key x:', this.publicKeyJwk.x?.substring(0, 10) + '...')

        // Store in both IndexedDB and localStorage
        await storeInIndexedDB({
            privateKey: privateKeyJwk,
            publicKey: this.publicKeyJwk
        })
        backupToLocalStorage(privateKeyJwk, this.publicKeyJwk)

        this.initialized = true
        console.log('[Crypto] Generated and stored new identity')
        return { isNew: true, publicKey: this.publicKeyJwk }
    }
    
    /**
     * Sign a challenge from the server
     * @param {string} challenge - The challenge string to sign
     * @returns {string} Base64-encoded signature
     */
    async sign(challenge) {
        if (!this.initialized) {
            await this.init()
        }
        return signMessage(this.privateKey, challenge)
    }
    
    /**
     * Get the public key as JWK
     */
    getPublicKey() {
        return this.publicKeyJwk
    }
    
    /**
     * Get a fingerprint of the public key (for display)
     */
    getKeyFingerprint() {
        if (!this.publicKeyJwk) return null
        
        // Create a short fingerprint from the x coordinate
        const x = this.publicKeyJwk.x || ''
        return x.substring(0, 8)
    }
    
    /**
     * Check if identity exists
     */
    async hasIdentity() {
        const stored = await getFromIndexedDB()
        if (stored) return true
        
        const backup = getFromLocalStorage()
        return !!backup
    }
    
    /**
     * Clear identity (for testing or recovery)
     */
    async clear() {
        try {
            const db = await openDB()
            const tx = db.transaction(STORE_NAME, 'readwrite')
            const store = tx.objectStore(STORE_NAME)
            store.delete(KEY_ID)
        } catch (e) {
            console.warn('Failed to clear IndexedDB:', e)
        }
        
        localStorage.removeItem(LS_BACKUP_KEY)
        
        this.privateKey = null
        this.publicKey = null
        this.publicKeyJwk = null
        this.initialized = false
    }
}

// Export singleton instance
export const cryptoIdentity = new CryptoIdentity()

// Also export for direct use
export {
    signMessage,
    verifySignature,
    generateKeyPair,
    exportPublicKey
}


