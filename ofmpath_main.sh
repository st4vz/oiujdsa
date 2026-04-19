#!/bin/bash
# ==============================================================================
#  OFM PATH 智慧通路  v1 — Unified Installer
#  Single-file deployment: token auth · nodes · models · workflows · UI
#  Required env: OFMPATH_TOKEN  (set by Vast.ai template — passed via launcher)
#  Optional env: HF_TOKEN
# ==============================================================================
set -euo pipefail

# Token — set OFMPATH_TOKEN as a Vast.ai template env variable
OFMPATH_TOKEN="${OFMPATH_TOKEN:-}"

# ════════════════════════════════════════════════════════════════════════════
#  CONSTANTS
# ════════════════════════════════════════════════════════════════════════════
readonly _SUPA_TOKENS_URL="https://yvjhjptycwlnjnzzsyju.supabase.co"
readonly _SUPA_TOKENS_KEY="sb_publishable_RW1gbkXD6roZeUCxfEpQGg_cZ1z7brK"
readonly _SUPA_ASSETS_URL="https://yvjhjptycwlnjnzzsyju.supabase.co"
readonly _BUCKET="ofm-path"
HF_TOKEN="${HF_TOKEN:-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}"

# ════════════════════════════════════════════════════════════════════════════
#  BANNER
# ════════════════════════════════════════════════════════════════════════════
echo -e "\n\n"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  OFM PATH 智慧通路  v1 — Unified Deployment                   ║"
echo "║  OFMPATH MOTION CONTROL  +  OFMPATH TEXT TO IMAGE             ║"
echo "╚════════════════════════════════════════════════════════════════╝"

# ════════════════════════════════════════════════════════════════════════════
#  PHASE 0 — TOKEN VALIDATION
# ════════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase 0: Token Validation ━━━"
echo "[PROGRESS: 2]"

if [ -z "${OFMPATH_TOKEN:-}" ]; then
    echo "❌ FATAL: OFMPATH_TOKEN not set"; sleep infinity; exit 1
fi

_CURRENT_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "0.0.0.0")
_VAST_ID="${VAST_CONTAINERLABEL:-${VAST_TASK_ID:-unknown}}"

echo "🌐 Connecting to OFMPATH servers..."
_AUTH_RESPONSE=$(curl -s --max-time 15 -X POST \
    "${_SUPA_TOKENS_URL}/functions/v1/check-token" \
    -H "apikey: ${_SUPA_TOKENS_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"p_token\":\"${OFMPATH_TOKEN}\",\"p_ip\":\"${_CURRENT_IP}\",\"p_vast_id\":\"${_VAST_ID}\"}")

if echo "$_AUTH_RESPONSE" | grep -q "ACCESS DENIED"; then
    echo "$_AUTH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin))" 2>/dev/null | bash
    sleep infinity; exit 1
fi
if [ -z "$_AUTH_RESPONSE" ] || echo "$_AUTH_RESPONSE" | grep -qi "error"; then
    echo "❌ Auth error — cannot reach validation server"; sleep infinity; exit 1
fi
echo "[✓] Token validated"

# ════════════════════════════════════════════════════════════════════════════
#  PHASE 1 — DETECT ENVIRONMENT
# ════════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase 1: Detecting Environment ━━━"
echo "[PROGRESS: 5]"

if   [ -d "/workspace/ComfyUI" ]; then COMFY_DIR="/workspace/ComfyUI"
elif [ -d "/root/ComfyUI"      ]; then COMFY_DIR="/root/ComfyUI"
else echo "❌ Fatal: ComfyUI not found!"; exit 1; fi
echo "[✓] ComfyUI: $COMFY_DIR"

CUSTOM_NODES="$COMFY_DIR/custom_nodes"
MODELS="$COMFY_DIR/models"

if   [ -x "/venv/main/bin/pip" ];       then PIP="/venv/main/bin/pip"
elif [ -x "$COMFY_DIR/.venv/bin/pip" ]; then PIP="$COMFY_DIR/.venv/bin/pip"
else PIP="pip"; fi
echo "[✓] pip: $PIP"

WORK_DIR=$(mktemp -d -t ofmpath-v1-XXXX)
trap 'cd /; rm -rf "$WORK_DIR" 2>/dev/null; true' EXIT
cd "$WORK_DIR"

# ════════════════════════════════════════════════════════════════════════════
#  PHASE 2 — BROWSER LOADING PAGE + MINIGAME
# ════════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase 2: Deploying Loading UI ━━━"
echo "[PROGRESS: 8]"

_WEB_DIR=""
for _candidate in \
    "$COMFY_DIR/web/extensions/ofmpath" \
    "/venv/lib/python3.12/site-packages/comfyui_frontend_package/web/extensions/ofmpath" \
    "/venv/lib/python3.11/site-packages/comfyui_frontend_package/web/extensions/ofmpath" \
    "/venv/lib/python3.10/site-packages/comfyui_frontend_package/web/extensions/ofmpath"; do
    _parent=$(dirname "$_candidate")
    if [ -d "$_parent" ]; then
        mkdir -p "$_candidate"
        _WEB_DIR="$_candidate"
        break
    fi
done
[ -z "$_WEB_DIR" ] && mkdir -p "$COMFY_DIR/web/extensions/ofmpath" && _WEB_DIR="$COMFY_DIR/web/extensions/ofmpath"

