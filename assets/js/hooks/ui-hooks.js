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

export const ProgressiveSignOutHook = {
    mounted() {
        this.timer = null
        this.morphTimer = null
        this.pressing = false
        this.duration = 3000

        this.el.style.userSelect = 'none'
        this.el.style.webkitUserSelect = 'none'
        this.el.style.touchAction = 'manipulation'

        this.createProgressRing()
        this.originalIcon = this.el.querySelector('svg')?.outerHTML
        this.iconContainer = this.el.querySelector('div.w-7')

        const startPress = (e) => {
            if (e.type === 'mousedown' && e.button !== 0) return
            e.preventDefault()

            this.pressing = true

            setTimeout(() => {
                if (!this.pressing) return
                this.progressSvg.style.opacity = '1'
                this.progressRing.style.strokeDashoffset = '0'
                if (navigator.vibrate) navigator.vibrate(10)
            }, 500)

            this.morphTimer = setTimeout(() => {
                if (!this.pressing) return
                if (this.iconContainer) {
                    this.iconContainer.innerHTML = `
                        <svg class="w-4 h-4 animate-pulse" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
                        </svg>
                    `
                }
                if (navigator.vibrate) navigator.vibrate([30, 30, 30])
            }, 1500)

            this.timer = setTimeout(() => {
                if (this.pressing) {
                    if (navigator.vibrate) navigator.vibrate([50, 50, 100])
                    this.pushEvent("sign_out", {})
                    this.pressing = false
                    this.resetVisuals()
                }
            }, this.duration)
        }

        const endPress = (e) => {
            if (!this.pressing) return

            this.pressing = false

            if (this.timer) {
                clearTimeout(this.timer)
                this.timer = null
            }
            if (this.morphTimer) {
                clearTimeout(this.morphTimer)
                this.morphTimer = null
            }

            this.resetVisuals()
        }

        this.el.addEventListener('mousedown', startPress)
        this.el.addEventListener('touchstart', startPress, { passive: false })
        this.el.addEventListener('mouseup', endPress)
        this.el.addEventListener('mouseleave', endPress)
        this.el.addEventListener('touchend', endPress)
        this.el.addEventListener('touchcancel', endPress)

        this.el.addEventListener('click', (e) => {
            e.preventDefault()
            e.stopPropagation()
        })
    },

    createProgressRing() {
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
        svg.setAttribute('class', 'progressive-sign-out-ring')
        svg.setAttribute('viewBox', '0 0 50 50')
        svg.style.cssText = 'position: absolute; inset: -4px; width: calc(100% + 8px); height: calc(100% + 8px); pointer-events: none; opacity: 0; transition: opacity 0.3s; z-index: 10;'

        const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle')
        circle.setAttribute('cx', '25')
        circle.setAttribute('cy', '25')
        circle.setAttribute('r', '22')
        circle.setAttribute('fill', 'none')
        circle.setAttribute('stroke', 'rgba(239, 68, 68, 0.8)')
        circle.setAttribute('stroke-width', '3')
        circle.setAttribute('stroke-linecap', 'round')
        circle.setAttribute('stroke-dasharray', '138.23')
        circle.setAttribute('stroke-dashoffset', '138.23')
        circle.setAttribute('transform', 'rotate(-90 25 25)')
        circle.style.transition = `stroke-dashoffset ${this.duration - 500}ms linear`

        svg.appendChild(circle)
        this.el.style.position = 'relative'
        this.el.appendChild(svg)
        this.progressRing = circle
        this.progressSvg = svg
    },

    resetVisuals() {
        this.progressSvg.style.opacity = '0'
        this.progressRing.style.transition = 'none'
        this.progressRing.style.strokeDashoffset = '138.23'
        this.progressRing.offsetHeight
        this.progressRing.style.transition = `stroke-dashoffset ${this.duration - 500}ms linear`

        if (this.iconContainer && this.originalIcon) {
            this.iconContainer.innerHTML = this.originalIcon
        }
    },

    destroyed() {
        if (this.timer) clearTimeout(this.timer)
        if (this.morphTimer) clearTimeout(this.morphTimer)
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
    ProgressiveSignOut: ProgressiveSignOutHook,
    SwipeableDrawer: SwipeableDrawerHook,
    LockScroll: LockScrollHook,
    PhotoGrid: PhotoGridHook,
    CopyToClipboard: CopyToClipboardHook,
    AutoFocus: AutoFocusHook,
    LongPressOrb: LongPressOrbHook,
    PinchZoomOut: PinchZoomOutHook,
    AutoDismiss: AutoDismissHook
}
