<template>
  <div class="app-background">
    <div class="cloud" style="top: 40px; left: -60px; width: 160px; height: 160px; opacity: 0.18;"></div>
    <div class="cloud" style="top: 140px; right: -40px; width: 120px; height: 120px; opacity: 0.14;"></div>
    <div class="cloud" style="bottom: 120px; left: -30px; width: 110px; height: 110px; opacity: 0.12;"></div>
    <RouterView />
  </div>
</template>

<script setup lang="ts">
import { RouterView } from 'vue-router';
</script>
