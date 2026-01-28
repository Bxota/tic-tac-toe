import { reactive, computed } from 'vue';
import { apiUrl } from './api';

type AuthUser = {
  id: number;
  discord_id?: string;
  username: string;
  avatar?: string;
  is_guest?: boolean;
};

type AuthState = {
  user: AuthUser | null;
  accessToken: string | null;
  status: 'idle' | 'loading' | 'ready';
};

type RefreshResponse = {
  user: AuthUser;
  access_token: string;
  expires_in: number;
  refresh_token?: string;
};

type TicketResponse = {
  ticket: string;
  expires_in: number;
};

const guestIdKey = 'ttt_guest_id';

const state = reactive<AuthState>({
  user: null,
  accessToken: null,
  status: 'idle',
});

const getOrCreateGuestId = (): string => {
  const stored = localStorage.getItem(guestIdKey);
  if (stored && stored.length > 0) {
    return stored;
  }
  const generated = crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  localStorage.setItem(guestIdKey, generated);
  return generated;
};

const guestId = getOrCreateGuestId();

const isAuthenticated = computed(() => Boolean(state.user));

const applySession = (payload: RefreshResponse): void => {
  state.user = payload.user;
  state.accessToken = payload.access_token;
};

const clearSession = (): void => {
  state.user = null;
  state.accessToken = null;
};

const refreshSession = async (): Promise<void> => {
  state.status = 'loading';
  try {
    const response = await fetch(apiUrl('/auth/refresh'), {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    if (!response.ok) {
      clearSession();
      state.status = 'ready';
      return;
    }
    const data = (await response.json()) as RefreshResponse;
    applySession(data);
  } catch (error) {
    clearSession();
  } finally {
    state.status = 'ready';
  }
};

const ensureAccessToken = async (): Promise<string | null> => {
  if (state.accessToken) {
    return state.accessToken;
  }
  await refreshSession();
  return state.accessToken;
};

const loginWithDiscord = (): void => {
  const returnTo = `${window.location.pathname}${window.location.search}${window.location.hash}`;
  const url = `${apiUrl('/auth/discord/login')}?return_to=${encodeURIComponent(returnTo)}&guest_id=${encodeURIComponent(guestId)}`;
  window.location.assign(url);
};

const logout = async (): Promise<void> => {
  try {
    await fetch(apiUrl('/auth/logout'), {
      method: 'POST',
      credentials: 'include',
      headers: state.accessToken ? { Authorization: `Bearer ${state.accessToken}` } : undefined,
    });
  } finally {
    clearSession();
  }
};

const getWsTicket = async (): Promise<string | null> => {
  const token = await ensureAccessToken();
  if (!token) {
    return null;
  }
  const response = await fetch(apiUrl('/auth/ws-ticket'), {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
    },
  });
  if (!response.ok) {
    return null;
  }
  const data = (await response.json()) as TicketResponse;
  return data.ticket;
};

export const useAuth = () => ({
  state,
  isAuthenticated,
  guestId,
  refreshSession,
  loginWithDiscord,
  logout,
  getWsTicket,
});
