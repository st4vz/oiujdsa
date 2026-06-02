#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
#  OFM PATH 智慧通路 — Inner Installer · VIDEO TOOLS
#  Deploys: OFMPATH MOTION, OFMPATH MASK MOTION, OFMPATH I2V NSFW, OFMPATH LIPSYNC
#  Fetched + decrypted by ofmpath_main.sh from Supabase bucket.
# ═══════════════════════════════════════════════════════════════════════════

# No `set -e` — we need to survive partial failures.

# ═══ ENV DIAGNOSTIC DUMP ═══
echo "[OFM-INNER] Starting at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[OFM-INNER] Shell: $BASH_VERSION"
echo "[OFM-INNER] PWD: $(pwd)"
echo "[OFM-INNER] USER: $(whoami)"
echo "[OFM-INNER] OFMPATH_TOKEN: ${OFMPATH_TOKEN:+set(len=${#OFMPATH_TOKEN})}${OFMPATH_TOKEN:-MISSING}"
echo "[OFM-INNER] OFMPATH_PAYLOAD_KEY: ${OFMPATH_PAYLOAD_KEY:+set(len=${#OFMPATH_PAYLOAD_KEY})}${OFMPATH_PAYLOAD_KEY:-MISSING}"
echo "[OFM-INNER] COMFYUI_DIR: ${COMFYUI_DIR:-unset}"
echo "[OFM-INNER] CUSTOM_NODES_DIR: ${CUSTOM_NODES_DIR:-unset}"
echo "[OFM-INNER] PIP: ${PIP:-unset}"

# ═══ DEFENSIVE VAR SETUP ═══
if [ -z "${OFMPATH_TOKEN:-}" ]; then
    echo "[OFM-INNER] ⚠ WARNING: OFMPATH_TOKEN not visible to child shell"
fi
if [ -z "${OFMPATH_PAYLOAD_KEY:-}" ]; then
    echo "[OFM-INNER] ⚠ WARNING: OFMPATH_PAYLOAD_KEY not visible to child shell"
    echo "[OFM-INNER]   → workflows cannot be decrypted but node/model install will continue"
fi
: "${COMFYUI_DIR:=/workspace/ComfyUI}"
: "${CUSTOM_NODES_DIR:=$COMFYUI_DIR/custom_nodes}"
: "${OFMPATH_SUPA_URL:=https://yvjhjptycwlnjnzzsyju.supabase.co}"
: "${OFMPATH_BUCKET:=ofm-path}"

MODELS="$COMFYUI_DIR/models"
WORKFLOWS_DIR="$COMFYUI_DIR/user/default/workflows"
HF_TOKEN="${HF_TOKEN:-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}"

if [ -z "${PIP:-}" ]; then
    if   [ -x "/venv/main/bin/pip" ];       then PIP="/venv/main/bin/pip"
    elif [ -x "$COMFYUI_DIR/.venv/bin/pip" ]; then PIP="$COMFYUI_DIR/.venv/bin/pip"
    else PIP="pip"; fi
    echo "[OFM-INNER] Detected PIP=$PIP"
fi

_fetch_secure() {
    local p="$1" d="$2" t=0
    local url="${OFMPATH_SUPA_URL}/storage/v1/object/public/${OFMPATH_BUCKET}/${p}"
    while [ $t -lt 5 ]; do
        t=$((t+1))
        curl -fsSL --max-time 120 --retry 2 --retry-delay 2 -o "$d" "$url" 2>/dev/null
        if [ -s "$d" ] && head -c 8 "$d" | grep -q "Salted__"; then return 0; fi
        rm -f "$d"; sleep 2
    done
    return 1
}
_decrypt_secure() {
    [ -f "$1" ] && [ -n "${OFMPATH_PAYLOAD_KEY:-}" ] || return 1
    openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 100000 \
        -pass "pass:${OFMPATH_PAYLOAD_KEY}" -in "$1" -out "$2" 2>/dev/null
}

echo -e "\n\n"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  OFM PATH 智慧通路  v1 — Inner Installer · VIDEO TOOLS         ║"
echo "║  MOTION · MASK MOTION · I2V NSFW · LIPSYNC                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE A — FETCH + DECRYPT WORKFLOWS
# ═══════════════════════════════════════════════════════════════════════════

mkdir -p "$WORKFLOWS_DIR" "$COMFYUI_DIR/input"

