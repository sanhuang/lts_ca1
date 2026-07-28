<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";
import L from "leaflet";

const wsUrl = import.meta.env.VITE_WS_URL || "ws://localhost:8000/ws";
const statusText = ref("connecting…");
const statusOk = ref(false);

let map: L.Map | null = null;
let marker: L.CircleMarker | null = null;
let polyline: L.Polyline | null = null;
const path: L.LatLngExpression[] = [];
let ws: WebSocket | null = null;
let reconnectTimer: number | undefined;

function connect() {
  statusText.value = `connecting ${wsUrl}`;
  ws = new WebSocket(wsUrl);

  ws.onopen = () => {
    statusOk.value = true;
    statusText.value = "live";
  };

  ws.onclose = () => {
    statusOk.value = false;
    statusText.value = "disconnected — retrying";
    reconnectTimer = window.setTimeout(connect, 2000);
  };

  ws.onerror = () => {
    statusOk.value = false;
    statusText.value = "error";
  };

  ws.onmessage = (ev) => {
    try {
      const msg = JSON.parse(ev.data as string);
      const data = msg.data ?? msg;
      const lat = Number(data.latitude);
      const lon = Number(data.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lon) || !map) return;

      const ll: L.LatLngExpression = [lat, lon];
      path.push(ll);
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
  map = L.map("map").setView([25.033, 121.5654], 15);
  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    attribution: "&copy; OpenStreetMap",
    maxZoom: 19,
  }).addTo(map);
  connect();
});

onUnmounted(() => {
  if (reconnectTimer) window.clearTimeout(reconnectTimer);
  ws?.close();
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
