import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
    appId: 'app.newinternet',
    appName: 'New Internet',
    webDir: 'build',

    server: {
        // For development - uncomment and set to your dev server
        // url: 'http://localhost:5173',
        // cleartext: true
    },

    plugins: {
        SplashScreen: {
            launchAutoHide: false,
            backgroundColor: '#0a0a0a',
            showSpinner: false
        },
        Keyboard: {
            resize: 'body',
            style: 'dark'
        },
        StatusBar: {
            style: 'dark',
            backgroundColor: '#0a0a0a'
        }
    },

    ios: {
        scheme: 'New Internet',
        backgroundColor: '#0a0a0a'
    },

    android: {
        backgroundColor: '#0a0a0a'
    }
};

export default config;
