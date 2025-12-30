/**
 * Auth Store for SvelteKit
 * Manages user authentication state with WebAuthn.
 */
import { writable, derived, get } from 'svelte/store';
import { api } from '$lib/phoenix';
import { registerCredential, authenticateWithCredential, isWebAuthnSupported } from '$lib/webauthn';

export interface User {
    id: number;
    username: string;
    display_name: string | null;
    avatar_url: string | null;
}

// Stores
export const user = writable<User | null>(null);
export const isLoading = writable(false);
export const authError = writable<string | null>(null);

// Derived stores
export const isAuthenticated = derived(user, $user => $user !== null);

/**
 * Initialize auth state by checking current session
 */
export async function initAuth(): Promise<void> {
    try {
        const me = await api.getMe();
        user.set(me);
    } catch {
        user.set(null);
    }
}

/**
 * Register a new user with WebAuthn
 */
export async function register(username: string): Promise<boolean> {
    if (!isWebAuthnSupported()) {
        authError.set('WebAuthn is not supported in this browser');
        return false;
    }

    isLoading.set(true);
    authError.set(null);

    try {
        // Get registration challenge from server
        const options = await api.getRegistrationChallenge(username);

        // Create credential using browser WebAuthn API
        const credential = await registerCredential(options);

        // Send credential to server for verification
        const result = await api.register(credential);

        if (result.success) {
            user.set(result.user);
            return true;
        } else {
            authError.set(result.error || 'Registration failed');
            return false;
        }
    } catch (error) {
        const message = error instanceof Error ? error.message : 'Registration failed';
        authError.set(message);
        return false;
    } finally {
        isLoading.set(false);
    }
}

/**
 * Login an existing user with WebAuthn
 */
export async function login(username: string): Promise<boolean> {
    if (!isWebAuthnSupported()) {
        authError.set('WebAuthn is not supported in this browser');
        return false;
    }

    isLoading.set(true);
    authError.set(null);

    try {
        // Get authentication challenge from server
        const options = await api.getLoginChallenge(username);

        // Authenticate using browser WebAuthn API
        const credential = await authenticateWithCredential(options);

        // Send assertion to server for verification
        const result = await api.login(credential);

        if (result.success) {
            user.set(result.user);
            return true;
        } else {
            authError.set(result.error || 'Login failed');
            return false;
        }
    } catch (error) {
        const message = error instanceof Error ? error.message : 'Login failed';
        authError.set(message);
        return false;
    } finally {
        isLoading.set(false);
    }
}

/**
 * Logout the current user
 */
export async function logout(): Promise<void> {
    try {
        await api.logout();
    } finally {
        user.set(null);
    }
}