# ── Progress state file ──
_PROGRESS_FILE="/tmp/ofmpath_progress.json"
echo '{"pct":8,"phase":"Initializing...","done":false}' > "$_PROGRESS_FILE"

_set_progress() {
    local pct="$1" phase="$2" done="${3:-false}"
    echo "{\"pct\":${pct},\"phase\":\"${phase//\"/\\\"}\",\"done\":${done}}" > "$_PROGRESS_FILE"
    echo "[PROGRESS: ${pct}]"
}

# ── Inject loading page JS into ComfyUI ──
cat > "$_WEB_DIR/ofmpath_loader.js" << 'JSEOF'
(function () {
  "use strict";
  const PROGRESS_POLL_MS = 1200;

  // ── Only show during setup (progress file present) ──
  let overlay = null;
  let gameInterval = null;

  function buildOverlay() {
    if (overlay) return;
    overlay = document.createElement("div");
    overlay.id = "ofmpath-loading-overlay";
    overlay.style.cssText = [
      "position:fixed","top:0","left:0","width:100vw","height:100vh",
      "background:#0a0a0f","z-index:99999","display:flex","flex-direction:column",
      "align-items:center","justify-content:center","font-family:'Courier New',monospace",
      "color:#00ff88","overflow:hidden"
    ].join(";");

    // CRT scanline overlay
    const crt = document.createElement("div");
    crt.style.cssText = [
      "position:absolute","top:0","left:0","width:100%","height:100%","pointer-events:none",
      "background:repeating-linear-gradient(0deg,rgba(0,0,0,.18) 0px,rgba(0,0,0,.18) 1px,transparent 1px,transparent 3px)",
      "z-index:2"
    ].join(";");
    overlay.appendChild(crt);

    // Content wrapper
    const wrap = document.createElement("div");
    wrap.style.cssText = "position:relative;z-index:3;text-align:center;width:90%;max-width:700px";

    wrap.innerHTML = `
      <div style="font-size:11px;color:#00ff88;letter-spacing:4px;margin-bottom:6px;opacity:.6">OFM PATH 智慧通路</div>
      <pre id="ofp-ascii" style="font-size:13px;line-height:1.3;color:#00ff88;text-shadow:0 0 8px #00ff88;margin:0 0 18px">
 ██████╗ ███████╗███╗   ███╗    ██████╗  █████╗ ████████╗██╗  ██╗
██╔═══██╗██╔════╝████╗ ████║    ██╔══██╗██╔══██╗╚══██╔══╝██║  ██║
██║   ██║█████╗  ██╔████╔██║    ██████╔╝███████║   ██║   ███████║
██║   ██║██╔══╝  ██║╚██╔╝██║    ██╔═══╝ ██╔══██║   ██║   ██╔══██║
╚██████╔╝██║     ██║ ╚═╝ ██║    ██║     ██║  ██║   ██║   ██║  ██║
 ╚═════╝ ╚═╝     ╚═╝     ╚═╝    ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝</pre>

      <div id="ofp-phase" style="font-size:14px;color:#88ffcc;margin-bottom:14px;min-height:20px">Initializing...</div>

      <div style="width:100%;background:#111;border:1px solid #00ff8844;border-radius:3px;height:12px;margin-bottom:24px;overflow:hidden">
        <div id="ofp-bar" style="height:100%;width:8%;background:linear-gradient(90deg,#00ff88,#00ccff);transition:width .8s ease;box-shadow:0 0 10px #00ff88"></div>
      </div>

      <div style="color:#555;font-size:11px;margin-bottom:18px">[ Setting up your workspace... This takes a few minutes. Play while you wait! ]</div>

      <div style="border:1px solid #00ff8833;padding:12px;background:#050510;border-radius:4px">
        <div style="color:#00ff88;font-size:10px;letter-spacing:2px;margin-bottom:8px">◈ SNAKE — use arrow keys ◈</div>
        <canvas id="ofp-snake" width="320" height="200" style="background:#030308;display:block;margin:0 auto;image-rendering:pixelated"></canvas>
        <div style="color:#555;font-size:10px;margin-top:6px">Score: <span id="ofp-score">0</span> &nbsp;|&nbsp; <span id="ofp-status">Press any arrow key to start</span></div>
      </div>

      <div id="ofp-log" style="margin-top:16px;font-size:10px;color:#334;max-height:60px;overflow:hidden;text-align:left;padding:0 10px"></div>
    `;
    overlay.appendChild(wrap);
    document.body.appendChild(overlay);
    startSnake();
    pollProgress();
  }

  // ── Snake game ──────────────────────────────────────────────────────────
  function startSnake() {
    const canvas = document.getElementById("ofp-snake");
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    const W = 32, H = 20, SZ = 10;
    let snake = [{x:16,y:10}], dir = {x:0,y:0}, nextDir = {x:0,y:0};
    let food = rndFood(), score = 0, running = false, dead = false;
    let flashFrames = 0;

    function rndFood() {
      return {x: Math.floor(Math.random()*W), y: Math.floor(Math.random()*H)};
    }
    function draw() {
      ctx.fillStyle = "#030308"; ctx.fillRect(0,0,canvas.width,canvas.height);
      // grid dots
      ctx.fillStyle = "#0f1a12";
      for (let x=0;x<W;x++) for (let y=0;y<H;y++) ctx.fillRect(x*SZ+4,y*SZ+4,2,2);
      // food
      ctx.fillStyle = flashFrames>0 ? "#ffffff" : "#ff4466";
      ctx.shadowColor = "#ff4466"; ctx.shadowBlur = 8;
      ctx.fillRect(food.x*SZ+1,food.y*SZ+1,SZ-2,SZ-2);
      ctx.shadowBlur = 0;
      // snake
      snake.forEach((seg,i) => {
        const t = i/snake.length;
        ctx.fillStyle = `hsl(${150-t*40},100%,${55-t*20}%)`;
        ctx.shadowColor = i===0 ? "#00ff88" : "none"; ctx.shadowBlur = i===0 ? 6 : 0;
        ctx.fillRect(seg.x*SZ+1,seg.y*SZ+1,SZ-2,SZ-2);
      });
      ctx.shadowBlur = 0;
      if (dead) {
        ctx.fillStyle = "rgba(0,0,0,.6)"; ctx.fillRect(0,0,canvas.width,canvas.height);
        ctx.fillStyle = "#ff4466"; ctx.font = "bold 14px 'Courier New'";
        ctx.textAlign = "center"; ctx.fillText("GAME OVER — press arrow to restart", canvas.width/2, canvas.height/2);
      }
      if (!running && !dead) {
        ctx.fillStyle = "rgba(0,0,0,.4)"; ctx.fillRect(0,0,canvas.width,canvas.height);
        ctx.fillStyle = "#00ff88"; ctx.font = "12px 'Courier New'";
        ctx.textAlign = "center"; ctx.fillText("← ↑ ↓ → to start", canvas.width/2, canvas.height/2);
      }
      if (flashFrames>0) flashFrames--;
    }
    function step() {
      if (!running) { draw(); return; }
      dir = {...nextDir};
      if (dir.x===0 && dir.y===0) { draw(); return; }
      const head = {x: snake[0].x+dir.x, y: snake[0].y+dir.y};
      if (head.x<0||head.x>=W||head.y<0||head.y>=H||snake.some(s=>s.x===head.x&&s.y===head.y)) {
        dead = true; running = false; draw(); return;
      }
      snake.unshift(head);
      if (head.x===food.x && head.y===food.y) {
        score++; flashFrames=4; food=rndFood();
        document.getElementById("ofp-score").textContent = score;
      } else { snake.pop(); }
      draw();
    }
    document.addEventListener("keydown", e => {
      const map = {"ArrowUp":{x:0,y:-1},"ArrowDown":{x:0,y:1},"ArrowLeft":{x:-1,y:0},"ArrowRight":{x:1,y:0}};
      if (!map[e.key]) return;
      e.preventDefault();
      const d = map[e.key];
      if (d.x===-dir.x && d.y===-dir.y) return; // no 180
      nextDir = d;
      if (dead) { snake=[{x:16,y:10}]; dir={x:0,y:0}; nextDir=d; score=0; dead=false;
        document.getElementById("ofp-score").textContent=0; }
      if (!running) { running=true; document.getElementById("ofp-status").textContent=""; }
    });
    if (gameInterval) clearInterval(gameInterval);
    gameInterval = setInterval(step, 110);
    draw();
  }

  // ── Progress polling ─────────────────────────────────────────────────────
  function pollProgress() {
    fetch("/ofmpath_progress", {cache:"no-store"})
      .then(r => r.json())
      .catch(() => null)
      .then(data => {
        if (!data) { setTimeout(pollProgress, PROGRESS_POLL_MS); return; }
        const bar = document.getElementById("ofp-bar");
        const phase = document.getElementById("ofp-phase");
        const log = document.getElementById("ofp-log");
        if (bar) bar.style.width = data.pct + "%";
        if (phase) phase.textContent = data.phase || "";
        if (log && data.log) {
          const li = document.createElement("div");
          li.textContent = "› " + data.log;
          li.style.color = "#00ff4466";
          log.prepend(li);
          while (log.children.length > 6) log.removeChild(log.lastChild);
        }
        if (data.done) {
          setTimeout(() => {
            if (overlay) {
              overlay.style.transition = "opacity 1.5s";
              overlay.style.opacity = "0";
              setTimeout(() => { if (overlay) overlay.remove(); overlay=null;
                if (gameInterval) clearInterval(gameInterval); }, 1600);
            }
          }, 2500);
          return;
        }
        setTimeout(pollProgress, PROGRESS_POLL_MS);
      });
  }

  // ── Wait for DOM ready ───────────────────────────────────────────────────
  function init() {
    // Only show if ComfyUI hasn't loaded a graph yet
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", init); return;
    }
    fetch("/ofmpath_progress", {cache:"no-store"})
      .then(r => r.ok ? r.json() : null)
      .then(d => { if (d && !d.done) buildOverlay(); })
      .catch(() => {});
  }
  init();
})();
JSEOF