WORKFLOW_MOTION=""
WORKFLOW_MASK_MOTION=""
WORKFLOW_I2V_NSFW=""
WORKFLOW_LIPSYNC=""

if _fetch_secure "OFMPATH_MOTION.json.enc" /tmp/motion.enc; then
    echo "[OFM-INNER] Fetched motion ($(stat -c%s /tmp/motion.enc) bytes)"
    if _decrypt_secure /tmp/motion.enc /tmp/motion.json; then
        if python3 -c "import json; d=json.load(open('/tmp/motion.json')); assert 'nodes' in d" 2>/dev/null; then
            WORKFLOW_MOTION=/tmp/motion.json
            echo "[OFM-INNER] ✓ OFMPATH MOTION workflow decrypted + validated"
        else echo "[OFM-INNER] ✗ MOTION JSON invalid after decrypt"; fi
    else echo "[OFM-INNER] ✗ MOTION decrypt failed (wrong key?)"; fi
    rm -f /tmp/motion.enc
else echo "[OFM-INNER] ✗ MOTION fetch failed"; fi

if _fetch_secure "OFMPATH_MASK_MOTION.json.enc" /tmp/mask_motion.enc; then
    echo "[OFM-INNER] Fetched mask_motion ($(stat -c%s /tmp/mask_motion.enc) bytes)"
    if _decrypt_secure /tmp/mask_motion.enc /tmp/mask_motion.json; then
        if python3 -c "import json; d=json.load(open('/tmp/mask_motion.json')); assert 'nodes' in d" 2>/dev/null; then
            WORKFLOW_MASK_MOTION=/tmp/mask_motion.json
            echo "[OFM-INNER] ✓ OFMPATH MASK MOTION workflow decrypted + validated"
        else echo "[OFM-INNER] ✗ MASK_MOTION JSON invalid after decrypt"; fi
    else echo "[OFM-INNER] ✗ MASK_MOTION decrypt failed"; fi
    rm -f /tmp/mask_motion.enc
else echo "[OFM-INNER] ✗ MASK_MOTION fetch failed"; fi

if _fetch_secure "OFMPATH_I2V_NSFW.json.enc" /tmp/i2v_nsfw.enc; then
    echo "[OFM-INNER] Fetched i2v_nsfw ($(stat -c%s /tmp/i2v_nsfw.enc) bytes)"
    if _decrypt_secure /tmp/i2v_nsfw.enc /tmp/i2v_nsfw.json; then
        if python3 -c "import json; d=json.load(open('/tmp/i2v_nsfw.json')); assert 'nodes' in d" 2>/dev/null; then
            WORKFLOW_I2V_NSFW=/tmp/i2v_nsfw.json
            echo "[OFM-INNER] ✓ OFMPATH I2V NSFW workflow decrypted + validated"
        else echo "[OFM-INNER] ✗ I2V_NSFW JSON invalid after decrypt"; fi
    else echo "[OFM-INNER] ✗ I2V_NSFW decrypt failed"; fi
    rm -f /tmp/i2v_nsfw.enc
else echo "[OFM-INNER] ✗ I2V_NSFW fetch failed"; fi

if _fetch_secure "OFMPATH_LIPSYNC.json.enc" /tmp/lipsync.enc; then
    echo "[OFM-INNER] Fetched lipsync ($(stat -c%s /tmp/lipsync.enc) bytes)"
    if _decrypt_secure /tmp/lipsync.enc /tmp/lipsync.json; then
        if python3 -c "import json; d=json.load(open('/tmp/lipsync.json')); assert 'nodes' in d" 2>/dev/null; then
            WORKFLOW_LIPSYNC=/tmp/lipsync.json
            echo "[OFM-INNER] ✓ OFMPATH LIPSYNC workflow decrypted + validated"
        else echo "[OFM-INNER] ✗ LIPSYNC JSON invalid after decrypt"; fi
    else echo "[OFM-INNER] ✗ LIPSYNC decrypt failed (wrong key?)"; fi
    rm -f /tmp/lipsync.enc
else echo "[OFM-INNER] ✗ LIPSYNC fetch failed"; fi


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE A.5 — EXTRA PIP PACKAGES
# ═══════════════════════════════════════════════════════════════════════════

echo "[OFM-INNER] Installing sageattention + triton..."
"$PIP" install sageattention triton --quiet 2>/dev/null || echo "[OFM-INNER] ⚠ sageattention/triton install failed (non-fatal)"
echo "[OFM-INNER] ✓ Extra pip packages done"


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE B — INSTALL CUSTOM NODES (29)
# ═══════════════════════════════════════════════════════════════════════════

