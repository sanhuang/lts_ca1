<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import L from "leaflet";

/** 對齊 Backend `GnssFixMessage`（GNSS_data） */
interface GnssFixData {
  latitude: number;
  longitude: number;
  altitude?: number | null;
  status?: number | null;
  timestamp?: string;
  frame_id?: string | null;
}

/** 對齊 Backend `WsEnvelope`（data_transfer_formatting） */
interface WsEnvelope {
  type: "gnss_fix" | "heartbeat" | "status";
  data?: GnssFixData | null;
}

/** 保留最近 N 點，避免長跑 polyline 無限膨脹卡頓（5Hz ≈ 100s） */
const MAX_PATH_POINTS = 500;
const RECONNECT_MS = 2000;
const STORAGE_KEY = "lts-map-init-v1";

function parseOptionalNumber(raw: string | undefined): number | undefined {
  if (raw === undefined || raw === "") return undefined;
  const n = Number(raw);
  return Number.isFinite(n) ? n : undefined;
}

const envInitLat = parseOptionalNumber(import.meta.env.VITE_INIT_LAT);
const envInitLon = parseOptionalNumber(import.meta.env.VITE_INIT_LON);
const initZoom = parseOptionalNumber(import.meta.env.VITE_INIT_ZOOM) ?? 16;

const wsUrl = import.meta.env.VITE_WS_URL || "ws://localhost:8000/ws";
const statusText = ref("connecting…");
const statusOk = ref(false);
/** 是否已收到至少一筆有效 GNSS（側欄 GNSS live） */
const gnssLive = ref(false);
const pickMode = ref(false);
const startLat = ref<number | null>(null);
const startLon = ref<number | null>(null);

const mapHint = computed(() =>
  pickMode.value
    ? "點地圖標定初始座標（Esc 取消）"
    : "可開啟「標定」後點地圖設初始位置",
);

const startCoordsText = computed(() => {
  if (startLat.value == null || startLon.value == null) return "未標定";
  return `${startLat.value.toFixed(5)}, ${startLon.value.toFixed(5)}`;
});

let map: L.Map | null = null;
let marker: L.CircleMarker | null = null;
let polyline: L.Polyline | null = null;
let startMarker: L.CircleMarker | null = null;
const path: L.LatLngExpression[] = [];
let ws: WebSocket | null = null;
let reconnectTimer: number | undefined;
let intentionalClose = false;
let viewedOnce = false;

function loadStoredStart(): { lat: number; lon: number } | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as { lat?: number; lon?: number };
    if (
      typeof parsed.lat === "number" &&
      typeof parsed.lon === "number" &&
      Number.isFinite(parsed.lat) &&
      Number.isFinite(parsed.lon)
    ) {
      return { lat: parsed.lat, lon: parsed.lon };
    }
  } catch {
    /* ignore */
  }
  return null;
}

function persistStart() {
  if (startLat.value == null || startLon.value == null) {
    localStorage.removeItem(STORAGE_KEY);
    return;
  }
  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify({ lat: startLat.value, lon: startLon.value }),
  );
}

function upsertStartMarker() {
  if (!map || startLat.value == null || startLon.value == null) {
    startMarker?.remove();
    startMarker = null;
    return;
  }
  const ll: L.LatLngExpression = [startLat.value, startLon.value];
  if (!startMarker) {
    startMarker = L.circleMarker(ll, {
      radius: 12,
      color: "#334155",
      fillColor: "#94a3b8",
      fillOpacity: 0.35,
      weight: 2,
      dashArray: "4 3",
    })
      .bindTooltip("start", { direction: "right" })
      .addTo(map);
  } else {
    startMarker.setLatLng(ll);
  }
}

function seedPathFromStart() {
  if (!map || startLat.value == null || startLon.value == null) return;
  const ll: L.LatLngExpression = [startLat.value, startLon.value];
  if (path.length === 0) {
    path.push(ll);
    ensureLayers(ll);
    polyline?.setLatLngs(path);
    marker?.setLatLng(ll);
  }
}

function setStart(lat: number, lon: number) {
  startLat.value = lat;
  startLon.value = lon;
  upsertStartMarker();
  seedPathFromStart();
  if (map && !viewedOnce) {
    map.setView([lat, lon], initZoom);
    viewedOnce = true;
  }
  persistStart();
}

function clearStart() {
  startLat.value = null;
  startLon.value = null;
  startMarker?.remove();
  startMarker = null;
  persistStart();
}

function ensureLayers(ll: L.LatLngExpression) {
  if (!map) return;
  if (!marker) {
    marker = L.circleMarker(ll, {
      radius: 8,
      color: "#0284c7",
      fillColor: "#38bdf8",
      fillOpacity: 0.9,
      weight: 2,
    })
      .bindTooltip("GNSS", {
        permanent: true,
        direction: "top",
        offset: [0, -10],
        className: "node-label",
      })
      .addTo(map);
  }
  if (!polyline) {
    polyline = L.polyline([], {
      color: "#38bdf8",
      weight: 4,
      opacity: 0.85,
    }).addTo(map);
  }
}

