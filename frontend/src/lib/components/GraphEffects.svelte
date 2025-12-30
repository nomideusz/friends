<script lang="ts">
    import { T, useTask, useThrelte } from "@threlte/core";
    import * as THREE from "three";
    import { onMount, onDestroy } from "svelte";
    import {
        EffectComposer,
        RenderPass,
        EffectPass,
        BloomEffect,
        BlendFunction,
    } from "postprocessing";

    // Props
    export let nodes: any[] = [];
    export let links: any[] = [];

    const { scene, renderer, camera, size } = useThrelte();

    // Particle system state
    let particleGeometry: THREE.BufferGeometry;
    let particleMaterial: THREE.ShaderMaterial;
    let particleSystem: THREE.Points;
    let particlePositions: Float32Array;
    let particleColors: Float32Array;
    let particleProgress: number[] = [];
    let particleLinkIndex: number[] = [];
    let particleDirection: number[] = []; // 1 = forward, -1 = backward (bi-directional)

    // Tweaked settings
    const PARTICLES_PER_LINK = 2; // Fewer particles (was 3)
    const BASE_SPEED = 0.15; // Slower flow (was 0.3)

    // Effect composer for bloom
    let composer: EffectComposer;

    // Gradient colors (pink to cyan)
    const colorStart = new THREE.Color(0xff6b9d); // Pink
    const colorEnd = new THREE.Color(0x00d4ff); // Cyan

    // Custom shader for gradient colored particles
    const vertexShader = `
        attribute vec3 color;
        varying vec3 vColor;
        void main() {
            vColor = color;
            vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
            gl_PointSize = 3.0 * (200.0 / -mvPosition.z);
            gl_Position = projectionMatrix * mvPosition;
        }
    `;

    const fragmentShader = `
        varying vec3 vColor;
        void main() {
            float dist = length(gl_PointCoord - vec2(0.5));
            if (dist > 0.5) discard;
            float alpha = 1.0 - smoothstep(0.3, 0.5, dist);
            gl_FragColor = vec4(vColor, alpha * 0.9);
        }
    `;

    // Initialize particles and bloom
    onMount(() => {
        if (!renderer || !scene || !camera) return;

        const cam = camera.current as unknown as THREE.PerspectiveCamera;
        const rend = renderer as unknown as THREE.WebGLRenderer;

        // Setup bloom post-processing (weaker bloom)
        composer = new EffectComposer(rend);
        composer.addPass(new RenderPass(scene, cam));

        const bloomEffect = new BloomEffect({
            intensity: 0.8, // Weaker bloom (was 1.5)
            luminanceThreshold: 0.3, // Higher threshold
            luminanceSmoothing: 0.8,
            blendFunction: BlendFunction.ADD,
            mipmapBlur: true,
        });

        composer.addPass(new EffectPass(cam, bloomEffect));

        // Initialize particle system
        initParticles();
    });

    function initParticles() {
        const numParticles = links.length * PARTICLES_PER_LINK * 2; // x2 for bi-directional
        if (numParticles === 0) return;

        particlePositions = new Float32Array(numParticles * 3);
        particleColors = new Float32Array(numParticles * 3);
        particleProgress = [];
        particleLinkIndex = [];
        particleDirection = [];

        // Initialize particles - half go forward, half go backward
        for (let i = 0; i < links.length; i++) {
            for (let j = 0; j < PARTICLES_PER_LINK; j++) {
                // Forward particle
                particleProgress.push(Math.random());
                particleLinkIndex.push(i);
                particleDirection.push(1);

                // Backward particle (bi-directional)
                particleProgress.push(Math.random());
                particleLinkIndex.push(i);
                particleDirection.push(-1);
            }
        }

        particleGeometry = new THREE.BufferGeometry();
        particleGeometry.setAttribute(
            "position",
            new THREE.BufferAttribute(particlePositions, 3),
        );
        particleGeometry.setAttribute(
            "color",
            new THREE.BufferAttribute(particleColors, 3),
        );

        // Use shader material for gradient colors
        particleMaterial = new THREE.ShaderMaterial({
            vertexShader,
            fragmentShader,
            transparent: true,
            blending: THREE.AdditiveBlending,
            depthWrite: false,
        });

        particleSystem = new THREE.Points(particleGeometry, particleMaterial);
        scene.add(particleSystem);
    }

    // Update particles every frame
    useTask((delta) => {
        if (!particleSystem || links.length === 0) return;

        const positions = particleGeometry.attributes.position
            .array as Float32Array;
        const colors = particleGeometry.attributes.color.array as Float32Array;

        for (let i = 0; i < particleProgress.length; i++) {
            // Update progress with direction (slower speed + organic variation)
            const speedVariation =
                0.8 + Math.sin(i * 0.7 + Date.now() * 0.001) * 0.2;
            particleProgress[i] +=
                delta * BASE_SPEED * speedVariation * particleDirection[i];

            // Wrap around for bi-directional flow
            if (particleProgress[i] > 1) particleProgress[i] = 0;
            if (particleProgress[i] < 0) particleProgress[i] = 1;

            const link = links[particleLinkIndex[i]];
            if (!link) continue;

            // Get source and target positions
            const source = typeof link.source === "object" ? link.source : null;
            const target = typeof link.target === "object" ? link.target : null;

            if (!source || !target) continue;

            const sx = source.x ?? 0;
            const sy = source.y ?? 0;
            const sz = source.z ?? 0;
            const tx = target.x ?? 0;
            const ty = target.y ?? 0;
            const tz = target.z ?? 0;

            // Interpolate position along the link
            const t = particleProgress[i];
            positions[i * 3] = sx + (tx - sx) * t;
            positions[i * 3 + 1] = sy + (ty - sy) * t;
            positions[i * 3 + 2] = sz + (tz - sz) * t;

            // Gradient color based on progress (pink → cyan)
            const color = new THREE.Color().lerpColors(colorStart, colorEnd, t);
            colors[i * 3] = color.r;
            colors[i * 3 + 1] = color.g;
            colors[i * 3 + 2] = color.b;
        }

        particleGeometry.attributes.position.needsUpdate = true;
        particleGeometry.attributes.color.needsUpdate = true;

        // Render with bloom
        if (composer) {
            composer.render(delta);
        }
    });

    // Cleanup
    onDestroy(() => {
        if (particleSystem && scene) {
            scene.remove(particleSystem);
        }
        if (particleGeometry) particleGeometry.dispose();
        if (particleMaterial) particleMaterial.dispose();
        if (composer) composer.dispose();
    });

    // Reinitialize particles when links change
    $: if (links.length > 0 && scene) {
        if (particleSystem) {
            scene.remove(particleSystem);
            particleGeometry?.dispose();
            particleMaterial?.dispose();
        }
        initParticles();
    }
</script>

<!-- This component is render-less, it adds effects to the scene -->
