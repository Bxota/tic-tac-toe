declare module '*.vue' {
  import type { DefineComponent } from 'vue';
  const component: DefineComponent<{}, {}, any>;
  export default component;
}

declare const __VITE_WS_URL__: string;
declare const __VITE_API_URL__: string;
