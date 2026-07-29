/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_WS_URL: string;
  readonly VITE_APP_ORIGIN: string;
  /** 地圖／起始標定緯度（未設則等首筆 GNSS 或手動標定） */
  readonly VITE_INIT_LAT?: string;
  /** 地圖／起始標定經度 */
  readonly VITE_INIT_LON?: string;
  /** 初始縮放；預設 16 */
  readonly VITE_INIT_ZOOM?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
