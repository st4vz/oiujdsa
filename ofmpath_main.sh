#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
#  OFM PATH 智慧通路 — Provisioning Bootstrap
#  Runs on Vast.ai as PROVISIONING_SCRIPT  ·  Public script (no secrets here)
#
#  Flow:
#  1.  Start OFM PATH preloader (snake game) on port 8188
#  2.  Install system dependencies (aria2, exiftool, psmisc)
#  3.  Validate OFMPATH_TOKEN against Supabase
#  4.  Wait for ai-dock ComfyUI base install to finish
#  5.  Stop ai-dock's ComfyUI supervisor
#  6.  Fetch + decrypt ofmpath_install.sh.enc from Supabase bucket
#  7.  Run inner installer (nodes, models, workflows, settings)
#  8.  Apply UI lockdown (anti-theft)
#  9.  Restart ComfyUI on port 8188 → browser auto-handoff from preloader
# ═══════════════════════════════════════════════════════════════════════════

# NOTE: no `set -e` — each phase handles its own errors so the preloader
# never gets orphaned on a silent exit.

# ── Supabase endpoints (public anon key, rate-limited via RLS) ──
export OFMPATH_SUPA_URL="https://yvjhjptycwlnjnzzsyju.supabase.co"
export OFMPATH_SUPA_KEY="sb_publishable_RW1gbkXD6roZeUCxfEpQGg_cZ1z7brK"
export OFMPATH_BUCKET="ofm-path"

# ── Constants ──
WORKSPACE="/workspace"
COMFYUI_DIR="$WORKSPACE/ComfyUI"
CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"