function applyFix(data: GnssFixData) {
  if (!map) return;
  const lat = Number(data.latitude);
  const lon = Number(data.longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return;

  const ll: L.LatLngExpression = [lat, lon];
  path.push(ll);
  if (path.length > MAX_PATH_POINTS) {
    path.splice(0, path.length - MAX_PATH_POINTS);
  }

  ensureLayers(ll);
  marker?.setLatLng(ll);
  polyline?.setLatLngs(path);
  gnssLive.value = true;

  if (!viewedOnce) {
    map.setView(ll, initZoom);
    viewedOnce = true;
  }
}

function fitView() {
  if (!map) return;
  const pts: L.LatLngExpression[] = [...path];
  if (startLat.value != null && startLon.value != null) {
    pts.push([startLat.value, startLon.value]);
  }
  if (pts.length === 0) return;
  if (pts.length === 1) {
    map.setView(pts[0], initZoom);
  } else {
    map.fitBounds(L.latLngBounds(pts as L.LatLngTuple[]), {
      padding: [40, 40],
    });
  }
  viewedOnce = true;
}

function onMapClick(e: L.LeafletMouseEvent) {
  if (!pickMode.value) return;
  setStart(e.latlng.lat, e.latlng.lng);
  pickMode.value = false;
}

function onKeydown(ev: KeyboardEvent) {
  if (ev.key === "Escape" && pickMode.value) pickMode.value = false;
}

function scheduleReconnect() {
  if (intentionalClose) return;
  if (reconnectTimer !== undefined) window.clearTimeout(reconnectTimer);
  statusText.value = "disconnected — retrying";
  reconnectTimer = window.setTimeout(connect, RECONNECT_MS);
}

function connect() {
  if (intentionalClose) return;
  if (reconnectTimer !== undefined) {
    window.clearTimeout(reconnectTimer);
    reconnectTimer = undefined;
  }
  statusText.value = `connecting ${wsUrl}`;
  ws = new WebSocket(wsUrl);
  ws.onopen = () => {
    statusOk.value = true;
    statusText.value = "ws live";
  };
  ws.onclose = () => {
    statusOk.value = false;
    gnssLive.value = false;
    scheduleReconnect();
  };
  ws.onerror = () => {
    statusOk.value = false;
    statusText.value = "error";
  };
  ws.onmessage = (ev) => {
    try {
      const msg = JSON.parse(ev.data as string) as WsEnvelope;
      if (msg.type !== "gnss_fix" || !msg.data) return;
      applyFix(msg.data);
    } catch {
      /* ignore malformed */
    }
  };
}

watch(pickMode, (on) => {
  map?.getContainer().classList.toggle("pick-mode", on);
});

onMounted(() => {
  intentionalClose = false;
  const stored = loadStoredStart();
  const hasEnv = envInitLat !== undefined && envInitLon !== undefined;
  const center: L.LatLngExpression = stored
    ? [stored.lat, stored.lon]
    : hasEnv
      ? [envInitLat!, envInitLon!]
      : [25.033, 121.5654];
  const zoom = stored || hasEnv ? initZoom : 12;

  map = L.map("map").setView(center, zoom);
  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    attribution: "&copy; OpenStreetMap",
    maxZoom: 19,
  }).addTo(map);
  map.on("click", onMapClick);
  window.addEventListener("keydown", onKeydown);

  if (stored) {
    setStart(stored.lat, stored.lon);
  } else if (hasEnv) {
    setStart(envInitLat!, envInitLon!);
  }

  connect();
});

onUnmounted(() => {
  intentionalClose = true;
  window.removeEventListener("keydown", onKeydown);
  if (reconnectTimer !== undefined) {
    window.clearTimeout(reconnectTimer);
    reconnectTimer = undefined;
  }
  ws?.close();
  ws = null;
  map?.off("click", onMapClick);
  startMarker?.remove();
  marker?.remove();
  polyline?.remove();
  map?.remove();
  map = null;
});
</script>

<template>
  <div class="layout">
    <aside class="panel">
      <header class="panel-head">
        <strong>LTS Map</strong>
        <span :class="statusOk ? 'status-ok' : 'status-bad'">{{ statusText }}</span>
      </header>

      <section class="panel-section">
        <h3>GNSS</h3>
        <p class="meta">
          <span :class="gnssLive ? 'pill live' : 'pill'">
            {{ gnssLive ? "GNSS live" : "awaiting" }}
          </span>
        </p>
        <p class="hint">收到 WebSocket <code>gnss_fix</code> 後顯示 live，並繪製當前位置與路徑。</p>
      </section>

      <section class="panel-section grow">
        <h3>初始位置</h3>
        <p class="hint">{{ mapHint }}</p>
        <p class="coords">{{ startCoordsText }}</p>
        <div class="btn-row">
          <button
            type="button"
            class="btn"
            :class="{ active: pickMode }"
            @click="pickMode = !pickMode"
          >
            {{ pickMode ? "點擊地圖中…" : "標定初始位置" }}
          </button>
          <button type="button" class="btn ghost" @click="fitView">視野對齊</button>
          <button
            v-if="startLat != null"
            type="button"
            class="btn ghost"
            @click="clearStart"
          >
            清除標定
          </button>
        </div>
      </section>

      <footer class="panel-foot muted">{{ wsUrl }}</footer>
    </aside>
    <div id="map" />
  </div>
</template>
