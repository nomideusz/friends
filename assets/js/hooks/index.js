/**
 * Hooks Index
 * Central export of all LiveView hooks organized by category
 */

import GraphHooks from './graph-hooks'
import AuthHooks from './auth-hooks'
import MediaHooks from './media-hooks'
import UIHooks from './ui-hooks'
import ChatHooks from './chat-hooks'

// Re-export getAudioContext for use in main app
export { getAudioContext } from './media-hooks'

// Combined hooks object
export default {
    ...GraphHooks,
    ...AuthHooks,
    ...MediaHooks,
    ...UIHooks,
    ...ChatHooks
}