# ── Logging (browser polls this via /install.log) ──
mkdir -p /tmp/ofmpath_loading
LOG_FILE="/tmp/ofmpath_loading/install.log"
echo "[OFM] OFM PATH 智慧通路 initialization started at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$LOG_FILE"
exec > >(stdbuf -oL tee -a "$LOG_FILE") 2>&1


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 1 — PRELOADER (CRT/scanline aesthetic + snake game)
# ═══════════════════════════════════════════════════════════════════════════
_start_preloader() {
    echo "[OFM] Starting preloader UX..."

    cat > /tmp/ofmpath_loading/index.html << 'PRELOADER_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>OFM PATH — Initializing...</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&family=Outfit:wght@300;400;500;600&display=swap');
  * { margin:0; padding:0; box-sizing:border-box; }
  html,body { height:100%; overflow:hidden; }
  body {
    background:#0a0a0f; color:#00ff88;
    font-family:'JetBrains Mono','Courier New',monospace;
    display:flex; justify-content:center; align-items:center;
    min-height:100vh; position:relative;
  }
  /* CRT scanlines */
  body::before {
    content:''; position:fixed; inset:0; pointer-events:none; z-index:2;
    background:repeating-linear-gradient(0deg,rgba(0,0,0,.18) 0,rgba(0,0,0,.18) 1px,transparent 1px,transparent 3px);
  }
  /* Soft ambient glow */
  body::after {
    content:''; position:fixed; inset:0; pointer-events:none; z-index:1;
    background:radial-gradient(ellipse at 50% 50%, rgba(0,255,136,0.05) 0%, transparent 60%);
  }
  .wrap {
    position:relative; z-index:10; max-width:640px; width:92%;
    padding:36px 40px; background:rgba(10,12,16,0.75);
    border:1px solid rgba(0,255,136,0.22); border-radius:4px;
    backdrop-filter:blur(8px); text-align:center;
    box-shadow:0 0 60px rgba(0,255,136,0.08), inset 0 0 0 1px rgba(0,255,136,0.08);
    animation:slideUp 0.8s cubic-bezier(0.16, 1, 0.3, 1) both;
  }
  @keyframes slideUp { from { opacity:0; transform:translateY(16px);} to { opacity:1; transform:translateY(0);} }
  .brand { font-size:11px; letter-spacing:4px; color:#00ff88; opacity:.55; margin-bottom:6px; }
  pre.ascii {
    font-size:11px; line-height:1.2; color:#00ff88;
    text-shadow:0 0 10px rgba(0,255,136,.6); margin:0 0 20px; white-space:pre;
    font-family:'JetBrains Mono','Courier New',monospace;
  }
  .version { font-size:10px; color:#00ff88; opacity:.5; letter-spacing:3px; margin-bottom:24px; text-transform:uppercase; }
  .status-badge {
    display:inline-flex; align-items:center; gap:10px;
    padding:7px 18px; background:rgba(0,255,136,0.06);
    border:1px solid rgba(0,255,136,0.25); border-radius:3px;
    font-size:12px; color:#88ffcc; margin-bottom:18px; letter-spacing:0.5px;
  }
  .dot { width:8px; height:8px; border-radius:50%; background:#00ff88; animation:dotPulse 1.3s infinite; box-shadow:0 0 8px #00ff88; }
  @keyframes dotPulse { 0%,100% { transform:scale(.8); opacity:.6;} 50% { transform:scale(1.25); opacity:1;} }
  .bar-track {
    width:100%; height:5px; background:rgba(0,255,136,0.08);
    border-radius:2px; overflow:hidden; margin-bottom:10px;
    box-shadow:inset 0 0 0 1px rgba(0,255,136,0.15);
  }
  .bar-fill {
    height:100%; width:0%;
    background:linear-gradient(90deg,#00ff88,#00ccff);
    transition:width .6s cubic-bezier(0.2,0.8,0.2,1);
    box-shadow:0 0 12px #00ff88;
  }
  .status-line {
    font-size:11px; color:#4a8a6a; min-height:16px; margin-bottom:24px;
    font-family:'JetBrains Mono',monospace; letter-spacing:0.3px;
  }
  /* Snake game container */
  .game {
    margin-bottom:16px; border-radius:3px; overflow:hidden;
    background:rgba(0,0,0,0.4); border:1px solid rgba(0,255,136,0.2);
    padding:14px; text-align:center;
  }
  #snake {
    background:#030308; border-radius:2px;
    border:1px solid rgba(0,255,136,0.15);
    display:block; margin:0 auto; image-rendering:pixelated;
  }
  #snake-score {
    font-size:11px; color:#00ff88; font-weight:600;
    margin-top:8px; letter-spacing:1px;
  }
  .game-hint { font-size:9px; color:rgba(0,255,136,0.35); margin-top:4px; letter-spacing:2px; text-transform:uppercase; }
  /* Model tracker */
  .tracker {
    width:100%; background:rgba(0,255,136,0.03);
    border:1px dashed rgba(0,255,136,0.3); border-radius:3px;
    padding:14px; display:flex; flex-direction:column; gap:10px;
    margin-bottom:6px;
  }
  .tracker-header {
    font-size:11px; color:#88ffcc; letter-spacing:0.5px;
    display:flex; justify-content:space-between;
  }
  .blocks {
    display:flex; flex-wrap:wrap; gap:4px; justify-content:flex-start;
  }
  .block {
    width:14px; height:14px; border-radius:2px;
    background:rgba(0,255,136,0.06);
    border:1px solid rgba(0,255,136,0.2); transition:all 0.3s;
    position:relative; overflow:hidden;
  }
  .block.filled {
    background:#00ff88; border-color:#00ff88;
    box-shadow:0 0 6px rgba(0,255,136,0.5);
  }
  .block.loading::after {
    content:''; position:absolute; bottom:0; left:0; right:0; height:50%;
    background:rgba(0,255,136,0.4); animation:fill 1s infinite alternate;
  }
  @keyframes fill { 0% { height:10%;} 100% { height:90%;} }
  .current { font-size:10px; color:rgba(136,255,204,0.5); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .footer { font-size:10px; color:rgba(0,255,136,0.25); letter-spacing:3px; margin-top:12px; text-transform:uppercase; }
  /* Error state */
  .error-state .bar-fill { background:#ff4466 !important; box-shadow:0 0 12px #ff4466; }
  .error-state .status-badge { color:#ff4466; border-color:rgba(255,68,102,0.4); }
  .error-state .dot { background:#ff4466; box-shadow:0 0 8px #ff4466; }
  #refresh-prompt { display:none; margin-top:18px; }
  .btn {
    background:linear-gradient(135deg,#00ff88,#00ccff); color:#0a0a0f;
    border:none; padding:11px 30px; border-radius:3px;
    font-size:12px; font-weight:600; cursor:pointer; letter-spacing:2px;
    font-family:'JetBrains Mono',monospace; text-transform:uppercase;
    box-shadow:0 0 20px rgba(0,255,136,0.3); transition:all .15s;
  }
  .btn:hover { transform:translateY(-1px); box-shadow:0 0 30px rgba(0,255,136,0.5); }
</style>
</head>
<body>
  <div class="wrap" id="main">
    <div class="brand">OFM PATH 智慧通路</div>
    <pre class="ascii">
 ██████╗ ███████╗███╗   ███╗    ██████╗  █████╗ ████████╗██╗  ██╗
██╔═══██╗██╔════╝████╗ ████║    ██╔══██╗██╔══██╗╚══██╔══╝██║  ██║
██║   ██║█████╗  ██╔████╔██║    ██████╔╝███████║   ██║   ███████║
██║   ██║██╔══╝  ██║╚██╔╝██║    ██╔═══╝ ██╔══██║   ██║   ██╔══██║
╚██████╔╝██║     ██║ ╚═╝ ██║    ██║     ██║  ██║   ██║   ██║  ██║
 ╚═════╝ ╚═╝     ╚═╝     ╚═╝    ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝</pre>
    <div class="version">V1 · SZN VAULT</div>

    <div class="status-badge" id="status-badge">
      <span class="dot"></span>
      <span id="status-text">Initializing environment...</span>
    </div>

    <div class="bar-track"><div class="bar-fill" id="bar"></div></div>
    <div class="status-line" id="status-line">▸ Connecting to SZN VAULT servers...</div>

    <div class="game">
      <canvas id="snake" width="480" height="200"></canvas>
      <div id="snake-score">◈ 0</div>
      <div class="game-hint">← → ↑ ↓ to play · awaiting deployment</div>
    </div>

    <div class="tracker" id="tracker" style="display:none;">
      <div class="tracker-header">
        <span>⬡ Syncing weights: <span id="model-count">0 / 0</span></span>
        <span id="speed"></span>
      </div>
      <div class="blocks" id="blocks"></div>
      <div class="current" id="current">▸ Awaiting...</div>
    </div>

    <div id="refresh-prompt">
      <p style="color:#88ffcc; font-size:12px; margin-bottom:12px;">▸ Deployment complete</p>
      <button class="btn" onclick="location.reload()">Launch Interface</button>
    </div>

    <div class="footer">SECURE DEPLOYMENT · SZN VAULT</div>
  </div>

<script>
// ── Anti-inspection (soft) ──
document.addEventListener("contextmenu", e => e.preventDefault(), true);
document.addEventListener("keydown", e => {
  const k = e.key ? e.key.toLowerCase() : "";
  if (e.key === "F12" || (e.ctrlKey && e.shiftKey && "ijc".includes(k)) || (e.ctrlKey && k === "u")) {
    e.preventDefault();
  }
}, true);

// ── Model download tracker (reads from install.log) ──
let modelState = { total: 0, done: 0, rendered: 0, lastDone: 0 };

function parseModelProgress(text) {
  const lines = text.split("\n");
  let total = 0, done = 0, current = '';
  for (const l of lines) {
    const m = l.match(/Found\s+(\d+)\s+models/);
    if (m) total = parseInt(m[1]);
  }
  for (const l of lines) {
    if (l.includes('[SUCCESS]')) done++;
    const s = l.match(/\[STARTING\]\s*'([^']+)'/);
    if (s) current = s[1];
  }
  if (total === 0) return;
  const tracker = document.getElementById("tracker");
  tracker.style.display = "flex";
  if (modelState.rendered !== total) {
    const wrap = document.getElementById("blocks");
    wrap.innerHTML = '';
    for (let i = 0; i < total; i++) {
      const c = document.createElement("div");
      c.className = "block"; c.id = "c" + i;
      wrap.appendChild(c);
    }
    modelState.rendered = total;
  }
  for (let i = 0; i < total; i++) {
    const c = document.getElementById("c" + i);
    if (!c) continue;
    if (i < done) c.className = "block filled";
    else if (i === done) c.className = "block loading";
    else c.className = "block";
  }
  document.getElementById("model-count").textContent = done + " / " + total;
  if (current && done < total) {
    const hex = "0x" + Math.floor(Math.random()*0xFFFFFF).toString(16).toUpperCase().padStart(6,'0');
    document.getElementById("current").textContent = "▸ Syncing " + hex + "...";
    document.getElementById("speed").textContent = (Math.random() * 18 + 6).toFixed(1) + " MB/s";
  } else if (done >= total && total > 0) {
    document.getElementById("current").textContent = "▸ All weights synced ✓";
    document.getElementById("speed").textContent = "";
  }
  modelState.lastDone = done; modelState.total = total; modelState.done = done;
}

// ── Log poll + handoff ──
let handoffStarted = false;

setInterval(async () => {
  try {
    const r = await fetch("ready?t=" + Date.now());
    if (r.ok && (await r.text()).trim() === "READY" && !handoffStarted) {
      handoffStarted = true; startHandoff();
    }
  } catch (_) {}
}, 2000);

function startHandoff() {
  document.getElementById("bar").style.width = "100%";
  document.getElementById("status-text").textContent = "Starting ComfyUI...";
  document.getElementById("speed").textContent = "";
  const ping = setInterval(async () => {
    try {
      const r = await fetch("/?_t=" + Date.now(), { cache: "no-store" });
      if (r.ok) {
        const html = await r.text();
        if (html.includes("comfyui") || html.includes("litegraph") || html.length > 5000) {
          clearInterval(ping); location.reload();
        }
      }
    } catch (_) {}
  }, 1500);
  setTimeout(() => { document.getElementById("refresh-prompt").style.display = "block"; }, 20000);
}

async function poll() {
  try {
    const res = await fetch("install.log?t=" + Date.now());
    if (!res.ok) return;
    const text = await res.text();
    const bar = document.getElementById("bar");
    const status = document.getElementById("status-text");
    const line = document.getElementById("status-line");
    const lines = text.split("\n").filter(l => l.trim());

    // obfuscated status line
    if (lines.length) {
      let raw = lines[lines.length-1].substring(0, 80);
      if (raw.includes("READY") || raw.includes("FULLY OPERATIONAL")) {
        line.textContent = "▸ Finalizing deployment...";
      } else {
        const chars = "████▓▓▒▒░░0123456789ABCDEF";
        let obf = "";
        for (let k=0; k<Math.min(raw.length, 24); k++) obf += chars.charAt(Math.floor(Math.random()*chars.length));
        const hex = "0x" + Math.floor(Math.random()*0xFFFFFF).toString(16).toUpperCase().padStart(6, "0");
        line.textContent = "▸ [" + hex + "] " + obf + (raw.length > 24 ? "..." : "");
      }
    }

    // progress bar
    let pct = 0;
    for (let i = lines.length - 1; i >= 0; i--) {
      const m = lines[i].match(/\[PROGRESS:\s*(\d+)\]/);
      if (m) { pct = parseInt(m[1]); break; }
    }
    if (pct > 0) bar.style.width = pct + "%";

    parseModelProgress(text);

    // error detection
    if (text.includes("ACCESS DENIED") || text.includes("TOKEN REJECTED") || text.includes("LICENSE DENIED") || text.includes("AUTH ERROR") || text.includes("CRITICAL HALT")) {
      bar.style.width = "100%";
      document.getElementById("main").classList.add("error-state");
      status.textContent = "⛔ Access denied";
      line.textContent = "Check OFMPATH_TOKEN. Retrying...";
      setTimeout(() => location.reload(), 10000);
      return;
    } else if (text.includes("SYSTEM FULLY OPERATIONAL") && !handoffStarted) {
      handoffStarted = true; startHandoff();
    } else {
      // update status text based on log content
      for (let i = lines.length - 1; i >= 0; i--) {
        const l = lines[i];
        if (l.includes("UI Lockdown") || l.includes("lockdown")) { status.textContent = "Applying UI protection..."; break; }
        else if (l.includes("Deploying workflow")) { status.textContent = "Deploying workflows..."; break; }
        else if (l.includes("Found") && l.includes("models")) { status.textContent = "Syncing model weights..."; break; }
        else if (l.includes("custom node") || l.includes("_install_node")) { status.textContent = "Installing custom nodes..."; break; }
        else if (l.includes("Validating token")) { status.textContent = "Verifying license..."; break; }
        else if (l.includes("ComfyUI base") || l.includes("Waiting for")) { status.textContent = "Building ComfyUI core..."; break; }
      }
    }
  } catch (e) {}
}
setInterval(poll, 1500); poll();

// ── Snake game (CRT green) ──
(function() {
  const can = document.getElementById('snake');
  if (!can) return;
  const ctx = can.getContext('2d');
  const G = 16;
  const COLS = Math.floor(can.width / G), ROWS = Math.floor(can.height / G);
  let snake = [{x:5, y:Math.floor(ROWS/2)}];
  let dir = {x:1, y:0};
  let food = newFood();
  let score = 0, alive = true;

  function newFood() {
    let f;
    do { f = {x:Math.floor(Math.random()*COLS), y:Math.floor(Math.random()*ROWS)}; }
    while (snake.some(s => s.x===f.x && s.y===f.y));
    return f;
  }

  function draw() {
    ctx.fillStyle = '#030308';
    ctx.fillRect(0, 0, can.width, can.height);
    // grid
    ctx.strokeStyle = 'rgba(0,255,136,0.04)';
    ctx.lineWidth = 0.5;
    for (let x=0; x<can.width; x+=G) { ctx.beginPath(); ctx.moveTo(x,0); ctx.lineTo(x,can.height); ctx.stroke(); }
    for (let y=0; y<can.height; y+=G) { ctx.beginPath(); ctx.moveTo(0,y); ctx.lineTo(can.width,y); ctx.stroke(); }
    // food
    ctx.save();
    ctx.shadowColor = '#ff4466'; ctx.shadowBlur = 10;
    ctx.fillStyle = '#ff4466';
    ctx.fillRect(food.x*G+2, food.y*G+2, G-4, G-4);
    ctx.restore();
    // snake
    snake.forEach((cell, i) => {
      if (i === 0) {
        ctx.save();
        ctx.shadowColor = '#00ff88'; ctx.shadowBlur = 8;
        ctx.fillStyle = '#00ff88';
        ctx.fillRect(cell.x*G+1, cell.y*G+1, G-2, G-2);
        ctx.restore();
      } else {
        const a = 1 - (i/snake.length)*0.6;
        ctx.fillStyle = 'rgba(0,255,136,' + a + ')';
        ctx.fillRect(cell.x*G+1, cell.y*G+1, G-2, G-2);
      }
    });
  }

  function step() {
    if (!alive) return;
    const head = {x:snake[0].x+dir.x, y:snake[0].y+dir.y};
    if (head.x < 0) head.x = COLS-1;
    else if (head.x >= COLS) head.x = 0;
    if (head.y < 0) head.y = ROWS-1;
    else if (head.y >= ROWS) head.y = 0;
    if (snake.some(s => s.x===head.x && s.y===head.y)) {
      alive = false;
      setTimeout(() => {
        snake = [{x:5, y:Math.floor(ROWS/2)}]; dir = {x:1, y:0};
        score = 0; alive = true; food = newFood();
        document.getElementById('snake-score').textContent = '◈ 0';
      }, 1500);
      return;
    }
    snake.unshift(head);
    if (head.x===food.x && head.y===food.y) {
      score++;
      document.getElementById('snake-score').textContent = '◈ ' + score;
      food = newFood();
    } else { snake.pop(); }
    draw();
  }

  document.addEventListener('keydown', e => {
    const K = {ArrowLeft:{x:-1,y:0}, ArrowRight:{x:1,y:0}, ArrowUp:{x:0,y:-1}, ArrowDown:{x:0,y:1}};
    if (K[e.key]) {
      const d = K[e.key];
      if (d.x !== -dir.x || d.y !== -dir.y) dir = d;
      e.preventDefault();
    }
  });

  draw(); setInterval(step, 110);
})();
</script>
</body>
</html>
PRELOADER_HTML

    cd /tmp/ofmpath_loading
    # Stop ai-dock supervisor for ComfyUI so we can claim 8188
    supervisorctl stop comfyui > /dev/null 2>&1 || true
    sleep 2
    fuser -k 8188/tcp > /dev/null 2>&1 || true
    sleep 1
    python3 -m http.server 8188 --bind 0.0.0.0 > /dev/null 2>&1 &
    export PRELOADER_PID=$!
    echo "[OFM] Preloader server started (PID: $PRELOADER_PID)"
    mkdir -p "$WORKSPACE"; cd "$WORKSPACE"
}


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 2 — SYSTEM DEPENDENCIES
# ═══════════════════════════════════════════════════════════════════════════
_install_deps() {
    echo "[PROGRESS: 5]"
    echo "=========================================="
    echo "Installing system dependencies..."
    apt-get update -qq
    apt-get install -y -qq psmisc wget aria2 curl libimage-exiftool-perl openssl
    echo "[OFM] System dependencies installed"

    # Python deps
    if [ -x "/venv/main/bin/pip" ]; then
        PIP="/venv/main/bin/pip"
    elif [ -x "$COMFYUI_DIR/.venv/bin/pip" ]; then
        PIP="$COMFYUI_DIR/.venv/bin/pip"
    else
        PIP="pip"
    fi
    export PIP
    "$PIP" install --quiet requests 2>/dev/null || true
    echo "[OFM] Python deps ready"
}


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 3 — TOKEN VALIDATION GATE
# ═══════════════════════════════════════════════════════════════════════════
_validate_token() {
    echo "[PROGRESS: 15]"
    echo "=========================================="
    echo "Validating token..."

    if [ -z "${OFMPATH_TOKEN:-}" ]; then
        _show_error_page "NO TOKEN PROVIDED<br><br>OFMPATH_TOKEN environment variable not set.<br>Add it to your Vast.ai template env vars."
        return
    fi

    # Format whitelist
    if ! [[ "$OFMPATH_TOKEN" =~ ^ofmpath_[A-Fa-f0-9]{40,64}$ ]]; then
        _show_error_page "INVALID TOKEN FORMAT<br><br>Token must match pattern: ofmpath_ + 48 hex chars"
        return
    fi

    # ── Derive payload secret via RPC ──
    echo "[OFM] Deriving payload key via RPC..."
    local SECRET_RESPONSE
    SECRET_RESPONSE=$(curl -s --max-time 15 -X POST \
        "${OFMPATH_SUPA_URL}/rest/v1/rpc/get_payload_secret" \
        -H "apikey: ${OFMPATH_SUPA_KEY}" \
        -H "Authorization: Bearer ${OFMPATH_SUPA_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"p_token\":\"${OFMPATH_TOKEN}\"}" 2>/dev/null)

    # get_payload_secret returns a JSON string directly (not an object)
    local MASTER_SECRET
    MASTER_SECRET=$(echo "$SECRET_RESPONSE" | python3 -c "import sys,json
try:
    d = json.load(sys.stdin)
    print(d if isinstance(d,str) and len(d) >= 32 else '')
except:
    print('')" 2>/dev/null)

    if [ -z "$MASTER_SECRET" ]; then
        local _ts=$(date -u +%Y%m%dT%H%M%SZ)
        echo "[OFM] CRITICAL HALT — E0:RPC at ${_ts}"
        _show_error_page "ACCESS DENIED<br><br>Token validation failed. Your subscription may be inactive.<br><br><span style='font-size:10px;color:#888;'>REF: E0-RPC-${_ts}</span>"
        return
    fi

    # Derive PBKDF2 password
    export OFMPATH_PAYLOAD_KEY=$(echo -n "$MASTER_SECRET" | sha256sum | cut -d' ' -f1)
    echo "[OFM] ✓ Token validated — session authorized"
    echo "[OFM] ✓ Payload key derived"
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
    echo "Waiting for Vast.ai base install..."

    local timeout=600 elapsed=0
    while [ ! -f "$COMFYUI_DIR/main.py" ]; do
        sleep 5; elapsed=$((elapsed + 5))
        if [ $elapsed -ge $timeout ]; then
            echo "[OFM] ERROR: ComfyUI base install timed out (${timeout}s)"
            _show_error_page "COMFYUI BASE INSTALL TIMEOUT<br><br>Base install did not complete within 10 minutes."
            return
        fi
    done
    echo "[OFM] ComfyUI base detected at $COMFYUI_DIR"

    # Update ComfyUI + frontend
    cd "$COMFYUI_DIR"
    git config --global --add safe.directory "$COMFYUI_DIR"
    git pull origin master 2>/dev/null || git pull origin main 2>/dev/null || true
    if git status 2>/dev/null | grep -q "HEAD detached"; then
        git fetch origin
        git checkout master 2>/dev/null || git checkout main 2>/dev/null
        git pull
    fi
    "$PIP" install --upgrade comfyui-frontend-package --quiet 2>/dev/null || true
    echo "[OFM] ComfyUI updated"
    cd "$WORKSPACE"

    # Stop ComfyUI to free port / prepare for injection
    supervisorctl stop comfyui >/dev/null 2>&1 || true
    sleep 2
}


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 6 — DEPLOY OFMPATH STACK (fetch + decrypt + run inner installer)
# ═══════════════════════════════════════════════════════════════════════════
_deploy_stack() {
    echo "[PROGRESS: 30]"
    echo "=========================================="
    echo "Deploying OFM PATH stack..."

    cd "$WORKSPACE"

    echo "[OFM] Fetching encrypted installer from bucket..."
    if _fetch_secure "ofmpath_install.sh.enc" "/tmp/ofmpath_install.sh.enc"; then
        if _decrypt_secure "/tmp/ofmpath_install.sh.enc" "/tmp/ofmpath_install.sh"; then
            rm -f /tmp/ofmpath_install.sh.enc
            chmod +x /tmp/ofmpath_install.sh
            echo "[OFM] Running OFM PATH installer..."
            bash /tmp/ofmpath_install.sh || echo "[OFM] ⚠ Installer had warnings (continuing)"
        else
            echo "[OFM] ⚠ Decrypt failed — falling back to inline installer"
            _inline_installer
        fi
    else
        echo "[OFM] ⚠ Bucket fetch failed — using inline fallback"
        _inline_installer
    fi

    rm -f /tmp/ofmpath_install.sh

    echo "[OFM] ✓ OFM PATH stack deployed"
}


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 6.5 — FALLBACK INLINE INSTALLER  (same payload, public copy)
#
#  If the encrypted inner installer can't be fetched/decrypted, this bare-bones
#  version runs the core node + model + workflow flow directly. The encrypted
#  version is preferred because its contents (node list, model URLs) are
#  hidden from public inspection.
# ═══════════════════════════════════════════════════════════════════════════
_inline_installer() {
    echo "[OFM] Running inline installer..."
    # Fetches the unencrypted fallback from the same GitHub repo as this script.
    # (Less secure but guarantees deployment works even if bucket is down.)
    local FALLBACK_URL="https://raw.githubusercontent.com/st4vz/oiujdsa/refs/heads/main/ofmpath_install.sh"
    if curl -fsSL --max-time 30 "$FALLBACK_URL" -o /tmp/ofmpath_install_fallback.sh 2>/dev/null; then
        chmod +x /tmp/ofmpath_install_fallback.sh
        bash /tmp/ofmpath_install_fallback.sh || echo "[OFM] ⚠ Fallback installer had warnings"
        rm -f /tmp/ofmpath_install_fallback.sh
    else
        echo "[OFM] ❌ Even fallback fetch failed — deployment incomplete"
    fi
}


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 7 — UI LOCKDOWN (anti-theft frontend hardening)
# ═══════════════════════════════════════════════════════════════════════════
_lockdown_ui() {
    echo "[PROGRESS: 92]"
    echo "=========================================="
    echo "Applying UI Lockdown..."

    local FRONTEND_DIR
    FRONTEND_DIR=$(python3 -c "import comfyui_frontend_package, os; print(os.path.dirname(comfyui_frontend_package.__file__))" 2>/dev/null)
    local FRONTEND_HTML="${FRONTEND_DIR}/static/index.html"

    if [ -f "$FRONTEND_HTML" ] && ! grep -q "OFMPATH-BOOT" "$FRONTEND_HTML"; then
        export FRONTEND_HTML
        python3 <<'PYINJECT'
import os
p = os.environ.get("FRONTEND_HTML", "")
if not os.path.isfile(p):
    raise SystemExit(0)
boot = '<script data-id="OFMPATH-BOOT">document.addEventListener("contextmenu",function(e){var t=e.target;if(t.tagName!=="CANVAS"){e.preventDefault();e.stopImmediatePropagation()}},true);document.addEventListener("keydown",function(e){var k=e.key?e.key.toLowerCase():"";if(e.key==="F12"||(e.ctrlKey&&e.shiftKey&&"ijc".includes(k))||(e.ctrlKey&&k==="u")||(e.ctrlKey&&"sepa".includes(k))){e.preventDefault();e.stopImmediatePropagation()}},true);setInterval(function(){var t=performance.now();debugger;if(performance.now()-t>100){document.body.innerHTML="";window.location.href="about:blank";setTimeout(function(){window.close()},10);}},500);</script>'
with open(p, 'r') as f: html = f.read()
html = html.replace("<head>", "<head>" + boot, 1)
with open(p, 'w') as f: f.write(html)
print("[OFM] ✓ Early-boot protection injected")
PYINJECT
    fi

    # Inject supervisor --disable-metadata flag
    if [ -f /etc/supervisor/conf.d/comfyui.conf ] && ! grep -q "disable-metadata" /etc/supervisor/conf.d/comfyui.conf; then
        sed -i 's/--listen 0.0.0.0/--listen 0.0.0.0 --disable-metadata/g' /etc/supervisor/conf.d/comfyui.conf
        supervisorctl update >/dev/null 2>&1 || true
        echo "[OFM] ✓ --disable-metadata injected into supervisor config"
    fi

    # Strip EXIF from any existing output/input media
    for d in "$COMFYUI_DIR/output" "$COMFYUI_DIR/input"; do
        [ -d "$d" ] && find "$d" \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \
            -o -iname "*.webp" -o -iname "*.mp4" -o -iname "*.webm" \) \
            -exec exiftool -overwrite_original -all= {} \; 2>/dev/null || true
    done

    echo "[OFM] ✓ UI Lockdown complete"
}


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE 8 — ENSURE COMFYUI STOPPED BEFORE FINAL HANDOFF
# ═══════════════════════════════════════════════════════════════════════════
_ensure_comfyui_stopped() {
    supervisorctl stop comfyui >/dev/null 2>&1 || true
    pkill -f "ComfyUI/main.py" 2>/dev/null || true
    sleep 2

    # Kill only non-preloader processes on 8188 so the preloader UI stays up
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
#  PHASE 9 — GRACEFUL HANDOFF  (preloader → ComfyUI)
# ═══════════════════════════════════════════════════════════════════════════
_finalize() {
    echo "[PROGRESS: 98]"
    echo "=========================================="
    echo "     SYSTEM FULLY OPERATIONAL             "
    echo "=========================================="

    # Signal the browser we're ready
    echo "SYSTEM FULLY OPERATIONAL" >> /tmp/ofmpath_loading/install.log 2>/dev/null || true
    echo "READY" > /tmp/ofmpath_loading/ready
    sync

    echo "[OFM] Signaling handoff — giving browser time to catch up..."
    sleep 5

    # Kill preloader
    echo "[OFM] Shutting down preloader..."
    [ -n "${PRELOADER_PID:-}" ] && { kill "$PRELOADER_PID" 2>/dev/null; sleep 1; kill -9 "$PRELOADER_PID" 2>/dev/null; }
    pkill -f "http.server 8188" 2>/dev/null || true
    sleep 1
    fuser -k 8188/tcp >/dev/null 2>&1 || true
    sleep 1

    # Wait for port to free
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

    # Start ComfyUI
    supervisorctl restart comfyui >/dev/null 2>&1 || supervisorctl start comfyui >/dev/null 2>&1 || true

    # Wait for it to come online
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

    rm -rf /tmp/ofmpath_loading

    echo "[OFM] ═══════════════════════════════════"
    echo "[OFM] OFM PATH 智慧通路 — Deployment complete"
    echo "[OFM] ComfyUI: http://localhost:8188"
    echo "[OFM] ═══════════════════════════════════"
}


# ═══════════════════════════════════════════════════════════════════════════
#  ERROR PAGE  (swap preloader HTML with error, then sleep forever)
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
         background:rgba(20,5,8,0.85); backdrop-filter:blur(18px);
         box-shadow:0 0 80px rgba(255,68,102,0.1); }
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
  <div class="footer">OFM PATH · SZN VAULT</div>
</div>
</body></html>
ERRHTML

    echo "[OFM] Error page deployed"
    sleep infinity
}


# ═══════════════════════════════════════════════════════════════════════════
#  EXECUTION ORDER
# ═══════════════════════════════════════════════════════════════════════════
_start_preloader         # Phase 1: CRT preloader + snake game
_install_deps            # Phase 2: System + Python deps
_validate_token          # Phase 3: ★ Token gate (halts on failure)
_wait_for_comfy          # Phase 4: Wait for Vast.ai ComfyUI base
_deploy_stack            # Phase 5: Fetch + decrypt + run inner installer
_ensure_comfyui_stopped  # Phase 6: Stop ComfyUI
_lockdown_ui             # Phase 7: UI anti-theft
_ensure_comfyui_stopped  # Phase 8: Confirm stopped before handoff
_finalize                # Phase 9: Handoff preloader → ComfyUI