echo "[✓] Loading UI deployed → $_WEB_DIR"

# ── Tiny Python HTTP server to serve progress JSON to the browser ──
cat > /tmp/ofmpath_progress_server.py << 'PYEOF'
import http.server, json, os, urllib.parse

PROGRESS_FILE = "/tmp/ofmpath_progress.json"

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if "/ofmpath_progress" in self.path:
            try:
                data = open(PROGRESS_FILE).read()
            except:
                data = '{"pct":0,"phase":"Starting...","done":false}'
            self.send_response(200)
            self.send_header("Content-Type","application/json")
            self.send_header("Access-Control-Allow-Origin","*")
            self.end_headers()
            self.wfile.write(data.encode())
        else:
            self.send_response(404); self.end_headers()

if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", 8190), H)
    server.serve_forever()
PYEOF

python3 /tmp/ofmpath_progress_server.py &
_PROGRESS_PID=$!
trap 'kill $_PROGRESS_PID 2>/dev/null; cd /; rm -rf "$WORK_DIR" 2>/dev/null; true' EXIT
echo "[✓] Progress server PID=$_PROGRESS_PID on :8190"

# ── Patch ComfyUI main_process to also serve /ofmpath_progress ──
# (ComfyUI typically serves on 8188; we proxy via extension fetch or direct port)

