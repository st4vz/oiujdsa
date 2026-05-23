#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
#  OFM PATH 智慧通路 — Inner Installer  (hardened v3 + LIPSYNC)
#  Fetched + decrypted by ofmpath_main.sh from Supabase bucket.
#  v3: Fixed HuggingFace XET storage compatibility, download resilience,
#      model path validation, vitpose integrity checks.
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
# These warn but don't kill the script — we want to see WHAT actually breaks
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

# Define fetch/decrypt if outer didn't propagate them (always safer to define)
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
echo "║  OFM PATH 智慧通路  v1 — Inner Installer                       ║"
echo "║  OFMPATH ANIMATOR + OFMPATH T2I + OFMPATH LIPSYNC              ║"
echo "╚════════════════════════════════════════════════════════════════╝"


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE A — FETCH + DECRYPT WORKFLOWS
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase A: Fetch workflows ━━━"
echo "[PROGRESS: 35]"

mkdir -p "$WORKFLOWS_DIR" "$COMFYUI_DIR/input"

WORKFLOW_MOTION=""
WORKFLOW_T2I=""
WORKFLOW_LIPSYNC=""

if _fetch_secure "ofmpath_motion.json.enc" /tmp/motion.enc; then
    echo "[OFM-INNER] Fetched motion ($(stat -c%s /tmp/motion.enc) bytes)"
    if _decrypt_secure /tmp/motion.enc /tmp/motion.json; then
        if python3 -c "import json; d=json.load(open('/tmp/motion.json')); assert 'nodes' in d" 2>/dev/null; then
            WORKFLOW_MOTION=/tmp/motion.json
            echo "[OFM-INNER] ✓ OFMPATH ANIMATOR workflow decrypted + validated"
        else
            echo "[OFM-INNER] ✗ MOTION JSON invalid after decrypt"
        fi
    else
        echo "[OFM-INNER] ✗ MOTION decrypt failed (wrong key?)"
    fi
    rm -f /tmp/motion.enc
else
    echo "[OFM-INNER] ✗ MOTION fetch failed"
fi

if _fetch_secure "ofmpath_t2i.json.enc" /tmp/t2i.enc; then
    echo "[OFM-INNER] Fetched t2i ($(stat -c%s /tmp/t2i.enc) bytes)"
    if _decrypt_secure /tmp/t2i.enc /tmp/t2i.json; then
        if python3 -c "import json; d=json.load(open('/tmp/t2i.json')); assert 'nodes' in d" 2>/dev/null; then
            WORKFLOW_T2I=/tmp/t2i.json
            echo "[OFM-INNER] ✓ OFMPATH T2I workflow decrypted + validated"
        else
            echo "[OFM-INNER] ✗ T2I JSON invalid after decrypt"
        fi
    else
        echo "[OFM-INNER] ✗ T2I decrypt failed"
    fi
    rm -f /tmp/t2i.enc
else
    echo "[OFM-INNER] ✗ T2I fetch failed"
fi

if _fetch_secure "OFMPATH_LIPSYNC.json.enc" /tmp/lipsync.enc; then
    echo "[OFM-INNER] Fetched lipsync ($(stat -c%s /tmp/lipsync.enc) bytes)"
    if _decrypt_secure /tmp/lipsync.enc /tmp/lipsync.json; then
        if python3 -c "import json; d=json.load(open('/tmp/lipsync.json')); assert 'nodes' in d" 2>/dev/null; then
            WORKFLOW_LIPSYNC=/tmp/lipsync.json
            echo "[OFM-INNER] ✓ OFMPATH LIPSYNC workflow decrypted + validated"
        else
            echo "[OFM-INNER] ✗ LIPSYNC JSON invalid after decrypt"
        fi
    else
        echo "[OFM-INNER] ✗ LIPSYNC decrypt failed (wrong key?)"
    fi
    rm -f /tmp/lipsync.enc
else
    echo "[OFM-INNER] ✗ LIPSYNC fetch failed"
fi


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE B — INSTALL CUSTOM NODES (29)
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase B: Install custom nodes ━━━"
echo "[PROGRESS: 42]"

# Explicit create + cd with hard verify
mkdir -p "$CUSTOM_NODES_DIR"
if ! cd "$CUSTOM_NODES_DIR"; then
    echo "[OFM-INNER] CRITICAL: cannot cd into $CUSTOM_NODES_DIR"
    echo "[OFM-INNER] Directory listing: $(ls -la "$COMFYUI_DIR" 2>/dev/null || echo 'comfy dir missing')"
    echo "[OFM-INNER] Aborting Phase B"
