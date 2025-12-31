/**
 * UI-related LiveView hooks
 * Handles: Navigation, modals, drawers, clipboard, scroll management
 */

export const HomeOrbHook = {
    mounted() {
        this.timer = null
        this.held = false
        this.hovered = false

        const startPress = (e) => {
            if (e.type === 'mousedown' && e.button !== 0) return

            this.held = false
            this.timer = setTimeout(() => {
                this.held = true
                if (navigator.vibrate) navigator.vibrate(10)
                this.pushEvent("show_breadcrumbs", {})
            }, 500)
        }

        const endPress = (e) => {
            if (this.timer) {
                clearTimeout(this.timer)
                this.timer = null
            }

            if (this.held) {
                e.preventDefault()
                e.stopPropagation()
            }
        }

        const handleMouseEnter = () => {
            if (!this.hovered) {
                this.hovered = true
                this.pushEvent("show_breadcrumbs", {})
            }
        }

        const handleMouseLeave = () => {
            if (this.hovered) {
                this.hovered = false
                setTimeout(() => {
                    if (!this.hovered) {
                        this.pushEvent("show_breadcrumbs", {})
                    }
                }, 300)
            }
        }

        this.el.addEventListener('mousedown', startPress)
        this.el.addEventListener('touchstart', startPress, { passive: false })
        this.el.addEventListener('mouseup', endPress)
        this.el.addEventListener('mouseleave', endPress)
        this.el.addEventListener('touchend', endPress)
        this.el.addEventListener('touchcancel', endPress)
        this.el.addEventListener('mouseenter', handleMouseEnter)
        this.el.addEventListener('mouseleave', handleMouseLeave)
    }
}

export const NavOrbLongPressHook = {
    mounted() {
        this.timer = null
        this.held = false

        const startPress = (e) => {
            if (e.type === 'mousedown' && e.button !== 0) return
            e.preventDefault()

            this.held = false
            this.timer = setTimeout(() => {
                this.held = true
                if (navigator.vibrate) navigator.vibrate([50, 50, 50])
                this.pushEvent("show_fullscreen_graph", {})
            }, 3000)
        }

        const endPress = (e) => {
            if (this.timer) {
                clearTimeout(this.timer)
                this.timer = null
            }

            if (this.held) {
                e.preventDefault()
                e.stopPropagation()
                this.held = false
            }
        }

        this.el.addEventListener('mousedown', startPress)
        this.el.addEventListener('touchstart', startPress, { passive: false })
        this.el.addEventListener('mouseup', endPress)
        this.el.addEventListener('mouseleave', endPress)
        this.el.addEventListener('touchend', endPress)
        this.el.addEventListener('touchcancel', endPress)
    },
    destroyed() {
        if (this.timer) clearTimeout(this.timer)
    }
}

/**
 * DraggableAvatar - Allows user to drag their avatar to any of 4 corners
 * On drop, snaps to nearest corner and saves preference to database
 */