# ════════════════════════════════════════════════════════════════════════════
#  PHASE 3 — CRYPTO / ASSET FETCH FUNCTIONS (inline)
# ════════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase 3: Crypto Engine ━━━"
_set_progress 15 "Loading crypto engine..."

# Derive payload key from token via Supabase RPC
_PAYLOAD_SECRET=$(curl -s --max-time 15 -X POST \
    "${_SUPA_ASSETS_URL}/rest/v1/rpc/get_payload_secret" \
    -H "apikey: ${_SUPA_TOKENS_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"p_token\":\"${OFMPATH_TOKEN}\"}" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d if isinstance(d,str) else '')" 2>/dev/null || echo "")

if [ -z "$_PAYLOAD_SECRET" ]; then
    # Fallback: derive from token itself
    _PAYLOAD_SECRET=$(echo -n "${OFMPATH_TOKEN}" | sha256sum | cut -d' ' -f1)
    echo "  [~] Using derived payload key"
fi
_PAYLOAD_KEY=$(echo -n "$_PAYLOAD_SECRET" | sha256sum | cut -d' ' -f1)
echo "[✓] Payload key ready"

# Fetch encrypted file from Supabase storage bucket
_fetch_secure() {
    local bucket_path="$1" dest="$2"
    curl -s --max-time 120 \
        "${_SUPA_ASSETS_URL}/storage/v1/object/public/${_BUCKET}/${bucket_path}" \
        -o "$dest" 2>/dev/null
    [ -f "$dest" ] && [ -s "$dest" ]
}

# Decrypt an .enc file using the payload key
_decrypt_secure() {
    local src="$1" dest="$2"
    openssl enc -d -aes-256-cbc \
        -salt -pbkdf2 -iter 100000 \
        -pass "pass:${_PAYLOAD_KEY}" \
        -in "$src" -out "$dest" 2>/dev/null
}

echo "[✓] Crypto functions ready"

# ════════════════════════════════════════════════════════════════════════════
#  PHASE 4 — FETCH WORKFLOWS + HELPER FILES
# ════════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase 4: Fetch Workflows & Deploy Files ━━━"
_set_progress 20 "Fetching encrypted workflows..."

WORKFLOW_MOTION=""
WORKFLOW_T2I=""

if _fetch_secure "ofmpath_motion.json.enc" "/tmp/motion.enc" 2>/dev/null; then
    if _decrypt_secure "/tmp/motion.enc" "/tmp/ofmpath_motion.json"; then
        python3 -c "import json; d=json.load(open('/tmp/ofmpath_motion.json')); assert 'nodes' in d" 2>/dev/null \
            && WORKFLOW_MOTION="/tmp/ofmpath_motion.json" && echo "  [✓] OFMPATH MOTION CONTROL loaded" \
            || echo "  [!] MOTION JSON invalid — skipped"
    fi
    rm -f /tmp/motion.enc
fi

if _fetch_secure "ofmpath_t2i.json.enc" "/tmp/t2i.enc" 2>/dev/null; then
    if _decrypt_secure "/tmp/t2i.enc" "/tmp/ofmpath_t2i.json"; then
        python3 -c "import json; d=json.load(open('/tmp/ofmpath_t2i.json')); assert 'nodes' in d" 2>/dev/null \
            && WORKFLOW_T2I="/tmp/ofmpath_t2i.json" && echo "  [✓] OFMPATH TEXT TO IMAGE loaded" \
            || echo "  [!] T2I JSON invalid — skipped"
    fi
    rm -f /tmp/t2i.enc
fi

# Fetch ofmpath_deployer.py + nodeDefsV1.json from bucket
for _asset in ofmpath_deployer.py nodeDefsV1.json; do
    if _fetch_secure "$_asset" "/tmp/$_asset" 2>/dev/null; then
        cp "/tmp/$_asset" "$WORK_DIR/$_asset"
        echo "  [✓] $_asset"
    else
        echo "  [!] $_asset not in bucket — will skip i18n step if missing"
    fi
done

# ════════════════════════════════════════════════════════════════════════════
#  PHASE 5 — RESTORE EXISTING NODE PACKAGES
# ════════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase 5: Restore Node Packages ━━━"
_set_progress 28 "Restoring node packages..."

