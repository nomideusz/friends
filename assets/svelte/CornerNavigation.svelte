<script>
    import CornerOrb from './CornerOrb.svelte';
    
    // Props passed from LiveView
    export let live = null;
    export let currentUser = null;
    export let pendingCount = 0;
    export let currentRoute = '/';
    export let rooms = [];
    export let contacts = [];
    
    // Create menu items
    const createMenuItems = [
        { 
            emoji: '📸', 
            label: 'Photo', 
            action: () => triggerPhotoUpload()
        },
        { 
            emoji: '📝', 
            label: 'Note', 
            action: () => live?.pushEvent('open_note_modal', {})
        },
        { 
            emoji: '🎤', 
            label: 'Voice', 
            action: () => live?.pushEvent('start_voice_recording', {})
        },
        { 
            emoji: '👥', 
            label: 'Group', 
            action: () => live?.pushEvent('open_create_group', {})
        },
        { 
            emoji: '👋', 
            label: 'Invite', 
            action: () => live?.pushEvent('open_invite_modal', {})
        }
    ];
    
    // User menu items
    const userMenuItems = [
        { 
            emoji: '👤', 
            label: 'Profile', 
            action: () => navigateTo('/network')
        },
        { 
            emoji: '🔐', 
            label: 'Devices', 
            action: () => navigateTo('/devices')
        },
        { 
            emoji: '🚪', 
            label: 'Sign Out', 
            action: () => live?.pushEvent('sign_out', {})
        }
    ];
    
    // Navigation menu items
    $: navMenuItems = [
        { 
            emoji: '🌐', 
            label: 'Graph', 
            action: () => live?.pushEvent('toggle_graph_drawer', {})
        },

        ...rooms.slice(0, 3).map(room => ({
            emoji: '💬',
            label: room.name || room.code,
            action: () => navigateTo(`/r/${room.code}`)
        }))
    ];
    
    function navigateTo(path) {
        window.location.href = path;
    }
    
    function triggerPhotoUpload() {
        // Find the photo input and trigger click
        const input = document.querySelector('#upload-form-feed_photo input') || 
                      document.querySelector('input[type="file"][name="photo"]');
        if (input) {
            input.click();
        } else {
            // Fallback: push event to open upload
            live?.pushEvent('open_photo_upload', {});
        }
    }
    
    function handleHomeClick() {
        if (currentRoute === '/') {
            // Already home, maybe show breadcrumb or do nothing
            return;
        }
        navigateTo('/');
    }
    
    $: isHome = currentRoute === '/' || currentRoute === '';
</script>

{#if currentUser}
    <!-- Top Left: Home Orb -->
    <CornerOrb 
        position="top-left"
        icon="orb"
        label="Home"
        showLabel={true}
        active={isHome}
        onClick={handleHomeClick}
    />
    
    <!-- Top Right: User Orb -->
    <CornerOrb 
        position="top-right"
        icon="user"
        label={currentUser.username}
        showLabel={true}
        notification={pendingCount > 0}
        menuItems={userMenuItems}
    />
    
    <!-- Bottom Left: Navigation Orb -->
    <CornerOrb 
        position="bottom-left"
        icon="menu"
        label="Navigate"
        showLabel={true}
        menuItems={navMenuItems}
    />
    
    <!-- Bottom Right: Create Orb -->
    <CornerOrb 
        position="bottom-right"
        icon="plus"
        label="Create"
        showLabel={true}
        menuItems={createMenuItems}
    />
{/if}