export const DraggableAvatarHook = {
    mounted() {
        this.isDragging = false
        this.startX = 0
        this.startY = 0
        this.currentX = 0
        this.currentY = 0
        this.originalPosition = this.el.dataset.position || 'top-right'

        // Create a clone for dragging visual
        this.ghost = null

        // Get the container (the avatar-hub-container div)
        this.container = this.el.closest('#avatar-hub-container') || this.el.parentElement

        const startDrag = (e) => {
            // Only start drag on long press (300ms)
            const clientX = e.type.includes('touch') ? e.touches[0].clientX : e.clientX
            const clientY = e.type.includes('touch') ? e.touches[0].clientY : e.clientY

            this.longPressTimer = setTimeout(() => {
                this.isDragging = true
                this.startX = clientX
                this.startY = clientY

                // Visual feedback - add dragging class
                this.el.classList.add('scale-125', 'opacity-80', 'z-[200]')
                if (navigator.vibrate) navigator.vibrate(20)

                // Show corner targets
                this.showCornerTargets()
            }, 300)
        }

        const onMove = (e) => {
            if (!this.isDragging) return

            e.preventDefault()

            const clientX = e.type.includes('touch') ? e.touches[0].clientX : e.clientX
            const clientY = e.type.includes('touch') ? e.touches[0].clientY : e.clientY

            this.currentX = clientX
            this.currentY = clientY

            // Move the container with the avatar
            const deltaX = clientX - this.startX
            const deltaY = clientY - this.startY

            this.container.style.transition = 'none'
            this.container.style.transform = `translate(${deltaX}px, ${deltaY}px)`

            // Highlight nearest corner
            this.highlightNearestCorner(clientX, clientY)
        }

        const endDrag = (e) => {
            // Clear long press timer
            if (this.longPressTimer) {
                clearTimeout(this.longPressTimer)
                this.longPressTimer = null
            }

            if (!this.isDragging) return

            this.isDragging = false

            // Remove dragging visual
            this.el.classList.remove('scale-125', 'opacity-80', 'z-[200]')

            // Determine which corner to snap to
            const corner = this.getNearestCorner(this.currentX, this.currentY)

            // Animate to corner position
            this.container.style.transition = 'transform 0.3s cubic-bezier(0.34, 1.56, 0.64, 1)'
            this.container.style.transform = ''

            // Hide corner targets
            this.hideCornerTargets()

            // If corner changed, save to DB
            if (corner !== this.originalPosition) {
                if (navigator.vibrate) navigator.vibrate([20, 50, 20])
                this.pushEvent('set_avatar_position', { position: corner })
                this.originalPosition = corner
            }
        }

        // Touch events
        this.el.addEventListener('touchstart', startDrag, { passive: true })
        document.addEventListener('touchmove', onMove, { passive: false })
        document.addEventListener('touchend', endDrag)
        document.addEventListener('touchcancel', endDrag)

        // Mouse events
        this.el.addEventListener('mousedown', startDrag)
        document.addEventListener('mousemove', onMove)
        document.addEventListener('mouseup', endDrag)

        this._startDrag = startDrag
        this._onMove = onMove
        this._endDrag = endDrag
    },

    getNearestCorner(x, y) {
        const w = window.innerWidth
        const h = window.innerHeight

        const isLeft = x < w / 2
        const isTop = y < h / 2

        if (isTop && isLeft) return 'top-left'
        if (isTop && !isLeft) return 'top-right'
        if (!isTop && isLeft) return 'bottom-left'
        return 'bottom-right'
    },

    showCornerTargets() {
        // Create overlay with corner targets
        this.overlay = document.createElement('div')
        this.overlay.className = 'fixed inset-0 z-[150] pointer-events-none'
        this.overlay.innerHTML = `
            <div class="absolute top-4 left-4 w-12 h-12 rounded-full border-2 border-dashed border-white/30 flex items-center justify-center text-white/40 corner-target" data-corner="top-left">↖</div>
            <div class="absolute top-4 right-4 w-12 h-12 rounded-full border-2 border-dashed border-white/30 flex items-center justify-center text-white/40 corner-target" data-corner="top-right">↗</div>
            <div class="absolute bottom-20 left-4 w-12 h-12 rounded-full border-2 border-dashed border-white/30 flex items-center justify-center text-white/40 corner-target" data-corner="bottom-left">↙</div>
            <div class="absolute bottom-20 right-4 w-12 h-12 rounded-full border-2 border-dashed border-white/30 flex items-center justify-center text-white/40 corner-target" data-corner="bottom-right">↘</div>
        `
        document.body.appendChild(this.overlay)
    },

    hideCornerTargets() {
        if (this.overlay) {
            this.overlay.remove()
            this.overlay = null
        }
    },

    highlightNearestCorner(x, y) {
        if (!this.overlay) return

        const nearest = this.getNearestCorner(x, y)

        this.overlay.querySelectorAll('.corner-target').forEach(el => {
            if (el.dataset.corner === nearest) {
                el.classList.remove('border-white/30', 'text-white/40')
                el.classList.add('border-white', 'text-white', 'bg-white/20', 'scale-110')
            } else {
                el.classList.add('border-white/30', 'text-white/40')
                el.classList.remove('border-white', 'text-white', 'bg-white/20', 'scale-110')
            }
        })
    },

    destroyed() {
        if (this.longPressTimer) clearTimeout(this.longPressTimer)
        this.hideCornerTargets()

        document.removeEventListener('touchmove', this._onMove)
        document.removeEventListener('touchend', this._endDrag)
        document.removeEventListener('touchcancel', this._endDrag)
        document.removeEventListener('mousemove', this._onMove)
        document.removeEventListener('mouseup', this._endDrag)
    }
}

