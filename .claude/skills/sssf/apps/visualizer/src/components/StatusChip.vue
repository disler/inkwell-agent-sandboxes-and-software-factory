<script setup lang="ts">
import { Check, Circle, LoaderCircle, X } from 'lucide-vue-next'

defineProps<{ status: string }>()

const ICONS: Record<string, unknown> = {
  success: Check,
  fail: X,
  running: LoaderCircle,
  queued: Circle,
}
</script>

<template>
  <span class="chip" :class="status">
    <component :is="ICONS[status] ?? Circle" class="chip-icon" :size="18" :stroke-width="2.5" />
    {{ status }}
  </span>
</template>

<style scoped>
.chip {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  padding: 3px 13px 3px 10px;
  border-radius: 999px;
  border: 1px solid var(--border);
  font-size: 16px;
  color: var(--dim);
  white-space: nowrap;
}

.chip-icon {
  flex: none;
}

.chip.success {
  color: var(--green);
  border-color: rgba(74, 222, 128, 0.45);
  background: rgba(74, 222, 128, 0.09);
  box-shadow: 0 0 12px rgba(74, 222, 128, 0.12);
}

.chip.fail {
  color: var(--red);
  border-color: rgba(255, 111, 103, 0.45);
  background: rgba(255, 111, 103, 0.09);
  box-shadow: 0 0 12px rgba(255, 111, 103, 0.12);
}

.chip.running {
  color: var(--blue);
  border-color: rgba(108, 182, 255, 0.45);
  background: rgba(108, 182, 255, 0.09);
  box-shadow: 0 0 12px rgba(108, 182, 255, 0.18);
}

.chip.running .chip-icon {
  animation: spin 1.1s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

.chip.queued {
  color: var(--dim);
  border-style: dashed;
}
</style>
