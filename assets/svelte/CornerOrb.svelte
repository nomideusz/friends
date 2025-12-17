<script>
    import { onMount } from 'svelte';
    
    // Props
    export let position = 'top-left'; // top-left, top-right, bottom-left, bottom-right
    export let icon = 'orb'; // orb, plus, user
    export let label = '';
    export let showLabel = false;
    export let active = false;
    export let notification = false;
    export let onClick = null;
    export let menuItems = []; // Array of { icon, label, action }
    
    let showMenu = false;
    let orbEl;
    
    // Position classes
    const positionClasses = {
        'top-left': 'top-4 left-4',
        'top-right': 'top-4 right-4',
        'bottom-left': 'bottom-4 left-4',
        'bottom-right': 'bottom-4 right-4'
    };
    
    // Menu position for radial expansion
    const menuPositions = {
        'top-left': { startAngle: 0, endAngle: 90 },
        'top-right': { startAngle: 90, endAngle: 180 },
        'bottom-left': { startAngle: 270, endAngle: 360 },
        'bottom-right': { startAngle: 180, endAngle: 270 }
    };
    
    function handleClick() {
        if (menuItems.length > 0) {
            showMenu = !showMenu;
        } else if (onClick) {
            onClick();
        }
    }
    
    function handleMenuItemClick(item) {
        showMenu = false;
        if (item.action) {
            item.action();
        }
    }
    
    function handleClickOutside(event) {
        if (orbEl && !orbEl.contains(event.target)) {
            showMenu = false;
        }
    }
    
    // Calculate radial menu item positions
    function getMenuItemStyle(index, total) {
        const { startAngle, endAngle } = menuPositions[position];
        const angleRange = endAngle - startAngle;
        const angleStep = total > 1 ? angleRange / (total - 1) : 0;
        const angle = startAngle + (angleStep * index);
        const radians = (angle * Math.PI) / 180;
        const radius = 70;
        
        const x = Math.cos(radians) * radius;
        const y = Math.sin(radians) * radius;
        
        return `transform: translate(${x}px, ${y}px);`;
    }
    
    onMount(() => {
        document.addEventListener('click', handleClickOutside);
        return () => {
            document.removeEventListener('click', handleClickOutside);
        };
    });
</script>

<div 
    bind:this={orbEl}
    class="fixed z-[100] {positionClasses[position]}"
>
    <!-- Main Orb Button -->
    <button
        type="button"
        class="corner-orb group relative flex items-center justify-center w-12 h-12 rounded-full transition-all duration-300 cursor-pointer
               bg-white/5 border border-white/10 backdrop-blur-md
               hover:bg-white/10 hover:border-white/20 hover:scale-110 hover:shadow-[0_0_30px_rgba(255,255,255,0.2)]
               {active ? 'bg-white/15 border-white/30 shadow-[0_0_25px_rgba(255,255,255,0.3)]' : ''}
               {showMenu ? 'bg-white/20 scale-110' : ''}"
        on:click={handleClick}
    >
        <!-- Icon -->
        {#if icon === 'orb'}
            <div class="w-3 h-3 rounded-full bg-white shadow-[0_0_15px_rgba(255,255,255,0.8)] group-hover:scale-110 transition-transform"></div>
        {:else if icon === 'plus'}
            <svg class="w-5 h-5 text-white/70 group-hover:text-white transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
            </svg>
        {:else if icon === 'user'}
            <svg class="w-5 h-5 text-white/70 group-hover:text-white transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
            </svg>
        {:else if icon === 'menu'}
            <svg class="w-5 h-5 text-white/70 group-hover:text-white transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
            </svg>
        {/if}
        
        <!-- Notification dot -->
        {#if notification}
            <div class="absolute -top-0.5 -right-0.5 w-2.5 h-2.5 rounded-full bg-red-500 border border-black"></div>
        {/if}
        
        <!-- Label (shows on hover) -->
        {#if showLabel && label}
            <div class="absolute whitespace-nowrap px-2 py-1 rounded bg-black/80 text-xs text-white/80 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none
                        {position.includes('left') ? 'left-14' : 'right-14'}
                        {position.includes('top') ? 'top-1/2 -translate-y-1/2' : 'bottom-1/2 translate-y-1/2'}">
                {label}
            </div>
        {/if}
    </button>
    
    <!-- Radial Menu -->
    {#if showMenu && menuItems.length > 0}
        <div class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2">
            {#each menuItems as item, i}
                <button
                    type="button"
                    class="absolute top-0 left-0 -translate-x-1/2 -translate-y-1/2 w-10 h-10 rounded-full 
                           bg-black/80 border border-white/20 backdrop-blur-md
                           flex items-center justify-center cursor-pointer
                           hover:bg-white/10 hover:border-white/40 hover:scale-110
                           transition-all duration-200 animate-in fade-in zoom-in-75"
                    style="{getMenuItemStyle(i, menuItems.length)} animation-delay: {i * 50}ms;"
                    on:click={() => handleMenuItemClick(item)}
                    title={item.label}
                >
                    {#if item.emoji}
                        <span class="text-base">{item.emoji}</span>
                    {:else if item.icon}
                        <span class="text-white/80">{@html item.icon}</span>
                    {:else}
                        <span class="text-xs text-white/80">{item.label?.charAt(0)}</span>
                    {/if}
                </button>
            {/each}
        </div>
    {/if}
</div>

<style>
    .corner-orb {
        -webkit-tap-highlight-color: transparent;
    }
</style>
