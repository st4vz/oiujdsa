#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
#  OFM PATH 智慧通路 — Inner Installer  (hardened v2)
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
echo "║  MOTION CONTROL + TEXT TO IMAGE                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE A — FETCH + DECRYPT WORKFLOWS
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase A: Fetch workflows ━━━"
echo "[PROGRESS: 35]"

mkdir -p "$WORKFLOWS_DIR" "$COMFYUI_DIR/input"

WORKFLOW_MOTION=""
WORKFLOW_T2I=""

if _fetch_secure "ofmpath_motion.json.enc" /tmp/motion.enc; then
    echo "[OFM-INNER] Fetched motion ($(stat -c%s /tmp/motion.enc) bytes)"
    if _decrypt_secure /tmp/motion.enc /tmp/motion.json; then
        if python3 -c "import json; d=json.load(open('/tmp/motion.json')); assert 'nodes' in d" 2>/dev/null; then
            WORKFLOW_MOTION=/tmp/motion.json
            echo "[OFM-INNER] ✓ MOTION CONTROL workflow decrypted + validated"
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
            echo "[OFM-INNER] ✓ TEXT TO IMAGE workflow decrypted + validated"
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


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE B — INSTALL CUSTOM NODES (28)
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
        local pct=$(( 42 + (_NODE_IDX * 12 / 28) ))
        echo "[PROGRESS: ${pct}]"

        if [ -d "$name" ]; then
            echo "  [ok] $name (${_NODE_IDX}/28) [already present]"
        else
            echo "  [+] $name (${_NODE_IDX}/28) cloning..."
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
    _install_node "ComfyUI-Crystools"              "https://github.com/crystian/ComfyUI-Crystools"
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
#  PHASE C — DOWNLOAD MODELS (49)
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase C: Download models ━━━"
echo "[PROGRESS: 55]"
echo "Found 49 models to verify"

_MODEL_IDX=0
_MODEL_TOTAL=49

_dl() {
    local dir="$1" file="$2" url="$3" label="${4:-asset}"
    _MODEL_IDX=$((_MODEL_IDX + 1))
    local pct=$(( 55 + (_MODEL_IDX * 35 / _MODEL_TOTAL) ))
    mkdir -p "$dir"
    echo "[STARTING] '${label}'"
    # Better cache check: must exist AND be bigger than 1KB (most config files are ≥1KB, real weights are MBs)
    if [ -f "$dir/$file" ] && [ "$(stat -c%s "$dir/$file" 2>/dev/null || echo 0)" -gt 1024 ]; then
        echo "  [ok] cached ($(stat -c%s "$dir/$file") bytes)"
        echo "[SUCCESS]"
        echo "[PROGRESS: ${pct}]"
        return
    fi
    # Tiny files (json, txt) don't need the 1KB check — accept any non-empty
    if [ -f "$dir/$file" ] && [ -s "$dir/$file" ] && [[ "$file" =~ \.(json|txt|jinja)$ ]]; then
        echo "  [ok] cached (small file)"
        echo "[SUCCESS]"
        echo "[PROGRESS: ${pct}]"
        return
    fi

    local hdr=""
    [[ "$url" =~ huggingface\.co ]] && hdr="Authorization: Bearer $HF_TOKEN"

    if command -v aria2c >/dev/null 2>&1; then
        if [ -n "$hdr" ]; then
            timeout 1800 aria2c --console-log-level=error -c -x 16 -s 16 -k 1M --header="$hdr" \
                -d "$dir" -o "$file" "$url" >/dev/null 2>&1 \
                || timeout 1800 curl -fsSL --retry 2 -H "$hdr" -o "$dir/$file" "$url" 2>/dev/null
        else
            timeout 1800 aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
                -d "$dir" -o "$file" "$url" >/dev/null 2>&1 \
                || timeout 1800 curl -fsSL --retry 2 -o "$dir/$file" "$url" 2>/dev/null
        fi
    else
        if [ -n "$hdr" ]; then
            timeout 1800 curl -fsSL --retry 2 -H "$hdr" -o "$dir/$file" "$url" 2>/dev/null
        else
            timeout 1800 curl -fsSL --retry 2 -o "$dir/$file" "$url" 2>/dev/null
        fi
    fi

    if [ -f "$dir/$file" ] && [ -s "$dir/$file" ]; then
        echo "  [dl] $(stat -c%s "$dir/$file") bytes"
        echo "[SUCCESS]"
    else
        echo "[FAILED] $label"
    fi
    echo "[PROGRESS: ${pct}]"
}

