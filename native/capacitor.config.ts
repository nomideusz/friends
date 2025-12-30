import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
    appId: 'com.friends.app',
    appName: 'Friends',
    webDir: 'www',
    server: {
        // Point to your Phoenix server
        // For development, use your local IP (not localhost!)
        url: 'http://192.168.1.100:4001', // Change to your Phoenix server URL
        cleartext: true, // Allow HTTP in development
    },
    // iOS specific settings
    ios: {
        contentInset: 'automatic',
        allowsLinkPreview: false,
    },
    // Android specific settings
    android: {
        allowMixedContent: true, // Allow HTTP content
    },
    // Plugin settings
    plugins: {
        SplashScreen: {
            launchAutoHide: true,
            backgroundColor: '#0a0a0a',
            androidSplashResourceName: 'splash',
            showSpinner: false,
        },
    },
};

export default config;
