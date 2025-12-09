<script>
  import { onMount, onDestroy } from 'svelte'
  
  export let places = []
  export let liveLocations = []
  export let addingPlace = false
  export let live
  
  let mapContainer
  let map = null
  let markers = {}
  let liveMarkers = {}
  
  // Default center (Warsaw)
  const defaultCenter = { lat: 52.2297, lng: 21.0122 }
  
  onMount(async () => {
    // Wait for Google Maps to load
    if (!window.google?.maps) {
      const apiKey = document.querySelector('meta[name="google-maps-api-key"]')?.content
      if (!apiKey) {
        console.warn('Google Maps API key not found')
        return
      }
      
      await new Promise(resolve => {
        const script = document.createElement('script')
        script.src = `https://maps.googleapis.com/maps/api/js?key=${apiKey}&callback=__gmapsCallback`
        script.async = true
        window.__gmapsCallback = () => {
          delete window.__gmapsCallback
          resolve()
        }
        document.head.appendChild(script)
      })
    }
    
    initMap()
  })
  
  onDestroy(() => {
    Object.values(markers).forEach(m => m.setMap(null))
    Object.values(liveMarkers).forEach(m => m.setMap(null))
  })
  
  function initMap() {
    if (!mapContainer || !window.google?.maps) return
    
    map = new google.maps.Map(mapContainer, {
      zoom: 13,
      center: defaultCenter,
      styles: [
        { elementType: "geometry", stylers: [{ color: "#0a0a0a" }] },
        { elementType: "labels.text.stroke", stylers: [{ color: "#0a0a0a" }] },
        { elementType: "labels.text.fill", stylers: [{ color: "#525252" }] },
        { featureType: "road", elementType: "geometry", stylers: [{ color: "#171717" }] },
        { featureType: "water", elementType: "geometry", stylers: [{ color: "#0a0a0a" }] },
        { featureType: "poi", stylers: [{ visibility: "off" }] },
        { featureType: "transit", stylers: [{ visibility: "off" }] }
      ],
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: true
    })
    
    // Add existing places
    places.forEach(place => addPlaceMarker(place))
    
    // Add live locations
    liveLocations.forEach(loc => addLiveMarker(loc))
    
    // Click to add place
    map.addListener('click', e => {
      if (addingPlace && live) {
        live.pushEvent('map_clicked', { lat: e.latLng.lat(), lng: e.latLng.lng() })
      }
    })
  }
  
  function addPlaceMarker(place) {
    if (!map) return
    
    if (markers[place.id]) {
      markers[place.id].setMap(null)
    }
    
    const marker = new google.maps.Marker({
      position: { lat: place.lat, lng: place.lng },
      map: map,
      title: place.name,
      icon: {
        path: google.maps.SymbolPath.CIRCLE,
        scale: 8,
        fillColor: '#fff',
        fillOpacity: 1,
        strokeColor: '#0a0a0a',
        strokeWeight: 2
      }
    })
    
    const infoWindow = new google.maps.InfoWindow({
      content: `
        <div style="font-family: monospace; padding: 8px; color: #000;">
          <strong>${place.name}</strong>
          ${place.description ? `<p style="margin: 4px 0 0; opacity: 0.6;">${place.description}</p>` : ''}
        </div>
      `
    })
    
    marker.addListener('click', () => infoWindow.open(map, marker))
    
    markers[place.id] = marker
  }
  
  function addLiveMarker(loc) {
    if (!map) return
    
    if (liveMarkers[loc.user_id]) {
      liveMarkers[loc.user_id].setPosition({ lat: loc.lat, lng: loc.lng })
      return
    }
    
    const marker = new google.maps.Marker({
      position: { lat: loc.lat, lng: loc.lng },
      map: map,
      title: loc.user_name || 'anonymous',
      icon: {
        path: google.maps.SymbolPath.CIRCLE,
        scale: 10,
        fillColor: loc.user_color || '#fff',
        fillOpacity: 1,
        strokeColor: '#fff',
        strokeWeight: 3
      },
      zIndex: 1000
    })
    
    liveMarkers[loc.user_id] = marker
  }
  
  // Reactive updates
  $: if (map && places) {
    places.forEach(place => addPlaceMarker(place))
  }
  
  $: if (map && liveLocations) {
    // Remove old markers
    const currentIds = liveLocations.map(l => l.user_id)
    Object.keys(liveMarkers).forEach(id => {
      if (!currentIds.includes(id)) {
        liveMarkers[id].setMap(null)
        delete liveMarkers[id]
      }
    })
    // Add/update markers
    liveLocations.forEach(loc => addLiveMarker(loc))
  }
</script>

<div 
  bind:this={mapContainer} 
  class="w-full h-[500px] bg-neutral-900"
  class:cursor-crosshair={addingPlace}
></div>

<style>
  :global(.gm-style-iw) {
    background: #fff !important;
  }
</style>