# DIFFUSION (3)
_dl "$MODELS/diffusion_models" "z_image_turbo_bf16.safetensors" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors" "z_image_bf16"
_dl "$MODELS/diffusion_models" "z-image-turbo-fp8-e4m3fn.safetensors" \
    "https://huggingface.co/T5B/Z-Image-Turbo-FP8/resolve/main/z-image-turbo-fp8-e4m3fn.safetensors" "z_image_fp8"
_dl "$MODELS/diffusion_models" "WanModel.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanModel.safetensors" "wan_diffusion"

# TEXT ENCODERS (3)
_dl "$MODELS/text_encoders" "qwen_3_4b.safetensors" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors" "qwen3_4b"
_dl "$MODELS/text_encoders" "umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors" \
    "https://huggingface.co/UmeAiRT/ComfyUI-Auto_installer/resolve/refs%2Fpr%2F5/models/clip/umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors" "umt5xxl"
_dl "$MODELS/text_encoders" "text_enc.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/text_enc.safetensors" "text_enc"

# CLIP VISION (2)
_dl "$MODELS/clip_vision" "klip_vision.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors" "clip_vision_k"
_dl "$MODELS/clip_vision" "clip_vision_h.safetensors" \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors" "clip_vision_h"

# VAE (2)
_dl "$MODELS/vae" "ae.safetensors" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors" "vae_ae"
_dl "$MODELS/vae" "vae.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/vae.safetensors" "vae_wan"

# CONTROLNET (2)
_dl "$MODELS/controlnet" "Wan21_Uni3C_controlnet_fp16.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_Uni3C_controlnet_fp16.safetensors" "ctrl_wan"
_dl "$MODELS/controlnet" "Z-Image-Turbo-Fun-Controlnet-Union.safetensors" \
    "https://huggingface.co/arhiteector/zimage/resolve/main/Z-Image-Turbo-Fun-Controlnet-Union.safetensors" "ctrl_zimg"

# CHECKPOINTS (1)
_dl "$MODELS/checkpoints" "detect.safetensors" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/detect.safetensors" "ckpt_detect"

# LORAS (7)
_dl "$MODELS/loras" "real.safetensors" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/real.safetensors" "lora_real"
_dl "$MODELS/loras" "XXX.safetensors" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/XXX.safetensors" "lora_xxx"
_dl "$MODELS/loras" "gpu.safetensors" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/gpu.safetensors" "lora_gpu"
_dl "$MODELS/loras" "WanFun.reworked.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanFun.reworked.safetensors" "lora_wanfun"
_dl "$MODELS/loras" "light.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/light.safetensors" "lora_light"
_dl "$MODELS/loras" "WanPusa.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanPusa.safetensors" "lora_pusa"
_dl "$MODELS/loras" "wan.reworked.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/wan.reworked.safetensors" "lora_wanrw"

# DETECTION (3)
_dl "$MODELS/detection" "yolov10m.onnx" \
    "https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx" "det_yolo"
_dl "$MODELS/detection" "vitpose_h_wholebody_data.bin" \
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_data.bin" "det_vitpose_data"
_dl "$MODELS/detection" "vitpose_h_wholebody_model.onnx" \
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_model.onnx" "det_vitpose_model"

# SAM (1)
_dl "$MODELS/sams" "sam_vit_b_01ec64.pth" \
    "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/sams/sam_vit_b_01ec64.pth" "sam_vit_b"

# UPSCALER (1)
_dl "$MODELS/upscale_models" "4xUltrasharp_4xUltrasharpV10.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/4xUltrasharp_4xUltrasharpV10.pt" "upscaler"

# ULTRALYTICS BBOX (11)
_dl "$MODELS/ultralytics/bbox" "face_yolov8s.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/face_yolov8s.pt" "bbox_face"
_dl "$MODELS/ultralytics/bbox" "femaleBodyDetection_yolo26.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/femaleBodyDetection_yolo26.pt" "bbox_body"
_dl "$MODELS/ultralytics/bbox" "female_breast-v4.2.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/female_breast-v4.2.pt" "bbox_breast"
_dl "$MODELS/ultralytics/bbox" "nipples_yolov8s.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/nipples_yolov8s.pt" "bbox_nipples"
_dl "$MODELS/ultralytics/bbox" "vagina-v4.2.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/vagina-v4.2.pt" "bbox_vagina"
_dl "$MODELS/ultralytics/bbox" "assdetailer.pt" \
    "https://huggingface.co/gazsuv/xmode/resolve/main/assdetailer.pt" "bbox_ass"