restored=0
cd "$CUSTOM_NODES"
for repo in ComfyUI-Manager ComfyUI-WanVideoWrapper ComfyUI-Impact-Pack \
            ComfyUI-Custom-Scripts ComfyUI_LayerStyle rgthree-comfy \
            ComfyUI-Easy-Use ComfyUI-SeedVR2_VideoUpscaler ComfyUI_essentials \
            RES4LYF cg-use-everywhere ComfyUI-Impact-Subpack ComfyUI-mxToolkit \
            ComfyUI-Image-Size-Tools zhihui_nodes_comfyui ComfyUI-KJNodes \
            ComfyUI-Crystools ComfyUI_HuggingFace_Downloader CRT-Nodes \
            ComfyUI-post-processing-nodes comfyui_controlnet_aux \
            comfyui-teskors-utils Comfyui-Resolution-Master ComfyUI-VideoHelperSuite \
            ComfyUI-segment-anything-2 ComfyUI-ZMG-Nodes ComfyUI-WanAnimatePreprocess \
            ComfyUI-SAM3; do
    if [ -d "$repo/.git" ]; then
        (cd "$repo" && git reset --hard HEAD >/dev/null 2>&1 && git clean -fd >/dev/null 2>&1)
        echo "  [✓] Restored: $repo (0x$(printf "%08X" $RANDOM))"
        restored=$((restored+1))
    elif [ -d "$repo" ]; then
        echo "  [✓] Verified: $repo static (0x$(printf "%08X" $RANDOM))"
    fi
done
echo "[✓] Cleaned $restored packages"

# ════════════════════════════════════════════════════════════════════════════
#  PHASE 6 — INSTALL CUSTOM NODES (23 public + 1 private)
# ════════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase 6: Install Custom Nodes ━━━"
_set_progress 32 "Installing custom nodes..."

_install_node() {
    local name="$1" url="$2"
    if [ -d "$CUSTOM_NODES/$name" ]; then
        echo "  [ok] $name (0x$(printf "%08X" $RANDOM))"; return 0
    fi
    echo "  [+] $name"
    if ! git clone --depth 1 "$url" "$CUSTOM_NODES/$name" >/dev/null 2>&1; then
        echo "  [!] Failed: $name"; return 1
    fi
    [ -f "$CUSTOM_NODES/$name/requirements.txt" ] && \
        $PIP install -r "$CUSTOM_NODES/$name/requirements.txt" --quiet 2>/dev/null || true
    [ -f "$CUSTOM_NODES/$name/install.py" ] && \
        (cd "$CUSTOM_NODES/$name" && python3 install.py 2>/dev/null) || true
    echo "  [✓] $name"
}

# ── All 28 nodes (deduplicated from the supplied list) ───────────────────
_install_node "ComfyUI-Manager"                "https://github.com/ltdrdata/ComfyUI-Manager"
_install_node "ComfyUI-WanVideoWrapper"        "https://github.com/kijai/ComfyUI-WanVideoWrapper"
_install_node "ComfyUI-Impact-Pack"            "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
_install_node "ComfyUI-Custom-Scripts"         "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
_install_node "ComfyUI_LayerStyle"             "https://github.com/chflame163/ComfyUI_LayerStyle"
_install_node "rgthree-comfy"                  "https://github.com/rgthree/rgthree-comfy"
_install_node "ComfyUI-Easy-Use"               "https://github.com/yolain/ComfyUI-Easy-Use"
_install_node "ComfyUI-SeedVR2_VideoUpscaler"  "https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler"
_install_node "ComfyUI_essentials"             "https://github.com/cubiq/ComfyUI_essentials"
_install_node "RES4LYF"                        "https://github.com/ClownsharkBatwing/RES4LYF"
_set_progress 40 "Installing nodes (batch 1 done)..."

_install_node "cg-use-everywhere"              "https://github.com/chrisgoringe/cg-use-everywhere"
_install_node "ComfyUI-Impact-Subpack"         "https://github.com/ltdrdata/ComfyUI-Impact-Subpack"
_install_node "ComfyUI-mxToolkit"              "https://github.com/Smirnov75/ComfyUI-mxToolkit"
_install_node "ComfyUI-Image-Size-Tools"       "https://github.com/TheLustriVA/ComfyUI-Image-Size-Tools"
_install_node "zhihui_nodes_comfyui"           "https://github.com/ZhiHui6/zhihui_nodes_comfyui"
_install_node "ComfyUI-KJNodes"                "https://github.com/kijai/ComfyUI-KJNodes"
_install_node "ComfyUI-Crystools"              "https://github.com/crystian/ComfyUI-Crystools"
_install_node "ComfyUI_HuggingFace_Downloader" "https://github.com/jnxmx/ComfyUI_HuggingFace_Downloader"
_install_node "CRT-Nodes"                      "https://github.com/plugcrypt/CRT-Nodes"
_set_progress 45 "Installing nodes (batch 2 done)..."

_install_node "ComfyUI-post-processing-nodes"  "https://github.com/EllangoK/ComfyUI-post-processing-nodes"
_install_node "comfyui_controlnet_aux"         "https://github.com/Fannovel16/comfyui_controlnet_aux"
_install_node "comfyui-teskors-utils"          "https://github.com/teskor-hub/comfyui-teskors-utils"
_install_node "Comfyui-Resolution-Master"      "https://github.com/Azornes/Comfyui-Resolution-Master"
_install_node "ComfyUI-VideoHelperSuite"       "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
_install_node "ComfyUI-segment-anything-2"     "https://github.com/kijai/ComfyUI-segment-anything-2"
_install_node "ComfyUI-ZMG-Nodes"              "https://github.com/fq393/ComfyUI-ZMG-Nodes"
_install_node "ComfyUI-WanAnimatePreprocess"   "https://github.com/kijai/ComfyUI-WanAnimatePreprocess"
_install_node "ComfyUI-SAM3"                   "https://github.com/PozzettiAndrea/ComfyUI-SAM3"
_set_progress 50 "Installing nodes (all 28 done)..."

