#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
#  OFM PATH 智慧通路 — Provisioning Bootstrap  (hardened v2)
#  Runs on Vast.ai as PROVISIONING_SCRIPT  ·  Public script (no secrets here)
# ═══════════════════════════════════════════════════════════════════════════

# NOTE: no `set -e` — each phase handles its own errors so the preloader
# never gets orphaned on a silent exit.

# ── Supabase endpoints ──
export OFMPATH_SUPA_URL="https://yvjhjptycwlnjnzzsyju.supabase.co"
export OFMPATH_SUPA_KEY="sb_publishable_RW1gbkXD6roZeUCxfEpQGg_cZ1z7brK"
export OFMPATH_BUCKET="ofm-path"

# ── Constants ──
WORKSPACE="/workspace"
COMFYUI_DIR="$WORKSPACE/ComfyUI"
CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"

# ── Logging ──
# Two logs: one TEMPORARY in /tmp for the browser to poll, one PERMANENT in
# /workspace that survives finalize cleanup for post-mortem debugging.
mkdir -p /tmp/ofmpath_loading "$WORKSPACE"
LOG_FILE="/tmp/ofmpath_loading/install.log"
DEBUG_LOG="$WORKSPACE/ofmpath_debug.log"
echo "[OFM] Init started at $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee "$LOG_FILE" > "$DEBUG_LOG"

