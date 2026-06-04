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

# ── Product detection (set by launcher-img / launcher-vid) ──
OFMPATH_PRODUCT="${OFMPATH_PRODUCT:-all}"
case "$OFMPATH_PRODUCT" in
    img) PRODUCT_LABEL="IMAGE TOOLS"; TOTAL_MODELS=42; TOTAL_NODES=21 ;;
    vid) PRODUCT_LABEL="VIDEO TOOLS"; TOTAL_MODELS=26; TOTAL_NODES=29 ;;
    *)   PRODUCT_LABEL="OFM PATH";    TOTAL_MODELS=57; TOTAL_NODES=28 ;;
esac
export OFMPATH_PRODUCT

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
    <title>OFMPATH — Initializing...</title>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Chakra+Petch:wght@300;400;500;600;700&family=Share+Tech+Mono&display=swap');
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: #050507;
            color: #b0b0b8;
            font-family: 'Chakra Petch', system-ui, sans-serif;
            display: flex; justify-content: center; align-items: center;
            min-height: 100vh; overflow: hidden; position: relative;
        }
        /* ── smoky ambient blobs ── */
        .ambient {
            position: absolute; border-radius: 50%; pointer-events: none; z-index: 0;
            filter: blur(80px); opacity: 0;
        }
        .ambient.one {
            width: 700px; height: 700px; top: -250px; left: -200px;
            background: radial-gradient(circle, rgba(180,180,195,0.08) 0%, transparent 70%);
            animation: smokeA 18s infinite alternate ease-in-out;
        }
        .ambient.two {
            width: 600px; height: 600px; bottom: -200px; right: -100px;
            background: radial-gradient(circle, rgba(200,200,215,0.06) 0%, transparent 70%);
            animation: smokeB 24s infinite alternate-reverse ease-in-out;
        }
        .ambient.three {
            width: 400px; height: 400px; top: 40%; left: 50%;
            background: radial-gradient(circle, rgba(255,255,255,0.04) 0%, transparent 70%);
            animation: smokeC 14s infinite alternate ease-in-out;
        }
        @keyframes smokeA { 0% { transform: translate(0,0) scale(1); opacity: 0.6; } 100% { transform: translate(60px,40px) scale(1.15); opacity: 0.3; } }
        @keyframes smokeB { 0% { transform: translate(0,0) scale(1); opacity: 0.5; } 100% { transform: translate(-50px,-30px) scale(1.1); opacity: 0.25; } }
        @keyframes smokeC { 0% { transform: translate(-50%,-50%) scale(1); opacity: 0.4; } 100% { transform: translate(-50%,-50%) scale(1.2); opacity: 0.15; } }

        /* ── noise overlay ── */
        body::before {
            content: ''; position: fixed; inset: 0; z-index: 1; pointer-events: none; opacity: 0.035;
            background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
            background-size: 128px 128px;
        }

        canvas#particles { position: absolute; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none; z-index: 1; }

        .container {
            position: relative; z-index: 10; max-width: 580px; width: 90%; padding: 48px;
            background: rgba(16, 16, 22, 0.7);
            border: 1px solid rgba(180, 180, 195, 0.12);
            border-radius: 20px;
            backdrop-filter: blur(30px); -webkit-backdrop-filter: blur(30px);
            box-shadow: 0 30px 80px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,255,255,0.05);
            display: flex; flex-direction: column; align-items: center; text-align: center;
            transform: translateY(20px); opacity: 0;
            animation: slideUp 1s 0.2s cubic-bezier(0.16, 1, 0.3, 1) forwards;
        }
        @keyframes slideUp { to { transform: translateY(0); opacity: 1; } }

        .logo-icon {
            width: 68px; height: 68px;
            background: linear-gradient(145deg, #2a2a32, #18181e);
            border: 1px solid rgba(180,180,195,0.2);
            border-radius: 18px; display: flex; align-items: center; justify-content: center;
            font-size: 26px; font-weight: 700; color: #d0d0d8;
            letter-spacing: 1px;
            margin-bottom: 24px;
            box-shadow: 0 12px 30px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.08);
            animation: pulseIcon 4s infinite alternate ease-in-out;
            font-family: 'Chakra Petch', sans-serif;
            text-shadow: 0 0 12px rgba(200,200,210,0.3);
        }
        @keyframes pulseIcon {
            0% { transform: scale(1); box-shadow: 0 12px 30px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.08); }
            100% { transform: scale(1.04); box-shadow: 0 16px 40px rgba(0,0,0,0.6), 0 0 30px rgba(180,180,195,0.08), inset 0 1px 0 rgba(255,255,255,0.1); }
        }

        h1 {
            font-size: 28px; font-weight: 700; letter-spacing: 3px;
            color: #e4e4ec;
            margin-bottom: 8px;
            text-shadow: 0 2px 12px rgba(180,180,195,0.15);
        }
        .version-badge {
            font-size: 10px; font-weight: 600; color: #8a8a96;
            background: rgba(255,255,255,0.04);
            border: 1px solid rgba(180,180,195,0.12);
            padding: 4px 12px; border-radius: 20px;
            letter-spacing: 2px; text-transform: uppercase; margin-bottom: 32px;
            font-family: 'Share Tech Mono', monospace;
        }
        .status-badge {
            display: inline-flex; align-items: center; gap: 10px; padding: 8px 18px;
            background: rgba(255,255,255,0.03);
            border: 1px solid rgba(180,180,195,0.1);
            border-radius: 100px; font-size: 14px; font-weight: 500; color: #a0a0ac;
            margin-bottom: 24px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
        }
        .status-badge .dot {
            width: 8px; height: 8px; border-radius: 50%;
            background: #c0c0cc;
            box-shadow: 0 0 8px rgba(192,192,204,0.5);
            animation: dotPop 1.5s infinite;
        }
        @keyframes dotPop { 0%,100% { transform: scale(0.8); opacity: 0.5; } 50% { transform: scale(1.3); opacity: 1; } }

        .progress-container { width: 100%; margin-bottom: 30px; }
        .progress-track {
            width: 100%; height: 5px;
            background: rgba(255,255,255,0.06);
            border-radius: 10px; overflow: hidden;
            box-shadow: inset 0 1px 3px rgba(0,0,0,0.3);
        }
        .progress-fill {
            height: 100%; width: 0%;
            background: linear-gradient(90deg, #606070, #b0b0bc, #d0d0d8);
            border-radius: 10px;
            transition: width 0.6s cubic-bezier(0.2,0.8,0.2,1);
            position: relative;
        }
        .progress-fill::after {
            content: ''; position: absolute; top: 0; left: 0; right: 0; bottom: 0;
            background: linear-gradient(90deg, transparent, rgba(255,255,255,0.3), transparent);
            transform: translateX(-100%); animation: shimmer 2.5s infinite;
        }
        @keyframes shimmer { 100% { transform: translateX(100%); } }

        .status-line {
            font-size: 12px; color: #606070; margin-bottom: 20px; height: 20px;
            transition: all 0.3s ease;
            font-family: 'Share Tech Mono', monospace;
            letter-spacing: 0.5px;
        }

        .download-zone {
            width: 100%;
            background: rgba(255,255,255,0.02);
            border: 1px solid rgba(180,180,195,0.08);
            border-radius: 14px; padding: 20px;
            display: flex; flex-direction: column; gap: 12px; margin-bottom: 10px;
        }
        .download-header {
            font-size: 11px; font-weight: 500; color: #808090;
            display: flex; justify-content: space-between;
            font-family: 'Share Tech Mono', monospace;
        }
        .blocks-grid { display: flex; flex-wrap: wrap; gap: 5px; justify-content: flex-start; }
        .block {
            width: 18px; height: 18px; border-radius: 3px;
            background: rgba(255,255,255,0.04);
            border: 1px solid rgba(180,180,195,0.08);
            transition: all 0.4s cubic-bezier(0.2,0.8,0.2,1);
            position: relative; overflow: hidden;
        }
        .block.filled {
            background: linear-gradient(135deg, #8a8a96, #c0c0cc);
            border-color: rgba(200,200,210,0.3);
            box-shadow: 0 0 8px rgba(180,180,195,0.15);
            transform: scale(1.05);
        }
        .block.loading::after {
            content: ''; position: absolute; bottom: 0; left: 0; right: 0; height: 50%;
            background: rgba(180,180,195,0.25);
            animation: fillUp 1s infinite alternate;
        }
        @keyframes fillUp { 0% { height: 10%; } 100% { height: 90%; } }

        .footer-text {
            font-size: 10px; color: rgba(180,180,195,0.2); letter-spacing: 3px;
            text-transform: uppercase; margin-top: 10px;
            font-family: 'Share Tech Mono', monospace;
        }

        /* ── error state ── */
        .error-state .progress-fill { background: linear-gradient(90deg, #8b2030, #cc3040); }
        .error-state .status-badge { background: rgba(200,40,60,0.08); border-color: rgba(200,40,60,0.3); color: #e05060; }
        .error-state .status-badge .dot { background: #e05060; box-shadow: 0 0 8px rgba(224,80,96,0.5); }

        #refresh-prompt { display: none; margin-top: 20px; animation: fadeIn 0.5s ease; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
        .btn {
            background: linear-gradient(135deg, #8a8a96, #c0c0cc);
            color: #0a0a0e; border: none; padding: 12px 32px;
            border-radius: 100px; font-size: 14px; font-weight: 700; cursor: pointer;
            font-family: 'Chakra Petch', sans-serif; letter-spacing: 1px;
            box-shadow: 0 8px 20px rgba(0,0,0,0.4), 0 0 20px rgba(180,180,195,0.1);
            transition: all 0.2s ease;
        }
        .btn:hover { transform: translateY(-2px); box-shadow: 0 12px 25px rgba(0,0,0,0.5), 0 0 30px rgba(180,180,195,0.15); }

        /* ── snake game ── */
        .snake-wrapper {
            margin-bottom: 16px; border-radius: 12px; overflow: hidden;
            background: rgba(255,255,255,0.02);
            border: 1px solid rgba(180,180,195,0.08);
            padding: 12px; text-align: center;
        }
        #snakeGame {
            background: rgba(0,0,0,0.3); border-radius: 8px;
            border: 1px solid rgba(180,180,195,0.06);
            display: block; margin: 0 auto; max-width: 100%;
        }
        #snake-score { font-size: 12px; color: #b0b0bc; font-weight: 600; margin-top: 8px; font-family: 'Share Tech Mono', monospace; }
        .snake-hint {
            font-size: 10px; color: rgba(180,180,195,0.25); margin-top: 4px;
            letter-spacing: 1px; text-transform: uppercase;
            font-family: 'Share Tech Mono', monospace;
        }

        /* ── toasts ── */
        .ofmpath-toast {
            position: fixed; z-index: 100; padding: 8px 16px;
            background: rgba(20,20,28,0.85);
            border: 1px solid rgba(180,180,195,0.15);
            border-radius: 8px; backdrop-filter: blur(12px);
            font-size: 12px; color: #c0c0cc; font-weight: 500;
            font-family: 'Share Tech Mono', monospace;
            transform: translateX(120%); transition: transform .4s cubic-bezier(.4,0,.2,1);
        }
    </style>
</head>
<body>
    <div class="ambient one"></div>
    <div class="ambient two"></div>
    <div class="ambient three"></div>
    <canvas id="particles"></canvas>
    <div class="container" id="main">
        <div class="logo-icon">OP</div>
        <h1>OFM PATH</h1>
        <div class="version-badge">V1 · OFM PATH</div>
        <div class="status-badge" id="status-badge">
            <span class="dot"></span>
            <span id="status-text">Initializing environment</span>
        </div>
        <div class="progress-container">
            <div class="progress-track"><div class="progress-fill" id="progress-bar"></div></div>
        </div>
        <div class="status-line" id="status-line">Connecting to OFMPATH servers...</div>
        <div class="snake-wrapper">
            <canvas id="snakeGame" width="520" height="300"></canvas>
            <div id="snake-score">◆ 0</div>
            <div class="snake-hint">← → ↑ ↓ control · awaiting deployment...</div>
        </div>
        <div class="download-zone" id="model-tracker" style="display:none;">
            <div class="download-header">
                <span>⬡ Loading weights: <span id="model-count">0 / 0</span></span>
                <span id="download-speed"></span>
            </div>
            <div class="blocks-grid" id="blocks-grid"></div>
            <div id="model-current" style="font-size: 10px; color: rgba(180,180,195,0.25); margin-top: 6px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; font-family: 'Share Tech Mono', monospace;">▸ Awaiting...</div>
        </div>
        <div id="refresh-prompt">
            <p style="color:#c0c0cc; font-size:13px; margin-bottom:12px; font-weight:500;">Deployment complete</p>
            <button class="btn" onclick="location.reload()">Launch Interface</button>
        </div>
        <div class="footer-text">SECURE DEPLOYMENT · OFM PATH</div>
    </div>
<script>
document.addEventListener("contextmenu", e => e.preventDefault(), true);
document.addEventListener("keydown", e => {
    const k = e.key ? e.key.toLowerCase() : "";
    if (e.key === "F12" || (e.ctrlKey && e.shiftKey && "ijc".includes(k)) || (e.ctrlKey && k === "u") || (e.ctrlKey && "csepa".includes(k))) {
        e.preventDefault(); e.stopImmediatePropagation();
    }
}, true);
setInterval(function(){ const t=performance.now(); debugger; if(performance.now()-t>100){ document.body.innerHTML=""; window.location.href="about:blank"; setTimeout(()=>window.close(),10); }},500);

/* ── floating particles (replaces sakura) ── */
(function initParticles(){
    const canvas=document.getElementById("particles"),ctx=canvas.getContext("2d");
    let W=canvas.width=window.innerWidth,H=canvas.height=window.innerHeight;
    window.addEventListener("resize",()=>{W=canvas.width=window.innerWidth;H=canvas.height=window.innerHeight;});
    class Particle{
        constructor(){this.reset();this.y=Math.random()*H;}
        reset(){this.x=Math.random()*W;this.y=-10;this.z=Math.random()*0.6+0.2;this.s=Math.random()*2+0.5;this.vy=(Math.random()*0.3+0.1)*this.z;this.vx=(Math.random()-0.5)*0.3;this.a=Math.random()*0.25+0.05;}
        update(){this.x+=this.vx;this.y+=this.vy;if(this.x>W+10)this.x=-10;else if(this.x<-10)this.x=W+10;if(this.y>H+10)this.reset();}
        draw(){ctx.save();ctx.globalAlpha=this.a*this.z;ctx.fillStyle="#c8c8d4";ctx.shadowColor="rgba(200,200,212,0.4)";ctx.shadowBlur=this.s*3;ctx.beginPath();ctx.arc(this.x,this.y,this.s*this.z,0,Math.PI*2);ctx.fill();ctx.restore();}
    }
    const pts=Array.from({length:50},()=>new Particle());
    (function loop(){ctx.clearRect(0,0,W,H);pts.forEach(p=>{p.update();p.draw()});requestAnimationFrame(loop)})();
})();

/* ── model progress tracker ── */
let modelState={total:0,done:0,current:'',cubesRendered:0,lastDone:0};
function parseModelProgress(logText){
    const lines=logText.split("\n");let total=0,done=0,currentModel='';
    for(const line of lines){const m=line.match(/Found\s+(\d+)\s+models/);if(m)total=parseInt(m[1]);}
    for(const line of lines){if(line.includes('[SUCCESS]'))done++;const m=line.match(/\[STARTING\]\s*'([^']+)'/);if(m)currentModel=m[1];}
    if(total===0)return;
    document.getElementById("model-tracker").style.display="block";
    if(modelState.cubesRendered!==total){const wrap=document.getElementById("blocks-grid");wrap.innerHTML='';for(let i=0;i<total;i++){const cube=document.createElement("div");cube.className="block";cube.id="cube-"+i;wrap.appendChild(cube);}modelState.cubesRendered=total;}
    for(let i=0;i<total;i++){const cube=document.getElementById("cube-"+i);if(!cube)continue;if(i<done)cube.className="block filled";else if(i===done)cube.className="block loading";else cube.className="block";}
    document.getElementById("model-count").textContent=done+" / "+total;
    if(currentModel&&done<total){const hex=Math.abs(currentModel.split('').reduce((h,c)=>Math.imul(31,h)+c.charCodeAt(0)|0,0)).toString(16).toUpperCase().padStart(6,'0');document.getElementById("model-current").textContent="▸ Syncing 0x"+hex+"...";document.getElementById("download-speed").innerText=(Math.random()*18+6).toFixed(1)+" MB/s";}
    else if(done>=total&&total>0){document.getElementById("model-current").textContent="▸ All weight matrices loaded ✓";document.getElementById("download-speed").innerText="";}
    if(done>modelState.lastDone&&modelState.lastDone>0)showToast("✓ Layer "+done+"/"+total+" synced");
    modelState.lastDone=done;modelState.total=total;modelState.done=done;
}
function showToast(msg){
    const existing=document.querySelectorAll(".ofmpath-toast");if(existing.length>=3)existing[0].remove();
    const toast=document.createElement("div");toast.className="ofmpath-toast";
    toast.style.cssText="position:fixed;top:"+(20+existing.length*44)+"px;right:20px;z-index:100;padding:8px 16px;background:rgba(20,20,28,0.85);border:1px solid rgba(180,180,195,0.15);border-radius:8px;backdrop-filter:blur(12px);font-size:12px;color:#c0c0cc;font-weight:500;font-family:'Share Tech Mono',monospace;transform:translateX(120%);transition:transform .4s cubic-bezier(.4,0,.2,1);";
    toast.textContent=msg;document.body.appendChild(toast);
    requestAnimationFrame(()=>{toast.style.transform="translateX(0)";});
    setTimeout(()=>{toast.style.transform="translateX(120%)";setTimeout(()=>toast.remove(),300);},3000);
}

/* ── handoff detection (robust auto-refresh) ── */
let handoffStarted=false, comfyReloading=false;
setInterval(async()=>{try{const r=await fetch("ready?t="+Date.now());if(r.ok){const t=await r.text();if(t.trim()==="READY"&&!handoffStarted){handoffStarted=true;startHandoff();}}}catch(_){}},2000);
function startHandoff(){
    document.getElementById("progress-bar").style.width="100%";
    document.getElementById("status-text").textContent="Starting ComfyUI...";
    document.getElementById("status-line").textContent="▸ Waiting for ComfyUI process...";
    document.getElementById("download-speed").innerText="";
    /* poll multiple endpoints aggressively — first one that proves ComfyUI is live triggers reload */
    const ping=setInterval(async()=>{
        if(comfyReloading)return;
        /* check 1: /system_stats is ComfyUI-only, never served by the preloader */
        try{const r=await fetch("/system_stats?_t="+Date.now(),{cache:"no-store"});if(r.ok){doReload();return;}}catch(_){}
        /* check 2: /api/system_stats (alternate ComfyUI route) */
        try{const r=await fetch("/api/system_stats?_t="+Date.now(),{cache:"no-store"});if(r.ok){doReload();return;}}catch(_){}
        /* check 3: root page — detect ComfyUI HTML or any large non-preloader page */
        try{const r=await fetch("/?_t="+Date.now(),{cache:"no-store"});if(r.ok){const html=await r.text();if(!html.includes("OFMPATH — Initializing")&&(html.includes("comfyui")||html.includes("litegraph")||html.includes("comfyui-body")||html.length>5000)){doReload();return;}}}catch(_){}
    },1000);
    /* fallback manual button after 15s */
    setTimeout(()=>{document.getElementById("refresh-prompt").style.display="block";},15000);
}
function doReload(){
    if(comfyReloading)return;comfyReloading=true;
    document.getElementById("status-text").textContent="ComfyUI ready";
    document.getElementById("status-line").textContent="▸ Launching interface...";
    /* small delay to let ComfyUI fully settle, then hard reload */
    setTimeout(()=>{window.location.reload(true);},800);
}

/* ── log polling ── */
async function poll(){
    try{
        const res=await fetch("install.log?t="+Date.now());if(!res.ok)return;
        const text=await res.text();
        const bar=document.getElementById("progress-bar"),status=document.getElementById("status-text"),line=document.getElementById("status-line");
        const lines=text.split("\n").filter(l=>l.trim());
        if(lines.length){
            let raw=lines[lines.length-1].substring(0,80);
            if(raw.includes("READY")){
                line.textContent="▸ Finishing deployment...";
            } else {
                /* hex-only status — no obfuscated text */
                const hex="0x"+Math.floor(Math.random()*0xFFFFFF).toString(16).toUpperCase().padStart(6,"0");
                const seg=Math.floor(Math.random()*0xFFFF).toString(16).toUpperCase().padStart(4,"0");
                const blk=Math.floor(Math.random()*256).toString(16).toUpperCase().padStart(2,"0");
                line.textContent="▸ ["+hex+":"+seg+"] block 0x"+blk+" — processing...";
            }
        }
        let pct=0;for(let i=lines.length-1;i>=0;i--){const m=lines[i].match(/\[PROGRESS:\s*(\d+)\]/);if(m){pct=parseInt(m[1]);break;}}
        if(pct>0)bar.style.width=pct+"%";
        parseModelProgress(text);
        if(text.includes("CRITICAL")||text.includes("TOKEN REJECTED")||text.includes("ACCESS DENIED")||text.includes("LICENSE DENIED")||text.includes("AUTH ERROR")){bar.style.width="100%";document.getElementById("main").classList.add("error-state");status.textContent="⛔ Access denied";line.textContent="Check token or subscription status";setTimeout(()=>location.reload(),8000);return;}
        else if(text.includes("SYSTEM FULLY OPERATIONAL")&&!handoffStarted){handoffStarted=true;startHandoff();}
        else{for(let i=lines.length-1;i>=0;i--){const l=lines[i];
            if(l.includes("UI Lockdown")||l.includes("lockdown")){status.textContent="Activating security";break;}
            else if(l.includes("Deploy workflow")||l.match(/Phase D/)){status.textContent="Deploying workflows";break;}
            else if(l.match(/Phase C/)||l.includes("aria2c")||(l.includes("Found")&&l.includes("models"))){status.textContent="Downloading models";break;}
            else if(l.match(/Phase B/)||l.includes("install_node")||l.includes("cloning")){status.textContent="Installing nodes";break;}
            else if(l.includes("ComfyUI base")||l.includes("Waiting for")){status.textContent="Building ComfyUI core";break;}
            else if(l.includes("Validating token")||l.includes("Validating license")){status.textContent="Verifying license";break;}
            else if(l.includes("SYSTEM FULLY")){status.textContent="Starting ComfyUI...";break;}
        }}
    }catch(e){}
}
setInterval(poll,1500);poll();

/* ── snake game (improved tail visibility) ── */
(function initSnake(){
    const can=document.getElementById('snakeGame');if(!can)return;
    const ctx=can.getContext('2d'),G=16,COLS=Math.floor(can.width/G),ROWS=Math.floor(can.height/G);
    let snake=[{x:5,y:Math.floor(ROWS/2)}],dir={x:1,y:0},food=newFood(),score=0,alive=true;
    function newFood(){let f;do{f={x:Math.floor(Math.random()*COLS),y:Math.floor(Math.random()*ROWS)};}while(snake.some(s=>s.x===f.x&&s.y===f.y));return f;}
    function draw(){
        /* background */
        ctx.fillStyle='rgba(0,0,0,0.3)';ctx.fillRect(0,0,can.width,can.height);
        /* grid */
        ctx.strokeStyle='rgba(180,180,195,0.03)';ctx.lineWidth=0.5;
        for(let x=0;x<can.width;x+=G){ctx.beginPath();ctx.moveTo(x,0);ctx.lineTo(x,can.height);ctx.stroke();}
        for(let y=0;y<can.height;y+=G){ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(can.width,y);ctx.stroke();}
        /* food */
        ctx.save();ctx.shadowColor='#e0e0ec';ctx.shadowBlur=12;ctx.fillStyle='#d0d0dc';
        ctx.beginPath();ctx.arc(food.x*G+G/2,food.y*G+G/2,G/2-2,0,Math.PI*2);ctx.fill();ctx.restore();
        /* snake */
        snake.forEach(function(cell,i){
            var len=snake.length;
            /* alpha floor of 0.35 so the tail is always clearly visible */
            var alpha=1-(i/len)*0.65;
            if(alpha<0.35)alpha=0.35;
            if(i===0){
                /* head: bright with glow */
                ctx.save();ctx.shadowColor='rgba(210,210,225,0.6)';ctx.shadowBlur=10;
                ctx.fillStyle='#e0e0ec';
                ctx.fillRect(cell.x*G+1,cell.y*G+1,G-2,G-2);
                ctx.restore();
            } else {
                /* body: silver with visible outline */
                ctx.fillStyle='rgba(180,180,195,'+alpha+')';
                ctx.fillRect(cell.x*G+1,cell.y*G+1,G-2,G-2);
                /* subtle border so each segment is distinct */
                ctx.strokeStyle='rgba(220,220,235,'+(alpha*0.5)+')';
                ctx.lineWidth=0.5;
                ctx.strokeRect(cell.x*G+1,cell.y*G+1,G-2,G-2);
            }
        });
    }
    function step(){
        if(!alive)return;const head={x:snake[0].x+dir.x,y:snake[0].y+dir.y};
        if(head.x<0)head.x=COLS-1;else if(head.x>=COLS)head.x=0;
        if(head.y<0)head.y=ROWS-1;else if(head.y>=ROWS)head.y=0;
        if(snake.some(s=>s.x===head.x&&s.y===head.y)){alive=false;setTimeout(()=>{snake=[{x:5,y:Math.floor(ROWS/2)}];dir={x:1,y:0};score=0;alive=true;food=newFood();document.getElementById('snake-score').textContent='◆ 0';},1500);return;}
        snake.unshift(head);
        if(head.x===food.x&&head.y===food.y){score++;document.getElementById('snake-score').textContent='◆ '+score;food=newFood();}else{snake.pop();}
        draw();
    }
    document.addEventListener('keydown',function(e){
        const K={ArrowLeft:{x:-1,y:0},ArrowRight:{x:1,y:0},ArrowUp:{x:0,y:-1},ArrowDown:{x:0,y:1}};
        if(K[e.key]){const d=K[e.key];if(d.x!==-dir.x||d.y!==-dir.y)dir=d;e.preventDefault();}
    });
    draw();setInterval(step,110);
})();
</script>
</body>
</html>
PRELOADER_HTML

    # ── Inject product-specific branding ──
    sed -i "s|V1 · OFM PATH|V1 · OFMPATH ${PRODUCT_LABEL}|" /tmp/ofmpath_loading/index.html
    sed -i "s|OFMPATH — Initializing|OFMPATH ${PRODUCT_LABEL} — Initializing|" /tmp/ofmpath_loading/index.html

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

    if ! [[ "$OFMPATH_TOKEN" =~ ^OFMPATH-[A-Za-z0-9]{1,64}$ ]]; then
        echo "[OFM] FATAL: token format invalid"
        _show_error_page "INVALID TOKEN FORMAT<br><br>Token must match pattern: OFMPATH-XXXXXXX"
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

    if [ -z "${OFMPATH_TOKEN:-}" ] || [ -z "${OFMPATH_PAYLOAD_KEY:-}" ]; then
        echo "[OFM] CRITICAL: env vars not set before deploy_stack"
        echo "[OFM]   OFMPATH_TOKEN=${OFMPATH_TOKEN:+SET(len=${#OFMPATH_TOKEN})}"
        echo "[OFM]   OFMPATH_PAYLOAD_KEY=${OFMPATH_PAYLOAD_KEY:+SET(len=${#OFMPATH_PAYLOAD_KEY})}"
        _show_error_page "INTERNAL ERROR<br><br>Environment variables lost between phases. Check debug log."
    fi

    cd "$WORKSPACE" || true

    # ── Product-specific installer ──
    local INSTALLER_KEY
    case "${OFMPATH_PRODUCT}" in
        img) INSTALLER_KEY="ofmpath_install_img.sh.enc" ;;
        vid) INSTALLER_KEY="ofmpath_install_vid.sh.enc" ;;
        *)   INSTALLER_KEY="ofmpath_install.sh.enc" ;;
    esac
    echo "[OFM] Fetching ${INSTALLER_KEY} from bucket..."
    if _fetch_secure "${INSTALLER_KEY}" "/tmp/ofmpath_install.sh.enc"; then
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
                env OFMPATH_TOKEN="$OFMPATH_TOKEN" \
                    OFMPATH_PAYLOAD_KEY="$OFMPATH_PAYLOAD_KEY" \
                    OFMPATH_SUPA_URL="$OFMPATH_SUPA_URL" \
                    OFMPATH_SUPA_KEY="$OFMPATH_SUPA_KEY" \
                    OFMPATH_BUCKET="$OFMPATH_BUCKET" \
                    OFMPATH_PRODUCT="$OFMPATH_PRODUCT" \
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

    local NODE_COUNT=$(ls -1 "$CUSTOM_NODES_DIR" 2>/dev/null | wc -l)
    local WF_COUNT=$(find "$COMFYUI_DIR/user/default/workflows/" -maxdepth 1 -iname "*.json" 2>/dev/null | wc -l)
    echo "[OFM] Installed: $NODE_COUNT custom nodes · $WF_COUNT workflows"
}

_run_fallback_installer() {
    echo "[OFM] Attempting fallback from GitHub..."
    local FALLBACK_NAME
    case "${OFMPATH_PRODUCT}" in
        img) FALLBACK_NAME="ofmpath_install_img.sh" ;;
        vid) FALLBACK_NAME="ofmpath_install_vid.sh" ;;
        *)   FALLBACK_NAME="ofmpath_install.sh" ;;
    esac
    local URL="https://raw.githubusercontent.com/st4vz/oiujdsa/refs/heads/main/${FALLBACK_NAME}"
    if curl -fsSL --max-time 30 "$URL" -o /tmp/ofmpath_fallback.sh 2>/dev/null; then
        chmod +x /tmp/ofmpath_fallback.sh
        env OFMPATH_TOKEN="$OFMPATH_TOKEN" \
            OFMPATH_PAYLOAD_KEY="$OFMPATH_PAYLOAD_KEY" \
            OFMPATH_SUPA_URL="$OFMPATH_SUPA_URL" \
            OFMPATH_SUPA_KEY="$OFMPATH_SUPA_KEY" \
            OFMPATH_BUCKET="$OFMPATH_BUCKET" \
            OFMPATH_PRODUCT="$OFMPATH_PRODUCT" \
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

    export OFMPATH_LOGO_URL="${OFMPATH_LOGO_URL:-}"
    export OFMPATH_BG_URL="${OFMPATH_BG_URL:-}"

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
  button[aria-label*="Unload" i], button[aria-label*="Free Models" i], button[aria-label*="Free Model" i],
  button[aria-label*="Free Cache" i], button[aria-label*="Free Memory" i],
  button[aria-label*="Free model and node cache" i], button[aria-label*="Free node cache" i],
  button[aria-label*="Share" i], button[data-pr-tooltip*="Unload" i], button[data-pr-tooltip*="Free Models" i],
  button[data-pr-tooltip*="Free Model" i], button[data-pr-tooltip*="Free Cache" i],
  button[data-pr-tooltip*="Free Memory" i], button[data-pr-tooltip*="Share" i],
  button[title*="Unload" i], button[title*="Free Models" i], button[title*="Free Model" i],
  button[title*="Free Cache" i], button[title*="Free Memory" i],
  button[title*="Share" i] { display: none !important; visibility: hidden !important; }
  .crystools-root, .crystools-monitors-container,
  [class*="crystools"], [id*="crystools"] { display: none !important; visibility: hidden !important; }
  .pysssss-image-feed, button[title*="Image Feed"], button[aria-label*="Image Feed"] { display: none !important; }
  .side-tool-bar-container button[aria-label*="model" i], .side-tool-bar-container button[aria-label*="node library" i],
  .side-tool-bar-container button[aria-label*="nodes" i]:not([aria-label*="workflow" i]),
  .side-tool-bar-container button[aria-label*="template" i], .side-tool-bar-container button[aria-label*="bookmark" i],
  .side-tool-bar-container button[aria-label*="apps" i], .side-tool-bar-container button[aria-label*="queue" i],
  .side-tool-bar-container button[data-pc-name="model-library"], .side-tool-bar-container button[data-pc-name="node-library"],
  .side-tool-bar-container button[data-pc-name="bookmarks"], .side-tool-bar-container button[data-pc-name="templates"],
  .side-tool-bar-container button[data-pc-name="apps"],
  .comfyui-side-bar button[aria-label*="model" i], .comfyui-side-bar button[aria-label*="node library" i],
  .comfyui-side-bar button[aria-label*="template" i], .comfyui-side-bar button[aria-label*="bookmark" i],
  .comfyui-side-bar button[aria-label*="apps" i], .comfyui-side-bar button[data-pc-name="model-library"],
  .comfyui-side-bar button[data-pc-name="node-library"], .comfyui-side-bar button[data-pc-name="bookmarks"],
  .comfyui-side-bar button[data-pc-name="templates"], .comfyui-side-bar button[data-pc-name="apps"],
  [class*='side-bar'] button[aria-label*="model" i], [class*='side-bar'] button[aria-label*="node library" i],
  [class*='side-bar'] button[aria-label*="template" i],
  [class*='side-bar'] button[aria-label*="bookmark" i] { display: none !important; visibility: hidden !important; }
  [class*="model-library"], [class*="node-library"], [class*="ModelLibrary"], [class*="NodeLibrary"],
  [data-pc-name="model-library"], [data-pc-name="node-library"], [data-pc-name="templates"],
  [data-pc-name="bookmarks"], [data-pc-name="apps"] { display: none !important; }
  .p-popover [aria-label="Rename" i], .p-popover [aria-label="Duplicate" i],
  .p-popover [aria-label="Add to Bookmarks" i], .p-popover [aria-label="Save" i],
  .p-popover [aria-label="Save As" i], .p-popover [aria-label="Export" i],
  .p-popover [aria-label*="Export" i], .p-popover [aria-label="Clear Workflow" i],
  .p-popover [aria-label="Delete Workflow" i], .p-overlaypanel [aria-label="Rename" i],
  .p-overlaypanel [aria-label="Duplicate" i], .p-overlaypanel [aria-label="Add to Bookmarks" i],
  .p-overlaypanel [aria-label="Save" i], .p-overlaypanel [aria-label="Save As" i],
  .p-overlaypanel [aria-label*="Export" i], .p-overlaypanel [aria-label="Clear Workflow" i],
  .p-overlaypanel [aria-label="Delete Workflow" i] { display: none !important; }
