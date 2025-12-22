/**
 * E2E Encryption for Direct Messages
 * Uses AES-GCM for message encryption
 * 
 * NOTE: This is a DEMO implementation. In production, you would use
 * proper key exchange (ECDH) with each user's public key.
 */

// Store conversation keys in memory
const conversationKeys = new Map();

/**
 * Get or create a conversation key
 * For demo: derives a deterministic key from conversation ID
 * In production: would use ECDH with participants' public keys
 */
async function getOrCreateKey(conversationId) {
  // Check memory first
  if (conversationKeys.has(conversationId)) {
    return conversationKeys.get(conversationId);
  }
  
  // Create a deterministic key from conversation ID
  // This allows all participants to derive the same key
  // NOTE: This is NOT secure for real E2E - just for demo!
  const encoder = new TextEncoder();
  const seedData = encoder.encode(`friends-conversation-${conversationId}-demo-key-v1`);
  
  // Hash the seed to create key material
  const hashBuffer = await window.crypto.subtle.digest('SHA-256', seedData);
  
  // Import as AES key
  const key = await window.crypto.subtle.importKey(
    "raw",
    hashBuffer,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"]
  );
  
  conversationKeys.set(conversationId, key);
  return key;
}

/**
 * Generate a random symmetric key for a conversation
 */
export async function generateConversationKey() {
  return await window.crypto.subtle.generateKey(
    { name: "AES-GCM", length: 256 },
    true,  // extractable
    ["encrypt", "decrypt"]
  );
}

/**
 * Export a CryptoKey to raw bytes
 */
export async function exportKey(key) {
  const exported = await window.crypto.subtle.exportKey("raw", key);
  return new Uint8Array(exported);
}

/**
 * Import raw bytes as an AES-GCM key
 */
export async function importKey(keyData) {
  return await window.crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "AES-GCM", length: 256 },
    true,  // extractable (needed for persistence)
    ["encrypt", "decrypt"]
  );
}

/**
 * Encrypt a message using AES-GCM
 * @returns {object} { encryptedContent: Uint8Array, nonce: Uint8Array }
 */
export async function encryptMessage(message, conversationId) {
  const key = await getOrCreateKey(conversationId);

  const encoder = new TextEncoder();
  const data = encoder.encode(message);
  
  // Generate random nonce (96 bits for AES-GCM)
  const nonce = window.crypto.getRandomValues(new Uint8Array(12));
  
  const encryptedContent = await window.crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce },
    key,
    data
  );

  return {
    encryptedContent: new Uint8Array(encryptedContent),
    nonce: nonce
  };
}

/**
 * Decrypt a message using AES-GCM
 */
export async function decryptMessage(encryptedContent, nonce, conversationId) {
  try {
    const key = await getOrCreateKey(conversationId);
    
    const decrypted = await window.crypto.subtle.decrypt(
      { name: "AES-GCM", iv: nonce },
      key,
      encryptedContent
    );

    const decoder = new TextDecoder();
    return decoder.decode(decrypted);
  } catch (e) {
    console.error("Decryption failed:", e);
    return "[Unable to decrypt - key mismatch]";
  }
}

/**
 * Encrypt voice note data
 */
export async function encryptVoiceNote(audioBlob, conversationId) {
  const key = await getOrCreateKey(conversationId);

  const audioData = await audioBlob.arrayBuffer();
  const nonce = window.crypto.getRandomValues(new Uint8Array(12));
  
  const encryptedContent = await window.crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce },
    key,
    audioData
  );

  return {
    encryptedContent: new Uint8Array(encryptedContent),
    nonce: nonce
  };
}

/**
 * Decrypt voice note data
 */
export async function decryptVoiceNote(encryptedContent, nonce, conversationId) {
  try {
    const key = await getOrCreateKey(conversationId);

    const decrypted = await window.crypto.subtle.decrypt(
      { name: "AES-GCM", iv: nonce },
      key,
      encryptedContent
    );

    return new Blob([decrypted], { type: "audio/webm" });
  } catch (e) {
    console.error("Voice decryption failed:", e);
    return null;
  }
}

/**
 * Convert Uint8Array to base64 string
 */
export function arrayToBase64(array) {
  let binary = "";
  for (let i = 0; i < array.length; i++) {
    binary += String.fromCharCode(array[i]);
  }
  return btoa(binary);
}

/**
 * Convert base64 string to Uint8Array
 */
export function base64ToArray(base64) {
  const binary = atob(base64);
  const array = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    array[i] = binary.charCodeAt(i);
  }
  return array;
}

// ============================================
// Key-based API (used by modular hooks)
// ============================================

/**
 * Load or create a conversation key (exported alias for getOrCreateKey)
 * @param {string} conversationId - Unique conversation identifier
 * @returns {Promise<CryptoKey>} The AES-GCM key
 */
export async function loadOrCreateConversationKey(conversationId) {
  return await getOrCreateKey(conversationId);
}

/**
 * Encrypt a text message using a pre-loaded key
 * @param {string} message - Plain text message
 * @param {CryptoKey} key - AES-GCM key
 * @returns {Promise<{encrypted: Uint8Array, nonce: Uint8Array}>}
 */
export async function encryptWithKey(message, key) {
  const encoder = new TextEncoder();
  const data = encoder.encode(message);
  
  const nonce = window.crypto.getRandomValues(new Uint8Array(12));
  
  const encryptedContent = await window.crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce },
    key,
    data
  );

  return {
    encrypted: new Uint8Array(encryptedContent),
    nonce: nonce
  };
}

/**
 * Decrypt a message using a pre-loaded key
 * @param {Uint8Array} encryptedBytes - Encrypted data
 * @param {Uint8Array} nonce - Nonce/IV used for encryption
 * @param {CryptoKey} key - AES-GCM key
 * @returns {Promise<string>} Decrypted plain text
 */
export async function decryptWithKey(encryptedBytes, nonce, key) {
  try {
    const decrypted = await window.crypto.subtle.decrypt(
      { name: "AES-GCM", iv: nonce },
      key,
      encryptedBytes
    );

    const decoder = new TextDecoder();
    return decoder.decode(decrypted);
  } catch (e) {
    console.error("Decryption failed:", e);
    return "[Unable to decrypt]";
  }
}

/**
 * Encrypt raw bytes (e.g., audio data) using a pre-loaded key
 * @param {Uint8Array} bytes - Raw bytes to encrypt
 * @param {CryptoKey} key - AES-GCM key
 * @returns {Promise<{encrypted: Uint8Array, nonce: Uint8Array}>}
 */
export async function encryptBytesWithKey(bytes, key) {
  const nonce = window.crypto.getRandomValues(new Uint8Array(12));
  
  const encryptedContent = await window.crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce },
    key,
    bytes
  );

  return {
    encrypted: new Uint8Array(encryptedContent),
    nonce: nonce
  };
}
