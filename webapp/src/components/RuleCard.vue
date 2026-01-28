<template>
  <div class="rule-card">
    <div class="rule-icon" :style="{ background: `${iconColor}2e`, color: iconColor }">
      <span aria-hidden="true">{{ icon }}</span>
    </div>
    <div>
      <p class="rule-title">{{ title }}</p>
      <p class="rule-desc">{{ description }}</p>
    </div>
  </div>
</template>

<script setup lang="ts">
defineProps<{
  title: string;
  description: string;
  icon: string;
  iconColor: string;
}>();
</script>