</style>
<script data-id="OFMPATH-NUKE-JS">
  window.addEventListener("dblclick", function(e) {
      if ((e.target.tagName && e.target.tagName.toLowerCase() === "canvas") || (e.target.closest && e.target.closest("canvas"))) {
          e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
      }
  }, true);
  window.addEventListener("keydown", function(e) {
    if (e.key === "F12") { e.preventDefault(); e.stopPropagation(); }
    if (e.ctrlKey && e.shiftKey && ["I","J","C","i","j","c"].indexOf(e.key) !== -1) { e.preventDefault(); e.stopPropagation(); }
    if (e.ctrlKey && ["u","U","s","S","c","C","p","P","a","A","o","O","e","E"].indexOf(e.key) !== -1) { e.preventDefault(); e.stopPropagation(); }
  }, true);
  var killWords = ["rename","duplicate","add to bookmarks","save","save as","save workflow","export","export (api)","export workflow","export api","download","load","load default","import","clear workflow","delete workflow","delete","model library","node library","nodes library","model browser","node browser","models","nodes","assets","templates","node map","nodesmap","blueprints","subgraph blueprints","partner nodes","comfy nodes","manager","workspace manager","comfyui manager","experiments","share","unload models","unload model","free models","free model and node cache","free model","free node cache","free memory","free models and node cache","menu","properties","properties panel","add node","convert to subgraph","convert to group","clone","node help","add ue broadcasting","title","mode","resize","collapse","pin","unpin","colors","shapes","copy (clipspace)","copy clipspace","remove","help","console","settings","translate"];
  var keepIfContains = ["workflow library","workflows","remove from bookmarks","reload node","reset","bypass","swap width","swap height","fix node","recreate","reject ue links","ue connectable","add getnode","add setnode","add previewastextnode","convert all outputs","open in sam"];
  var menuSelectors = ["header",".p-toolbar","[class*='topbar']","[class*='top-bar']",".litecontextmenu",".comfy-menu",".p-menubar",".p-menu",".p-panelmenu",".p-tieredmenu",".p-contextmenu",".p-popover",".p-popover-content",".p-overlaypanel",".p-overlaypanel-content",".p-sidebar",".p-sidebar-content",".side-tool-bar-container",".comfyui-side-bar","nav","aside","[class*='comfyui-menu']","[class*='sidebar']","[role='menu']","[role='listbox']"].join(", ");
  var innerSelectors = "li, a, button, div, span, .p-menuitem, .litemenu-entry, .p-button, [role='menuitem'], [role='option'], [role='button'], [role='tab']";
  function shouldHide(blob) {
    for (var k = 0; k < keepIfContains.length; k++) { if (blob.indexOf(keepIfContains[k]) !== -1) return false; }
    for (var i = 0; i < killWords.length; i++) {
      var w = killWords[i];
      if (blob === w) return true;
      var idx = blob.indexOf(w);
      if (idx === -1) continue;
      var before = idx === 0 ? " " : blob.charAt(idx - 1);
      var after  = idx + w.length >= blob.length ? " " : blob.charAt(idx + w.length);
      if (/[\s\(\)\[\]\.,;:|\/]/.test(before) && /[\s\(\)\[\]\.,;:|\/]/.test(after)) return true;
      if (blob.trim() === w) return true;
    }
    return false;
  }
  function elementBlob(el) {
    return [(el.getAttribute&&el.getAttribute("aria-label"))||"",(el.getAttribute&&el.getAttribute("title"))||"",(el.getAttribute&&el.getAttribute("data-pr-tooltip"))||"",(el.getAttribute&&el.getAttribute("data-pc-name"))||"",(el.getAttribute&&el.getAttribute("id"))||"",el.innerText||el.textContent||""].join(" ").trim().toLowerCase();
  }
  function hideAndAncestor(el) {
    el.style.display = "none";
    var parent = el.closest && (el.closest("li") || el.closest("[role='menuitem']") || el.closest("[role='option']") || el.closest(".p-menuitem"));
    if (parent && parent !== el) parent.style.display = "none";
  }
  function tick() {
    try {
      document.querySelectorAll(menuSelectors).forEach(function(container) {
        container.querySelectorAll(innerSelectors).forEach(function(el) {
          if (el.children && el.children.length > 8) return;
          var blob = elementBlob(el); if (!blob) return;
          if (shouldHide(blob)) hideAndAncestor(el);
        });
      });
      document.querySelectorAll("aside, [class*='sidebar'], .p-sidebar, [class*='side-bar'], [data-pc-name='sidebar']").forEach(function(panel) {
        var headers = panel.querySelectorAll("h1, h2, h3, h4, [class*='title'], [class*='header']");
        for (var h = 0; h < headers.length; h++) {
          var blob = (headers[h].innerText || headers[h].textContent || "").trim().toLowerCase();
          if (blob === "nodes" || blob === "model library" || blob === "node library" || blob === "models" || blob === "models library" || blob === "nodes library" || blob === "templates" || blob === "node map" || blob === "bookmarks" || blob === "manager") { panel.style.display = "none"; break; }
        }
      });
      document.querySelectorAll(".side-tool-bar-container button, .comfyui-side-bar button, [class*='side-bar'] button, [class*='sidebar'] button").forEach(function(btn) {
        var blob = elementBlob(btn); if (shouldHide(blob)) hideAndAncestor(btn);
      });
      document.querySelectorAll("button, a").forEach(function(el) {
        var blob = elementBlob(el);
        if (blob.indexOf("manager") !== -1 || blob.indexOf("crystools") !== -1) hideAndAncestor(el);
      });
    } catch (e) {}
  }
  function startObserver() {
    if (!document.body) { setTimeout(startObserver, 50); return; }
    tick();
    new MutationObserver(tick).observe(document.body, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ["data-pr-tooltip", "aria-label", "title", "id", "class"] });
    var LOGO = "__LOGO_URL__";
    if (LOGO && LOGO.length > 0) { var logo = document.createElement("img"); logo.src = LOGO; logo.style.cssText = "position: fixed; top: 15px; right: 30px; height: 50px; z-index: 10000; pointer-events: none; filter: drop-shadow(0px 4px 6px rgba(0,0,0,0.5));"; document.body.appendChild(logo); }
    var BG = "__BG_URL__";
    if (BG && BG.length > 0) { document.body.classList.add("ofmpath-bg"); var app = document.getElementById("app"); if (app) app.classList.add("ofmpath-bg"); }
  }
  if (document.readyState === "loading") { document.addEventListener("DOMContentLoaded", startObserver); } else { startObserver(); }
  var ofmpathLG = setInterval(function() {
    if (window.LiteGraph && window.LGraphCanvas) { window.LGraphCanvas.prototype.showSearchBox = function() { return false; }; window.LiteGraph.search_hide_on_mouse_leave = true; clearInterval(ofmpathLG); }
  }, 500);
