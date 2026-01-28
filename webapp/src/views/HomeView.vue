<template>
  <div class="container">
    <div class="row between">
      <CircleIconButton icon="i" @click="showInfo = true" />
      <CircleIconButton icon="?" @click="goRules" />
    </div>

    <div class="spacer"></div>

    <div class="row center" style="flex-direction: column;">
      <GameLogo />
      <div style="height: 16px;"></div>
      <h1 class="section-title">Tic-Tac-Toe</h1>
      <p class="subtitle">Jouez en temps reel avec un ami</p>
    </div>

    <div class="spacer"></div>

    <SoftButton label="Creer un salon prive" @click="openCreate" />
    <div style="height: 14px;"></div>
    <SoftButton label="Rejoindre un salon" :filled="false" @click="openJoin(false)" />
    <div style="height: 12px;"></div>
    <SoftButton label="Observer un salon" :filled="false" @click="openJoin(true)" />
    <div style="height: 12px;"></div>

    <p class="small center muted">Serveur: {{ game.state.serverUrl }}</p>
  </div>

  <ModalDialog v-model="showInfo">
    <template #title>Infos</template>
    <p class="small">
      Parties privees en temps reel. Utilise un code pour rejoindre.
    </p>
    <template #actions>
      <SoftButton label="OK" @click="showInfo = false" />
    </template>
  </ModalDialog>

  <ModalDialog v-model="showNameDialog">
    <template #title>Ton nom</template>
    <input v-model.trim="createName" class="input" placeholder="Ton nom" />
    <template #actions>
      <SoftButton label="Annuler" :filled="false" @click="showNameDialog = false" />
      <SoftButton label="Continuer" @click="confirmCreate" />
    </template>
  </ModalDialog>

  <ModalDialog v-model="showJoinDialog">
    <template #title>{{ joinSpectator ? 'Observer un salon' : 'Rejoindre un salon' }}</template>
    <div style="display: grid; gap: 12px;">
      <input v-model.trim="joinCode" class="input" placeholder="Code du salon (ex: ABCDEF)" />
      <input v-model.trim="joinName" class="input" placeholder="Ton nom" />
    </div>
    <template #actions>
      <SoftButton label="Annuler" :filled="false" @click="showJoinDialog = false" />
      <SoftButton :label="joinSpectator ? 'Observer' : 'Rejoindre'" @click="confirmJoin" />
    </template>
  </ModalDialog>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import CircleIconButton from '../components/CircleIconButton.vue';
import SoftButton from '../components/SoftButton.vue';
import GameLogo from '../components/GameLogo.vue';
import ModalDialog from '../components/ModalDialog.vue';
import { useGame } from '../composables/useGame';

const router = useRouter();
const game = useGame();

const showInfo = ref(false);
const showNameDialog = ref(false);
const showJoinDialog = ref(false);
const joinSpectator = ref(false);

const lastName = ref(localStorage.getItem('ttt_last_name') || '');
const createName = ref(lastName.value);
const joinName = ref(lastName.value);
const joinCode = ref('');

const goRules = () => {
  router.push('/rules');
};

const openCreate = () => {
  createName.value = lastName.value;
  showNameDialog.value = true;
};

const openJoin = (spectator: boolean): void => {
  joinSpectator.value = spectator;
  joinCode.value = '';
  joinName.value = lastName.value;
  showJoinDialog.value = true;
};

const persistName = (name: string): void => {
  if (!name) return;
  lastName.value = name;
  localStorage.setItem('ttt_last_name', name);
};

const confirmCreate = async (): Promise<void> => {
  if (!createName.value) {
    return;
  }
  persistName(createName.value);
  showNameDialog.value = false;
  game.leaveRoom();
  router.push('/game');
  await game.createRoom(createName.value);
};

const confirmJoin = async (): Promise<void> => {
  if (!joinCode.value || !joinName.value) {
    return;
  }
  persistName(joinName.value);
  showJoinDialog.value = false;
  game.leaveRoom();
  router.push('/game');
  await game.joinRoom(joinCode.value, joinName.value, joinSpectator.value);
};
</script>