# tee to BOTH logs, line-buffered
exec > >(stdbuf -oL tee -a "$LOG_FILE" "$DEBUG_LOG") 2>&1


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 1 — PRELOADER HTML (port 8188)
# ═══════════════════════════════════════════════════════════════════════════
_start_preloader() {
    echo "[OFM] Deploying preloader HTML..."

    cat > /tmp/ofmpath_loading/index.html << 'PRELOADER_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>OFM PATH — Initializing...</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&display=swap');
  * { margin:0; padding:0; box-sizing:border-box; }
  html,body { height:100%; overflow-x:hidden; }
  body { background:#0a0a0a; color:#f0e6cf; font-family:'JetBrains Mono','Courier New',monospace;
         display:flex; justify-content:center; align-items:flex-start; min-height:100vh; position:relative;
         padding:32px 16px; }
  body::before { content:''; position:fixed; inset:0; pointer-events:none; z-index:2;
                 background:repeating-linear-gradient(0deg,rgba(0,0,0,.35) 0,rgba(0,0,0,.35) 1px,transparent 1px,transparent 3px); }
  body::after { content:''; position:fixed; inset:0; pointer-events:none; z-index:1;
                background:radial-gradient(ellipse at 50% 50%, rgba(240,230,207,0.04) 0%, transparent 65%); }
  .wrap { position:relative; z-index:10; max-width:720px; width:100%; padding:32px 36px;
          background:rgba(15,12,8,0.7); border:1px solid rgba(240,230,207,0.18); border-radius:4px;
          backdrop-filter:blur(8px);
          box-shadow:0 0 60px rgba(240,230,207,0.05), inset 0 0 0 1px rgba(240,230,207,0.06);
          animation:slideUp 0.8s cubic-bezier(0.16, 1, 0.3, 1) both; }
  @keyframes slideUp { from { opacity:0; transform:translateY(16px);} to { opacity:1; transform:translateY(0);} }
  .brand { text-align:center; font-size:11px; letter-spacing:4px; color:#f0e6cf; opacity:.6; margin-bottom:8px; }
  pre.ascii { font-size:11px; line-height:1.2; color:#faf1d6;
              text-shadow:0 0 10px rgba(255,245,221,.35); margin:0 0 18px; white-space:pre; text-align:center;
              font-family:'JetBrains Mono','Courier New',monospace; }
  .version { text-align:center; font-size:10px; color:#f0e6cf; opacity:.5; letter-spacing:3px; margin-bottom:22px; text-transform:uppercase; }
  .header-row { display:flex; justify-content:space-between; align-items:center; gap:12px; margin-bottom:14px; flex-wrap:wrap; }
  .status-badge { display:inline-flex; align-items:center; gap:10px; padding:7px 16px;
                  background:rgba(240,230,207,0.05); border:1px solid rgba(240,230,207,0.22); border-radius:3px;
                  font-size:12px; color:#faf1d6; letter-spacing:0.4px; }
  .dot { width:8px; height:8px; border-radius:50%; background:#f5efd6;
         animation:dotPulse 1.3s infinite; box-shadow:0 0 8px #f5efd6; }
  @keyframes dotPulse { 0%,100% { transform:scale(.8); opacity:.6;} 50% { transform:scale(1.25); opacity:1;} }
  .elapsed { font-family:'JetBrains Mono',monospace; font-size:12px; color:rgba(240,230,207,0.7); letter-spacing:1px; }
  .bar-track { width:100%; height:4px; background:rgba(240,230,207,0.08); border-radius:2px;
               overflow:hidden; margin-bottom:6px; box-shadow:inset 0 0 0 1px rgba(240,230,207,0.15); }
  .bar-fill { height:100%; width:0%; background:linear-gradient(90deg,#f0e6cf,#faf1d6);
              transition:width .6s cubic-bezier(0.2,0.8,0.2,1); box-shadow:0 0 10px rgba(240,230,207,0.4); }
  .bar-label { display:flex; justify-content:space-between; font-size:10px; color:rgba(240,230,207,0.45);
               letter-spacing:1px; margin-bottom:22px; text-transform:uppercase; }
  .stats { display:grid; grid-template-columns:repeat(4, 1fr); gap:10px; margin-bottom:18px; }
  .stat { background:rgba(240,230,207,0.04); border:1px solid rgba(240,230,207,0.15); border-radius:3px; padding:12px 10px; }
  .stat-label { font-size:9px; color:rgba(240,230,207,0.55); letter-spacing:1.5px; text-transform:uppercase; margin-bottom:6px; }
  .stat-value { font-size:22px; color:#faf1d6; font-weight:600; line-height:1; }
  .stat-value .sub { font-size:11px; color:rgba(240,230,207,0.4); }
  .stat-hint { font-size:9px; color:rgba(240,230,207,0.4); margin-top:4px; letter-spacing:0.5px; }
  .panel { background:rgba(240,230,207,0.03); border:1px dashed rgba(240,230,207,0.22); border-radius:3px;
           padding:14px; margin-bottom:14px; }
  .panel-label { font-size:10px; color:rgba(240,230,207,0.55); letter-spacing:1.5px; text-transform:uppercase; margin-bottom:12px; }
  .ladder { display:flex; gap:6px; font-size:10px; }
  .rung { flex:1; padding:7px 4px; text-align:center; border-radius:2px; transition:all 0.4s; }
  .rung.future { background:rgba(240,230,207,0.05); color:rgba(240,230,207,0.5); border:1px solid rgba(240,230,207,0.15); }
  .rung.done { background:rgba(240,230,207,0.12); color:#0a0a0a; font-weight:600; }
  .rung.active { background:rgba(240,230,207,0.28); color:#0a0a0a; font-weight:600; box-shadow:0 0 10px rgba(240,230,207,0.3); }
  .rung .code { font-size:8px; letter-spacing:1px; opacity:0.6; display:block; margin-bottom:2px; }
  .rung.done .code, .rung.active .code { color:rgba(10,10,10,0.6); opacity:1; }
  .weights-head { display:flex; justify-content:space-between; align-items:center; margin-bottom:10px; }
  .weights-count { font-size:10px; color:rgba(240,230,207,0.55); letter-spacing:1.5px; text-transform:uppercase; }
  .weights-speed { font-size:10px; color:#faf1d6; letter-spacing:0.5px; }
  .blocks { display:flex; flex-wrap:wrap; gap:4px; margin-bottom:10px; }
  .block { width:12px; height:12px; border-radius:2px;
           background:rgba(240,230,207,0.06); border:1px solid rgba(240,230,207,0.2); transition:all 0.3s; }
  .block.filled { background:#f0e6cf; border-color:#f0e6cf; box-shadow:0 0 6px rgba(240,230,207,0.45); }
  .block.loading { background:rgba(240,230,207,0.2); border-color:rgba(240,230,207,0.4); animation:dotPulse 1.3s infinite; }
  .block.failed { background:rgba(201,122,95,0.25); border-color:rgba(201,122,95,0.6); }
  .current-file { font-size:10px; color:rgba(250,241,214,0.5); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .log-panel { background:rgba(0,0,0,0.5); border:1px solid rgba(240,230,207,0.12); border-radius:3px;
               padding:12px 14px; height:145px; overflow:hidden; position:relative; }
  .log-label { font-size:9px; color:rgba(240,230,207,0.45); letter-spacing:1.5px; text-transform:uppercase; margin-bottom:8px; }
  .log-lines { font-family:'JetBrains Mono',monospace; font-size:10px; line-height:1.55;
               color:rgba(240,230,207,0.7); overflow:hidden; }
  .log-line { display:flex; gap:10px; white-space:nowrap; }
  .log-ts { color:rgba(240,230,207,0.4); min-width:45px; flex-shrink:0; }
  .log-icon { flex-shrink:0; }
  .log-icon.ok { color:rgba(250,241,214,0.5); }
  .log-icon.run { color:#faf1d6; }
  .log-icon.warn { color:#c97a5f; }
  .log-icon.info { color:rgba(250,241,214,0.5); }
  .log-msg { overflow:hidden; text-overflow:ellipsis; flex:1; min-width:0; }
  .log-line.warn .log-msg { color:rgba(201,122,95,0.85); }
  .log-line.run .log-msg { color:#faf1d6; }
  .footer { text-align:center; font-size:10px; color:rgba(240,230,207,0.25); letter-spacing:3px; margin-top:18px; text-transform:uppercase; }
  .error-state .bar-fill { background:#c97a5f !important; box-shadow:0 0 10px #c97a5f; }
  .error-state .status-badge { color:#c97a5f; border-color:rgba(201,122,95,0.4); }
  .error-state .dot { background:#c97a5f; box-shadow:0 0 8px #c97a5f; }
  #refresh-prompt { display:none; margin-top:18px; text-align:center; }
  .btn { background:linear-gradient(135deg,#f0e6cf,#faf1d6); color:#0a0a0a;
         border:none; padding:11px 30px; border-radius:3px; font-size:12px; font-weight:600;
         cursor:pointer; letter-spacing:2px; font-family:'JetBrains Mono',monospace; text-transform:uppercase;
         box-shadow:0 0 20px rgba(240,230,207,0.3); transition:all .15s; }
  .btn:hover { transform:translateY(-1px); box-shadow:0 0 30px rgba(240,230,207,0.5); }
  @media (max-width: 540px) {
    .stats { grid-template-columns:repeat(2,1fr); }
    .ladder { flex-wrap:wrap; }
    .rung { min-width:45px; }
  }
</style>
</head>
<body>
  <div class="wrap" id="main">
    <div class="brand">OFMPATH.COM</div>
    <pre class="ascii">
 ██████╗ ███████╗███╗   ███╗    ██████╗  █████╗ ████████╗██╗  ██╗
██╔═══██╗██╔════╝████╗ ████║    ██╔══██╗██╔══██╗╚══██╔══╝██║  ██║
██║   ██║█████╗  ██╔████╔██║    ██████╔╝███████║   ██║   ███████║
██║   ██║██╔══╝  ██║╚██╔╝██║    ██╔═══╝ ██╔══██║   ██║   ██╔══██║
╚██████╔╝██║     ██║ ╚═╝ ██║    ██║     ██║  ██║   ██║   ██║  ██║
 ╚═════╝ ╚═╝     ╚═╝     ╚═╝    ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝</pre>
    <div class="version">V1 · OFM PATH</div>

    <div class="header-row">
      <div class="status-badge">
        <span class="dot"></span><span id="status-text">Initializing environment...</span>
      </div>
      <div class="elapsed" id="elapsed">00:00</div>
    </div>

    <div class="bar-track"><div class="bar-fill" id="bar"></div></div>
    <div class="bar-label">
      <span>Overall deployment</span>
      <span id="pct-text">0%</span>
    </div>

    <div class="stats">
      <div class="stat">
        <div class="stat-label">Nodes</div>
        <div class="stat-value"><span id="nodes-done">0</span><span class="sub">/28</span></div>
        <div class="stat-hint">installed</div>
      </div>
      <div class="stat">
        <div class="stat-label">Models</div>
        <div class="stat-value"><span id="models-done">0</span><span class="sub">/<span id="models-total">49</span></span></div>
        <div class="stat-hint">synced</div>
      </div>
      <div class="stat">
        <div class="stat-label">Data</div>
        <div class="stat-value"><span id="data-gb">0.0</span><span class="sub"> GB</span></div>
        <div class="stat-hint">of ~75 GB</div>
      </div>
      <div class="stat">
        <div class="stat-label">ETA</div>
        <div class="stat-value"><span id="eta">&mdash;</span></div>
        <div class="stat-hint">remaining</div>
      </div>
    </div>

    <div class="panel">
      <div class="panel-label">Pipeline</div>
      <div class="ladder" id="ladder">
        <div class="rung future" data-phase="A"><span class="code">A</span>Workflows</div>
        <div class="rung future" data-phase="B"><span class="code">B</span>Nodes</div>
        <div class="rung future" data-phase="C"><span class="code">C</span>Models</div>
        <div class="rung future" data-phase="D"><span class="code">D</span>Deploy</div>
        <div class="rung future" data-phase="E"><span class="code">E</span>Settings</div>
        <div class="rung future" data-phase="F"><span class="code">F</span>Lockdown</div>
      </div>
    </div>

    <div class="panel" id="weights-panel" style="display:none;">
      <div class="weights-head">
        <span class="weights-count">Model weights &middot; <span id="weights-count-text">0 / 49</span></span>
        <span class="weights-speed" id="weights-speed"></span>
      </div>
      <div class="blocks" id="blocks"></div>
      <div class="current-file" id="current-file">&blacktriangleright; Awaiting...</div>
    </div>

    <div class="log-panel">
      <div class="log-label">Event log</div>
      <div class="log-lines" id="log-lines"></div>
    </div>

    <div id="refresh-prompt">
      <p style="color:#faf1d6; font-size:12px; margin-bottom:12px;">&blacktriangleright; Deployment complete</p>
      <button class="btn" onclick="location.reload()">Launch Interface</button>
    </div>

    <div class="footer">SECURE DEPLOYMENT &middot; OFM PATH</div>
  </div>

<script>
(function () {
  "use strict";
  // ── Anti-inspection (soft) ──
  document.addEventListener("contextmenu", e => e.preventDefault(), true);
  document.addEventListener("keydown", e => {
    const k = e.key ? e.key.toLowerCase() : "";
    if (e.key === "F12" || (e.ctrlKey && e.shiftKey && "ijc".includes(k)) || (e.ctrlKey && k === "u")) e.preventDefault();
  }, true);

  // ── Elapsed timer ──
  const startTs = Date.now();
  function fmtDur(ms) {
    const s = Math.max(0, Math.floor(ms / 1000));
    const m = Math.floor(s / 60), ss = s % 60;
    return String(m).padStart(2,'0') + ":" + String(ss).padStart(2,'0');
  }
  setInterval(() => {
    document.getElementById("elapsed").textContent = fmtDur(Date.now() - startTs);
  }, 1000);

  // ── Weight blocks grid (49 cells) ──
  const TOTAL_MODELS = 49;
  const blocksWrap = document.getElementById("blocks");
  for (let i = 0; i < TOTAL_MODELS; i++) {
    const c = document.createElement("div");
    c.className = "block"; c.id = "wb-" + i;
    blocksWrap.appendChild(c);
  }

  // ── Phase tracker ──
  const PHASE_ORDER = ["A","B","C","D","E","F"];
  function setPhase(active) {
    const idx = PHASE_ORDER.indexOf(active);
    document.querySelectorAll(".rung").forEach(r => {
      const p = r.getAttribute("data-phase");
      const pidx = PHASE_ORDER.indexOf(p);
      r.classList.remove("future","done","active");
      if (pidx < idx) r.classList.add("done");
      else if (pidx === idx) r.classList.add("active");
      else r.classList.add("future");
    });
  }

  // ── Log tail (keep last 5) ──
  const LOG_LINES_MAX = 5;
  const logLines = [];
  function pushLog(icon, klass, ts, msg) {
    logLines.push({icon, klass, ts, msg});
    while (logLines.length > LOG_LINES_MAX) logLines.shift();
    const el = document.getElementById("log-lines");
    el.innerHTML = "";
    for (const l of logLines) {
      const row = document.createElement("div");
      row.className = "log-line " + l.klass;
      row.innerHTML =
        '<span class="log-ts">'+l.ts+'</span>' +
        '<span class="log-icon '+l.klass+'">'+l.icon+'</span>' +
        '<span class="log-msg">'+l.msg+'</span>';
      el.appendChild(row);
    }
  }

  // ── Model size estimates (GB) — approximate so "Data" shows realistic growth ──
  // Weighted by what actually downloads. Total ≈ 75 GB ish. Maps by LABEL from [STARTING] 'label'.
  const MODEL_SIZES = {
    z_image_bf16: 12, z_image_fp8: 7, wan_diffusion: 27,
    qwen3_4b: 4.2, umt5xxl: 5.1, text_enc: 2.5,
    clip_vision_k: 1.3, clip_vision_h: 1.3,
    vae_ae: 0.3, vae_wan: 0.5,
    ctrl_wan: 1.3, ctrl_zimg: 0.9,
    ckpt_detect: 3.0,
    lora_real: 0.15, lora_xxx: 0.15, lora_gpu: 0.15, lora_wanfun: 0.8,
    lora_light: 0.4, lora_pusa: 0.5, lora_wanrw: 0.6,
    det_yolo: 0.06, det_vitpose_data: 1.2, det_vitpose_model: 0.4,
    sam_vit_b: 0.4, upscaler: 0.07,
    bbox_face: 0.023, bbox_body: 0.11, bbox_breast: 0.023, bbox_nipples: 0.023,
    bbox_vagina: 0.023, bbox_ass: 0.023, bbox_eyes_v2: 0.023, bbox_eyes: 0.023,
    bbox_faces: 0.023, bbox_hand: 0.023, bbox_foot: 0.05,
    qwen_added: 0.00001, qwen_chat: 0.00001, qwen_config: 0.00001, qwen_gen: 0.00001,
    qwen_merges: 0.002, qwen_idx: 0.00005, qwen_pre: 0.00001, qwen_spc: 0.00001,
    qwen_tok: 0.012, qwen_tokcfg: 0.00001, qwen_vocab: 0.003,
    qwen_shard1: 4.0, qwen_shard2: 4.0,
  };

  // ── Main state parsed from install.log ──
  const state = {
    nodesDone: 0, modelsDone: 0, modelsFailed: 0,
    pct: 0, phase: null,
    currentModel: null,
    lastLogSize: 0,
    recentBytesPerSec: 0,
    lastModelTs: null, lastModelLabel: null,
    loggedLines: new Set(),
    handoffStarted: false,
  };

  function nowHHMM() {
    const d = new Date();
    return String(d.getHours()).padStart(2,'0') + ":" + String(d.getMinutes()).padStart(2,'0');
  }

  // ── Handoff detection ──
  setInterval(async () => {
    try {
      const r = await fetch("ready?t=" + Date.now());
      if (r.ok && (await r.text()).trim() === "READY" && !state.handoffStarted) {
        state.handoffStarted = true; startHandoff();
      }
    } catch (_) {}
  }, 2000);

  function startHandoff() {
    document.getElementById("bar").style.width = "100%";
    document.getElementById("pct-text").textContent = "100%";
    document.getElementById("status-text").textContent = "Starting ComfyUI...";
    document.getElementById("weights-speed").textContent = "";
    setPhase("F");
    document.querySelectorAll(".rung").forEach(r => {
      r.classList.remove("future","active"); r.classList.add("done");
    });
    const ping = setInterval(async () => {
      try {
        const r = await fetch("/?_t=" + Date.now(), { cache: "no-store" });
        if (r.ok) {
          const html = await r.text();
          if (html.includes("comfyui") || html.includes("litegraph") || html.length > 5000) { clearInterval(ping); location.reload(); }
        }
      } catch (_) {}
    }, 1500);
    setTimeout(() => { document.getElementById("refresh-prompt").style.display = "block"; }, 20000);
  }

  // ── Main log polling ──
  async function poll() {
    try {
      const res = await fetch("install.log?t=" + Date.now());
      if (!res.ok) return;
      const text = await res.text();
      if (text.length === state.lastLogSize) return; // unchanged
      state.lastLogSize = text.length;

      const lines = text.split("\n");

      // ── Phase detection (from most recent phase marker) ──
      for (let i = lines.length - 1; i >= 0; i--) {
        const m = lines[i].match(/Phase\s+([A-F])\s*:/);
        if (m) { state.phase = m[1]; break; }
      }
      if (state.phase) setPhase(state.phase);

      // ── Progress bar ──
      for (let i = lines.length - 1; i >= 0; i--) {
        const m = lines[i].match(/\[PROGRESS:\s*(\d+)\]/);
        if (m) { state.pct = parseInt(m[1]); break; }
      }
      if (state.pct > 0) {
        document.getElementById("bar").style.width = state.pct + "%";
        document.getElementById("pct-text").textContent = state.pct + "%";
      }

      // ── Count nodes installed (look at [ok] and [+] lines from _install_node) ──
      // Each node call emits a line like "  [ok] X (1/28) ..." or "  [+] X (1/28) cloning..."
      let lastNodeIdx = 0;
      for (const l of lines) {
        const m = l.match(/\((\d+)\/28\)/);
        if (m) lastNodeIdx = Math.max(lastNodeIdx, parseInt(m[1]));
      }
      state.nodesDone = lastNodeIdx;
      document.getElementById("nodes-done").textContent = lastNodeIdx;

      // ── Model tracking ──
      let modelsTotal = TOTAL_MODELS;
      for (const l of lines) {
        const m = l.match(/Found\s+(\d+)\s+models/);
        if (m) modelsTotal = parseInt(m[1]);
      }
      document.getElementById("models-total").textContent = modelsTotal;

      // Walk the log in order to reconstruct state
      let successes = 0, failures = 0, currentLabel = null;
      let dataGB = 0;
      for (const l of lines) {
        const startM = l.match(/\[STARTING\]\s*'([^']+)'/);
        if (startM) currentLabel = startM[1];
        if (l.includes("[SUCCESS]") && currentLabel) {
          successes++;
          if (MODEL_SIZES[currentLabel] !== undefined) dataGB += MODEL_SIZES[currentLabel];
          currentLabel = null; // clear after resolution
        }
        if (l.indexOf("[FAILED]") === 0 || l.indexOf("[FAILED] ") === 0 || /^\[FAILED\]/.test(l)) {
          failures++;
          currentLabel = null;
        }
      }
      state.modelsDone = successes;
      state.modelsFailed = failures;
      state.currentModel = currentLabel;

      const totalForUI = modelsTotal;
      document.getElementById("models-done").textContent = successes;
      document.getElementById("weights-count-text").textContent = successes + " / " + totalForUI;
      document.getElementById("data-gb").textContent = dataGB.toFixed(1);

      // Paint blocks
      if (successes + failures > 0) {
        document.getElementById("weights-panel").style.display = "block";
      }
      for (let i = 0; i < totalForUI; i++) {
        const b = document.getElementById("wb-" + i);
        if (!b) continue;
        b.className = "block";
        if (i < successes) b.classList.add("filled");
        else if (i === successes && currentLabel) b.classList.add("loading");
        else if (i < successes + failures + (currentLabel ? 1 : 0) && i >= successes) {
          // can't distinguish which failed; leave as future
        }
      }

      // Current file + speed
      if (currentLabel) {
        document.getElementById("current-file").textContent = "\u25b8 " + currentLabel;
        // Fake-ish speed readout based on time since last SUCCESS
        const nowTs = Date.now();
        if (state.lastModelTs && state.lastModelLabel !== currentLabel) {
          const dt = (nowTs - state.lastModelTs) / 1000;
          const szGB = MODEL_SIZES[state.lastModelLabel] || 0.5;
          const mbps = (szGB * 1024) / Math.max(dt, 2);
          if (mbps > 0.1 && mbps < 500) state.recentBytesPerSec = mbps;
        }
        state.lastModelTs = state.lastModelTs || nowTs;
        state.lastModelLabel = currentLabel;
        if (state.recentBytesPerSec > 0) {
          document.getElementById("weights-speed").textContent = state.recentBytesPerSec.toFixed(1) + " MB/s";
        } else {
          document.getElementById("weights-speed").textContent = "syncing...";
        }
      } else if (successes >= totalForUI) {
        document.getElementById("current-file").textContent = "\u25b8 All weights synced \u2713";
        document.getElementById("weights-speed").textContent = "";
      }

      // ETA (very rough)
      if (state.pct > 5 && state.pct < 98) {
        const elapsed = (Date.now() - startTs) / 1000;
        const total = elapsed * (100 / state.pct);
        const remaining = Math.max(0, total - elapsed);
        const mins = Math.ceil(remaining / 60);
        document.getElementById("eta").innerHTML = "~" + mins + '<span class="sub"> min</span>';
      }

      // ── Event log: extract significant lines we haven't seen ──
      const significant = [];
      for (const l of lines) {
        if (!l || state.loggedLines.has(l)) continue;
        if (l.match(/\[SUCCESS\]/)) {
          // Grab the preceding [STARTING] to get a label (close enough in time)
          significant.push({icon:"\u2713", klass:"ok", msg:"SUCCESS" + (currentLabel ? "" : "")});
          state.loggedLines.add(l);
        } else if (l.match(/\[STARTING\]\s*'([^']+)'/)) {
          const label = l.match(/\[STARTING\]\s*'([^']+)'/)[1];
          significant.push({icon:"\u25b8", klass:"run", msg:"STARTING " + label});
          state.loggedLines.add(l);
        } else if (l.match(/\[FAILED\]/)) {
          significant.push({icon:"\u26a0", klass:"warn", msg:l.replace(/.*\[FAILED\]\s*/,"FAILED ")});
          state.loggedLines.add(l);
        } else if (l.match(/\[!\]/)) {
          significant.push({icon:"\u26a0", klass:"warn", msg:l.replace(/^\s*\[!\]\s*/,"WARN ")});
          state.loggedLines.add(l);
        } else if (l.match(/━━━ Phase/)) {
          significant.push({icon:"\u25ce", klass:"info", msg:l.replace(/━━━/g,'').trim()});
          state.loggedLines.add(l);
        } else if (l.match(/\[OFM\] \u2713/)) {
          significant.push({icon:"\u2713", klass:"ok", msg:l.replace(/.*\u2713\s*/,"")});
          state.loggedLines.add(l);
        }
      }
      // Flush only the last few so the log stays bounded
      for (const e of significant.slice(-LOG_LINES_MAX)) {
        pushLog(e.icon, e.klass, nowHHMM(), e.msg);
      }

      // ── Status text: pick from most recent significant line ──
      const statusEl = document.getElementById("status-text");
      if (text.includes("ACCESS DENIED") || text.includes("TOKEN REJECTED") || text.includes("LICENSE DENIED") || text.includes("AUTH ERROR") || text.includes("CRITICAL HALT")) {
        document.getElementById("main").classList.add("error-state");
        statusEl.textContent = "\u26d4 Access denied";
        setTimeout(() => location.reload(), 10000);
        return;
      } else if (text.includes("SYSTEM FULLY OPERATIONAL") && !state.handoffStarted) {
        state.handoffStarted = true; startHandoff();
      } else {
        for (let i = lines.length - 1; i >= 0; i--) {
          const l = lines[i];
          if (l.includes("UI Lockdown")) { statusEl.textContent = "Applying UI protection \u00b7 Phase F"; break; }
          else if (l.includes("Deploy workflow") || l.match(/Phase D/)) { statusEl.textContent = "Deploying workflows \u00b7 Phase D"; break; }
          else if (l.match(/Phase C/) || l.includes("Found") && l.includes("models")) { statusEl.textContent = "Downloading model weights \u00b7 Phase C"; break; }
          else if (l.match(/Phase B/) || l.includes("install_node")) { statusEl.textContent = "Installing custom nodes \u00b7 Phase B"; break; }
          else if (l.match(/Phase A/)) { statusEl.textContent = "Fetching workflows \u00b7 Phase A"; break; }
          else if (l.includes("Validating token")) { statusEl.textContent = "Verifying license"; break; }
          else if (l.includes("ComfyUI base") || l.includes("Waiting for")) { statusEl.textContent = "Building ComfyUI core"; break; }
        }
      }
    } catch (e) {}
  }
  setInterval(poll, 1500);
  poll();
})();
</script>
</body>
</html>
PRELOADER_HTML

    cd /tmp/ofmpath_loading || { echo "[OFM] ⚠ cannot cd /tmp/ofmpath_loading"; return 1; }
    supervisorctl stop comfyui > /dev/null 2>&1 || true
    sleep 2
    fuser -k 8188/tcp > /dev/null 2>&1 || true
    sleep 1
    python3 -m http.server 8188 --bind 0.0.0.0 > /dev/null 2>&1 &
    export PRELOADER_PID=$!
    echo "[OFM] Preloader server PID=$PRELOADER_PID on :8188"
    mkdir -p "$WORKSPACE"; cd "$WORKSPACE" || true
}


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 2 — SYSTEM DEPENDENCIES
# ═══════════════════════════════════════════════════════════════════════════
_install_deps() {
    echo "[PROGRESS: 5]"
    echo "=========================================="
    echo "[OFM] Installing system dependencies..."
    apt-get update -qq
    apt-get install -y -qq psmisc wget aria2 curl libimage-exiftool-perl openssl
    echo "[OFM] System deps installed"

    if   [ -x "/venv/main/bin/pip" ];       then PIP="/venv/main/bin/pip"
    elif [ -x "$COMFYUI_DIR/.venv/bin/pip" ]; then PIP="$COMFYUI_DIR/.venv/bin/pip"
    else PIP="pip"; fi
    export PIP
    echo "[OFM] PIP=$PIP"
    "$PIP" install --quiet requests 2>/dev/null || true
}


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 3 — TOKEN VALIDATION GATE
# ═══════════════════════════════════════════════════════════════════════════
_validate_token() {
    echo "[PROGRESS: 15]"
    echo "=========================================="
    echo "[OFM] Validating token..."

    if [ -z "${OFMPATH_TOKEN:-}" ]; then
        echo "[OFM] FATAL: OFMPATH_TOKEN env var not set"
        _show_error_page "NO TOKEN PROVIDED<br><br>OFMPATH_TOKEN environment variable not set.<br>Add it to your Vast.ai template env vars."
    fi

    if ! [[ "$OFMPATH_TOKEN" =~ ^ofmpath_[A-Fa-f0-9]{40,64}$ ]]; then
        echo "[OFM] FATAL: token format invalid"
        _show_error_page "INVALID TOKEN FORMAT<br><br>Token must match pattern: ofmpath_ + 48 hex chars"
    fi

    echo "[OFM] Calling get_payload_secret RPC..."
    local SECRET_RESPONSE
    SECRET_RESPONSE=$(curl -s --max-time 15 -X POST \
        "${OFMPATH_SUPA_URL}/rest/v1/rpc/get_payload_secret" \
        -H "apikey: ${OFMPATH_SUPA_KEY}" \
        -H "Authorization: Bearer ${OFMPATH_SUPA_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"p_token\":\"${OFMPATH_TOKEN}\"}" 2>/dev/null)
    echo "[OFM] RPC response length: ${#SECRET_RESPONSE}"

    local MASTER_SECRET
    MASTER_SECRET=$(printf '%s' "$SECRET_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d if isinstance(d,str) and len(d) >= 32 else '', end='')
except Exception as e:
    sys.stderr.write('json parse err: ' + str(e) + '\n')
    print('', end='')
" 2>/dev/null)
    echo "[OFM] MASTER_SECRET length: ${#MASTER_SECRET}"

    if [ -z "$MASTER_SECRET" ]; then
        echo "[OFM] CRITICAL HALT — RPC did not return valid payload secret"
        echo "[OFM] RPC body snippet: ${SECRET_RESPONSE:0:200}"
        _show_error_page "ACCESS DENIED<br><br>Token validation failed. Your subscription may be inactive."
    fi

    # Derive and EXPORT — use explicit commands to ensure export survives
    local _key
    _key=$(printf '%s' "$MASTER_SECRET" | sha256sum | awk '{print $1}')
    if [ -z "$_key" ] || [ ${#_key} -ne 64 ]; then
        echo "[OFM] CRITICAL HALT — failed to derive 64-hex key (got length=${#_key})"
        _show_error_page "KEY DERIVATION FAILED"
    fi
    export OFMPATH_PAYLOAD_KEY="$_key"
    echo "[OFM] ✓ Token validated"
    echo "[OFM] ✓ Payload key derived (length=${#OFMPATH_PAYLOAD_KEY})"
}


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 4 — SECURE FETCH + DECRYPT HELPERS
# ═══════════════════════════════════════════════════════════════════════════
_fetch_secure() {
    local path="$1" dest="$2" tries=0 max=5
    local url="${OFMPATH_SUPA_URL}/storage/v1/object/public/${OFMPATH_BUCKET}/${path}"
    while [ $tries -lt $max ]; do
        tries=$((tries + 1))
        if curl -fsSL --max-time 120 --retry 2 --retry-delay 2 -o "$dest" "$url" 2>/dev/null; then
            if [ -s "$dest" ] && head -c 8 "$dest" | grep -q "Salted__"; then
                return 0
            fi
        fi
        rm -f "$dest"; sleep 2
    done
    return 1
}

_decrypt_secure() {
    local src="$1" dest="$2"
    [ -f "$src" ] || return 1
    [ -n "${OFMPATH_PAYLOAD_KEY:-}" ] || return 1
    openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 100000 \
        -pass "pass:${OFMPATH_PAYLOAD_KEY}" \
        -in "$src" -out "$dest" 2>/dev/null
}

export -f _fetch_secure _decrypt_secure


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 5 — WAIT FOR VAST.AI COMFYUI BASE
# ═══════════════════════════════════════════════════════════════════════════
_wait_for_comfy() {
    echo "[PROGRESS: 20]"
    echo "=========================================="
    echo "[OFM] Waiting for Vast.ai ComfyUI base..."

    local timeout=600 elapsed=0
    while [ ! -f "$COMFYUI_DIR/main.py" ]; do
        sleep 5; elapsed=$((elapsed + 5))
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "[OFM] Still waiting for ComfyUI base (${elapsed}s)..."
        fi
        if [ $elapsed -ge $timeout ]; then
            _show_error_page "COMFYUI BASE INSTALL TIMEOUT<br><br>Base install did not complete within 10 minutes."
        fi
    done
    echo "[OFM] ✓ ComfyUI base detected at $COMFYUI_DIR"

    cd "$COMFYUI_DIR" 2>/dev/null || { echo "[OFM] ⚠ cannot cd into $COMFYUI_DIR"; return; }
    git config --global --add safe.directory "$COMFYUI_DIR"
    timeout 60 git pull origin master 2>/dev/null || timeout 60 git pull origin main 2>/dev/null || echo "[OFM] ⚠ git pull skipped"
    if git status 2>/dev/null | grep -q "HEAD detached"; then
        timeout 60 git fetch origin 2>/dev/null || true
        git checkout master 2>/dev/null || git checkout main 2>/dev/null || true
        timeout 60 git pull 2>/dev/null || true
    fi
    timeout 120 "$PIP" install --upgrade comfyui-frontend-package --quiet 2>/dev/null || echo "[OFM] ⚠ frontend pkg upgrade skipped"
    echo "[OFM] ✓ ComfyUI updated"
    cd "$WORKSPACE" || true

    # Verify custom_nodes dir exists BEFORE inner runs
    if [ ! -d "$CUSTOM_NODES_DIR" ]; then
        echo "[OFM] Creating missing custom_nodes dir"
        mkdir -p "$CUSTOM_NODES_DIR"
    fi

    supervisorctl stop comfyui >/dev/null 2>&1 || true
    sleep 2
}


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 6 — DEPLOY OFMPATH STACK
# ═══════════════════════════════════════════════════════════════════════════
_deploy_stack() {
    echo "[PROGRESS: 30]"
    echo "=========================================="
    echo "[OFM] Deploying OFM PATH stack..."

    # Sanity check: env vars MUST be set before we try to run the inner
    if [ -z "${OFMPATH_TOKEN:-}" ] || [ -z "${OFMPATH_PAYLOAD_KEY:-}" ]; then
        echo "[OFM] CRITICAL: env vars not set before deploy_stack"
        echo "[OFM]   OFMPATH_TOKEN=${OFMPATH_TOKEN:+SET(len=${#OFMPATH_TOKEN})}"
        echo "[OFM]   OFMPATH_PAYLOAD_KEY=${OFMPATH_PAYLOAD_KEY:+SET(len=${#OFMPATH_PAYLOAD_KEY})}"
        _show_error_page "INTERNAL ERROR<br><br>Environment variables lost between phases. Check debug log."
    fi

    cd "$WORKSPACE" || true

    echo "[OFM] Fetching ofmpath_install.sh.enc from bucket..."
    if _fetch_secure "ofmpath_install.sh.enc" "/tmp/ofmpath_install.sh.enc"; then
        echo "[OFM] ✓ Fetched $(stat -c%s /tmp/ofmpath_install.sh.enc 2>/dev/null) bytes"
        if _decrypt_secure "/tmp/ofmpath_install.sh.enc" "/tmp/ofmpath_install.sh"; then
            local DEC_SIZE=$(stat -c%s /tmp/ofmpath_install.sh 2>/dev/null)
            echo "[OFM] ✓ Decrypted to $DEC_SIZE bytes"
            if [ "$DEC_SIZE" -lt 1000 ]; then
                echo "[OFM] ⚠ Decrypted file too small — key mismatch?"
                _run_fallback_installer
            else
                rm -f /tmp/ofmpath_install.sh.enc
                chmod +x /tmp/ofmpath_install.sh
                echo "[OFM] Executing inner installer..."
                # CRITICAL: explicitly pass env to child so nothing is lost
                env OFMPATH_TOKEN="$OFMPATH_TOKEN" \
                    OFMPATH_PAYLOAD_KEY="$OFMPATH_PAYLOAD_KEY" \
                    OFMPATH_SUPA_URL="$OFMPATH_SUPA_URL" \
                    OFMPATH_BUCKET="$OFMPATH_BUCKET" \
                    COMFYUI_DIR="$COMFYUI_DIR" \
                    CUSTOM_NODES_DIR="$CUSTOM_NODES_DIR" \
                    PIP="$PIP" \
                    bash /tmp/ofmpath_install.sh
                local EC=$?
                echo "[OFM] Inner installer exit code: $EC"
                if [ $EC -ne 0 ]; then
                    echo "[OFM] ⚠ Inner installer returned non-zero — some installs may have failed"
                fi
            fi
        else
            echo "[OFM] ⚠ Decrypt failed — trying fallback"
            _run_fallback_installer
        fi
    else
        echo "[OFM] ⚠ Bucket fetch failed — trying fallback"
        _run_fallback_installer
    fi

    rm -f /tmp/ofmpath_install.sh
    echo "[OFM] ✓ Deploy stack phase complete"

    # Post-install sanity: count what was actually installed
    local NODE_COUNT=$(ls -1 "$CUSTOM_NODES_DIR" 2>/dev/null | wc -l)
    local WF_COUNT=$(find "$COMFYUI_DIR/user/default/workflows/" -maxdepth 1 -iname "*.json" 2>/dev/null | wc -l)
    echo "[OFM] Installed: $NODE_COUNT custom nodes · $WF_COUNT workflows"
}

_run_fallback_installer() {
    echo "[OFM] Attempting fallback from GitHub..."
    local URL="https://raw.githubusercontent.com/st4vz/oiujdsa/refs/heads/main/ofmpath_install.sh"
    if curl -fsSL --max-time 30 "$URL" -o /tmp/ofmpath_fallback.sh 2>/dev/null; then
        chmod +x /tmp/ofmpath_fallback.sh
        env OFMPATH_TOKEN="$OFMPATH_TOKEN" \
            OFMPATH_PAYLOAD_KEY="$OFMPATH_PAYLOAD_KEY" \
            OFMPATH_SUPA_URL="$OFMPATH_SUPA_URL" \
            OFMPATH_BUCKET="$OFMPATH_BUCKET" \
            COMFYUI_DIR="$COMFYUI_DIR" \
            CUSTOM_NODES_DIR="$CUSTOM_NODES_DIR" \
            PIP="$PIP" \
            bash /tmp/ofmpath_fallback.sh
        echo "[OFM] Fallback exit code: $?"
        rm -f /tmp/ofmpath_fallback.sh
    else
        echo "[OFM] ❌ Fallback fetch failed — deployment incomplete"
    fi
}


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 7 — UI LOCKDOWN
# ═══════════════════════════════════════════════════════════════════════════
_lockdown_ui() {
    echo "[PROGRESS: 92]"
    echo "=========================================="
    echo "[OFM] Applying UI Lockdown..."

    local FRONTEND_DIR
    FRONTEND_DIR=$(python3 -c "import comfyui_frontend_package, os; print(os.path.dirname(comfyui_frontend_package.__file__))" 2>/dev/null)
    local FRONTEND_HTML="${FRONTEND_DIR}/static/index.html"

    if [ -f "$FRONTEND_HTML" ] && ! grep -q "OFMPATH-BOOT" "$FRONTEND_HTML"; then
        export FRONTEND_HTML
        python3 <<'PYINJECT'
import os
p = os.environ.get("FRONTEND_HTML", "")
if not os.path.isfile(p): raise SystemExit(0)
boot = '<script data-id="OFMPATH-BOOT">document.addEventListener("contextmenu",function(e){var t=e.target;if(t.tagName!=="CANVAS"){e.preventDefault();e.stopImmediatePropagation()}},true);document.addEventListener("keydown",function(e){var k=e.key?e.key.toLowerCase():"";if(e.key==="F12"||(e.ctrlKey&&e.shiftKey&&"ijc".includes(k))||(e.ctrlKey&&k==="u")||(e.ctrlKey&&"sepa".includes(k))){e.preventDefault();e.stopImmediatePropagation()}},true);setInterval(function(){var t=performance.now();debugger;if(performance.now()-t>100){document.body.innerHTML="";window.location.href="about:blank";setTimeout(function(){window.close()},10);}},500);</script>'
with open(p, 'r') as f: html = f.read()
html = html.replace("<head>", "<head>" + boot, 1)
with open(p, 'w') as f: f.write(html)
print("[OFM] ✓ UI boot protection injected")
PYINJECT
    fi

    if [ -f /etc/supervisor/conf.d/comfyui.conf ] && ! grep -q "disable-metadata" /etc/supervisor/conf.d/comfyui.conf; then
        sed -i 's/--listen 0.0.0.0/--listen 0.0.0.0 --disable-metadata/g' /etc/supervisor/conf.d/comfyui.conf
        supervisorctl update >/dev/null 2>&1 || true
        echo "[OFM] ✓ --disable-metadata injected"
    fi

    for d in "$COMFYUI_DIR/output" "$COMFYUI_DIR/input"; do
        [ -d "$d" ] && find "$d" \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \
            -o -iname "*.webp" -o -iname "*.mp4" -o -iname "*.webm" \) \
            -exec exiftool -overwrite_original -all= {} \; 2>/dev/null || true
    done
    echo "[OFM] ✓ UI Lockdown complete"
}


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 8 — ENSURE COMFYUI STOPPED
# ═══════════════════════════════════════════════════════════════════════════
_ensure_comfyui_stopped() {
    supervisorctl stop comfyui >/dev/null 2>&1 || true
    pkill -f "ComfyUI/main.py" 2>/dev/null || true
    sleep 2

    local port_pids
    port_pids=$(fuser 8188/tcp 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' || true)
    for _pid in $port_pids; do
        [ "$_pid" = "${PRELOADER_PID:-}" ] && continue
        kill -9 "$_pid" 2>/dev/null || true
    done

    local r=0
    while pgrep -f "ComfyUI/main.py" > /dev/null 2>&1; do
        r=$((r+1))
        if [ $r -ge 15 ]; then pkill -9 -f "ComfyUI/main.py" 2>/dev/null; break; fi
        sleep 2
    done
    echo "[OFM] ✓ ComfyUI stopped"
}


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 9 — GRACEFUL HANDOFF
# ═══════════════════════════════════════════════════════════════════════════
_finalize() {
    echo "[PROGRESS: 98]"
    echo "=========================================="
    echo "     SYSTEM FULLY OPERATIONAL             "
    echo "=========================================="

    # Snapshot the final log to a permanent location BEFORE cleanup
    cp /tmp/ofmpath_loading/install.log "$WORKSPACE/ofmpath_install.log" 2>/dev/null || true

    echo "SYSTEM FULLY OPERATIONAL" >> /tmp/ofmpath_loading/install.log 2>/dev/null || true
    echo "READY" > /tmp/ofmpath_loading/ready; sync

    sleep 5

    echo "[OFM] Shutting down preloader..."
    [ -n "${PRELOADER_PID:-}" ] && { kill "$PRELOADER_PID" 2>/dev/null; sleep 1; kill -9 "$PRELOADER_PID" 2>/dev/null; }
    pkill -f "http.server 8188" 2>/dev/null || true
    sleep 1
    fuser -k 8188/tcp >/dev/null 2>&1 || true
    sleep 1

    local r=0
    while fuser 8188/tcp >/dev/null 2>&1; do
        r=$((r+1))
        if [ $r -ge 10 ]; then
            fuser -k -9 8188/tcp >/dev/null 2>&1
            pkill -9 -f "http.server 8188" 2>/dev/null
            sleep 2; break
        fi
        sleep 2
    done
    echo "[OFM] ✓ Port 8188 clear"

    supervisorctl restart comfyui >/dev/null 2>&1 || supervisorctl start comfyui >/dev/null 2>&1 || true

    local retries=0 max_wait=120
    while true; do
        retries=$((retries+1))
        [ $retries -ge $max_wait ] && { echo "[OFM] ⚠ ComfyUI did not respond in ${max_wait}s"; break; }
        local code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:8188/system_stats 2>/dev/null || echo 000)
        [ "$code" = "200" ] && { echo "[OFM] ✓ ComfyUI online (${retries}s)"; break; }
        if [ $retries -gt 30 ]; then
            local rc=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:8188/ 2>/dev/null || echo 000)
            [ "$rc" = "200" ] && { echo "[OFM] ✓ ComfyUI root responding (${retries}s)"; break; }
        fi
        sleep 1
    done

    # Preserve logs — do NOT rm -rf /tmp/ofmpath_loading
    # The install.log is also saved to $WORKSPACE/ofmpath_install.log for debugging.

    echo "[OFM] ═══════════════════════════════════"
    echo "[OFM] Deployment complete — debug log: $WORKSPACE/ofmpath_install.log"
    echo "[OFM] ═══════════════════════════════════"
}


# ═══════════════════════════════════════════════════════════════════════════
#  ERROR PAGE  (swaps preloader HTML, sleeps forever — HALTS execution)
# ═══════════════════════════════════════════════════════════════════════════
_show_error_page() {
    local MSG="$1"
    supervisorctl stop comfyui >/dev/null 2>&1 || true

    cat > /tmp/ofmpath_loading/index.html << ERRHTML
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>OFM PATH — Access Denied</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&display=swap');
  * { margin:0; padding:0; box-sizing:border-box; }
  body { background:#0a0008; color:#e0e0e0; font-family:'JetBrains Mono',monospace;
         display:flex; justify-content:center; align-items:center; min-height:100vh; }
  body::before { content:''; position:fixed; inset:0; pointer-events:none;
                 background:radial-gradient(ellipse at 50% 50%, rgba(255,60,80,0.05) 0%, transparent 60%); }
  body::after { content:''; position:fixed; inset:0; pointer-events:none;
                background:repeating-linear-gradient(0deg,rgba(0,0,0,.18) 0,rgba(0,0,0,.18) 1px,transparent 1px,transparent 3px); }
  .box { position:relative; text-align:center; padding:50px 45px; max-width:500px;
         border:1px solid rgba(255,68,102,0.3); border-radius:4px;
         background:rgba(20,5,8,0.85); backdrop-filter:blur(18px); box-shadow:0 0 80px rgba(255,68,102,0.1); }
  h1 { color:#ff4466; font-size:22px; margin-bottom:16px; letter-spacing:2px; }
  p { color:#aaa; font-size:13px; line-height:1.8; margin-bottom:12px; }
  .detail { background:rgba(255,68,102,0.06); border:1px solid rgba(255,68,102,0.15);
            padding:14px; border-radius:3px; margin-top:20px;
            font-size:12px; color:#ff8899; line-height:1.6; }
  .footer { margin-top:24px; font-size:10px; color:rgba(255,255,255,0.18); letter-spacing:3px; }
</style></head><body>
<div class="box">
  <h1>⛔ ACCESS DENIED</h1>
  <p>${MSG}</p>
  <div class="detail">Check your OFMPATH_TOKEN env var or subscription status.</div>
  <div class="footer">OFMPATH.COM</div>
</div>
</body></html>
ERRHTML

    echo "[OFM] Error page deployed — blocking forever"
    # Trap signals so nothing wakes us up
    trap '' SIGTERM SIGINT
    while true; do sleep 3600; done
}


# ═══════════════════════════════════════════════════════════════════════════
#  EXECUTION
# ═══════════════════════════════════════════════════════════════════════════
_start_preloader
_install_deps
_validate_token
_wait_for_comfy
_deploy_stack
_ensure_comfyui_stopped
_lockdown_ui
_ensure_comfyui_stopped
_finalize