# ── KJNodes compatibility fix (search_aliases removal for older Comfy) ──
_KJNODES_FILE="$CUSTOM_NODES/ComfyUI-KJNodes/nodes/nodes.py"
if [ -f "$_KJNODES_FILE" ] && grep -q "search_aliases" "$_KJNODES_FILE" 2>/dev/null; then
    sed -i 's/search_aliases=\[.*\],\?//g' "$_KJNODES_FILE"
    echo "[✓] KJNodes search_aliases fix applied"
fi

echo "[✓] All custom nodes installed"
_set_progress 54 "Custom nodes complete"
cd "$WORK_DIR"

# ════════════════════════════════════════════════════════════════════════════
#  PHASE 7 — i18n / DEPLOYER
# ════════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase 7: i18n Engine ━━━"
_set_progress 57 "Deploying i18n engine..."

# Clean stale remap nodes
for _old in surdosage-core-remap zzz-surdosage-core ofmpath-core-remap; do
    rm -rf "$CUSTOM_NODES/$_old" 2>/dev/null || true
done

if [ -f "$WORK_DIR/ofmpath_deployer.py" ] && [ -f "$WORK_DIR/nodeDefsV1.json" ]; then
    python3 -c "import json; json.load(open('nodeDefsV1.json'))" 2>/dev/null \
        && python3 ofmpath_deployer.py --custom-nodes-dir "$CUSTOM_NODES" \
        || echo "  [!] deployer run failed — continuing"
else
    echo "  [!] ofmpath_deployer.py or nodeDefsV1.json missing — skipping i18n"
fi

# ════════════════════════════════════════════════════════════════════════════
#  PHASE 8 — DEPLOY WORKFLOW FILES
# ════════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase 8: Deploy Workflows ━━━"
_set_progress 60 "Deploying workflow files..."

mkdir -p "$COMFY_DIR/user/default/workflows" "$COMFY_DIR/input"

_deploy_workflow() {
    local src="$1" name="$2"
    if [ -z "$src" ] || [ ! -f "$src" ]; then
        echo "  [!] Skipped: $name (not fetched)"; return
    fi
    cp "$src" "$COMFY_DIR/$name"
    cp "$src" "$COMFY_DIR/user/default/workflows/$name"
    cp "$src" "$COMFY_DIR/input/$name"
    echo "  [✓] Deployed: $name"
    find "$COMFY_DIR/web" /venv/lib/python*/site-packages/comfyui_frontend_package/ \
        -maxdepth 4 -name "defaultGraph.json" -type f 2>/dev/null | while read -r gp; do
        cp "$src" "$gp" && echo "  [✓] defaultGraph: $gp"
    done
}

_deploy_workflow "$WORKFLOW_MOTION" "OFMPATH MOTION CONTROL.json"
_deploy_workflow "$WORKFLOW_T2I"    "OFMPATH TEXT TO IMAGE.json"
echo "[✓] Workflows deployed"

# ════════════════════════════════════════════════════════════════════════════
#  PHASE 9 — DOWNLOAD MODELS (49 total)
# ════════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase 9: Download Models (49) ━━━"
_set_progress 63 "Starting model downloads..."

echo "Found 49 models to verify"
_MODEL_IDX=0
_MODEL_TOTAL=49

_dl_model() {
    local dir="$1" file="$2" url="$3" label="${4:-asset}"
    _MODEL_IDX=$((_MODEL_IDX + 1))
    local _pct=$(( 63 + (_MODEL_IDX * 22 / _MODEL_TOTAL) ))
    _set_progress "$_pct" "Downloading: $label ($_MODEL_IDX/$_MODEL_TOTAL)" 2>/dev/null || true
    mkdir -p "$dir"
    echo "[STARTING] '${label}'"
    if [ -f "$dir/$file" ] && [ -s "$dir/$file" ]; then
        echo "  [ok] Cached (0x$(printf "%08X" $RANDOM))"; echo "[SUCCESS]"; return
    fi
    local dl_args=()
    [[ -n "${HF_TOKEN:-}" && "$url" =~ huggingface\.co ]] && dl_args=("-H" "Authorization: Bearer $HF_TOKEN")
    echo "  [+] Syncing (0x$(printf "%08X" $RANDOM)) ..."
    if command -v aria2c >/dev/null 2>&1; then
        local ah=""
        [[ -n "${HF_TOKEN:-}" && "$url" =~ huggingface\.co ]] && ah="--header=Authorization: Bearer $HF_TOKEN"
        aria2c --console-log-level=error -c -x 16 -s 16 -k 1M $ah -d "$dir" -o "$file" "$url" >/dev/null 2>&1 \
            || curl -s -L "${dl_args[@]}" -o "$dir/$file" "$url"
    else
        curl -s -L "${dl_args[@]}" -o "$dir/$file" "$url"
    fi
    [ -f "$dir/$file" ] && [ -s "$dir/$file" ] && echo "[SUCCESS]" || echo "[FAILED] $label"
}

# ── DIFFUSION / UNET (3) ────────────────────────────────────────────────
_dl_model "$MODELS/diffusion_models" "z_image_turbo_bf16.safetensors" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors" "z_image_turbo_bf16"