mkdir -p "$CUSTOM_NODES_DIR"
if ! cd "$CUSTOM_NODES_DIR"; then
    echo "[OFM-INNER] CRITICAL: cannot cd into $CUSTOM_NODES_DIR"
    echo "[OFM-INNER] Aborting Phase B"
else
    echo "[OFM-INNER] Working dir: $(pwd)"
    _NODE_IDX=0
    _NODE_TOTAL=29

    _install_node() {
        local name="$1" url="$2"
        _NODE_IDX=$((_NODE_IDX + 1))
        if [ -d "$name" ]; then
            echo "  [ok] $name (${_NODE_IDX}/${_NODE_TOTAL}) [already present]"
        else
            echo "  [+] $name (${_NODE_IDX}/${_NODE_TOTAL}) cloning..."
            if ! timeout 120 git clone --depth 1 "$url" "$name" 2>&1 | tail -3; then
                echo "  [!] Clone timeout/failed: $name (continuing)"
                return 0
            fi
        fi
        if [ -f "$name/requirements.txt" ]; then
            echo "  [·] $name: installing requirements..."
            if ! timeout 180 "$PIP" install -r "$name/requirements.txt" --quiet 2>&1 | tail -3; then
                echo "  [!] Requirements timeout/errors: $name (continuing)"
            fi
        fi
    }

    # ── MOTION + MASK_MOTION nodes (23) ──
    _install_node "ComfyUI-Manager"                "https://github.com/ltdrdata/ComfyUI-Manager"
    _install_node "ComfyUI-WanVideoWrapper"        "https://github.com/kijai/ComfyUI-WanVideoWrapper"
    _install_node "ComfyUI-Impact-Pack"            "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
    _install_node "ComfyUI-SeedVR2_VideoUpscaler"  "https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler"
    _install_node "ComfyUI_LayerStyle"             "https://github.com/chflame163/ComfyUI_LayerStyle"
    _install_node "rgthree-comfy"                  "https://github.com/rgthree/rgthree-comfy"
    _install_node "ComfyUI-Easy-Use"               "https://github.com/yolain/ComfyUI-Easy-Use"
    _install_node "ComfyUI-KJNodes"                "https://github.com/kijai/ComfyUI-KJNodes"
    _install_node "ComfyUI-VideoHelperSuite"       "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    _install_node "ComfyUI-segment-anything-2"     "https://github.com/kijai/ComfyUI-segment-anything-2"
    _install_node "ComfyUI_essentials"             "https://github.com/cubiq/ComfyUI_essentials"
    _install_node "ComfyUI-ZMG-Nodes"              "https://github.com/fq393/ComfyUI-ZMG-Nodes"
    _install_node "ComfyUI-WanAnimatePreprocess"   "https://github.com/kijai/ComfyUI-WanAnimatePreprocess"
    _install_node "ComfyUI_HuggingFace_Downloader" "https://github.com/jnxmx/ComfyUI_HuggingFace_Downloader"
    _install_node "CRT-Nodes"                      "https://github.com/plugcrypt/CRT-Nodes"
    _install_node "ComfyUI-Custom-Scripts"         "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
    _install_node "RES4LYF"                        "https://github.com/ClownsharkBatwing/RES4LYF"
    _install_node "cg-use-everywhere"              "https://github.com/chrisgoringe/cg-use-everywhere"
    _install_node "ComfyUI-Impact-Subpack"         "https://github.com/ltdrdata/ComfyUI-Impact-Subpack"
    _install_node "ComfyUI-mxToolkit"              "https://github.com/Smirnov75/ComfyUI-mxToolkit"
    _install_node "ComfyUI-Crystools"              "https://github.com/crystian/ComfyUI-Crystools"
    _install_node "comfyui-teskors-utils"          "https://github.com/teskor-hub/comfyui-teskors-utils.git"
    _install_node "ComfyUI-SAM3"                   "https://github.com/PozzettiAndrea/ComfyUI-SAM3"

    # ── LIPSYNC-only nodes ──
    _install_node "audio-separation-nodes-comfyui"  "https://github.com/christian-byrne/audio-separation-nodes-comfyui"
    _install_node "comfy-mtb"                       "https://github.com/melMass/comfy_mtb"

    # ── I2V_NSFW-only nodes ──
    _install_node "ComfyUI-VFI"                     "https://github.com/GACLove/ComfyUI-VFI"
    _install_node "ComfyUI-PainterI2V"              "https://github.com/LDNKS094/ComfyUI-PainterI2V"
    _install_node "ComfyUI-VideoUpscaler"           "https://github.com/ShmuelRonen/ComfyUI-VideoUpscaler"

    # ── Private ──
    _install_node "comfyui-closer-tool"             "https://github.com/st4vz/comfyui-closer-tool"

    KJ="$CUSTOM_NODES_DIR/ComfyUI-KJNodes/nodes/nodes.py"
    if [ -f "$KJ" ] && grep -q "search_aliases" "$KJ" 2>/dev/null; then
        sed -i 's/search_aliases=\[.*\],\?//g' "$KJ"
        echo "[OFM-INNER] ✓ KJNodes search_aliases fix applied"
    fi

    # SAM3 needs comfy-env install for pixi environment
    if [ -d "$CUSTOM_NODES_DIR/ComfyUI-SAM3" ] && [ -f "$CUSTOM_NODES_DIR/ComfyUI-SAM3/install.py" ]; then
        echo "[OFM-INNER] Running SAM3 install.py (comfy-env setup)..."
        (cd "$CUSTOM_NODES_DIR/ComfyUI-SAM3" && timeout 300 python3 install.py 2>&1 | tail -5) || echo "[OFM-INNER] ⚠ SAM3 install.py failed (non-fatal)"
    fi

    INSTALLED_NODES=$(ls -1 "$CUSTOM_NODES_DIR" 2>/dev/null | wc -l)
    echo "[OFM-INNER] ✓ Phase B done: $INSTALLED_NODES nodes in $CUSTOM_NODES_DIR"
