/**
 * Utility functions for Friends app
 * Device fingerprinting, image optimization, etc.
 */

// Generate device fingerprint - hardware characteristics that are consistent across browsers
export function generateFingerprint() {
    const components = [
        screen.width,
        screen.height,
        screen.colorDepth,
        new Date().getTimezoneOffset(),
        screen.availWidth,
        screen.availHeight,
        navigator.hardwareConcurrency || 0,
        navigator.maxTouchPoints || 0,
        navigator.language
    ]

    const fingerprint = components.join('|')

    // FNV-1a hash
    let hash = 2166136261
    for (let i = 0; i < fingerprint.length; i++) {
        hash ^= fingerprint.charCodeAt(i)
        hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24)
    }

    return (hash >>> 0).toString(16)
}

// Get or create browser ID (unique per browser)
export function getBrowserId() {
    const key = 'friends_browser_id'
    let id = localStorage.getItem(key)

    if (!id) {
        id = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
            const r = Math.random() * 16 | 0
            const v = c === 'x' ? r : (r & 0x3 | 0x8)
            return v.toString(16)
        })
        localStorage.setItem(key, id)
    }

    return id
}

// Generate thumbnail from image file
export function generateThumbnail(file, maxSize = 300) {
    return new Promise(resolve => {
        if (!file.type.startsWith('image/') || file.type === 'image/gif') {
            resolve(null)
            return
        }

        const img = new Image()
        const canvas = document.createElement('canvas')
        const ctx = canvas.getContext('2d')

        img.onload = () => {
            let { width, height } = img

            if (width > height) {
                height = Math.round((height * maxSize) / width)
                width = maxSize
            } else {
                width = Math.round((width * maxSize) / height)
                height = maxSize
            }

            canvas.width = width
            canvas.height = height
            ctx.imageSmoothingEnabled = true
            ctx.imageSmoothingQuality = 'high'
            ctx.drawImage(img, 0, 0, width, height)

            const dataUrl = canvas.toDataURL('image/jpeg', 0.7)
            URL.revokeObjectURL(img.src)
            resolve(dataUrl)
        }

        img.onerror = () => resolve(null)
        img.src = URL.createObjectURL(file)
    })
}

// Optimize image before upload
export function optimizeImage(file, maxSize = 1200) {
    return new Promise(resolve => {
        if (!file.type.startsWith('image/') || file.type === 'image/gif') {
            resolve(file)
            return
        }

        const img = new Image()
        const canvas = document.createElement('canvas')
        const ctx = canvas.getContext('2d')

        img.onload = () => {
            let { width, height } = img

            if (width > maxSize || height > maxSize) {
                if (width > height) {
                    height = Math.round((height * maxSize) / width)
                    width = maxSize
                } else {
                    width = Math.round((width * maxSize) / height)
                    height = maxSize
                }
            }

            canvas.width = width
            canvas.height = height
            ctx.drawImage(img, 0, 0, width, height)

            canvas.toBlob(blob => {
                if (blob) {
                    const optimized = new File([blob], file.name, {
                        type: 'image/jpeg',
                        lastModified: Date.now()
                    })
                    resolve(optimized)
                } else {
                    resolve(file)
                }
            }, 'image/jpeg', 0.85)
        }

        img.onerror = () => resolve(file)
        img.src = URL.createObjectURL(file)
    })
}

// Format time for audio players
export function formatTime(seconds) {
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins}:${secs.toString().padStart(2, '0')}`
}