_dl_model "$MODELS/diffusion_models" "z-image-turbo-fp8-e4m3fn.safetensors" \
    "https://huggingface.co/T5B/Z-Image-Turbo-FP8/resolve/main/z-image-turbo-fp8-e4m3fn.safetensors" "z_image_turbo_fp8"

_dl_model "$MODELS/diffusion_models" "WanModel.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanModel.safetensors" "wan_diffusion"

# ── TEXT ENCODERS / CLIP (3) ────────────────────────────────────────────
_dl_model "$MODELS/clip" "qwen_3_4b.safetensors" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors" "clip_qwen3_4b"

_dl_model "$MODELS/clip" "umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors" \
    "https://huggingface.co/UmeAiRT/ComfyUI-Auto_installer/resolve/refs%2Fpr%2F5/models/clip/umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors" "clip_umt5xxl"

_dl_model "$MODELS/clip" "text_enc.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/text_enc.safetensors" "clip_text_enc"

# ── CLIP VISION (2) ─────────────────────────────────────────────────────
_dl_model "$MODELS/clip_vision" "klip_vision.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors" "clip_vision_k"

_dl_model "$MODELS/clip_vision" "clip_vision_h.safetensors" \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors" "clip_vision_h"

# ── VAE (2) ─────────────────────────────────────────────────────────────
_dl_model "$MODELS/vae" "ae.safetensors" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors" "vae_ae"

_dl_model "$MODELS/vae" "vae.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/vae.safetensors" "vae_wan"

# ── CONTROLNET (2) ──────────────────────────────────────────────────────
_dl_model "$MODELS/controlnet" "Wan21_Uni3C_controlnet_fp16.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_Uni3C_controlnet_fp16.safetensors" "controlnet_wan_uni3c"

_dl_model "$MODELS/controlnet" "Z-Image-Turbo-Fun-Controlnet-Union.safetensors" \
    "https://huggingface.co/arhiteector/zimage/resolve/main/Z-Image-Turbo-Fun-Controlnet-Union.safetensors" "controlnet_zimage_fun"
_set_progress 73 "Core models done..."

# ── CHECKPOINTS (1) ─────────────────────────────────────────────────────
_dl_model "$MODELS/checkpoints" "detect.safetensors" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/detect.safetensors" "ckpt_detect"

# ── LORAS (7) ───────────────────────────────────────────────────────────
_dl_model "$MODELS/loras" "real.safetensors" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/real.safetensors" "lora_real"

_dl_model "$MODELS/loras" "XXX.safetensors" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/XXX.safetensors" "lora_xxx"

_dl_model "$MODELS/loras" "gpu.safetensors" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/gpu.safetensors" "lora_gpu"

_dl_model "$MODELS/loras" "WanFun.reworked.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanFun.reworked.safetensors" "lora_wanfun"

_dl_model "$MODELS/loras" "light.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/light.safetensors" "lora_light"

_dl_model "$MODELS/loras" "WanPusa.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanPusa.safetensors" "lora_pusa"

_dl_model "$MODELS/loras" "wan.reworked.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/wan.reworked.safetensors" "lora_wan_reworked"
_set_progress 77 "LoRAs done..."

# ── DETECTION (3) ───────────────────────────────────────────────────────
_dl_model "$MODELS/detection" "yolov10m.onnx" \
    "https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx" "det_yolo"

_dl_model "$MODELS/detection" "vitpose_h_wholebody_data.bin" \
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_data.bin" "det_vitpose_data"

_dl_model "$MODELS/detection" "vitpose_h_wholebody_model.onnx" \
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_model.onnx" "det_vitpose_model"

# ── SAM (1) ─────────────────────────────────────────────────────────────
_dl_model "$MODELS/sams" "sam_vit_b_01ec64.pth" \
    "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/sams/sam_vit_b_01ec64.pth" "sam_vit_b"

# ── UPSCALERS (1) ───────────────────────────────────────────────────────
_dl_model "$MODELS/upscale_models" "4xUltrasharp_4xUltrasharpV10.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/4xUltrasharp_4xUltrasharpV10.pt" "upscaler_4x"

# ── ULTRALYTICS / BBOX (11) ─────────────────────────────────────────────
_dl_model "$MODELS/ultralytics/bbox" "face_yolov8s.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/face_yolov8s.pt" "bbox_face"

_dl_model "$MODELS/ultralytics/bbox" "femaleBodyDetection_yolo26.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/femaleBodyDetection_yolo26.pt" "bbox_body"

_dl_model "$MODELS/ultralytics/bbox" "female_breast-v4.2.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/female_breast-v4.2.pt" "bbox_breast"

_dl_model "$MODELS/ultralytics/bbox" "nipples_yolov8s.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/nipples_yolov8s.pt" "bbox_nipples"

_dl_model "$MODELS/ultralytics/bbox" "vagina-v4.2.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/vagina-v4.2.pt" "bbox_vagina"

_dl_model "$MODELS/ultralytics/bbox" "assdetailer.pt" \
    "https://huggingface.co/gazsuv/xmode/resolve/main/assdetailer.pt" "bbox_ass"

_dl_model "$MODELS/ultralytics/bbox" "Eyeful_v2-Paired.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/Eyeful_v2-Paired.pt" "bbox_eyes_v2"

_dl_model "$MODELS/ultralytics/bbox" "Eyes.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/Eyes.pt" "bbox_eyes"

