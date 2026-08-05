<script setup lang="ts">
import { useRoute, hrefFor, phaseCrumb } from './lib/router'
import SessionsList from './components/SessionsList.vue'
import SessionTrace from './components/SessionTrace.vue'

const route = useRoute()
</script>

<template>
  <div class="app">
    <header class="topbar">
      <nav class="crumbs">
        <!-- Inline copy of public/logo.svg (the favicon) so the mark renders
             crisply with no fetch; keep the two in sync. -->
        <svg class="logo" viewBox="0 0 32 32" aria-hidden="true">
          <rect x="4" y="6" width="17" height="5" rx="2.5" fill="#e8b64a" />
          <rect x="8" y="13.5" width="20" height="5" rx="2.5" fill="#c89bff" />
          <rect x="4" y="21" width="13" height="5" rx="2.5" fill="#5ad2dd" />
        </svg>
        <span class="brand">Super Simple Software Factory</span>
        <span class="sep">›</span>
        <a :href="hrefFor()" :class="{ current: !route.adwId }">sessions</a>
        <template v-if="route.adwId">
          <span class="sep">›</span>
          <a :href="hrefFor(route.adwId)" :class="{ current: !route.phaseId }">{{
            route.adwId
          }}</a>
        </template>
        <template v-if="route.adwId && route.phaseId">
          <span class="sep">›</span>
          <span class="current">{{ phaseCrumb ?? route.phaseId }}</span>
        </template>
      </nav>
      <span class="live-hint"><span class="live-dot" /> live</span>
    </header>
    <main>
      <SessionsList v-if="!route.adwId" />
      <SessionTrace v-else :key="route.adwId" :adw-id="route.adwId" :phase-id="route.phaseId" />
    </main>
  </div>
</template>

<style scoped>
.topbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 15px 28px;
  background: rgba(11, 15, 24, 0.72);
  backdrop-filter: blur(14px);
  -webkit-backdrop-filter: blur(14px);
  position: sticky;
  top: 0;
  z-index: 10;
}

/* Gradient hairline instead of a hard border — the brand colors, whispered. */
.topbar::after {
  content: '';
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  height: 1px;
  background: linear-gradient(
    90deg,
    rgba(200, 155, 255, 0.45),
    rgba(90, 210, 221, 0.35) 40%,
    rgba(90, 210, 221, 0.06)
  );
}

.crumbs {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 17px;
  min-width: 0;
}

.logo {
  width: 28px;
  height: 28px;
  flex: none;
  filter: drop-shadow(0 0 8px rgba(200, 155, 255, 0.35));
}

.brand {
  background: linear-gradient(90deg, var(--purple), var(--cyan));
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
  font-weight: 700;
  letter-spacing: 0.05em;
  white-space: nowrap;
}

.sep {
  color: var(--faint);
}

.crumbs a {
  color: var(--dim);
}

.crumbs a:hover {
  color: var(--text);
}

.crumbs .current {
  color: var(--text);
}

.live-hint {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  color: var(--dim);
  font-size: 16px;
  white-space: nowrap;
}

.live-dot {
  width: 9px;
  height: 9px;
  border-radius: 50%;
  background: var(--green);
  box-shadow: 0 0 10px rgba(74, 222, 128, 0.7);
  animation: pulse 1.6s ease-in-out infinite;
}
</style>