/**
 * TetheredLineHook
 * Draws and animates an SVG line from the avatar to the drawer
 */
export const TetheredLineHook = {
    mounted() {
        this.avatarPosition = this.el.dataset.avatarPosition || 'top-right'
        this.drawerId = this.el.dataset.drawerId

        // Wait for drawer to render
        requestAnimationFrame(() => {
            this.updateLine()
        })

        // Update on resize
        this._onResize = () => this.updateLine()
        window.addEventListener('resize', this._onResize)

        // Animate line appearance
        this.animateLine()
    },

    updated() {
        this.avatarPosition = this.el.dataset.avatarPosition || 'top-right'
        this.updateLine()
    },

    updateLine() {
        const line = this.el.querySelector('.tether-line')
        if (!line) return

        const avatar = document.getElementById('avatar-hub-trigger')
        const drawer = document.getElementById(this.drawerId)

        if (!avatar || !drawer) return

        const avatarRect = avatar.getBoundingClientRect()
        const drawerRect = drawer.getBoundingClientRect()

        // Avatar center point
        const avatarCenterX = avatarRect.left + avatarRect.width / 2
        const avatarCenterY = avatarRect.top + avatarRect.height / 2

        // Drawer connection point (edge closest to avatar)
        let drawerX, drawerY

        if (this.avatarPosition.includes('left')) {
            // Drawer is on left, connect to right edge of drawer
            drawerX = drawerRect.right
            drawerY = Math.min(Math.max(avatarCenterY, drawerRect.top + 50), drawerRect.bottom - 50)
        } else {
            // Drawer is on right, connect to left edge of drawer
            drawerX = drawerRect.left
            drawerY = Math.min(Math.max(avatarCenterY, drawerRect.top + 50), drawerRect.bottom - 50)
        }

        line.setAttribute('x1', avatarCenterX)
        line.setAttribute('y1', avatarCenterY)
        line.setAttribute('x2', drawerX)
        line.setAttribute('y2', drawerY)
    },

    animateLine() {
        const line = this.el.querySelector('.tether-line')
        if (!line) return

        // Animate stroke-dashoffset for a "drawing" effect
        const length = 500 // approximate max length
        line.style.strokeDasharray = length
        line.style.strokeDashoffset = length
        line.style.transition = 'stroke-dashoffset 0.4s ease-out'

        requestAnimationFrame(() => {
            line.style.strokeDashoffset = '0'
        })
    },

    destroyed() {
        window.removeEventListener('resize', this._onResize)
    }
}

export const SwipeableDrawerHook = {
    mounted() {
        const handle = this.el.querySelector('[data-drawer-handle]') || this.el.querySelector('.py-3') || this.el
        const closeEvent = this.el.dataset.closeEvent || 'close_drawer'
        let startY = 0
        let currentY = 0
        let dragging = false

        const onTouchStart = (e) => {
            startY = e.touches[0].clientY
            currentY = startY
            dragging = true
            this.el.style.transition = 'none'
        }

        const onTouchMove = (e) => {
            if (!dragging) return
            currentY = e.touches[0].clientY
            const diff = currentY - startY
            if (diff > 0) {
                this.el.style.transform = `translateY(${diff}px)`
            }
        }

        const onTouchEnd = () => {
            if (!dragging) return
            dragging = false
            this.el.style.transition = 'transform 0.3s ease-out'

            const diff = currentY - startY
            if (diff > 100) {
                // Swipe down threshold reached - close
                this.el.style.transform = `translateY(100%)`
                setTimeout(() => this.pushEvent(closeEvent, {}), 200)
            } else {
                this.el.style.transform = 'translateY(0)'
            }
        }

        handle.addEventListener('touchstart', onTouchStart, { passive: true })
        this.el.addEventListener('touchmove', onTouchMove, { passive: true })
        this.el.addEventListener('touchend', onTouchEnd)

        this._onTouchStart = onTouchStart
        this._onTouchMove = onTouchMove
        this._onTouchEnd = onTouchEnd
        this._handle = handle
    },

    destroyed() {
        if (this._handle) {
            this._handle.removeEventListener('touchstart', this._onTouchStart)
        }
        this.el.removeEventListener('touchmove', this._onTouchMove)
        this.el.removeEventListener('touchend', this._onTouchEnd)
    }
}