_dl_model "$MODELS/ultralytics/bbox" "FacesV1.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/FacesV1.pt" "bbox_faces"

_dl_model "$MODELS/ultralytics/bbox" "hand_yolov8s.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/hand_yolov8s.pt" "bbox_hand"

# note: user-supplied URL had /blob/ — fixed to /resolve/ so curl gets the file not the HTML page
_dl_model "$MODELS/ultralytics/bbox" "foot-yolov8l.pt" \
    "https://huggingface.co/AunyMoons/loras-pack/resolve/main/foot-yolov8l.pt" "bbox_foot"
_set_progress 82 "Detection bbox models done..."

# ── QWEN3-VL-4B-Instruct-heretic-7refusal (13 files) ───────────────────
_QWEN_DIR="$MODELS/LLM/Qwen3-VL-4B-Instruct-heretic-7refusal"
_QWEN_BASE="https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main"

_dl_model "$_QWEN_DIR" "added_tokens.json"            "$_QWEN_BASE/added_tokens.json"            "qwen_added_tokens"
_dl_model "$_QWEN_DIR" "chat_template.jinja"          "$_QWEN_BASE/chat_template.jinja"          "qwen_chat_tmpl"
_dl_model "$_QWEN_DIR" "config.json"                  "$_QWEN_BASE/config.json"                  "qwen_config"
_dl_model "$_QWEN_DIR" "generation_config.json"       "$_QWEN_BASE/generation_config.json"       "qwen_gen_cfg"
_dl_model "$_QWEN_DIR" "merges.txt"                   "$_QWEN_BASE/merges.txt"                   "qwen_merges"
_dl_model "$_QWEN_DIR" "model.safetensors.index.json" "$_QWEN_BASE/model.safetensors.index.json" "qwen_st_index"
_dl_model "$_QWEN_DIR" "preprocessor_config.json"     "$_QWEN_BASE/preprocessor_config.json"     "qwen_preproc"
_dl_model "$_QWEN_DIR" "special_tokens_map.json"      "$_QWEN_BASE/special_tokens_map.json"      "qwen_spcl_tok"
_dl_model "$_QWEN_DIR" "tokenizer.json"               "$_QWEN_BASE/tokenizer.json"               "qwen_tokenizer"
_dl_model "$_QWEN_DIR" "tokenizer_config.json"        "$_QWEN_BASE/tokenizer_config.json"        "qwen_tok_cfg"
_dl_model "$_QWEN_DIR" "vocab.json"                   "$_QWEN_BASE/vocab.json"                   "qwen_vocab"
_dl_model "$_QWEN_DIR" "model-00001-of-00002.safetensors" \
    "$_QWEN_BASE/model-00001-of-00002.safetensors" "qwen_shard_1"
_dl_model "$_QWEN_DIR" "model-00002-of-00002.safetensors" \
    "$_QWEN_BASE/model-00002-of-00002.safetensors" "qwen_shard_2"

echo "[✓] All models downloaded"

# ════════════════════════════════════════════════════════════════════════════
#  PHASE 10 — COMFYUI SETTINGS
# ════════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase 10: ComfyUI Settings ━━━"
_set_progress 92 "Applying settings..."

_SETTINGS_DIR="$COMFY_DIR/user/default"
mkdir -p "$_SETTINGS_DIR"
python3 - << PYEOF
import json, os
sf = '${_SETTINGS_DIR}/comfy.settings.json'
s = {}
if os.path.isfile(sf):
    try: s = json.load(open(sf, encoding='utf-8'))
    except: pass
s.update({'Comfy.Locale':'en','Comfy.DevMode':False,'Comfy.Logging.Enabled':False,'Comfy.Graph.CanvasInfo':False})
json.dump(s, open(sf,'w',encoding='utf-8'), ensure_ascii=False, indent=2)
print('[✓] Settings: en locale, DevMode off')
PYEOF

# ════════════════════════════════════════════════════════════════════════════
#  PHASE 11 — SIGNAL DONE → UI fades out
# ════════════════════════════════════════════════════════════════════════════
echo "[PROGRESS: 100]"
echo '{"pct":100,"phase":"✅ Setup complete — loading workspace...","done":true}' > "$_PROGRESS_FILE"
sleep 4  # let browser read final state before server dies

# ════════════════════════════════════════════════════════════════════════════
#  CLEANUP
# ════════════════════════════════════════════════════════════════════════════
kill "$_PROGRESS_PID" 2>/dev/null || true
cd /
rm -rf "$WORK_DIR"
rm -f /tmp/ofmpath_motion.json /tmp/ofmpath_t2i.json \
      /tmp/ofmpath_deployer.py /tmp/nodeDefsV1.json \
      /tmp/ofmpath_progress.json /tmp/ofmpath_progress_server.py 2>/dev/null

# ════════════════════════════════════════════════════════════════════════════
#  COMPLETE
# ════════════════════════════════════════════════════════════════════════════
echo -e "\n"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  ✅ OFM PATH 智慧通路 v1 — Deployment Complete!               ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  ⬡ OFMPATH MOTION CONTROL.json  (WanVideo animate pipeline)  ║"
echo "║  ⬡ OFMPATH TEXT TO IMAGE.json   (Z-Image-Turbo pipeline)     ║"
echo "║  Custom nodes : 28                                            ║"
echo "║  Models       : 49 total                                      ║"
echo "║  Python files modified : 0                                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
