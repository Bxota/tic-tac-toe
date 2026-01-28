import { reactive } from 'vue';
import { apiUrl } from './api';
import { useAuth } from './useAuth';

type StatsPayload = {
  total: number;
  wins: number;
  losses: number;
  draws: number;
};

type StatsState = {
  stats: StatsPayload | null;
  status: 'idle' | 'loading' | 'ready';
  errorMessage: string | null;
};

const state = reactive<StatsState>({
  stats: null,
  status: 'idle',
  errorMessage: null,
});

const loadStats = async (): Promise<void> => {
  const auth = useAuth();
  state.status = 'loading';
  state.errorMessage = null;

  if (!auth.state.accessToken) {
    await auth.refreshSession();
  }

  const token = auth.state.accessToken;
  if (!token) {
    state.stats = null;
    state.status = 'ready';
    state.errorMessage = 'Non connecte.';
    return;
  }

  try {
    const response = await fetch(apiUrl('/api/stats'), {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!response.ok) {
      state.stats = null;
      state.status = 'ready';
      state.errorMessage = 'Impossible de charger les stats.';
      return;
    }
    state.stats = (await response.json()) as StatsPayload;
  } catch (error) {
    state.stats = null;
    state.errorMessage = 'Erreur reseau.';
  } finally {
    state.status = 'ready';
  }
};

const clearStats = (): void => {
  state.stats = null;
  state.status = 'idle';
  state.errorMessage = null;
};

export const useStats = () => ({
  state,
  loadStats,
  clearStats,
});