export const LockScrollHook = {
    mounted() {
        document.body.style.overflow = 'hidden'
    },
    destroyed() {
        document.body.style.overflow = ''
    }
}

export const PhotoGridHook = {
    mounted() {
        this.observer = null
        this.observeImages()
    },
    updated() {
        this.observeImages()
    },
    destroyed() {
        if (this.observer) {
            this.observer.disconnect()
        }
    },
    observeImages() {
        if (this.observer) {
            this.observer.disconnect()
        }

        this.observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    const img = entry.target
                    if (img.dataset.src) {
                        img.src = img.dataset.src
                        img.removeAttribute('data-src')
                        this.observer.unobserve(img)
                    }
                }
            })
        }, { rootMargin: '100px' })

        this.el.querySelectorAll('img[data-src]').forEach(img => {
            this.observer.observe(img)
        })
    }
}

export const CopyToClipboardHook = {
    mounted() {
        const handleClick = async (event) => {
            event.preventDefault()
            const text = this.el.dataset.copyText || this.el.textContent

            try {
                await navigator.clipboard.writeText(text)

                const originalText = this.el.textContent
                this.el.textContent = 'Copied!'
                this.el.classList.add('text-green-400')

                setTimeout(() => {
                    this.el.textContent = originalText
                    this.el.classList.remove('text-green-400')
                }, 2000)
            } catch (err) {
                console.error('Copy failed:', err)
            }
        }

        this.el.addEventListener('click', handleClick)
        this._handleClick = handleClick
    },
    destroyed() {
        this.el.removeEventListener('click', this._handleClick)
    }
}

export const AutoFocusHook = {
    mounted() {
        // Small delay to ensure DOM is ready after LiveView update
        setTimeout(() => {
            this.el.focus()
        }, 50)
    }
}

export const LongPressOrbHook = {
    mounted() {
        this.timer = null
        this.pressing = false
        this.duration = 3000

        this.createProgressRing()

        this.el.addEventListener('mousedown', (e) => this.startPress(e))
        this.el.addEventListener('touchstart', (e) => this.startPress(e), { passive: false })
        this.el.addEventListener('mouseup', () => this.endPress())
        this.el.addEventListener('mouseleave', () => this.endPress())
        this.el.addEventListener('touchend', () => this.endPress())
        this.el.addEventListener('touchcancel', () => this.endPress())
    },

    createProgressRing() {
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
        svg.setAttribute('viewBox', '0 0 50 50')
        svg.style.cssText = 'position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; opacity: 0; transition: opacity 0.3s;'

        const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle')
        circle.setAttribute('cx', '25')
        circle.setAttribute('cy', '25')
        circle.setAttribute('r', '22')
        circle.setAttribute('fill', 'none')
        circle.setAttribute('stroke', 'rgba(255, 255, 255, 0.8)')
        circle.setAttribute('stroke-width', '2')
        circle.setAttribute('stroke-dasharray', '138.23')
        circle.setAttribute('stroke-dashoffset', '138.23')
        circle.setAttribute('transform', 'rotate(-90 25 25)')
        circle.style.transition = `stroke-dashoffset ${this.duration}ms linear`

        svg.appendChild(circle)
        this.el.style.position = 'relative'
        this.el.appendChild(svg)
        this.progressRing = circle
        this.progressSvg = svg
    },

    startPress(e) {
        if (e.type === 'mousedown' && e.button !== 0) return
        e.preventDefault()

        this.pressing = true
        this.progressSvg.style.opacity = '1'
        this.progressRing.style.strokeDashoffset = '0'

        this.timer = setTimeout(() => {
            if (this.pressing) {
                this.pushEvent("long_press_complete", {})
            }
        }, this.duration)
    },

    endPress() {
        this.pressing = false

        if (this.timer) {
            clearTimeout(this.timer)
            this.timer = null
        }

        this.progressSvg.style.opacity = '0'
        this.progressRing.style.transition = 'none'
        this.progressRing.style.strokeDashoffset = '138.23'
        this.progressRing.offsetHeight
        this.progressRing.style.transition = `stroke-dashoffset ${this.duration}ms linear`
    },

    destroyed() {
        if (this.timer) clearTimeout(this.timer)
    }
}


