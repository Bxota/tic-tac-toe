<template>
  <button class="board-cell" type="button" @click="$emit('click')" :style="{ color: color }">
    {{ value }}
  </button>
</template>

<script setup lang="ts">
import { computed } from 'vue';

const props = withDefaults(
  defineProps<{
    value?: string;
  }>(),
  {
    value: '',
  },
);

defineEmits<{
  (event: 'click'): void;
}>();

const color = computed(() => {
  if (props.value === 'X') return 'var(--accent-green)';
  if (props.value === 'O') return 'var(--accent-red)';
  return 'var(--text-primary)';
});
</script>