_dl "$MODELS/ultralytics/bbox" "Eyeful_v2-Paired.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/Eyeful_v2-Paired.pt" "bbox_eyes_v2"
_dl "$MODELS/ultralytics/bbox" "Eyes.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/Eyes.pt" "bbox_eyes"
_dl "$MODELS/ultralytics/bbox" "FacesV1.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/FacesV1.pt" "bbox_faces"
_dl "$MODELS/ultralytics/bbox" "hand_yolov8s.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/hand_yolov8s.pt" "bbox_hand"
_dl "$MODELS/ultralytics/bbox" "foot-yolov8l.pt" \
    "https://huggingface.co/AunyMoons/loras-pack/resolve/main/foot-yolov8l.pt" "bbox_foot"

# QWEN3 VL (13)
_QWEN_DIR="$MODELS/LLM/Qwen3-VL-4B-Instruct-heretic-7refusal"
_QWEN_BASE="https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main"
_dl "$_QWEN_DIR" "added_tokens.json"            "$_QWEN_BASE/added_tokens.json"            "qwen_added"
_dl "$_QWEN_DIR" "chat_template.jinja"          "$_QWEN_BASE/chat_template.jinja"          "qwen_chat"
_dl "$_QWEN_DIR" "config.json"                  "$_QWEN_BASE/config.json"                  "qwen_config"
_dl "$_QWEN_DIR" "generation_config.json"       "$_QWEN_BASE/generation_config.json"       "qwen_gen"
_dl "$_QWEN_DIR" "merges.txt"                   "$_QWEN_BASE/merges.txt"                   "qwen_merges"
_dl "$_QWEN_DIR" "model.safetensors.index.json" "$_QWEN_BASE/model.safetensors.index.json" "qwen_idx"
_dl "$_QWEN_DIR" "preprocessor_config.json"     "$_QWEN_BASE/preprocessor_config.json"     "qwen_pre"
_dl "$_QWEN_DIR" "special_tokens_map.json"      "$_QWEN_BASE/special_tokens_map.json"      "qwen_spc"
_dl "$_QWEN_DIR" "tokenizer.json"               "$_QWEN_BASE/tokenizer.json"               "qwen_tok"
_dl "$_QWEN_DIR" "tokenizer_config.json"        "$_QWEN_BASE/tokenizer_config.json"        "qwen_tokcfg"
_dl "$_QWEN_DIR" "vocab.json"                   "$_QWEN_BASE/vocab.json"                   "qwen_vocab"
_dl "$_QWEN_DIR" "model-00001-of-00002.safetensors" "$_QWEN_BASE/model-00001-of-00002.safetensors" "qwen_shard1"
_dl "$_QWEN_DIR" "model-00002-of-00002.safetensors" "$_QWEN_BASE/model-00002-of-00002.safetensors" "qwen_shard2"

echo "[OFM-INNER] ✓ Phase C model downloads complete"


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

_deploy_workflow "$WORKFLOW_MOTION" "MOTION CONTROL.json"
_deploy_workflow "$WORKFLOW_T2I"    "TEXT TO IMAGE.json"

rm -f /tmp/motion.json /tmp/t2i.json


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
    "Comfy.Sidebar.Size": "small"
}
SETTINGSJSON
echo "[OFM-INNER] ✓ Settings written"


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE F — INVENTORY REPORT
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase F: Inventory ━━━"
_total_files=0
for _d in diffusion_models text_encoders clip_vision vae controlnet loras checkpoints sams upscale_models detection ultralytics/bbox LLM; do
    _p="$MODELS/$_d"
    [ -d "$_p" ] || continue
    _n=$(find "$_p" -type f 2>/dev/null | wc -l)
    _sz=$(du -sh "$_p" 2>/dev/null | cut -f1)
    printf "  %-22s %3d files  %s\n" "$_d" "$_n" "$_sz"
    _total_files=$((_total_files + _n))
done
echo "  ──────────────────────────────────────────"
echo "  Total model files:  $_total_files"
echo "  Disk free: $(df -h "$MODELS" 2>/dev/null | tail -1 | awk '{print $4 " / " $2}')"

CUSTOM_NODE_COUNT=$(ls -1 "$CUSTOM_NODES_DIR" 2>/dev/null | wc -l)
WF_COUNT=$(find "$WORKFLOWS_DIR" -maxdepth 1 -iname "*.json" 2>/dev/null | wc -l)
echo "  Custom nodes: $CUSTOM_NODE_COUNT"
echo "  Workflows in workflows dir: $WF_COUNT"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  ✅ OFM PATH 智慧通路 — Inner installer complete              ║"
echo "╠════════════════════════════════════════════════════════════════╣"
printf "║  Models: %-3d · Nodes: %-3d · Workflows: %-2d                      ║\n" "$_total_files" "$CUSTOM_NODE_COUNT" "$WF_COUNT"
echo "╚════════════════════════════════════════════════════════════════╝"

exit 0
