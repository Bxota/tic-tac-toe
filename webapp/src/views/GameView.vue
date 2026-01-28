<template>
  <div class="container">
    <div class="row between">
    <CircleIconButton icon="<" @click="goBack" />
      <span style="font-weight: 700; font-size: 14px;">Salon {{ roomCode }}</span>
      <span style="width: 40px;"></span>
    </div>

    <div style="height: 12px;"></div>

    <button class="muted small" style="background: none; border: none; cursor: pointer;" @click="copyCode">
      Tap pour copier le code
    </button>

    <div style="height: 16px;"></div>

    <div class="row" style="gap: 12px;">
      <PlayerStatusCard
        :label="playerLabelX"
        :symbol="isSpectator ? 'X' : symbol"
        :connected="isSpectator ? isPlayerConnected('X') : youConnected"
        highlight="var(--accent-green)"
      />
      <PlayerStatusCard
        :label="playerLabelO"
        :symbol="isSpectator ? 'O' : opponentSymbol"
        :connected="isSpectator ? isPlayerConnected('O') : opponentConnected"
        highlight="var(--accent-red)"
      />
    </div>

    <div style="height: 20px;"></div>

    <h2 class="section-title" style="font-size: 18px; text-align: center;">{{ statusText }}</h2>

    <p v-if="game.state.errorMessage" class="small center" style="color: var(--accent-orange); margin-top: 8px;">
      {{ game.state.errorMessage }}
    </p>

    <div style="height: 20px;"></div>

    <div class="board">
      <BoardCell
        v-for="(cell, index) in board"
        :key="index"
        :value="cell"
        @click="handleMove(index)"
      />
    </div>

    <div style="height: 18px;"></div>

    <SoftButton
      v-if="showRematch"
      label="Rejouer"
      @click="game.requestRematch"
    />
    <div v-if="showRematch" style="height: 12px;"></div>

    <SoftButton
      v-if="showReconnect"
      label="Reconnecter"
      @click="game.reconnect"
    />

    <SoftButton
      v-if="game.state.roomClosed"
      label="Retour accueil"
      @click="goBack"
    />
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import CircleIconButton from '../components/CircleIconButton.vue';
import PlayerStatusCard from '../components/PlayerStatusCard.vue';
import BoardCell from '../components/BoardCell.vue';
import SoftButton from '../components/SoftButton.vue';
import { useGame } from '../composables/useGame';

const router = useRouter();
const game = useGame();

const roomCode = computed(() => game.state.roomCode || '----');
const state = computed(() => game.state.gameState);
const symbol = computed(() => game.state.symbol || 'X');
const opponentSymbol = computed(() => (symbol.value === 'X' ? 'O' : 'X'));
const isSpectator = computed(() => game.isSpectator.value);
const board = computed(() => state.value?.board ?? Array.from({ length: 9 }, () => ''));

const isPlayerConnected = (playerSymbol: string): boolean => {
  return state.value?.players?.[playerSymbol]?.connected ?? false;
};

const playerName = (playerSymbol: string): string => {
  return state.value?.players?.[playerSymbol]?.name ?? '';
};

const youConnected = computed(() => isPlayerConnected(symbol.value) || game.isConnected.value);
const opponentConnected = computed(() => isPlayerConnected(opponentSymbol.value));

const playerLabelX = computed(() => {
  if (isSpectator.value) {
    return playerName('X') || 'Joueur X';
  }
  const name = playerName(symbol.value);
  return name ? `Toi - ${name}` : 'Toi';
});

const playerLabelO = computed(() => {
  if (isSpectator.value) {
    return playerName('O') || 'Joueur O';
  }
  const name = playerName(opponentSymbol.value);
  return name ? name : 'Adversaire';
});

const statusText = computed(() => {
  if (game.state.roomClosed) {
    return 'Salon ferme';
  }
  if (game.state.connectionStatus === 'connecting') {
    return 'Connexion en cours...';
  }
  if (game.state.connectionStatus === 'disconnected' && !state.value) {
    return 'Connexion perdue';
  }
  if (!state.value) {
    return 'En attente du serveur...';
  }
  switch (state.value.status) {
    case 'waiting':
      return isSpectator.value ? 'En attente de joueurs' : 'En attente d\'un adversaire';
    case 'paused':
      return isSpectator.value ? 'Joueur deconnecte' : 'Adversaire deconnecte';
    case 'win':
      if (isSpectator.value || !state.value.winner) {
        return 'Partie terminee';
      }
      return state.value.winner === symbol.value ? 'Victoire !' : 'Defaite';
    case 'draw':
      return 'Match nul';
    case 'in_progress':
      if (isSpectator.value) {
        return 'Partie en cours';
      }
      return state.value.turn === symbol.value ? 'A ton tour' : 'Tour adverse';
    default:
      return 'En attente';
  }
});

const bothPlayersConnected = computed(() => isPlayerConnected('X') && isPlayerConnected('O'));
const showRematch = computed(() => {
  const status = state.value?.status ?? '';
  return ['win', 'draw'].includes(status) &&
    bothPlayersConnected.value && !game.state.roomClosed && !isSpectator.value;
});

const showReconnect = computed(() => {
  return game.state.connectionStatus !== 'connected' &&
    !game.state.roomClosed &&
    Boolean(game.state.roomCode);
});

const goBack = (): void => {
  game.leaveRoom();
  router.push('/');
};

const copyCode = async (): Promise<void> => {
  try {
    await navigator.clipboard.writeText(roomCode.value);
  } catch (error) {
    // no-op
  }
};

const handleMove = (index: number): void => {
  if (!state.value || isSpectator.value) {
    return;
  }
  if (state.value.status !== 'in_progress') {
    return;
  }
  if (state.value.turn !== symbol.value) {
    return;
  }
  if (board.value[index]) {
    return;
  }
  game.sendMove(index);
};
</script>
