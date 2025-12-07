/**
 * Device Linking Module
 * 
 * Allows transferring crypto identity between browsers/devices via:
 * 1. QR code scanning
 * 2. Manual code entry
 * 
 * The transfer is encrypted with a PIN for security.
 */

import QRCode from 'qrcode'
import { cryptoIdentity } from './crypto-identity'

/**
 * Generate a 6-digit PIN for transfer encryption
 */
function generatePin() {
    return String(Math.floor(100000 + Math.random() * 900000))
}

/**
 * Derive an encryption key from PIN using PBKDF2
 */
async function deriveKeyFromPin(pin, salt) {
    const encoder = new TextEncoder()
    const pinData = encoder.encode(pin)
    
    const keyMaterial = await crypto.subtle.importKey(
        'raw',
        pinData,
        'PBKDF2',
        false,
        ['deriveBits', 'deriveKey']
    )
    
    return await crypto.subtle.deriveKey(
        {
            name: 'PBKDF2',
            salt: salt,
            iterations: 100000,
            hash: 'SHA-256'
        },
        keyMaterial,
        { name: 'AES-GCM', length: 256 },
        false,
        ['encrypt', 'decrypt']
    )
}

/**
 * Encrypt the identity data with PIN
 */
async function encryptIdentity(identityData, pin) {
    const salt = crypto.getRandomValues(new Uint8Array(16))
    const iv = crypto.getRandomValues(new Uint8Array(12))
    const key = await deriveKeyFromPin(pin, salt)
    
    const encoder = new TextEncoder()
    const data = encoder.encode(JSON.stringify(identityData))
    
    const encrypted = await crypto.subtle.encrypt(
        { name: 'AES-GCM', iv: iv },
        key,
        data
    )
    
    // Combine salt + iv + encrypted data
    const combined = new Uint8Array(salt.length + iv.length + encrypted.byteLength)
    combined.set(salt, 0)
    combined.set(iv, salt.length)
    combined.set(new Uint8Array(encrypted), salt.length + iv.length)
    
    // Convert to base64 for QR code
    return btoa(String.fromCharCode(...combined))
}

/**
 * Decrypt the identity data with PIN
 */
async function decryptIdentity(encryptedBase64, pin) {
    try {
        const combined = Uint8Array.from(atob(encryptedBase64), c => c.charCodeAt(0))
        
        const salt = combined.slice(0, 16)
        const iv = combined.slice(16, 28)
        const encrypted = combined.slice(28)
        
        const key = await deriveKeyFromPin(pin, salt)
        
        const decrypted = await crypto.subtle.decrypt(
            { name: 'AES-GCM', iv: iv },
            key,
            encrypted
        )
        
        const decoder = new TextDecoder()
        return JSON.parse(decoder.decode(decrypted))
    } catch (e) {
        console.error('Decryption failed:', e)
        return null
    }
}

/**
 * Export current identity for transfer
 */
async function exportIdentity() {
    const hasIdentity = await cryptoIdentity.hasIdentity()
    if (!hasIdentity) {
        throw new Error('No identity to export')
    }
    
    await cryptoIdentity.init()
    
    // Get the raw key data from storage
    const DB_NAME = 'FriendsIdentity'
    const STORE_NAME = 'keys'
    const KEY_ID = 'identity'
    
    return new Promise((resolve, reject) => {
        const request = indexedDB.open(DB_NAME, 1)
        request.onerror = () => reject(request.error)
        request.onsuccess = () => {
            const db = request.result
            const tx = db.transaction(STORE_NAME, 'readonly')
            const store = tx.objectStore(STORE_NAME)
            const getRequest = store.get(KEY_ID)
            
            getRequest.onsuccess = () => {
                if (getRequest.result) {
                    resolve({
                        privateKey: getRequest.result.privateKey,
                        publicKey: getRequest.result.publicKey
                    })
                } else {
                    reject(new Error('Identity not found'))
                }
            }
            getRequest.onerror = () => reject(getRequest.error)
        }
    })
}

/**
 * Import identity from transfer data
 */
async function importIdentity(identityData) {
    const DB_NAME = 'FriendsIdentity'
    const STORE_NAME = 'keys'
    const KEY_ID = 'identity'
    const LS_BACKUP_KEY = 'friends_identity_backup'
    
    // Clear existing identity first
    await cryptoIdentity.clear()
    
    // Store in IndexedDB
    return new Promise((resolve, reject) => {
        const request = indexedDB.open(DB_NAME, 1)
        
        request.onupgradeneeded = (event) => {
            const db = event.target.result
            if (!db.objectStoreNames.contains(STORE_NAME)) {
                db.createObjectStore(STORE_NAME, { keyPath: 'id' })
            }
        }
        
        request.onerror = () => reject(request.error)
        request.onsuccess = () => {
            const db = request.result
            const tx = db.transaction(STORE_NAME, 'readwrite')
            const store = tx.objectStore(STORE_NAME)
            
            const putRequest = store.put({
                id: KEY_ID,
                privateKey: identityData.privateKey,
                publicKey: identityData.publicKey
            })
            
            putRequest.onsuccess = () => {
                // Also backup to localStorage
                try {
                    localStorage.setItem(LS_BACKUP_KEY, JSON.stringify({
                        privateKey: identityData.privateKey,
                        publicKey: identityData.publicKey
                    }))
                } catch (e) {
                    console.warn('localStorage backup failed:', e)
                }
                
                resolve(identityData.publicKey)
            }
            putRequest.onerror = () => reject(putRequest.error)
        }
    })
}

/**
 * Device Link Manager
 */
class DeviceLinkManager {
    constructor() {
        this.currentPin = null
        this.currentCode = null
    }
    
    /**
     * Generate a transfer code and QR code for linking a new device
     * @returns {{ pin: string, code: string, qrDataUrl: Promise<string> }}
     */
    async generateTransferCode() {
        const identity = await exportIdentity()
        const pin = generatePin()
        const encryptedCode = await encryptIdentity(identity, pin)
        
        this.currentPin = pin
        this.currentCode = encryptedCode
        
        // Generate QR code as data URL
        const qrDataUrl = await QRCode.toDataURL(encryptedCode, {
            width: 256,
            margin: 2,
            color: {
                dark: '#000000',
                light: '#ffffff'
            }
        })
        
        return {
            pin,
            code: encryptedCode,
            qrDataUrl
        }
    }
    
    /**
     * Import identity from a transfer code
     * @param {string} code - The encrypted transfer code
     * @param {string} pin - The 6-digit PIN
     * @returns {Object|null} The public key if successful, null if failed
     */
    async importFromCode(code, pin) {
        const identity = await decryptIdentity(code, pin)
        
        if (!identity) {
            return null
        }
        
        const publicKey = await importIdentity(identity)
        
        // Reinitialize crypto identity with the imported key
        await cryptoIdentity.init()
        
        return publicKey
    }
}

export const deviceLinkManager = new DeviceLinkManager()
export { generatePin, encryptIdentity, decryptIdentity }