fi


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE C — DOWNLOAD MODELS (aria2c parallel)
# ═══════════════════════════════════════════════════════════════════════════

# ── Install aria2 if missing ──
if ! command -v aria2c &>/dev/null; then
    echo "[OFM-INNER] Installing aria2..."
    apt-get install -y -qq aria2 2>/dev/null || true
fi

# ── aria2c manifest builder ──
_MANIFEST=/tmp/ofmpath_dl.txt
rm -f "$_MANIFEST"

_add() {
    local dir="$1" fname="$2" url="$3"
    mkdir -p "$dir"
    if [ -f "$dir/$fname" ] && [ -s "$dir/$fname" ]; then
        echo "  [ok] $fname"
        return
    fi
    printf '%s\n  dir=%s\n  out=%s\n' "$url" "$dir" "$fname" >> "$_MANIFEST"
    if [[ "$url" == *huggingface.co* ]] && [ -n "${HF_TOKEN:-}" ]; then
        printf '  header=Authorization: Bearer %s\n' "$HF_TOKEN" >> "$_MANIFEST"
    fi
    printf '\n' >> "$_MANIFEST"
}

# ─── MOTION + MASK_MOTION (Animator) ──────────────────────────────────────
_add "$MODELS/clip"        "klip_vision.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors"
_add "$MODELS/clip_vision" "klip_vision.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors"
_add "$MODELS/clip_vision" "clip_vision_h.safetensors" \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"
_add "$MODELS/text_encoders" "text_enc.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/text_enc.safetensors"
_add "$MODELS/unet"         "z_image_turbo_bf16.safetensors" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
_add "$MODELS/vae"          "vae.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/vae.safetensors"
_add "$MODELS/diffusion_models" "WanModel.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanModel.safetensors"

# Animator: detection
_add "$MODELS/detection" "yolov10m.onnx" \
    "https://huggingface.co/st4vz/process_checkpoint/resolve/main/yolov10m.onnx"
_add "$MODELS/detection" "vitpose_h_wholebody_data.bin" \
    "https://huggingface.co/st4vz/process_checkpoint/resolve/main/vitpose_h_wholebody_data.bin"
_add "$MODELS/detection" "vitpose_h_wholebody_model.onnx" \
    "https://huggingface.co/st4vz/process_checkpoint/resolve/main/vitpose_h_wholebody_model.onnx"

# Animator: loras
_add "$MODELS/loras" "WanFun.reworked.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanFun.reworked.safetensors"
_add "$MODELS/loras" "light.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/light.safetensors"
_add "$MODELS/loras" "WanPusa.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanPusa.safetensors"
_add "$MODELS/loras" "wan.reworked.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/wan.reworked.safetensors"

