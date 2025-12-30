/**
 * Native feature helpers for Capacitor.
 * Provides graceful fallbacks for web.
 */
import { Capacitor } from '@capacitor/core';
import { Haptics, ImpactStyle, NotificationType } from '@capacitor/haptics';
import { StatusBar, Style } from '@capacitor/status-bar';
import { SplashScreen } from '@capacitor/splash-screen';

// Check if running in native app
export const isNative = Capacitor.isNativePlatform();
export const platform = Capacitor.getPlatform();

/**
 * Haptic feedback helpers
 */
export const haptics = {
    /**
     * Light impact - for node hover, button press
     */
    async light() {
        if (isNative) {
            await Haptics.impact({ style: ImpactStyle.Light });
        }
    },

    /**
     * Medium impact - for node selection, navigation
     */
    async medium() {
        if (isNative) {
            await Haptics.impact({ style: ImpactStyle.Medium });
        }
    },

    /**
     * Heavy impact - for important actions
     */
    async heavy() {
        if (isNative) {
            await Haptics.impact({ style: ImpactStyle.Heavy });
        }
    },

    /**
     * Success notification - for completed actions
     */
    async success() {
        if (isNative) {
            await Haptics.notification({ type: NotificationType.Success });
        }
    },

    /**
     * Warning notification - for warnings/errors
     */
    async warning() {
        if (isNative) {
            await Haptics.notification({ type: NotificationType.Warning });
        }
    },

    /**
     * Warmth pulse - the signature "New Internet" haptic
     * Subtle double-tap that feels like a heartbeat
     */
    async warmthPulse() {
        if (isNative) {
            await Haptics.impact({ style: ImpactStyle.Light });
            await new Promise(r => setTimeout(r, 60));
            await Haptics.impact({ style: ImpactStyle.Light });
        } else {
            // Web fallback - visual pulse
            document.body.classList.add('warmth-pulse');
            setTimeout(() => document.body.classList.remove('warmth-pulse'), 300);
        }
    }
};

/**
 * Status bar helpers
 */
export const statusBar = {
    async setDark() {
        if (isNative) {
            await StatusBar.setStyle({ style: Style.Dark });
            await StatusBar.setBackgroundColor({ color: '#0a0a0a' });
        }
    },

    async hide() {
        if (isNative) {
            await StatusBar.hide();
        }
    },

    async show() {
        if (isNative) {
            await StatusBar.show();
        }
    }
};

/**
 * Splash screen helpers
 */
export const splash = {
    async hide() {
        if (isNative) {
            await SplashScreen.hide({ fadeOutDuration: 300 });
        }
    }
};

/**
 * Initialize native features on app start
 */
export async function initNative() {
    if (isNative) {
        await statusBar.setDark();
        // Delay splash hide for smooth transition
        setTimeout(() => splash.hide(), 500);
    }
}
