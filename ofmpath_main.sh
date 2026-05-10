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
  html,body { height:100%; overflow:hidden; }   /* never scroll the page itself */
  body { background:#0a0a0a; color:#f0e6cf; font-family:'JetBrains Mono','Courier New',monospace;
         display:flex; justify-content:center; align-items:center; height:100vh;
         position:relative; padding:clamp(8px, 2vh, 32px) 16px; }
  body::before { content:''; position:fixed; inset:0; pointer-events:none; z-index:2;
                 background:repeating-linear-gradient(0deg,rgba(0,0,0,.35) 0,rgba(0,0,0,.35) 1px,transparent 1px,transparent 3px); }
  body::after { content:''; position:fixed; inset:0; pointer-events:none; z-index:1;
                background:radial-gradient(ellipse at 50% 50%, rgba(240,230,207,0.04) 0%, transparent 65%); }

  /* Wrap fits within viewport — internal scroll only as last-resort fallback */
  .wrap { position:relative; z-index:10; max-width:780px; width:100%;
          max-height:calc(100vh - clamp(16px, 4vh, 64px));
          overflow-y:auto;
          padding:clamp(16px, 3vh, 48px) clamp(20px, 4vw, 50px) clamp(16px, 2.5vh, 44px);
          background:rgba(15,12,8,0.7); border:1px solid rgba(240,230,207,0.18); border-radius:4px;
          backdrop-filter:blur(8px);
          box-shadow:0 0 60px rgba(240,230,207,0.05), inset 0 0 0 1px rgba(240,230,207,0.06);
          animation:slideUp 0.8s cubic-bezier(0.16, 1, 0.3, 1) both;
          display:flex; flex-direction:column; }
  /* Hide scrollbar in webkit while still allowing scroll if needed */
  .wrap::-webkit-scrollbar { width:4px; }
  .wrap::-webkit-scrollbar-thumb { background:rgba(240,230,207,0.15); border-radius:2px; }

  @keyframes slideUp { from { opacity:0; transform:translateY(16px);} to { opacity:1; transform:translateY(0);} }
  .brand { text-align:center; font-size:12px; letter-spacing:5px; color:#f0e6cf; opacity:.6; margin-bottom:clamp(6px, 1vh, 14px); }
  pre.ascii { font-size:clamp(8px, 1.4vh, 14px); line-height:1.25; color:#faf1d6;
              text-shadow:0 0 10px rgba(255,245,221,.35); margin:0 0 clamp(10px, 2vh, 24px); white-space:pre; text-align:center;
              font-family:'JetBrains Mono','Courier New',monospace; }
  .version { text-align:center; font-size:11px; color:#f0e6cf; opacity:.5; letter-spacing:4px; margin-bottom:clamp(12px, 2.5vh, 32px); text-transform:uppercase; }
  .header-row { display:grid; grid-template-columns:1fr auto 1fr; align-items:center; gap:12px; margin-bottom:clamp(8px, 1.2vh, 14px); }
  .header-row .status-badge { grid-column:2; justify-self:center; }
  .header-row .elapsed { grid-column:3; justify-self:end; }
  .status-badge { display:inline-flex; align-items:center; gap:10px; padding:clamp(6px, 1vh, 10px) 20px;
                  background:rgba(240,230,207,0.05); border:1px solid rgba(240,230,207,0.22); border-radius:3px;
                  font-size:13px; color:#faf1d6; letter-spacing:0.4px; }
  .dot { width:8px; height:8px; border-radius:50%; background:#f5efd6;
         animation:dotPulse 1.3s infinite; box-shadow:0 0 8px #f5efd6; }
  @keyframes dotPulse { 0%,100% { transform:scale(.8); opacity:.6;} 50% { transform:scale(1.25); opacity:1;} }
  .elapsed { font-family:'JetBrains Mono',monospace; font-size:12px; color:rgba(240,230,207,0.7); letter-spacing:1px; }
  .bar-track { width:100%; height:6px; background:rgba(240,230,207,0.08); border-radius:3px;
               overflow:hidden; margin-bottom:8px; box-shadow:inset 0 0 0 1px rgba(240,230,207,0.15); }
  .bar-fill { height:100%; width:0%; background:linear-gradient(90deg,#f0e6cf,#faf1d6);
              transition:width .6s cubic-bezier(0.2,0.8,0.2,1); box-shadow:0 0 10px rgba(240,230,207,0.4); }
  .bar-label { display:flex; justify-content:space-between; font-size:11px; color:rgba(240,230,207,0.45);
               letter-spacing:1px; margin-bottom:clamp(12px, 2.5vh, 32px); text-transform:uppercase; }
  .stats { display:grid; grid-template-columns:repeat(3, 1fr); gap:clamp(8px, 1.5vh, 14px); margin-bottom:clamp(12px, 2vh, 28px); }
  .stat { background:rgba(240,230,207,0.04); border:1px solid rgba(240,230,207,0.15); border-radius:3px; padding:clamp(10px, 1.6vh, 20px) clamp(12px, 1.6vw, 18px); }
  .stat-label { font-size:10px; color:rgba(240,230,207,0.55); letter-spacing:2px; text-transform:uppercase; margin-bottom:clamp(4px, 0.8vh, 10px); }
  .stat-value { font-size:clamp(20px, 3.5vh, 30px); color:#faf1d6; font-weight:600; line-height:1; }
  .stat-value .sub { font-size:14px; color:rgba(240,230,207,0.4); }
  .stat-hint { font-size:10px; color:rgba(240,230,207,0.4); margin-top:8px; letter-spacing:0.5px; }
  .panel { background:rgba(240,230,207,0.03); border:1px dashed rgba(240,230,207,0.22); border-radius:3px;
           padding:clamp(10px, 1.6vh, 20px) clamp(14px, 1.8vw, 22px); margin-bottom:clamp(10px, 1.6vh, 20px); }
  .panel-label { font-size:11px; color:rgba(240,230,207,0.55); letter-spacing:2px; text-transform:uppercase; margin-bottom:clamp(8px, 1.4vh, 18px); }
  .ladder { display:flex; gap:8px; font-size:11px; }
  .rung { flex:1; padding:clamp(6px, 1vh, 14px) 6px; text-align:center; border-radius:3px; transition:all 0.4s; }
  .rung.future { background:rgba(240,230,207,0.05); color:rgba(240,230,207,0.5); border:1px solid rgba(240,230,207,0.15); }
  .rung.done { background:rgba(240,230,207,0.12); color:#0a0a0a; font-weight:600; }
  .rung.active { background:rgba(240,230,207,0.28); color:#0a0a0a; font-weight:600; box-shadow:0 0 10px rgba(240,230,207,0.3); }
  .rung .code { font-size:9px; letter-spacing:1.5px; opacity:0.6; display:block; margin-bottom:5px; }
  .rung.done .code, .rung.active .code { color:rgba(10,10,10,0.6); opacity:1; }
  .weights-head { display:flex; justify-content:space-between; align-items:center; margin-bottom:10px; }
  .weights-count { font-size:10px; color:rgba(240,230,207,0.55); letter-spacing:1.5px; text-transform:uppercase; }
  .weights-speed { font-size:10px; color:#faf1d6; letter-spacing:0.5px; }
  .blocks { display:flex; flex-wrap:wrap; gap:5px; margin-bottom:clamp(8px, 1.2vh, 14px); }
  .block { width:14px; height:14px; border-radius:2px;
           background:rgba(240,230,207,0.06); border:1px solid rgba(240,230,207,0.2); transition:all 0.3s; }
  .block.filled { background:#f0e6cf; border-color:#f0e6cf; box-shadow:0 0 6px rgba(240,230,207,0.45); }
  .block.loading { background:rgba(240,230,207,0.2); border-color:rgba(240,230,207,0.4); animation:dotPulse 1.3s infinite; }
  .block.failed { background:rgba(201,122,95,0.25); border-color:rgba(201,122,95,0.6); }
  .current-file { font-size:10px; color:rgba(250,241,214,0.5); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .footer { text-align:center; font-size:11px; color:rgba(240,230,207,0.25); letter-spacing:4px; margin-top:clamp(14px, 2.5vh, 32px); text-transform:uppercase; }
  .error-state .bar-fill { background:#c97a5f !important; box-shadow:0 0 10px #c97a5f; }
  .error-state .status-badge { color:#c97a5f; border-color:rgba(201,122,95,0.4); }
  .error-state .dot { background:#c97a5f; box-shadow:0 0 8px #c97a5f; }
  #refresh-prompt { display:none; margin-top:18px; text-align:center; }
  .btn { background:linear-gradient(135deg,#f0e6cf,#faf1d6); color:#0a0a0a;
         border:none; padding:11px 30px; border-radius:3px; font-size:12px; font-weight:600;
         cursor:pointer; letter-spacing:2px; font-family:'JetBrains Mono',monospace; text-transform:uppercase;
         box-shadow:0 0 20px rgba(240,230,207,0.3); transition:all .15s; }
  .btn:hover { transform:translateY(-1px); box-shadow:0 0 30px rgba(240,230,207,0.5); }

  /* Narrow screens — stack stats, allow ladder wrap */
  @media (max-width: 540px) {
    .stats { grid-template-columns:repeat(2,1fr); }
    .ladder { flex-wrap:wrap; }
    .rung { min-width:45px; }
  }

  /* Short viewports (laptop/embedded screens) — drop the ASCII art entirely */
  @media (max-height: 720px) {
    pre.ascii { display:none; }
    .version { margin-bottom:14px; }
  }
  /* Very short viewports — also drop the brand line and shrink the panel */
  @media (max-height: 560px) {
    .brand, .footer { display:none; }
    .stat-value { font-size:18px; }
    .stat-value .sub { font-size:11px; }
    .stat { padding:8px 12px; }
    .stat-label { margin-bottom:4px; }
    .panel { padding:10px 14px; margin-bottom:8px; }
    .header-row { margin-bottom:8px; }
    .stats { margin-bottom:10px; }
    .bar-label { margin-bottom:10px; }
  }
  /* Crunch mode — under 440px tall (rare, but possible on iframes/popups) */
  @media (max-height: 440px) {
    .panel, .ladder { display:none; }   /* hide phase ladder + nodes panel */
    .stats { display:none; }            /* hide stat tiles */
    .version { display:none; }
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
      <span></span>
      <span id="pct-text">0%</span>
    </div>

    <div class="stats">
      <div class="stat">
        <div class="stat-label">Nodes</div>
        <div class="stat-value"><span id="nodes-done">0</span><span class="sub">/<span id="nodes-total">28</span></span></div>
        <div class="stat-hint">installed</div>
      </div>
      <div class="stat">
        <div class="stat-label">Models</div>
        <div class="stat-value"><span id="models-done">0</span><span class="sub">/<span id="models-total">49</span></span></div>
        <div class="stat-hint">synced</div>
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
        <div class="rung future" data-phase="INIT"><span class="code">1</span>Initializing</div>
        <div class="rung future" data-phase="B"><span class="code">2</span>Nodes</div>
        <div class="rung future" data-phase="C"><span class="code">3</span>Models</div>
        <div class="rung future" data-phase="D"><span class="code">4</span>Deploy</div>
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
  const PHASE_ORDER = ["INIT","B","C","D"];
  function mapPhase(internal) {
    if (internal === "A") return "INIT";
    if (internal === "B") return "B";
    if (internal === "C") return "C";
    if (internal === "D" || internal === "E" || internal === "F") return "D";
    return "INIT";
  }
  function setPhase(active) {
    const uiPhase = mapPhase(active);
    const idx = PHASE_ORDER.indexOf(uiPhase);
    document.querySelectorAll(".rung").forEach(r => {
      const p = r.getAttribute("data-phase");
      const pidx = PHASE_ORDER.indexOf(p);
      r.classList.remove("future","done","active");
      if (pidx < idx) r.classList.add("done");
      else if (pidx === idx) r.classList.add("active");
      else r.classList.add("future");
    });
  }

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
      // Each node call emits a line like "  [ok] X (1/28) ..." or "  [+] X (3/28) cloning..."
      // We capture BOTH the current index and the total — the total varies between releases
      // (currently 28, was 27 previously). Don't hardcode it.
      let lastNodeIdx = 0;
      let nodesTotal = 0;
      for (const l of lines) {
        const m = l.match(/\((\d+)\/(\d+)\)/);
        if (m) {
          const idx = parseInt(m[1]);
          const tot = parseInt(m[2]);
          // Only trust matches that look like node-install pace (total roughly 20-50, not e.g. download bytes)
          if (tot >= 10 && tot <= 100) {
            lastNodeIdx = Math.max(lastNodeIdx, idx);
            nodesTotal = Math.max(nodesTotal, tot);
          }
        }
      }
      state.nodesDone = lastNodeIdx;
      document.getElementById("nodes-done").textContent = lastNodeIdx;
      // Update the /N denominator if we learned the real total from the log
      if (nodesTotal > 0) {
        const denomEl = document.getElementById("nodes-total");
        if (denomEl) denomEl.textContent = nodesTotal;
      }

      // ── Model tracking ──
      let modelsTotal = TOTAL_MODELS;
      for (const l of lines) {
        const m = l.match(/Found\s+(\d+)\s+models/);
        if (m) modelsTotal = parseInt(m[1]);
      }
      document.getElementById("models-total").textContent = modelsTotal;

      // Walk the log in order to reconstruct state
      let successes = 0, failures = 0, currentLabel = null;
      for (const l of lines) {
        const startM = l.match(/\[STARTING\]\s*'([^']+)'/);
        if (startM) currentLabel = startM[1];
        if (l.includes("[SUCCESS]") && currentLabel) {
          successes++;
          currentLabel = null;
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
      }

      // Current file + speed
      if (currentLabel) {
        document.getElementById("current-file").textContent = "\u25b8 " + currentLabel;
        const nowTs = Date.now();
        if (state.lastModelTs && state.lastModelLabel !== currentLabel) {
          const dt = (nowTs - state.lastModelTs) / 1000;
          const mbps = 512 / Math.max(dt, 2);
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

      // ── ETA — bytes-based projection ──
      // Strategy: from the log we know per-model declared size ("[dl] N bytes").
      // We sum total bytes of the manifest, sum bytes of completed models, and
      // project remaining time using the observed download rate.
      // Falls back to pct-based extrapolation early in the run when we have no rate signal.
      try {
        // Per-model declared sizes — match "  [dl] 12309866400 bytes"
        const sizesByOrder = [];
        for (const l of lines) {
          const m = l.match(/\[dl\]\s+(\d+)\s+bytes/);
          if (m) sizesByOrder.push(parseInt(m[1]));
        }
        // Walk in order: bytes_done = sum of sizes of models that hit [SUCCESS]
        let bytesDone = 0, bytesTotal = 0, nextSizeIdx = 0, currentBytes = 0;
        for (const l of lines) {
          if (l.match(/\[STARTING\]/)) {
            // The next [dl] line gives us this model's size
            // (we resolve it lazily below by reading the next "[dl]" after this STARTING)
          }
          const dl = l.match(/\[dl\]\s+(\d+)\s+bytes/);
          if (dl) {
            currentBytes = parseInt(dl[1]);
            bytesTotal += currentBytes;
          }
          if (l.includes("[SUCCESS]")) {
            bytesDone += currentBytes;
            currentBytes = 0;
          }
          if (/^\[FAILED\]/.test(l)) {
            // Treat failed as "won't be retried" — count as done so ETA doesn't stall on it
            bytesDone += currentBytes;
            currentBytes = 0;
          }
        }

        // Rate: bytes per second. Prefer observed (recentBytesPerSec is in MB/s).
        let bps = (state.recentBytesPerSec || 0) * 1024 * 1024;

        // If we don't have a rate signal yet but we've completed models, derive it from elapsed
        if (bps <= 0 && bytesDone > 0 && state.firstDownloadTs) {
          const dlElapsed = Math.max(1, (Date.now() - state.firstDownloadTs) / 1000);
          bps = bytesDone / dlElapsed;
        }
        if (state.firstDownloadTs == null && bytesDone > 0) {
          state.firstDownloadTs = Date.now();
        }

        const bytesRemaining = Math.max(0, bytesTotal - bytesDone);
        let etaSec = null;

        // Primary: bytes-based projection using observed throughput
        if (bps > 1024 * 1024 && bytesTotal > 0 && bytesRemaining > 0) {
          etaSec = bytesRemaining / bps;
          etaSec += 30;  // tail for Phase D (deploy + lockdown + finalize)
        }

        if (etaSec == null && state.pct > 5 && state.pct < 98) {
          // Fallback: pct-based extrapolation. Prefer install start time from
          // the log itself ([OFM-INNER] Starting at <ISO>) so a page-reload
          // mid-run doesn't reset the elapsed clock.
          let installStartMs = null;
          for (const l of lines) {
            const m = l.match(/Starting at\s+(\S+)/);
            if (m) { const t = Date.parse(m[1]); if (!isNaN(t)) installStartMs = t; break; }
          }
          const elapsed = ((Date.now() - (installStartMs || startTs))) / 1000;
          if (elapsed > 30) {  // need at least 30s to make a sensible projection
            const totalEst = elapsed * (100 / state.pct);
            etaSec = Math.max(0, totalEst - elapsed);
          }
        }

        if (etaSec != null && etaSec >= 0) {
          // Smooth — average against previous reading to prevent jitter
          if (state.lastEtaSec != null) {
            etaSec = state.lastEtaSec * 0.7 + etaSec * 0.3;
          }
          state.lastEtaSec = etaSec;

          let label;
          if (etaSec < 60)        label = "<1<span class=\"sub\"> min</span>";
          else if (etaSec < 3600) label = "~" + Math.ceil(etaSec / 60) + '<span class="sub"> min</span>';
          else                    label = (etaSec / 3600).toFixed(1) + '<span class="sub"> hrs</span>';
          document.getElementById("eta").innerHTML = label;
        }
      } catch (e) { /* ETA is best-effort, never break the UI */ }

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
          if (l.includes("UI Lockdown") || l.match(/Phase F/) || l.match(/Phase E/)) { statusEl.textContent = "Finalizing deployment \u00b7 Phase D"; break; }
          else if (l.includes("Deploy workflow") || l.match(/Phase D/)) { statusEl.textContent = "Deploying workflows \u00b7 Phase D"; break; }
          else if (l.match(/Phase C/) || l.includes("Found") && l.includes("models")) { statusEl.textContent = "Downloading model weights \u00b7 Phase C"; break; }
          else if (l.match(/Phase B/) || l.includes("install_node")) { statusEl.textContent = "Installing custom nodes \u00b7 Phase B"; break; }
          else if (l.match(/Phase A/)) { statusEl.textContent = "Initializing \u00b7 Phase INIT"; break; }
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

    # ── Capture public IP for token-IP binding (anti-leak protection) ──
    local PUBLIC_IP
    PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null \
        || curl -s --max-time 5 https://ifconfig.me 2>/dev/null \
        || curl -s --max-time 5 https://icanhazip.com 2>/dev/null \
        || echo "0.0.0.0")
    PUBLIC_IP=$(printf '%s' "$PUBLIC_IP" | tr -d '[:space:]' | head -c 45)
    echo "[OFM] Public IP captured (len=${#PUBLIC_IP})"
    export OFMPATH_PUBLIC_IP="$PUBLIC_IP"

    echo "[OFM] Calling get_payload_secret RPC (with IP binding)..."
    local SECRET_RESPONSE
    SECRET_RESPONSE=$(curl -s --max-time 15 -X POST \
        "${OFMPATH_SUPA_URL}/rest/v1/rpc/get_payload_secret" \
        -H "apikey: ${OFMPATH_SUPA_KEY}" \
        -H "Authorization: Bearer ${OFMPATH_SUPA_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"p_token\":\"${OFMPATH_TOKEN}\",\"p_ip\":\"${PUBLIC_IP}\"}" 2>/dev/null)
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
        _show_error_page "ACCESS DENIED<br><br>Token validation failed.<br>Possible causes: subscription inactive, token revoked, or anti-leak protection triggered (token already bound to a different IP)."
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
    echo "[OFM] Installing persistent UI Lockdown watcher..."

    # Optional branding (set via env vars in your Vast.ai template if you host your own).
    export OFMPATH_LOGO_URL="${OFMPATH_LOGO_URL:-}"
    export OFMPATH_BG_URL="${OFMPATH_BG_URL:-}"

    # ── Write the watcher script to /usr/local/bin ──
    # This script keeps re-patching on a loop. Why a loop:
    # • At provisioning time, comfyui_frontend_package may not be installed yet
    #   (ComfyUI fetches it on first launch via uv).
    # • ComfyUI startup runs `uv sync` which can REINSTALL the frontend wheel,
    #   wiping any earlier patch.
    # • The watcher catches both cases — runs every N seconds, re-injects if the
    #   marker is missing.
    cat > /usr/local/bin/ofmpath_lockdown.py << 'WATCHER_EOF'
#!/usr/bin/env python3
"""OFMPATH UI lockdown watcher — keeps comfyui_frontend_package and
ComfyUI/web index.html patched even after pip/uv reinstalls the wheel."""
import os
import site
import sys
import time

LOGO_URL    = os.environ.get("OFMPATH_LOGO_URL", "") or ""
BG_URL      = os.environ.get("OFMPATH_BG_URL",   "") or ""
COMFYUI_DIR = os.environ.get("COMFYUI_DIR", "/workspace/ComfyUI")
INTERVAL    = int(os.environ.get("OFMPATH_WATCHER_INTERVAL", "10"))
MARKER      = "OFMPATH NATIVE UI TWEAKS"

BOOT = (
    '<script data-id="OFMPATH-BOOT">'
    'document.addEventListener("contextmenu",function(e){'
        'var t=e.target;if(t&&t.tagName!=="CANVAS"){e.preventDefault();e.stopImmediatePropagation()}'
    '},true);'
    'setInterval(function(){var t=performance.now();debugger;'
        'if(performance.now()-t>100){document.body.innerHTML="";'
        'window.location.href="about:blank";setTimeout(function(){window.close()},10);}'
    '},500);'
    '</script>'
)

# Build patch_code with simple .format() — no f-string brace headaches
# Note: CSS/JS literal braces stay as { }, only {LOGO_URL} and {BG_URL} are placeholders.
PATCH_TEMPLATE = """
<!-- OFMPATH NATIVE UI TWEAKS -->
<style data-id="OFMPATH-NUKE">
  body.ofmpath-bg, #app.ofmpath-bg, .comfy-app-main.ofmpath-bg, .graph-canvas-container.ofmpath-bg {
      background-image: url("__BG_URL__") !important;
      background-size: cover !important;
      background-position: center !important;
      background-attachment: fixed !important;
  }
  canvas.litegraph, canvas.lgraphcanvas { opacity: 0.92 !important; }

  .comfy-logo, .comfyui-logo, svg[class*="comfyui-logo"],
  [aria-label="Menu"], [data-pr-tooltip="Menu"],
  [data-pc-section="menuicon"] { display: none !important; }

  .p-sidebar-right, .p-dialog-right,
  [data-pc-name="sidebar"][class*="right"],
  .lite-searchbox, .comfyui-node-search, [class*="node-search"] { display: none !important; }

  #cm-manager-btn,
  button[id*="manager" i],
  [data-pr-tooltip*="Manager" i],
  [title*="Manager" i],
  [aria-label*="Manager" i] { display: none !important; }

  /* Top-toolbar dangerous icon buttons — Unload Models / Free Cache / Share */
  button[aria-label*="Unload" i],
  button[aria-label*="Free Models" i],
  button[aria-label*="Free Model" i],
  button[aria-label*="Free Cache" i],
  button[aria-label*="Free Memory" i],
  button[aria-label*="Free model and node cache" i],
  button[aria-label*="Free node cache" i],
  button[aria-label*="Share" i],
  button[data-pr-tooltip*="Unload" i],
  button[data-pr-tooltip*="Free Models" i],
  button[data-pr-tooltip*="Free Model" i],
  button[data-pr-tooltip*="Free Cache" i],
  button[data-pr-tooltip*="Free Memory" i],
  button[data-pr-tooltip*="Share" i],
  button[title*="Unload" i],
  button[title*="Free Models" i],
  button[title*="Free Model" i],
  button[title*="Free Cache" i],
  button[title*="Free Memory" i],
  button[title*="Share" i] { display: none !important; visibility: hidden !important; }

  .crystools-root, .crystools-monitors-container,
  [class*="crystools"], [id*="crystools"] { display: none !important; visibility: hidden !important; }

  .pysssss-image-feed,
  button[title*="Image Feed"],
  button[aria-label*="Image Feed"] { display: none !important; }

  /* Left-rail sidebar nav buttons — Model Library / Node Library / Templates / Bookmarks / Apps / Workflows-list */
  .side-tool-bar-container button[aria-label*="model" i],
  .side-tool-bar-container button[aria-label*="node library" i],
  .side-tool-bar-container button[aria-label*="nodes" i]:not([aria-label*="workflow" i]),
  .side-tool-bar-container button[aria-label*="template" i],
  .side-tool-bar-container button[aria-label*="bookmark" i],
  .side-tool-bar-container button[aria-label*="apps" i],
  .side-tool-bar-container button[aria-label*="queue" i],
  .side-tool-bar-container button[data-pc-name="model-library"],
  .side-tool-bar-container button[data-pc-name="node-library"],
  .side-tool-bar-container button[data-pc-name="bookmarks"],
  .side-tool-bar-container button[data-pc-name="templates"],
  .side-tool-bar-container button[data-pc-name="apps"],
  .comfyui-side-bar button[aria-label*="model" i],
  .comfyui-side-bar button[aria-label*="node library" i],
  .comfyui-side-bar button[aria-label*="template" i],
  .comfyui-side-bar button[aria-label*="bookmark" i],
  .comfyui-side-bar button[aria-label*="apps" i],
  .comfyui-side-bar button[data-pc-name="model-library"],
  .comfyui-side-bar button[data-pc-name="node-library"],
  .comfyui-side-bar button[data-pc-name="bookmarks"],
  .comfyui-side-bar button[data-pc-name="templates"],
  .comfyui-side-bar button[data-pc-name="apps"],
  [class*='side-bar'] button[aria-label*="model" i],
  [class*='side-bar'] button[aria-label*="node library" i],
  [class*='side-bar'] button[aria-label*="template" i],
  [class*='side-bar'] button[aria-label*="bookmark" i] { display: none !important; visibility: hidden !important; }

  /* Sidebar panels themselves — Model Library, Node Library content panes */
  [class*="model-library"],
  [class*="node-library"],
  [class*="ModelLibrary"],
  [class*="NodeLibrary"],
  [data-pc-name="model-library"],
  [data-pc-name="node-library"],
  [data-pc-name="templates"],
  [data-pc-name="bookmarks"],
  [data-pc-name="apps"] { display: none !important; }

  /* Graph-dropdown / popover items — Save / Save As / Export / Export (API) / Rename / Duplicate / Delete / Add to Bookmarks */
  /* These render as <li> or <div> inside .p-popover or .p-overlaypanel — we use :is() with attribute matching */
  .p-popover [aria-label="Rename" i],
  .p-popover [aria-label="Duplicate" i],
  .p-popover [aria-label="Add to Bookmarks" i],
  .p-popover [aria-label="Save" i],
  .p-popover [aria-label="Save As" i],
  .p-popover [aria-label="Export" i],
  .p-popover [aria-label*="Export" i],
  .p-popover [aria-label="Clear Workflow" i],
  .p-popover [aria-label="Delete Workflow" i],
  .p-overlaypanel [aria-label="Rename" i],
  .p-overlaypanel [aria-label="Duplicate" i],
  .p-overlaypanel [aria-label="Add to Bookmarks" i],
  .p-overlaypanel [aria-label="Save" i],
  .p-overlaypanel [aria-label="Save As" i],
  .p-overlaypanel [aria-label*="Export" i],
  .p-overlaypanel [aria-label="Clear Workflow" i],
  .p-overlaypanel [aria-label="Delete Workflow" i] { display: none !important; }
</style>

<script data-id="OFMPATH-NUKE-JS">
  // 1. Block double-click on canvas (kills LiteGraph node-search popup)
  window.addEventListener("dblclick", function(e) {
      if ((e.target.tagName && e.target.tagName.toLowerCase() === "canvas") || (e.target.closest && e.target.closest("canvas"))) {
          e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
      }
  }, true);

  // 2. Block devtools + save/export/clipboard hotkeys
  window.addEventListener("keydown", function(e) {
    if (e.key === "F12") { e.preventDefault(); e.stopPropagation(); }
    if (e.ctrlKey && e.shiftKey && ["I","J","C","i","j","c"].indexOf(e.key) !== -1) { e.preventDefault(); e.stopPropagation(); }
    if (e.ctrlKey && ["u","U","s","S","c","C","v","V","p","P","a","A","o","O","e","E"].indexOf(e.key) !== -1) { e.preventDefault(); e.stopPropagation(); }
  }, true);

  // 3. Surgical menu-item killer (top bar, sidebar, right-click context menus, popover dropdowns)
  // NOTE: no "workflow" whitelist — we explicitly kill Save/Export/Clear/Delete Workflow
  // because those are workflow-exfiltration vectors.
  var killWords = [
      // Top-bar dropdown items (Graph dropdown, etc.)
      "rename", "duplicate", "add to bookmarks",
      "save", "save as", "save workflow",
      "export", "export (api)", "export workflow", "export api",
      "download", "load", "load default", "import",
      "clear workflow", "delete workflow", "delete",
      // Sidebar tabs (Model Library, Nodes, etc.)
      "model library", "node library", "nodes library",
      "model browser", "node browser",
      "models", "nodes", "assets", "templates", "node map", "nodesmap",
      "blueprints", "subgraph blueprints", "partner nodes", "comfy nodes",
      // Top-bar dangerous buttons
      "manager", "workspace manager", "comfyui manager",
      "experiments", "share",
      "unload models", "unload model",
      "free models", "free model and node cache", "free model", "free node cache",
      "free memory", "free models and node cache",
      "menu",
      // Right-click on node/canvas
      "properties", "properties panel",
      "add node", "convert to subgraph", "convert to group",
      "clone", "node help", "add ue broadcasting",
      // Right-click cosmetic / dangerous node options
      "title", "mode", "resize", "collapse",
      "pin", "unpin",
      "colors", "shapes",
      "copy (clipspace)", "copy clipspace",
      "remove",
      // Misc
      "help", "console", "settings", "translate"
  ];

  // Phrases that should NEVER hide an element (whitelist for false positives).
  // - "workflows" / "workflow library" — top-level user-facing
  // - "title bar" / "set title" — sometimes labels for KEEP items
  // - "remove from bookmarks" — would be hidden by "remove" otherwise (we want bookmarks ops working)
  // - reload/reject/etc — items the user explicitly wanted to keep
  var keepIfContains = [
    "workflow library", "workflows",
    "remove from bookmarks",
    "reload node", "reset",
    "bypass",                  // node-functional
    "swap width", "swap height",
    "fix node", "recreate",
    "reject ue links", "ue connectable",
    "add getnode", "add setnode", "add previewastextnode",
    "convert all outputs",
    "open in sam"
  ];

  // Containers to scan. Includes popovers/overlays (Graph dropdown), all sidebars, all menus.
  var menuSelectors = [
      "header", ".p-toolbar", "[class*='topbar']", "[class*='top-bar']",
      ".litecontextmenu", ".comfy-menu",
      ".p-menubar", ".p-menu", ".p-panelmenu", ".p-tieredmenu", ".p-contextmenu",
      ".p-popover", ".p-popover-content", ".p-overlaypanel", ".p-overlaypanel-content",
      ".p-sidebar", ".p-sidebar-content",
      ".side-tool-bar-container", ".comfyui-side-bar",
      "nav", "aside",
      "[class*='comfyui-menu']", "[class*='sidebar']",
      "[role='menu']", "[role='listbox']"
  ].join(", ");

  // ALL descendants worth checking inside a container.
  // Includes <div> and role-based selectors because ComfyUI's new nav uses those.
  var innerSelectors = "li, a, button, div, span, .p-menuitem, .litemenu-entry, .p-button, [role='menuitem'], [role='option'], [role='button'], [role='tab']";

  function shouldHide(blob) {
    for (var k = 0; k < keepIfContains.length; k++) {
      if (blob.indexOf(keepIfContains[k]) !== -1) return false;
    }
    for (var i = 0; i < killWords.length; i++) {
      var w = killWords[i];
      // Match if blob equals word, or contains word as a "token" (surrounded by spaces/start/end)
      if (blob === w) return true;
      var idx = blob.indexOf(w);
      if (idx === -1) continue;
      var before = idx === 0 ? " " : blob.charAt(idx - 1);
      var after  = idx + w.length >= blob.length ? " " : blob.charAt(idx + w.length);
      if (/[\s\(\)\[\]\.,;:|\/]/.test(before) && /[\s\(\)\[\]\.,;:|\/]/.test(after)) return true;
      // Also match short whole-string buttons where the entire text IS the kill word
      if (blob.trim() === w) return true;
    }
    return false;
  }

  function elementBlob(el) {
    return [
      (el.getAttribute && el.getAttribute("aria-label")) || "",
      (el.getAttribute && el.getAttribute("title")) || "",
      (el.getAttribute && el.getAttribute("data-pr-tooltip")) || "",
      (el.getAttribute && el.getAttribute("data-pc-name")) || "",
      (el.getAttribute && el.getAttribute("id")) || "",
      el.innerText || el.textContent || ""
    ].join(" ").trim().toLowerCase();
  }

  function hideAndAncestor(el) {
    // Hide the element itself
    el.style.display = "none";
    // ALSO hide its closest <li>, role=menuitem, or role=option — sometimes the
    // visible row is a parent wrapper, not the element with the text.
    var parent = el.closest && (el.closest("li") || el.closest("[role='menuitem']") || el.closest("[role='option']") || el.closest(".p-menuitem"));
    if (parent && parent !== el) parent.style.display = "none";
  }

  function tick() {
    try {
      // Pass 1: scan inside known menu containers
      document.querySelectorAll(menuSelectors).forEach(function(container) {
        container.querySelectorAll(innerSelectors).forEach(function(el) {
          // Skip elements that are themselves containers of MANY children (avoid nuking entire panels here)
          if (el.children && el.children.length > 8) return;
          var blob = elementBlob(el);
          if (!blob) return;
          if (shouldHide(blob)) hideAndAncestor(el);
        });
      });

      // Pass 2: kill entire sidebar panels (Model Library, Nodes browser) — these
      // render as <aside>/<div> with a header containing the panel name.
      document.querySelectorAll("aside, [class*='sidebar'], .p-sidebar, [class*='side-bar'], [data-pc-name='sidebar']").forEach(function(panel) {
        // Find a header/title element inside the panel
        var headers = panel.querySelectorAll("h1, h2, h3, h4, [class*='title'], [class*='header']");
        for (var h = 0; h < headers.length; h++) {
          var blob = (headers[h].innerText || headers[h].textContent || "").trim().toLowerCase();
          if (blob === "nodes" || blob === "model library" || blob === "node library" ||
              blob === "models" || blob === "models library" || blob === "nodes library" ||
              blob === "templates" || blob === "node map" || blob === "bookmarks" || blob === "manager") {
            panel.style.display = "none";
            break;
          }
        }
      });

      // Pass 3: kill sidebar nav rail buttons (the icons that open Nodes/Models/etc panels).
      // These live in .side-tool-bar-container or [class*='side-bar'] as buttons.
      document.querySelectorAll(".side-tool-bar-container button, .comfyui-side-bar button, [class*='side-bar'] button, [class*='sidebar'] button").forEach(function(btn) {
        var blob = elementBlob(btn);
        if (shouldHide(blob)) hideAndAncestor(btn);
      });

      // Pass 4: global fallback — any button/link with manager/crystools text anywhere
      document.querySelectorAll("button, a").forEach(function(el) {
        var blob = elementBlob(el);
        if (blob.indexOf("manager") !== -1 || blob.indexOf("crystools") !== -1) {
          hideAndAncestor(el);
        }
      });
    } catch (e) {}
  }

  function startObserver() {
    if (!document.body) { setTimeout(startObserver, 50); return; }
    tick();
    new MutationObserver(tick).observe(document.body, {
      childList: true, subtree: true, characterData: true,
      attributes: true,
      attributeFilter: ["data-pr-tooltip", "aria-label", "title", "id", "class"]
    });

    // Optional logo
    var LOGO = "__LOGO_URL__";
    if (LOGO && LOGO.length > 0) {
      var logo = document.createElement("img");
      logo.src = LOGO;
      logo.style.cssText = "position: fixed; top: 15px; right: 30px; height: 50px; z-index: 10000; pointer-events: none; filter: drop-shadow(0px 4px 6px rgba(0,0,0,0.5));";
      document.body.appendChild(logo);
    }
    var BG = "__BG_URL__";
    if (BG && BG.length > 0) {
      document.body.classList.add("ofmpath-bg");
      var app = document.getElementById("app");
      if (app) app.classList.add("ofmpath-bg");
    }
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", startObserver);
  } else {
    startObserver();
  }

  // 4. Override LiteGraph search box from inside the engine
  var ofmpathLG = setInterval(function() {
    if (window.LiteGraph && window.LGraphCanvas) {
      window.LGraphCanvas.prototype.showSearchBox = function() { return false; };
      window.LiteGraph.search_hide_on_mouse_leave = true;
      clearInterval(ofmpathLG);
    }
  }, 500);
</script>
<!-- /OFMPATH NATIVE UI TWEAKS -->
"""


def discover_targets():
    """Find every plausible frontend index.html on disk, RIGHT NOW."""
    candidates = []
    try:
        for sp in site.getsitepackages():
            candidates.append(os.path.join(sp, "comfyui_frontend_package", "static", "index.html"))
    except Exception:
        pass
    try:
        candidates.append(os.path.join(site.getusersitepackages(), "comfyui_frontend_package", "static", "index.html"))
    except Exception:
        pass
    # /venv/main is where Vast's vast-pytorch image puts the comfy venv
    for venv in ("/venv/main", "/opt/venv", "/usr"):
        for py in ("python3.10", "python3.11", "python3.12", "python3.13"):
            candidates.append(os.path.join(venv, "lib", py, "site-packages", "comfyui_frontend_package", "static", "index.html"))
    candidates.append(os.path.join(COMFYUI_DIR, "web", "index.html"))

    seen, targets = set(), []
    for p in candidates:
        if p and p not in seen and os.path.isfile(p):
            seen.add(p); targets.append(p)
    return targets


def patch(path):
    """Patch a single index.html. Returns True if it was patched, False if already patched or failed."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        if MARKER in content:
            return False  # already patched

        patch_code = (PATCH_TEMPLATE
                      .replace("__BG_URL__",   BG_URL)
                      .replace("__LOGO_URL__", LOGO_URL))

        if "</head>" in content:
            new_content = content.replace("</head>", BOOT + patch_code + "\n</head>", 1)
        elif "<head>" in content:
            new_content = content.replace("<head>", "<head>" + BOOT + patch_code, 1)
        else:
            new_content = BOOT + patch_code + content

        with open(path, "w", encoding="utf-8") as f:
            f.write(new_content)
        return True
    except Exception as e:
        sys.stderr.write("[OFMPATH-LOCKDOWN] failed to patch {}: {}\n".format(path, e))
        return False


def run_once():
    targets = discover_targets()
    if not targets:
        return 0, 0
    patched = 0
    for t in targets:
        if patch(t):
            print("[OFMPATH-LOCKDOWN] patched: {}".format(t), flush=True)
            patched += 1
    return patched, len(targets)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "watch"
    if mode == "once":
        patched, total = run_once()
        print("[OFMPATH-LOCKDOWN] one-shot: patched={} of {} files found".format(patched, total))
        return 0
    # watch mode (default)
    print("[OFMPATH-LOCKDOWN] watcher started (interval={}s)".format(INTERVAL), flush=True)
    while True:
        try:
            run_once()
        except Exception as e:
            sys.stderr.write("[OFMPATH-LOCKDOWN] tick error: {}\n".format(e))
        time.sleep(INTERVAL)


if __name__ == "__main__":
    sys.exit(main())
WATCHER_EOF
    chmod +x /usr/local/bin/ofmpath_lockdown.py
    echo "[OFM] ✓ Watcher script written to /usr/local/bin/ofmpath_lockdown.py"

    # ── Install as supervisor service ──
    cat > /etc/supervisor/conf.d/ofmpath_lockdown.conf << SUPV_EOF
[program:ofmpath_lockdown]
command=/usr/bin/env python3 /usr/local/bin/ofmpath_lockdown.py watch
autostart=true
autorestart=true
startretries=999
stdout_logfile=/workspace/ofmpath_lockdown.log
stderr_logfile=/workspace/ofmpath_lockdown.log
stdout_logfile_maxbytes=2MB
environment=OFMPATH_LOGO_URL="${OFMPATH_LOGO_URL}",OFMPATH_BG_URL="${OFMPATH_BG_URL}",COMFYUI_DIR="${COMFYUI_DIR}",OFMPATH_WATCHER_INTERVAL="10"
SUPV_EOF
    echo "[OFM] ✓ Supervisor service registered: ofmpath_lockdown"

    # ── Run once synchronously now (will be a no-op if frontend not installed yet — watcher handles that) ──
    OFMPATH_LOGO_URL="$OFMPATH_LOGO_URL" OFMPATH_BG_URL="$OFMPATH_BG_URL" COMFYUI_DIR="$COMFYUI_DIR" \
        python3 /usr/local/bin/ofmpath_lockdown.py once || true

    # ── Reload supervisor so the watcher actually starts ──
    supervisorctl reread >/dev/null 2>&1 || true
    supervisorctl update  >/dev/null 2>&1 || true
    supervisorctl start ofmpath_lockdown >/dev/null 2>&1 || true

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
    echo "[OFM] ✓ UI Lockdown complete (watcher running in background)"
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
