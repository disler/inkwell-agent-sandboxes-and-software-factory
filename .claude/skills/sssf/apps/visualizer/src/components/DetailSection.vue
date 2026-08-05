<script setup lang="ts">
import type { Component } from 'vue'

defineProps<{
  title: string
  /** Lucide icon component rendered before the title. */
  icon?: Component
  /** Shown after the title; omit for sections without a natural count. */
  count?: number | null
  open: boolean
}>()

defineEmits<{ toggle: [] }>()
</script>

<template>
  <section class="dsec">
    <button class="dsec-head" @click="$emit('toggle')">
      <span class="chev">{{ open ? '▾' : '▸' }}</span>
      <component :is="icon" v-if="icon" class="dsec-icon" :size="19" :stroke-width="2" />
      <span class="dsec-title">{{ title }}</span>
      <span v-if="count != null" class="dsec-count dim">({{ count }})</span>
    </button>
    <div v-if="open" class="dsec-body">
      <slot />
    </div>
  </section>
</template>

<style scoped>
.dsec {
  margin-bottom: 14px;
}

.dsec-head {
  display: flex;
  align-items: center;
  gap: 9px;
  width: 100%;
  padding: 6px 8px;
  background: none;
  border: none;
  border-bottom: 1px solid var(--border-soft);
  border-radius: 6px 6px 0 0;
  color: var(--dim);
  font-size: 16px;
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: lowercase;
  cursor: pointer;
  text-align: left;
}

.dsec-icon {
  flex: none;
  color: var(--faint);
}

.dsec-head:hover {
  background: var(--panel-2);
  color: var(--text);
}

.chev {
  color: var(--faint);
  flex: none;
}

.dsec-count {
  font-weight: 500;
}

.dsec-body {
  padding-top: 10px;
}
</style>
