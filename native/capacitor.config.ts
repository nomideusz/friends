import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
    appId: 'online.newinternet.app',
    appName: 'New Internet',
    webDir: 'www',
    server: {
        // Use production server for passkey RP ID validation
        url: 'https://newinternet.online',
        // cleartext: false by default for HTTPS
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
