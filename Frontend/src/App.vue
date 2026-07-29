<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";
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

const wsUrl = import.meta.env.VITE_WS_URL || "ws://localhost:8000/ws";
const statusText = ref("connecting…");
const statusOk = ref(false);

let map: L.Map | null = null;
let marker: L.CircleMarker | null = null;
let polyline: L.Polyline | null = null;
const path: L.LatLngExpression[] = [];
let ws: WebSocket | null = null;
let reconnectTimer: number | undefined;
let intentionalClose = false;

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
    statusText.value = "live";
  };

  ws.onclose = () => {
    statusOk.value = false;
    scheduleReconnect();
  };

  ws.onerror = () => {
    statusOk.value = false;
    statusText.value = "error";
    // 瀏覽器會接著觸發 onclose，由 scheduleReconnect 處理重連
  };

  ws.onmessage = (ev) => {
    try {
      const msg = JSON.parse(ev.data as string) as WsEnvelope;
      // 僅處理熱路徑信封：{ type: "gnss_fix", data: { latitude, longitude, ... } }
      if (msg.type !== "gnss_fix" || !msg.data) return;
      const lat = Number(msg.data.latitude);
      const lon = Number(msg.data.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lon) || !map) return;

      const ll: L.LatLngExpression = [lat, lon];
      path.push(ll);
      if (path.length > MAX_PATH_POINTS) {
        path.splice(0, path.length - MAX_PATH_POINTS);
      }

      if (!marker) {
        marker = L.circleMarker(ll, {
          radius: 8,
          color: "#0ea5e9",
          fillColor: "#38bdf8",
          fillOpacity: 0.9,
        }).addTo(map);
        map.setView(ll, 16);
      } else {
        marker.setLatLng(ll);
      }
      if (!polyline) {
        polyline = L.polyline(path, { color: "#38bdf8", weight: 4 }).addTo(map);
      } else {
        polyline.setLatLngs(path);
      }
    } catch {
      /* ignore malformed */
    }
  };
}

onMounted(() => {
  intentionalClose = false;
  map = L.map("map").setView([25.033, 121.5654], 15);
  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    attribution: "&copy; OpenStreetMap",
    maxZoom: 19,
  }).addTo(map);
  connect();
});

onUnmounted(() => {
  intentionalClose = true;
  if (reconnectTimer !== undefined) {
    window.clearTimeout(reconnectTimer);
    reconnectTimer = undefined;
  }
  ws?.close();
  ws = null;
  map?.remove();
});
</script>

<template>
  <div class="toolbar">
    <strong>LTS Map</strong>
    <span :class="statusOk ? 'status-ok' : 'status-bad'">{{ statusText }}</span>
    <span>{{ wsUrl }}</span>
  </div>
  <div id="map" />
</template>