/**
 * PinchZoomOut - Detects 2-finger pinch-out (zoom-out) gesture
 * Shows the welcome graph when user pinches out, like zooming out to see the network
 */
export const PinchZoomOutHook = {
    mounted() {
        this.initialDistance = null
        this.triggered = false

        const getDistance = (touches) => {
            const dx = touches[0].clientX - touches[1].clientX
            const dy = touches[0].clientY - touches[1].clientY
            return Math.sqrt(dx * dx + dy * dy)
        }

        const onTouchStart = (e) => {
            if (e.touches.length === 2) {
                this.initialDistance = getDistance(e.touches)
                this.triggered = false
            }
        }

        const onTouchMove = (e) => {
            if (e.touches.length === 2 && this.initialDistance && !this.triggered) {
                const currentDistance = getDistance(e.touches)
                const delta = currentDistance - this.initialDistance

                // Pinch OUT (fingers spreading apart) - delta is positive
                // Require at least 100px spread to trigger
                if (delta > 100) {
                    this.triggered = true
                    if (navigator.vibrate) navigator.vibrate(15)
                    this.pushEvent("show_welcome_graph", {})
                }
            }
        }

        const onTouchEnd = () => {
            this.initialDistance = null
        }

        this.el.addEventListener('touchstart', onTouchStart, { passive: true })
        this.el.addEventListener('touchmove', onTouchMove, { passive: true })
        this.el.addEventListener('touchend', onTouchEnd)
        this.el.addEventListener('touchcancel', onTouchEnd)

        this._onTouchStart = onTouchStart
        this._onTouchMove = onTouchMove
        this._onTouchEnd = onTouchEnd
    },

    destroyed() {
        this.el.removeEventListener('touchstart', this._onTouchStart)
        this.el.removeEventListener('touchmove', this._onTouchMove)
        this.el.removeEventListener('touchend', this._onTouchEnd)
        this.el.removeEventListener('touchcancel', this._onTouchEnd)
    }
}

/**
 * AutoDismiss - Auto-hides flash/toast messages after delay
 */
export const AutoDismissHook = {
    mounted() {
        this.timer = setTimeout(() => {
            this.el.style.transition = 'opacity 0.3s, transform 0.3s'
            this.el.style.opacity = '0'
            this.el.style.transform = 'translate(-50%, 10px)'

            setTimeout(() => {
                this.pushEvent("lv:clear-flash", { key: this.el.id.replace('flash-', '') })
            }, 300)
        }, 4000)
    },

    destroyed() {
        if (this.timer) clearTimeout(this.timer)
    }
}

export default {
    HomeOrb: HomeOrbHook,
    NavOrbLongPress: NavOrbLongPressHook,
    DraggableAvatar: DraggableAvatarHook,
    TetheredLine: TetheredLineHook,
    SwipeableDrawer: SwipeableDrawerHook,
    LockScroll: LockScrollHook,
    PhotoGrid: PhotoGridHook,
    CopyToClipboard: CopyToClipboardHook,
    AutoFocus: AutoFocusHook,
    LongPressOrb: LongPressOrbHook,
    PinchZoomOut: PinchZoomOutHook,
    AutoDismiss: AutoDismissHook
}
