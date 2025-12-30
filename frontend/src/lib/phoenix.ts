/**
 * Phoenix WebSocket connection for SvelteKit frontend.
 * Connects to Phoenix Channels for real-time updates.
 */
import { Socket, Presence } from 'phoenix';
import { writable, type Writable } from 'svelte/store';

// Configuration
const SOCKET_URL = import.meta.env.DEV
    ? 'ws://localhost:4001/api/socket'
    : `wss://${window.location.host}/api/socket`;

// Connection state store
export const connected = writable(false);
export const connectionError: Writable<string | null> = writable(null);

// Socket singleton
let socket: Socket | null = null;

/**
 * Initialize Phoenix socket connection
 */
export function initSocket(token?: string): Socket {
    if (socket) return socket;

    socket = new Socket(SOCKET_URL, {
        params: token ? { token } : {},
        reconnectAfterMs: (tries: number) => [1000, 2000, 5000, 10000][Math.min(tries - 1, 3)],
    });

    socket.onOpen(() => {
        connected.set(true);
        connectionError.set(null);
        console.log('[Phoenix] Connected');
    });

    socket.onClose(() => {
        connected.set(false);
        console.log('[Phoenix] Disconnected');
    });

    socket.onError((error) => {
        connectionError.set('Connection error');
        console.error('[Phoenix] Error:', error);
    });

    socket.connect();
    return socket;
}

/**
 * Get the socket instance (initialize if needed)
 */
export function getSocket(): Socket {
    if (!socket) {
        return initSocket();
    }
    return socket;
}

/**
 * Disconnect the socket
 */
export function disconnectSocket(): void {
    if (socket) {
        socket.disconnect();
        socket = null;
        connected.set(false);
    }
}

// ============================================================================
// Presence Store
// ============================================================================

export interface UserPresence {
    id: string;
    username: string;
    avatar?: string;
    online_at: number;
    typing?: boolean;
}

export const presenceStore: Writable<Map<string, UserPresence>> = writable(new Map());

/**
 * Join a room channel with presence tracking
 */
export function joinRoom(roomId: string) {
    const socket = getSocket();
    const channel = socket.channel(`room:${roomId}`, {});

    // Presence tracking
    const presence = new Presence(channel);

    presence.onSync(() => {
        const users = new Map<string, UserPresence>();
        presence.list((id: string, { metas }: { metas: any[] }) => {
            const meta = metas[0];
            users.set(id, {
                id,
                username: meta.username || id,
                avatar: meta.avatar,
                online_at: meta.online_at,
                typing: meta.typing || false
            });
        });
        presenceStore.set(users);
    });

    channel.join()
        .receive('ok', () => {
            console.log(`[Phoenix] Joined room:${roomId}`);
        })
        .receive('error', (resp) => {
            console.error(`[Phoenix] Failed to join room:${roomId}`, resp);
        });

    return {
        channel,
        presence,
        leave: () => {
            channel.leave();
            presenceStore.set(new Map());
        }
    };
}

// ============================================================================
// Graph Channel (Real-time updates)
// ============================================================================

export interface GraphUpdateCallbacks {
    onNewUser?: (userData: { id: number; username: string; display_name?: string }) => void;
    onNewConnection?: (data: { from_id: number; to_id: number }) => void;
    onConnectionRemoved?: (data: { from_id: number; to_id: number }) => void;
    onUserDeleted?: (data: { user_id: number }) => void;
    onSignal?: (data: { user_id: number }) => void;
}

/**
 * Join the global graph channel for real-time updates
 */
export function joinGraph(callbacks: GraphUpdateCallbacks) {
    const socket = getSocket();
    const channel = socket.channel('friends:global', {});

    // Subscribe to graph events
    channel.on('friend_accepted', (data: any) => {
        // New connection between users
        if (callbacks.onNewConnection) {
            callbacks.onNewConnection({
                from_id: data.user_id || data.from_id,
                to_id: data.friend_user_id || data.to_id
            });
        }
    });

    channel.on('friend_removed', (data: any) => {
        if (callbacks.onConnectionRemoved) {
            callbacks.onConnectionRemoved({
                from_id: data.user_id || data.from_id,
                to_id: data.friend_user_id || data.to_id
            });
        }
    });

    channel.on('welcome_new_user', (userData: any) => {
        if (callbacks.onNewUser) {
            callbacks.onNewUser(userData);
        }
    });

    channel.on('welcome_user_deleted', (data: any) => {
        if (callbacks.onUserDeleted) {
            callbacks.onUserDeleted(data);
        }
    });

    channel.on('welcome_signal', (data: any) => {
        if (callbacks.onSignal) {
            callbacks.onSignal(data);
        }
    });

    channel.join()
        .receive('ok', () => {
            console.log('[Phoenix] Joined friends:global channel');
        })
        .receive('error', (resp: any) => {
            console.error('[Phoenix] Failed to join friends:global', resp);
        });

    return {
        channel,
        leave: () => channel.leave()
    };
}

// ============================================================================
// Message Store
// ============================================================================

export interface Message {
    id: string;
    sender_id: string;
    content: string;
    type: 'text' | 'voice' | 'image';
    metadata?: Record<string, any>;
    inserted_at: string;
}

export const messagesStore: Writable<Message[]> = writable([]);

/**
 * Subscribe to room messages
 */
export function subscribeToMessages(channel: any) {
    channel.on('new_message', (msg: Message) => {
        messagesStore.update(messages => [...messages, msg]);
    });

    channel.on('message_deleted', ({ id }: { id: string }) => {
        messagesStore.update(messages => messages.filter(m => m.id !== id));
    });
}

// ============================================================================
// API Client
// ============================================================================

const API_BASE = import.meta.env.DEV
    ? 'http://localhost:4001/api/v1'
    : '/api/v1';

/**
 * Fetch wrapper with auth
 */
async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
    const response = await fetch(`${API_BASE}${path}`, {
        ...options,
        headers: {
            'Content-Type': 'application/json',
            ...options.headers,
        },
        credentials: 'include', // Include session cookies
    });

    if (!response.ok) {
        throw new Error(`API Error: ${response.status}`);
    }

    return response.json();
}

export const api = {
    // Auth
    getRegistrationChallenge: (username: string) =>
        apiFetch<any>('/auth/register/challenge', {
            method: 'POST',
            body: JSON.stringify({ username })
        }),
    register: (credential: any) =>
        apiFetch<any>('/auth/register', {
            method: 'POST',
            body: JSON.stringify({ credential })
        }),
    getLoginChallenge: (username: string) =>
        apiFetch<any>('/auth/login/challenge', {
            method: 'POST',
            body: JSON.stringify({ username })
        }),
    login: (credential: any) =>
        apiFetch<any>('/auth/login', {
            method: 'POST',
            body: JSON.stringify({ credential })
        }),
    logout: () =>
        apiFetch<any>('/auth/logout', { method: 'POST' }),

    // Users
    getMe: () => apiFetch<any>('/me'),
    getUser: (id: string) => apiFetch<any>(`/users/${id}`),
    searchUsers: (q: string) => apiFetch<any>(`/users/search?q=${encodeURIComponent(q)}`),
    getFriends: () => apiFetch<any>('/friends'),

    // Rooms
    getRooms: () => apiFetch<any>('/rooms'),
    getRoom: (id: string) => apiFetch<any>(`/rooms/${id}`),
    getRoomMessages: (id: string) => apiFetch<any>(`/rooms/${id}/messages`),

    // Graph
    getGraph: () => apiFetch<any>('/graph'),
};