# Animator: controlnet
_add "$MODELS/controlnet" "Wan21_Uni3C_controlnet_fp16.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_Uni3C_controlnet_fp16.safetensors"

# ─── I2V NSFW ─────────────────────────────────────────────────────────────
_add "$MODELS/diffusion_models" "Wan2.2_Remix_NSFW_i2v_14b_high_lighting_v2.0.safetensors" \
    "https://huggingface.co/FX-FeiHou/wan2.2-Remix/resolve/main/NSFW/Wan2.2_Remix_NSFW_i2v_14b_high_lighting_v2.0.safetensors"
_add "$MODELS/diffusion_models" "Wan2.2_Remix_NSFW_i2v_14b_low_lighting_v2.0.safetensors" \
    "https://huggingface.co/FX-FeiHou/wan2.2-Remix/resolve/main/NSFW/Wan2.2_Remix_NSFW_i2v_14b_low_lighting_v2.0.safetensors"
_add "$MODELS/clip" "nsfw_wan_umt5-xxl_fp8_scaled.safetensors" \
    "https://huggingface.co/NSFW-API/NSFW-Wan-UMT5-XXL/resolve/main/nsfw_wan_umt5-xxl_fp8_scaled.safetensors"
_add "$MODELS/vae" "wan_2.1_vae.safetensors" \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors"
_add "$MODELS/upscale_models" "4x_foolhardy_Remacri.pth" \
    "https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth"

# ─── LIPSYNC ──────────────────────────────────────────────────────────────
_add "$MODELS/loras" "lightx2v_T2V_14B_cfg_step_distill_v2_lora_rank128_bf16.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_T2V_14B_cfg_step_distill_v2_lora_rank128_bf16.safetensors"
_add "$MODELS/loras" "Wan2.1-Fun-14B-InP-HPS2.1_reward_lora_comfy.safetensors" \
    "https://huggingface.co/Kijai/Wan2.1-Fun-Reward-LoRAs-comfy/resolve/main/Wan2.1-Fun-14B-InP-HPS2.1_reward_lora_comfy.safetensors"
_add "$MODELS/text_encoders" "umt5-xxl-enc-fp8_e4m3fn.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/umt5-xxl-enc-fp8_e4m3fn.safetensors"
_add "$MODELS/vae" "Wan2_1_VAE_bf16.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1_VAE_bf16.safetensors"
_add "$MODELS/diffusion_models" "Wan2_1-I2V-14B-480p_fp8_e4m3fn_scaled_KJ.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/I2V/Wan2_1-I2V-14B-480p_fp8_e4m3fn_scaled_KJ.safetensors"
_add "$MODELS/diffusion_models/InfiniteTalk" "Wan2_1-InfiniteTalk-Single_fp16.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/InfiniteTalk/Wan2_1-InfiniteTalk-Single_fp16.safetensors"

# ── Fire aria2c ──
if [ -f "$_MANIFEST" ] && [ -s "$_MANIFEST" ]; then
    _QUEUED=$(grep -c '^https://' "$_MANIFEST" 2>/dev/null || echo 0)
    echo "[OFM-INNER] aria2c: $_QUEUED files queued"
    aria2c \
        --input-file="$_MANIFEST" \
        --max-concurrent-downloads=10 \
        --split=32 \
        --max-connection-per-server=16 \
        --min-split-size=5M \
        --continue=true \
        --retry-wait=2 \
        --max-tries=5 \
        --timeout=120 \
        --connect-timeout=10 \
        --allow-overwrite=false \
        --auto-file-renaming=false \
        --file-allocation=none \
        --optimize-concurrent-downloads=true \
        --console-log-level=warn \
        --summary-interval=30 \
        2>&1 | grep -v "^$" || true
    rm -f "$_MANIFEST"
    echo "[OFM-INNER] ✓ aria2c batch complete"
else
    echo "[OFM-INNER] All models already cached, skipping aria2c"
fi

echo "[OFM-INNER] ✓ Phase C model downloads complete"


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE D — DEPLOY WORKFLOWS
# ═══════════════════════════════════════════════════════════════════════════

