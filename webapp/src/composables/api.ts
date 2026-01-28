const apiBase = typeof __VITE_API_URL__ === 'string' ? __VITE_API_URL__ : '';
const apiPrefix = apiBase.endsWith('/') ? apiBase.slice(0, -1) : apiBase;

export const apiUrl = (path: string): string => (apiPrefix ? `${apiPrefix}${path}` : path);
