import { PushNotifications } from '@capacitor/push-notifications';
import { Capacitor } from '@capacitor/core';

const PushNotificationsHook = {
    mounted() {
        if (Capacitor.isNativePlatform()) {
            this.initPushNotifications();
        }
    },

    async initPushNotifications() {
        try {
            // Check current permission status
            let permStatus = await PushNotifications.checkPermissions();

            if (permStatus.receive === 'prompt') {
                permStatus = await PushNotifications.requestPermissions();
            }

            if (permStatus.receive !== 'granted') {
                console.warn('Push notification permission not granted');
                return;
            }

            // Register with Apple / Google to receive push via APNS/FCM
            await PushNotifications.register();

            // Listen for registration success
            PushNotifications.addListener('registration', (token) => {
                console.log('Push registration success, token:', token.value);
                // Send token to backend
                this.pushEvent('register_device_token', {
                    token: token.value,
                    platform: Capacitor.getPlatform()
                });
            });

            // Listen for registration errors
            PushNotifications.addListener('registrationError', (error) => {
                console.error('Push registration error: ', error);
            });

            // Listen for incoming notifications
            PushNotifications.addListener('pushNotificationReceived', (notification) => {
                console.log('Push received: ', notification);
                // Optionally trigger a UI update or event
                this.pushEvent('push_notification_received', notification);
            });

            // Listen for notification actions (tapped)
            PushNotifications.addListener('pushNotificationActionPerformed', (notification) => {
                console.log('Push action performed: ', notification);
                this.pushEvent('push_notification_action', notification);
            });

        } catch (e) {
            console.error('Failed to initialize push notifications', e);
        }
    }
};

export default PushNotificationsHook;