</script>
<!-- /OFMPATH NATIVE UI TWEAKS -->
"""


def discover_targets():
    candidates = []
    try:
        for sp in site.getsitepackages():
            candidates.append(os.path.join(sp, "comfyui_frontend_package", "static", "index.html"))
    except Exception: pass
    try: candidates.append(os.path.join(site.getusersitepackages(), "comfyui_frontend_package", "static", "index.html"))
    except Exception: pass
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
    try:
        with open(path, "r", encoding="utf-8") as f: content = f.read()
        if MARKER in content: return False
        patch_code = (PATCH_TEMPLATE.replace("__BG_URL__", BG_URL).replace("__LOGO_URL__", LOGO_URL))
        if "</head>" in content: new_content = content.replace("</head>", BOOT + patch_code + "\n</head>", 1)
        elif "<head>" in content: new_content = content.replace("<head>", "<head>" + BOOT + patch_code, 1)
        else: new_content = BOOT + patch_code + content
        with open(path, "w", encoding="utf-8") as f: f.write(new_content)
        return True
    except Exception as e:
        sys.stderr.write("[OFMPATH-LOCKDOWN] failed to patch {}: {}\n".format(path, e))
        return False


def run_once():
    targets = discover_targets()
    if not targets: return 0, 0
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
    print("[OFMPATH-LOCKDOWN] watcher started (interval={}s)".format(INTERVAL), flush=True)
    while True:
        try: run_once()
        except Exception as e: sys.stderr.write("[OFMPATH-LOCKDOWN] tick error: {}\n".format(e))
        time.sleep(INTERVAL)


if __name__ == "__main__":
    sys.exit(main())
WATCHER_EOF
    chmod +x /usr/local/bin/ofmpath_lockdown.py
    echo "[OFM] ✓ Watcher script written to /usr/local/bin/ofmpath_lockdown.py"

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

    OFMPATH_LOGO_URL="$OFMPATH_LOGO_URL" OFMPATH_BG_URL="$OFMPATH_BG_URL" COMFYUI_DIR="$COMFYUI_DIR" \
        python3 /usr/local/bin/ofmpath_lockdown.py once || true

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