else
    echo "[OFM-INNER] Working dir: $(pwd)"
    _NODE_IDX=0

    _install_node() {
        local name="$1" url="$2"
        _NODE_IDX=$((_NODE_IDX + 1))
        local pct=$(( 42 + (_NODE_IDX * 12 / 29) ))
        echo "[PROGRESS: ${pct}]"

        if [ -d "$name" ]; then
            echo "  [ok] $name (${_NODE_IDX}/29) [already present]"
        else
            echo "  [+] $name (${_NODE_IDX}/29) cloning..."
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
    _install_node "cg-use-everywhere"              "https://github.com/chrisgoringe/cg-use-everywhere"
    _install_node "ComfyUI-Impact-Subpack"         "https://github.com/ltdrdata/ComfyUI-Impact-Subpack"
    _install_node "ComfyUI-mxToolkit"              "https://github.com/Smirnov75/ComfyUI-mxToolkit"
    _install_node "ComfyUI-Image-Size-Tools"       "https://github.com/TheLustriVA/ComfyUI-Image-Size-Tools"
    _install_node "zhihui_nodes_comfyui"           "https://github.com/ZhiHui6/zhihui_nodes_comfyui"
    _install_node "ComfyUI-KJNodes"                "https://github.com/kijai/ComfyUI-KJNodes"
    _install_node "ComfyUI_HuggingFace_Downloader" "https://github.com/jnxmx/ComfyUI_HuggingFace_Downloader"
    _install_node "CRT-Nodes"                      "https://github.com/plugcrypt/CRT-Nodes"
    _install_node "ComfyUI-post-processing-nodes"  "https://github.com/EllangoK/ComfyUI-post-processing-nodes"
    _install_node "comfyui_controlnet_aux"         "https://github.com/Fannovel16/comfyui_controlnet_aux"
    _install_node "comfyui-teskors-utils"          "https://github.com/teskor-hub/comfyui-teskors-utils"
    _install_node "Comfyui-Resolution-Master"      "https://github.com/Azornes/Comfyui-Resolution-Master"
    _install_node "ComfyUI-VideoHelperSuite"       "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    _install_node "ComfyUI-segment-anything-2"     "https://github.com/kijai/ComfyUI-segment-anything-2"
    _install_node "ComfyUI-ZMG-Nodes"              "https://github.com/fq393/ComfyUI-ZMG-Nodes"
    _install_node "ComfyUI-WanAnimatePreprocess"   "https://github.com/kijai/ComfyUI-WanAnimatePreprocess"
    _install_node "ComfyUI-SAM3"                   "https://github.com/PozzettiAndrea/ComfyUI-SAM3"
    _install_node "audio-separation-nodes-comfyui"  "https://github.com/christian-byrne/audio-separation-nodes-comfyui"
    _install_node "comfy-mtb"                       "https://github.com/melMass/comfy_mtb"

    # KJNodes compat fix
    KJ="$CUSTOM_NODES_DIR/ComfyUI-KJNodes/nodes/nodes.py"
    if [ -f "$KJ" ] && grep -q "search_aliases" "$KJ" 2>/dev/null; then
        sed -i 's/search_aliases=\[.*\],\?//g' "$KJ"
        echo "[OFM-INNER] ✓ KJNodes search_aliases fix applied"
    fi

    INSTALLED_NODES=$(ls -1 "$CUSTOM_NODES_DIR" 2>/dev/null | wc -l)
    echo "[OFM-INNER] ✓ Phase B done: $INSTALLED_NODES nodes in $CUSTOM_NODES_DIR"
fi


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE C — DOWNLOAD MODELS (57 total)
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase C: Download models ━━━"
echo "[PROGRESS: 55]"
echo "Found 57 models to verify"

# Ensure huggingface_hub is available (XET fallback)
if ! python3 -c "from huggingface_hub import hf_hub_download" 2>/dev/null; then
    echo "[OFM-INNER] Installing huggingface_hub..."
    "$PIP" install -q huggingface_hub 2>/dev/null || true
fi
export HF_HUB_ENABLE_HF_TRANSFER=0
export HF_HUB_DISABLE_SYMLINKS_WARNING=1

# ═══ PHASE C: BATCH PARALLEL MODEL DOWNLOADS ═══
# aria2c batch input file → all 57 files at once, 8 concurrent streams,
# 16 connections per file. Saturates the pipe on 32GB+ instances.
# XET-broken files get a second pass via hf_hub_download.

_MANIFEST=/tmp/ofmpath_dl_manifest.txt
_FAILDIR=/tmp/ofmpath_failures
rm -f "$_MANIFEST"
mkdir -p "$_FAILDIR"

_HF_HDR="Authorization: Bearer $HF_TOKEN"

# ── Build aria2c input file ──
# Format: URL\n  dir=X\n  out=Y\n  header=Z\n\n
_add() {
    local dir="$1" file="$2" url="$3"
    mkdir -p "$dir"
    # Skip if already cached (exists + non-empty)
    if [ -f "$dir/$file" ] && [ -s "$dir/$file" ]; then
        return
    fi
    local dl_url="$url"
    [[ "$dl_url" =~ huggingface\.co ]] && [[ "$dl_url" =~ /resolve/ ]] && [[ "$dl_url" != *"?download=true"* ]] && dl_url="${dl_url}?download=true"
    echo "$dl_url" >> "$_MANIFEST"
    echo "  dir=$dir" >> "$_MANIFEST"
    echo "  out=$file" >> "$_MANIFEST"
    if [[ "$url" =~ huggingface\.co ]] && [ -n "${HF_TOKEN:-}" ]; then
        echo "  header=$_HF_HDR" >> "$_MANIFEST"
    fi
    echo "" >> "$_MANIFEST"
}

# DIFFUSION (3)
_add "$MODELS/diffusion_models" "z_image_turbo_bf16.safetensors" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
_add "$MODELS/diffusion_models" "z-image-turbo-fp8-e4m3fn.safetensors" \
    "https://huggingface.co/T5B/Z-Image-Turbo-FP8/resolve/main/z-image-turbo-fp8-e4m3fn.safetensors"
_add "$MODELS/diffusion_models" "WanModel.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanModel.safetensors"

# TEXT ENCODERS (3)
_add "$MODELS/text_encoders" "qwen_3_4b.safetensors" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors"
_add "$MODELS/text_encoders" "umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors" \
    "https://huggingface.co/UmeAiRT/ComfyUI-Auto_installer/resolve/refs%2Fpr%2F5/models/clip/umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors"
_add "$MODELS/text_encoders" "text_enc.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/text_enc.safetensors"

# CLIP VISION (2)
_add "$MODELS/clip_vision" "klip_vision.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors"
_add "$MODELS/clip_vision" "clip_vision_h.safetensors" \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"

# VAE (2)
_add "$MODELS/vae" "ae.safetensors" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors"
_add "$MODELS/vae" "vae.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/vae.safetensors"

# CONTROLNET (2)
_add "$MODELS/controlnet" "Wan21_Uni3C_controlnet_fp16.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_Uni3C_controlnet_fp16.safetensors"
_add "$MODELS/controlnet" "Z-Image-Turbo-Fun-Controlnet-Union.safetensors" \
    "https://huggingface.co/arhiteector/zimage/resolve/main/Z-Image-Turbo-Fun-Controlnet-Union.safetensors"

# CHECKPOINTS (1)
_add "$MODELS/checkpoints" "detect.safetensors" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/detect.safetensors"

# LORAS (7)
_add "$MODELS/loras" "real.safetensors" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/real.safetensors"
_add "$MODELS/loras" "XXX.safetensors" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/XXX.safetensors"
_add "$MODELS/loras" "gpu.safetensors" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/gpu.safetensors"
_add "$MODELS/loras" "WanFun.reworked.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanFun.reworked.safetensors"
_add "$MODELS/loras" "light.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/light.safetensors"
_add "$MODELS/loras" "WanPusa.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanPusa.safetensors"
_add "$MODELS/loras" "wan.reworked.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/wan.reworked.safetensors"

# LIPSYNC-SPECIFIC (6)
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
_add "$MODELS/diffusion_models/InfiniteTalk" "Wan2_1-InfiniteTalk-Single_fp8_e4m3fn_scaled_KJ.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/InfiniteTalk/Wan2_1-InfiniteTalk-Single_fp8_e4m3fn_scaled_KJ.safetensors"

# DETECTION (3) — XET-broken, handled by _hf_direct after batch
# (vitpose + yolov10m excluded from aria2c batch)

# SAM (1) — handled by _hf_direct

# UPSCALER (1)
_add "$MODELS/upscale_models" "4xUltrasharp_4xUltrasharpV10.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/4xUltrasharp_4xUltrasharpV10.pt"

# ULTRALYTICS BBOX (11) — face/hand/foot XET-broken, handled by _hf_direct
_add "$MODELS/ultralytics/bbox" "femaleBodyDetection_yolo26.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/femaleBodyDetection_yolo26.pt"
_add "$MODELS/ultralytics/bbox" "female_breast-v4.2.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/female_breast-v4.2.pt"
_add "$MODELS/ultralytics/bbox" "nipples_yolov8s.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/nipples_yolov8s.pt"
_add "$MODELS/ultralytics/bbox" "vagina-v4.2.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/vagina-v4.2.pt"
_add "$MODELS/ultralytics/bbox" "assdetailer.pt" \
    "https://huggingface.co/gazsuv/xmode/resolve/main/assdetailer.pt"
_add "$MODELS/ultralytics/bbox" "Eyeful_v2-Paired.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/Eyeful_v2-Paired.pt"
_add "$MODELS/ultralytics/bbox" "Eyes.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/Eyes.pt"
_add "$MODELS/ultralytics/bbox" "FacesV1.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/FacesV1.pt"

# QWEN3 VL (13)
_QWEN_DIR="$MODELS/LLM/Qwen3-VL-4B-Instruct-heretic-7refusal"
_QWEN_BASE="https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main"
_add "$_QWEN_DIR" "added_tokens.json"            "$_QWEN_BASE/added_tokens.json"
_add "$_QWEN_DIR" "chat_template.jinja"          "$_QWEN_BASE/chat_template.jinja"
_add "$_QWEN_DIR" "config.json"                  "$_QWEN_BASE/config.json"
_add "$_QWEN_DIR" "generation_config.json"       "$_QWEN_BASE/generation_config.json"
_add "$_QWEN_DIR" "merges.txt"                   "$_QWEN_BASE/merges.txt"
_add "$_QWEN_DIR" "model.safetensors.index.json" "$_QWEN_BASE/model.safetensors.index.json"
_add "$_QWEN_DIR" "preprocessor_config.json"     "$_QWEN_BASE/preprocessor_config.json"
_add "$_QWEN_DIR" "special_tokens_map.json"      "$_QWEN_BASE/special_tokens_map.json"
_add "$_QWEN_DIR" "tokenizer.json"               "$_QWEN_BASE/tokenizer.json"
_add "$_QWEN_DIR" "tokenizer_config.json"        "$_QWEN_BASE/tokenizer_config.json"
_add "$_QWEN_DIR" "vocab.json"                   "$_QWEN_BASE/vocab.json"
_add "$_QWEN_DIR" "model-00001-of-00002.safetensors" "$_QWEN_BASE/model-00001-of-00002.safetensors"
_add "$_QWEN_DIR" "model-00002-of-00002.safetensors" "$_QWEN_BASE/model-00002-of-00002.safetensors"

# SEEDVR2 (2)
_add "$MODELS/SEEDVR2" "seedvr2_ema_7b_sharp_fp16.safetensors" \
    "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_7b_sharp_fp16.safetensors"
_add "$MODELS/SEEDVR2" "ema_vae_fp16.safetensors" \
    "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors"

# ── Run aria2c batch ──
_NEED_DL=$(grep -c '^http' "$_MANIFEST" 2>/dev/null || echo 0)
if [ "$_NEED_DL" -gt 0 ]; then
    echo "[OFM-INNER] Downloading $_NEED_DL models via aria2c (8 concurrent × 16 conn each)..."
    timeout 3600 aria2c \
        --input-file="$_MANIFEST" \
        --max-concurrent-downloads=8 \
        --split=16 \
        --max-connection-per-server=16 \
        --min-split-size=1M \
        --continue=true \
        --auto-file-renaming=false \
        --allow-overwrite=true \
        --console-log-level=warn \
        --summary-interval=10 \
        --download-result=full \
        2>&1 | tail -30
    echo "[PROGRESS: 80]"
else
    echo "[OFM-INNER] All models cached, skipping downloads"
    echo "[PROGRESS: 80]"
fi
rm -f "$_MANIFEST"

# ── Direct hf_hub_download for XET-broken repos ──
# These repos break aria2c (returns HTML error pages as valid 200 responses).
# Download them ONLY via hf_hub_download — never through aria2c.
echo "[OFM-INNER] Downloading XET-incompatible models via hf_hub..."
_hf_direct() {
    local dir="$1" file="$2" repo="$3" rpath="$4"
    if [ -f "$dir/$file" ] && [ -s "$dir/$file" ]; then
        echo "  [ok] $file (cached)"
        return 0
    fi
    echo "  [hf-hub] $file ← $repo/$rpath"
    mkdir -p "$dir"
    python3 -c "
import shutil, os
from huggingface_hub import hf_hub_download
p = hf_hub_download(repo_id='$repo', filename='$rpath', token=False)
os.makedirs('$dir', exist_ok=True)
shutil.copy2(p, '$dir/$file')
print(f'    OK: {os.path.getsize(\"$dir/$file\")} bytes')
" 2>&1 || echo "  [✗] FAILED: $file"
}
_hf_direct "$MODELS/ultralytics/bbox" "face_yolov8s.pt"              "Bingsu/adetailer" "face_yolov8s.pt"
_hf_direct "$MODELS/ultralytics/bbox" "hand_yolov8s.pt"              "Bingsu/adetailer" "hand_yolov8s.pt"
_hf_direct "$MODELS/detection" "vitpose_h_wholebody_model.onnx"      "Kijai/vitpose_comfy" "onnx/vitpose_h_wholebody_model.onnx"
_hf_direct "$MODELS/detection" "vitpose_h_wholebody_data.bin"        "Kijai/vitpose_comfy" "onnx/vitpose_h_wholebody_data.bin"
_hf_direct "$MODELS/detection" "yolov10m.onnx"                       "Wan-AI/Wan2.2-Animate-14B" "process_checkpoint/det/yolov10m.onnx"
_hf_direct "$MODELS/ultralytics/bbox" "foot-yolov8l.pt"              "AunyMoons/loras-pack" "foot-yolov8l.pt"
_hf_direct "$MODELS/sams" "sam_vit_b_01ec64.pth"                     "datasets/Gourieff/ReActor" "models/sams/sam_vit_b_01ec64.pth"

# ── Verify remaining aria2c downloads, fallback via hf_hub if missing ──
echo "[OFM-INNER] Verifying aria2c downloads..."
_hf_fallback() {
    local dir="$1" file="$2" repo="$3" rpath="$4"
    if [ -f "$dir/$file" ] && [ -s "$dir/$file" ]; then
        return 0
    fi
    echo "  [hf-hub] $file ← $repo/$rpath"
    mkdir -p "$dir"
    python3 -c "
import shutil, os
from huggingface_hub import hf_hub_download
p = hf_hub_download(repo_id='$repo', filename='$rpath', token=False)
os.makedirs('$dir', exist_ok=True)
shutil.copy2(p, '$dir/$file')
print(f'    OK: {os.path.getsize(\"$dir/$file\")} bytes')
" 2>&1 || echo "  [✗] FAILED: $file"
}

# Full sweep: any model still missing gets hf_hub_download
_hf_fallback "$MODELS/diffusion_models" "z_image_turbo_bf16.safetensors" "Comfy-Org/z_image_turbo" "split_files/diffusion_models/z_image_turbo_bf16.safetensors"
_hf_fallback "$MODELS/diffusion_models" "z-image-turbo-fp8-e4m3fn.safetensors" "T5B/Z-Image-Turbo-FP8" "z-image-turbo-fp8-e4m3fn.safetensors"
_hf_fallback "$MODELS/diffusion_models" "WanModel.safetensors" "wdsfdsdf/OFMHUB" "WanModel.safetensors"
_hf_fallback "$MODELS/text_encoders" "qwen_3_4b.safetensors" "Comfy-Org/z_image_turbo" "split_files/text_encoders/qwen_3_4b.safetensors"
_hf_fallback "$MODELS/text_encoders" "umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors" "UmeAiRT/ComfyUI-Auto_installer" "models/clip/umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors"
_hf_fallback "$MODELS/text_encoders" "text_enc.safetensors" "wdsfdsdf/OFMHUB" "text_enc.safetensors"
_hf_fallback "$MODELS/clip_vision" "klip_vision.safetensors" "wdsfdsdf/OFMHUB" "klip_vision.safetensors"
_hf_fallback "$MODELS/clip_vision" "clip_vision_h.safetensors" "Comfy-Org/Wan_2.1_ComfyUI_repackaged" "split_files/clip_vision/clip_vision_h.safetensors"
_hf_fallback "$MODELS/vae" "ae.safetensors" "Comfy-Org/z_image_turbo" "split_files/vae/ae.safetensors"
_hf_fallback "$MODELS/vae" "vae.safetensors" "wdsfdsdf/OFMHUB" "vae.safetensors"
_hf_fallback "$MODELS/controlnet" "Wan21_Uni3C_controlnet_fp16.safetensors" "Kijai/WanVideo_comfy" "Wan21_Uni3C_controlnet_fp16.safetensors"
_hf_fallback "$MODELS/controlnet" "Z-Image-Turbo-Fun-Controlnet-Union.safetensors" "arhiteector/zimage" "Z-Image-Turbo-Fun-Controlnet-Union.safetensors"
_hf_fallback "$MODELS/checkpoints" "detect.safetensors" "gazsuv/sudoku" "detect.safetensors"
_hf_fallback "$MODELS/loras" "real.safetensors" "gazsuv/sudoku" "real.safetensors"
_hf_fallback "$MODELS/loras" "XXX.safetensors" "gazsuv/sudoku" "XXX.safetensors"
_hf_fallback "$MODELS/loras" "gpu.safetensors" "gazsuv/sudoku" "gpu.safetensors"
_hf_fallback "$MODELS/loras" "WanFun.reworked.safetensors" "wdsfdsdf/OFMHUB" "WanFun.reworked.safetensors"
_hf_fallback "$MODELS/loras" "light.safetensors" "wdsfdsdf/OFMHUB" "light.safetensors"
_hf_fallback "$MODELS/loras" "WanPusa.safetensors" "wdsfdsdf/OFMHUB" "WanPusa.safetensors"
_hf_fallback "$MODELS/loras" "wan.reworked.safetensors" "wdsfdsdf/OFMHUB" "wan.reworked.safetensors"
_hf_fallback "$MODELS/loras" "lightx2v_T2V_14B_cfg_step_distill_v2_lora_rank128_bf16.safetensors" "Kijai/WanVideo_comfy" "Lightx2v/lightx2v_T2V_14B_cfg_step_distill_v2_lora_rank128_bf16.safetensors"
_hf_fallback "$MODELS/loras" "Wan2.1-Fun-14B-InP-HPS2.1_reward_lora_comfy.safetensors" "Kijai/Wan2.1-Fun-Reward-LoRAs-comfy" "Wan2.1-Fun-14B-InP-HPS2.1_reward_lora_comfy.safetensors"
_hf_fallback "$MODELS/text_encoders" "umt5-xxl-enc-fp8_e4m3fn.safetensors" "Kijai/WanVideo_comfy" "umt5-xxl-enc-fp8_e4m3fn.safetensors"
_hf_fallback "$MODELS/vae" "Wan2_1_VAE_bf16.safetensors" "Kijai/WanVideo_comfy" "Wan2_1_VAE_bf16.safetensors"
_hf_fallback "$MODELS/diffusion_models" "Wan2_1-I2V-14B-480p_fp8_e4m3fn_scaled_KJ.safetensors" "Kijai/WanVideo_comfy_fp8_scaled" "I2V/Wan2_1-I2V-14B-480p_fp8_e4m3fn_scaled_KJ.safetensors"
_hf_fallback "$MODELS/diffusion_models/InfiniteTalk" "Wan2_1-InfiniteTalk-Single_fp8_e4m3fn_scaled_KJ.safetensors" "Kijai/WanVideo_comfy_fp8_scaled" "InfiniteTalk/Wan2_1-InfiniteTalk-Single_fp8_e4m3fn_scaled_KJ.safetensors"
_hf_fallback "$MODELS/upscale_models" "4xUltrasharp_4xUltrasharpV10.pt" "gazsuv/pussydetectorv4" "4xUltrasharp_4xUltrasharpV10.pt"
_hf_fallback "$MODELS/ultralytics/bbox" "femaleBodyDetection_yolo26.pt" "gazsuv/pussydetectorv4" "femaleBodyDetection_yolo26.pt"
_hf_fallback "$MODELS/ultralytics/bbox" "female_breast-v4.2.pt" "gazsuv/pussydetectorv4" "female_breast-v4.2.pt"
_hf_fallback "$MODELS/ultralytics/bbox" "nipples_yolov8s.pt" "gazsuv/pussydetectorv4" "nipples_yolov8s.pt"
_hf_fallback "$MODELS/ultralytics/bbox" "vagina-v4.2.pt" "gazsuv/pussydetectorv4" "vagina-v4.2.pt"
_hf_fallback "$MODELS/ultralytics/bbox" "assdetailer.pt" "gazsuv/xmode" "assdetailer.pt"
_hf_fallback "$MODELS/ultralytics/bbox" "Eyeful_v2-Paired.pt" "gazsuv/pussydetectorv4" "Eyeful_v2-Paired.pt"
_hf_fallback "$MODELS/ultralytics/bbox" "Eyes.pt" "gazsuv/pussydetectorv4" "Eyes.pt"
_hf_fallback "$MODELS/ultralytics/bbox" "FacesV1.pt" "gazsuv/pussydetectorv4" "FacesV1.pt"
_hf_fallback "$_QWEN_DIR" "added_tokens.json" "svjack/Qwen3-VL-4B-Instruct-heretic-7refusal" "added_tokens.json"
_hf_fallback "$_QWEN_DIR" "chat_template.jinja" "svjack/Qwen3-VL-4B-Instruct-heretic-7refusal" "chat_template.jinja"
_hf_fallback "$_QWEN_DIR" "config.json" "svjack/Qwen3-VL-4B-Instruct-heretic-7refusal" "config.json"
_hf_fallback "$_QWEN_DIR" "generation_config.json" "svjack/Qwen3-VL-4B-Instruct-heretic-7refusal" "generation_config.json"
_hf_fallback "$_QWEN_DIR" "merges.txt" "svjack/Qwen3-VL-4B-Instruct-heretic-7refusal" "merges.txt"
_hf_fallback "$_QWEN_DIR" "model.safetensors.index.json" "svjack/Qwen3-VL-4B-Instruct-heretic-7refusal" "model.safetensors.index.json"
_hf_fallback "$_QWEN_DIR" "preprocessor_config.json" "svjack/Qwen3-VL-4B-Instruct-heretic-7refusal" "preprocessor_config.json"
_hf_fallback "$_QWEN_DIR" "special_tokens_map.json" "svjack/Qwen3-VL-4B-Instruct-heretic-7refusal" "special_tokens_map.json"
_hf_fallback "$_QWEN_DIR" "tokenizer.json" "svjack/Qwen3-VL-4B-Instruct-heretic-7refusal" "tokenizer.json"
_hf_fallback "$_QWEN_DIR" "tokenizer_config.json" "svjack/Qwen3-VL-4B-Instruct-heretic-7refusal" "tokenizer_config.json"
_hf_fallback "$_QWEN_DIR" "vocab.json" "svjack/Qwen3-VL-4B-Instruct-heretic-7refusal" "vocab.json"
_hf_fallback "$_QWEN_DIR" "model-00001-of-00002.safetensors" "svjack/Qwen3-VL-4B-Instruct-heretic-7refusal" "model-00001-of-00002.safetensors"
_hf_fallback "$_QWEN_DIR" "model-00002-of-00002.safetensors" "svjack/Qwen3-VL-4B-Instruct-heretic-7refusal" "model-00002-of-00002.safetensors"
_hf_fallback "$MODELS/SEEDVR2" "seedvr2_ema_7b_sharp_fp16.safetensors" "numz/SeedVR2_comfyUI" "seedvr2_ema_7b_sharp_fp16.safetensors"
_hf_fallback "$MODELS/SEEDVR2" "ema_vae_fp16.safetensors" "numz/SeedVR2_comfyUI" "ema_vae_fp16.safetensors"

echo "[PROGRESS: 88]"


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE C.5 — MODEL PATH FIXES + CRITICAL VERIFICATION
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase C.5: Model path fixes + verification ━━━"

echo ""

# Fix 1: Copy 4xUltrasharp to checkpoints (some workflows expect it there instead of upscale_models)
mkdir -p "$MODELS/checkpoints"
if [ -f "$MODELS/upscale_models/4xUltrasharp_4xUltrasharpV10.pt" ]; then
    cp "$MODELS/upscale_models/4xUltrasharp_4xUltrasharpV10.pt" "$MODELS/checkpoints/"
    echo "[OFM-INNER] ✓ Copied 4xUltrasharp to checkpoints"
fi

# Fix 2: Copy Eyeful_v2 to checkpoints/bbox (workflow expects checkpoints/bbox NOT ultralytics/bbox)
mkdir -p "$MODELS/checkpoints/bbox"
if [ -f "$MODELS/ultralytics/bbox/Eyeful_v2-Paired.pt" ]; then
    cp "$MODELS/ultralytics/bbox/Eyeful_v2-Paired.pt" "$MODELS/checkpoints/bbox/"
    echo "[OFM-INNER] ✓ Copied Eyeful_v2 to checkpoints/bbox"
fi

# Fix 3: Copy face/hand detectors to checkpoints/bbox (some workflows use different paths)
if [ -f "$MODELS/ultralytics/bbox/face_yolov8s.pt" ]; then
    cp "$MODELS/ultralytics/bbox/face_yolov8s.pt" "$MODELS/checkpoints/bbox/" 2>/dev/null || true
    echo "[OFM-INNER] ✓ Copied face_yolov8s to checkpoints/bbox"
fi
if [ -f "$MODELS/ultralytics/bbox/hand_yolov8s.pt" ]; then
    cp "$MODELS/ultralytics/bbox/hand_yolov8s.pt" "$MODELS/checkpoints/bbox/" 2>/dev/null || true
    echo "[OFM-INNER] ✓ Copied hand_yolov8s to checkpoints/bbox"
fi
echo "[OFM-INNER] ✓ Path fixes applied"

# Fix 5: LIPSYNC workflow expects loras in checkpoints/ (detect-style references)
for _f in gpu.safetensors real.safetensors XXX.safetensors; do
    if [ -f "$MODELS/loras/$_f" ]; then
        cp "$MODELS/loras/$_f" "$MODELS/checkpoints/" 2>/dev/null || true
    fi
done
echo "[OFM-INNER] ✓ Copied gpu/real/XXX loras to checkpoints"

# Fix 6: LIPSYNC expects bbox detectors in checkpoints/bbox
for _f in assdetailer.pt female_breast-v4.2.pt vagina-v4.2.pt; do
    if [ -f "$MODELS/ultralytics/bbox/$_f" ]; then
        cp "$MODELS/ultralytics/bbox/$_f" "$MODELS/checkpoints/bbox/" 2>/dev/null || true
    fi
done
echo "[OFM-INNER] ✓ Copied LIPSYNC bbox models to checkpoints/bbox"

# ── v3: Additional path mirrors for cross-workflow compat ──
# Some Impact Pack nodes search ultralytics/bbox, others search checkpoints/bbox.
# Ensure ALL bbox models exist in BOTH locations.
echo "[OFM-INNER] Syncing bbox models across ultralytics/bbox ↔ checkpoints/bbox..."
mkdir -p "$MODELS/ultralytics/bbox" "$MODELS/checkpoints/bbox"
for _f in "$MODELS/ultralytics/bbox"/*.pt; do
    [ -f "$_f" ] || continue
    _bn=$(basename "$_f")
    if [ ! -f "$MODELS/checkpoints/bbox/$_bn" ]; then
        cp "$_f" "$MODELS/checkpoints/bbox/" 2>/dev/null || true
    fi
done
for _f in "$MODELS/checkpoints/bbox"/*.pt; do
    [ -f "$_f" ] || continue
    _bn=$(basename "$_f")
    if [ ! -f "$MODELS/ultralytics/bbox/$_bn" ]; then
        cp "$_f" "$MODELS/ultralytics/bbox/" 2>/dev/null || true
    fi
done
echo "[OFM-INNER] ✓ Bbox model sync complete"


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE D — DEPLOY WORKFLOWS
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase D: Deploy workflows ━━━"
echo "[PROGRESS: 90]"

_deploy_workflow() {
    local src="$1" name="$2"
    if [ -z "$src" ] || [ ! -f "$src" ]; then
        echo "  [!] Skipped: $name (not fetched)"
        return
    fi
    cp "$src" "$COMFYUI_DIR/$name" 2>/dev/null && echo "  [✓] $COMFYUI_DIR/$name"
    cp "$src" "$WORKFLOWS_DIR/$name" 2>/dev/null && echo "  [✓] $WORKFLOWS_DIR/$name"
    cp "$src" "$COMFYUI_DIR/input/$name" 2>/dev/null && echo "  [✓] input/$name"
    # Overwrite defaultGraph.json in any frontend location so the workflow autoloads
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

_deploy_workflow "$WORKFLOW_MOTION"  "OFMPATH ANIMATOR.json"
_deploy_workflow "$WORKFLOW_T2I"     "OFMPATH T2I.json"
_deploy_workflow "$WORKFLOW_LIPSYNC" "OFMPATH LIPSYNC.json"

rm -f /tmp/motion.json /tmp/t2i.json /tmp/lipsync.json


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE E — COMFYUI SETTINGS
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase E: ComfyUI settings ━━━"
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
echo -e "\n━━━ Phase F: Inventory ━━━"
_total_files=0
for _d in diffusion_models diffusion_models/InfiniteTalk text_encoders clip_vision vae controlnet loras checkpoints sams upscale_models detection ultralytics/bbox LLM SEEDVR2; do
    _p="$MODELS/$_d"
    [ -d "$_p" ] || continue
    _n=$(find "$_p" -maxdepth 1 -type f 2>/dev/null | wc -l)
    _sz=$(du -sh "$_p" 2>/dev/null | cut -f1)
    printf "  %-30s %3d files  %s\n" "$_d" "$_n" "$_sz"
    _total_files=$((_total_files + _n))
done
echo "  ──────────────────────────────────────────"
echo "  Total model files:  $_total_files"
echo "  Disk free: $(df -h "$MODELS" 2>/dev/null | tail -1 | awk '{print $4 " / " $2}')"

CUSTOM_NODE_COUNT=$(ls -1 "$CUSTOM_NODES_DIR" 2>/dev/null | wc -l)
WF_COUNT=$(find "$WORKFLOWS_DIR" -maxdepth 1 -iname "*.json" 2>/dev/null | wc -l)
echo "  Custom nodes: $CUSTOM_NODE_COUNT"
echo "  Workflows in workflows dir: $WF_COUNT"

# ── v3: Final critical model audit ──
echo ""
echo "━━━ Critical Model Audit ━━━"
_AUDIT_FAIL=0
_audit() {
    local path="$1" label="$2"
    if [ -f "$path" ] && [ -s "$path" ]; then
        printf "  ✓ %-45s %s\n" "$label" "$(stat -c%s "$path") bytes"
    else
        printf "  ✗ %-45s MISSING\n" "$label"
        _AUDIT_FAIL=$((_AUDIT_FAIL + 1))
    fi
}
_audit "$MODELS/ultralytics/bbox/face_yolov8s.pt"      "face_yolov8s.pt [T2I]"
_audit "$MODELS/ultralytics/bbox/hand_yolov8s.pt"      "hand_yolov8s.pt [T2I]"
_audit "$MODELS/detection/vitpose_h_wholebody_model.onnx" "vitpose_h_wholebody_model.onnx [ANIMATOR]"
_audit "$MODELS/detection/vitpose_h_wholebody_data.bin"   "vitpose_h_wholebody_data.bin [ANIMATOR]"
_audit "$MODELS/detection/yolov10m.onnx"                  "yolov10m.onnx [ANIMATOR]"
_audit "$MODELS/ultralytics/bbox/foot-yolov8l.pt"       "foot-yolov8l.pt [T2I]"

if [ $_AUDIT_FAIL -gt 0 ]; then
    echo "  ⚠ $_AUDIT_FAIL critical models still missing — check network/HF access"
else
    echo "  ✓ All critical models present"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  ✅ OFM PATH 智慧通路 — Inner installer complete              ║"
echo "╠════════════════════════════════════════════════════════════════╣"
printf "║  Models: %-3d · Nodes: %-3d · Workflows: %-2d                      ║\n" "$_total_files" "$CUSTOM_NODE_COUNT" "$WF_COUNT"
echo "╚════════════════════════════════════════════════════════════════╝"

exit 0
