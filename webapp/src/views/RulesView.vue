<template>
  <div class="container">
    <CircleIconButton icon="<" @click="goBack" />
    <div style="height: 18px;"></div>
    <h1 class="section-title">Regles du jeu</h1>
    <div style="height: 20px;"></div>

    <RuleCard
      title="Gagner"
      description="Aligne 3 symboles sur une ligne. Partie terminee."
      icon="*"
      icon-color="var(--accent-orange)"
    />
    <div style="height: 14px;"></div>
    <RuleCard
      title="Perdre"
      description="L'adversaire aligne 3 symboles. Partie terminee."
      icon="x"
      icon-color="var(--accent-red)"
    />
    <div style="height: 14px;"></div>
    <RuleCard
      title="Match nul"
      description="Grille pleine sans vainqueur. Partie terminee."
      icon="="
      icon-color="var(--accent-blue)"
    />
  </div>
</template>

<script setup lang="ts">
import { useRouter } from 'vue-router';
import CircleIconButton from '../components/CircleIconButton.vue';
import RuleCard from '../components/RuleCard.vue';

const router = useRouter();

const goBack = (): void => {
  router.back();
};
</script>
