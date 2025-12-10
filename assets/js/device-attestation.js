/**
 * Device Attestation Module
 *
 * Creates device fingerprints and manages trusted devices list.
 * Used for security monitoring and recovery hints.
 */

/**
 * Generate a device fingerprint based on browser/system characteristics
 * Note: This is best-effort and can change, but helps identify devices
 * @returns {Promise<string>} Device fingerprint hash
 */
export async function generateDeviceFingerprint() {
    const components = []

    // User agent
    components.push(navigator.userAgent)

    // Screen resolution
    components.push(`${screen.width}x${screen.height}x${screen.colorDepth}`)

    // Timezone
    components.push(Intl.DateTimeFormat().resolvedOptions().timeZone)

    // Language
    components.push(navigator.language)

    // Platform
    components.push(navigator.platform)

    // Hardware concurrency (CPU cores)
    components.push(navigator.hardwareConcurrency || 'unknown')

    // Device memory (if available)
    components.push(navigator.deviceMemory || 'unknown')

    // Touch support
    components.push(navigator.maxTouchPoints || 0)

    // Canvas fingerprint (basic)
    try {
        const canvas = document.createElement('canvas')
        const ctx = canvas.getContext('2d')
        ctx.textBaseline = 'top'
        ctx.font = '14px Arial'
        ctx.fillText('friends', 2, 2)
        components.push(canvas.toDataURL())
    } catch (e) {
        components.push('canvas-unavailable')
    }

    // WebGL vendor/renderer
    try {
        const canvas = document.createElement('canvas')
        const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl')
        if (gl) {
            const debugInfo = gl.getExtension('WEBGL_debug_renderer_info')
            if (debugInfo) {
                components.push(gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL))
                components.push(gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL))
            }
        }
    } catch (e) {
        components.push('webgl-unavailable')
    }

    // Combine all components
    const fingerprintString = components.join('|')

    // Hash the fingerprint
    const encoder = new TextEncoder()
    const data = encoder.encode(fingerprintString)
    const hashBuffer = await crypto.subtle.digest('SHA-256', data)
    const hashArray = Array.from(new Uint8Array(hashBuffer))
    const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('')

    return hashHex
}

/**
 * Get a human-readable device name
 * @returns {string} Device name (e.g., "Chrome on macOS", "Firefox on Windows")
 */
export function getDeviceName() {
    const ua = navigator.userAgent
    let browser = 'Unknown Browser'
    let os = 'Unknown OS'

    // Detect browser
    if (ua.includes('Firefox')) browser = 'Firefox'
    else if (ua.includes('Edg')) browser = 'Edge'
    else if (ua.includes('Chrome')) browser = 'Chrome'
    else if (ua.includes('Safari') && !ua.includes('Chrome')) browser = 'Safari'
    else if (ua.includes('Opera') || ua.includes('OPR')) browser = 'Opera'

    // Detect OS
    if (ua.includes('Windows')) os = 'Windows'
    else if (ua.includes('Mac OS X')) os = 'macOS'
    else if (ua.includes('Linux')) os = 'Linux'
    else if (ua.includes('Android')) os = 'Android'
    else if (ua.includes('iOS') || ua.includes('iPhone') || ua.includes('iPad')) os = 'iOS'

    return `${browser} on ${os}`
}

/**
 * Device class to manage device information
 */
export class DeviceAttestation {
    constructor() {
        this.fingerprint = null
        this.deviceName = null
        this.initialized = false
    }

    /**
     * Initialize device attestation
     * @returns {Object} { fingerprint: string, deviceName: string }
     */
    async init() {
        if (this.initialized) {
            return {
                fingerprint: this.fingerprint,
                deviceName: this.deviceName
            }
        }

        this.fingerprint = await generateDeviceFingerprint()
        this.deviceName = getDeviceName()
        this.initialized = true

        console.log('[Device] Fingerprint:', this.fingerprint.substring(0, 16) + '...')
        console.log('[Device] Name:', this.deviceName)

        return {
            fingerprint: this.fingerprint,
            deviceName: this.deviceName
        }
    }

    /**
     * Get short fingerprint for display
     * @returns {string} First 8 characters of fingerprint
     */
    getShortFingerprint() {
        return this.fingerprint ? this.fingerprint.substring(0, 8) : null
    }

    /**
     * Get full device info
     * @returns {Object}
     */
    getDeviceInfo() {
        return {
            fingerprint: this.fingerprint,
            deviceName: this.deviceName,
            shortFingerprint: this.getShortFingerprint(),
            timestamp: Date.now()
        }
    }
}

// Export singleton instance
export const deviceAttestation = new DeviceAttestation()