_deploy_workflow() {
    local src="$1" name="$2"
    if [ -z "$src" ] || [ ! -f "$src" ]; then
        echo "  [!] Skipped: $name (not fetched)"
        return
    fi
    cp "$src" "$COMFYUI_DIR/$name" 2>/dev/null && echo "  [✓] $COMFYUI_DIR/$name"
    cp "$src" "$WORKFLOWS_DIR/$name" 2>/dev/null && echo "  [✓] $WORKFLOWS_DIR/$name"
    cp "$src" "$COMFYUI_DIR/input/$name" 2>/dev/null && echo "  [✓] input/$name"
    local fg_paths=()
    [ -d "$COMFYUI_DIR/web" ] && fg_paths+=("$COMFYUI_DIR/web")
    for _p in /venv/lib/python*/site-packages/comfyui_frontend_package/; do
        [ -d "$_p" ] && fg_paths+=("$_p")
    done
    if [ ${#fg_paths[@]} -gt 0 ]; then
        find "${fg_paths[@]}" -maxdepth 4 -name "defaultGraph.json" -type f 2>/dev/null | while read -r gp; do
            cp "$src" "$gp" && echo "  [✓] defaultGraph: $gp"
        done
    fi
}

_deploy_workflow "$WORKFLOW_MOTION"       "OFMPATH MOTION.json"
_deploy_workflow "$WORKFLOW_MASK_MOTION"  "OFMPATH MASK MOTION.json"
_deploy_workflow "$WORKFLOW_I2V_NSFW"     "OFMPATH I2V NSFW.json"
_deploy_workflow "$WORKFLOW_LIPSYNC"      "OFMPATH LIPSYNC.json"
rm -f /tmp/motion.json /tmp/mask_motion.json /tmp/i2v_nsfw.json /tmp/lipsync.json


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE E — COMFYUI SETTINGS
# ═══════════════════════════════════════════════════════════════════════════
SETTINGS_DIR="$COMFYUI_DIR/user/default"
mkdir -p "$SETTINGS_DIR"

cat > "$SETTINGS_DIR/comfy.settings.json" << 'SETTINGSJSON'
{
    "Comfy.Locale": "en",
    "Comfy.DevMode": false,
    "Comfy.Logging.Enabled": false,
    "Comfy.Graph.CanvasInfo": false,
    "Comfy.NodeSearchBoxImpl": "default",
    "Comfy.Workflow.WorkflowTabsPosition": "Sidebar",
    "Comfy.Sidebar.Location": "left",
    "Comfy.Sidebar.Size": "small",
    "Crystools.ShowMonitor": false,
    "Crystools.ShowCPU": false,
    "Crystools.ShowGPU": false,
    "Crystools.ShowRAM": false,
    "Crystools.ShowVRAM": false,
    "Crystools.ShowHDD": false,
    "Crystools.ShowTemperature": false,
    "pysssss.ImageFeed.hidden": true,
    "pysssss.ImageFeed.location": "hidden",
    "Comfy.Extension.pysssss.ImageFeed": false,
    "rgthree.features.progress_bar.enabled": false,
    "rgthree.features.menu_auto_queue.enabled": false
}
SETTINGSJSON
echo "[OFM-INNER] ✓ Settings written"


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE F — INVENTORY REPORT
# ═══════════════════════════════════════════════════════════════════════════
_total_files=0
for _d in diffusion_models diffusion_models/InfiniteTalk text_encoders clip clip_vision vae controlnet loras upscale_models detection unet; do
    _p="$MODELS/$_d"
    [ -d "$_p" ] || continue
    _n=$(find "$_p" -maxdepth 1 -type f 2>/dev/null | wc -l)
    _sz=$(du -sh "$_p" 2>/dev/null | cut -f1)
    printf "  %-30s %3d files  %s\n" "$_d" "$_n" "$_sz"
    _total_files=$((_total_files + _n))
done
echo "  Total model files:  $_total_files"

CUSTOM_NODE_COUNT=$(ls -1 "$CUSTOM_NODES_DIR" 2>/dev/null | wc -l)
WF_COUNT=$(find "$WORKFLOWS_DIR" -maxdepth 1 -iname "*.json" 2>/dev/null | wc -l)
echo "  Custom nodes: $CUSTOM_NODE_COUNT"
echo "  Workflows: $WF_COUNT"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  ✅ OFM PATH 智慧通路 — VIDEO TOOLS installer complete         ║"
echo "╠════════════════════════════════════════════════════════════════╣"
printf "║  Models: %-3d · Nodes: %-3d · Workflows: %-2d                      ║\n" "$_total_files" "$CUSTOM_NODE_COUNT" "$WF_COUNT"
echo "╚════════════════════════════════════════════════════════════════╝"

exit 0
