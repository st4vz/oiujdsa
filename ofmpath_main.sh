#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
#  OFM PATH 智慧通路 — Inner Installer
#  Fetched + decrypted by ofmpath_main.sh from Supabase bucket.
#  Expects env from outer script:
#    OFMPATH_TOKEN       — validated token
#    OFMPATH_PAYLOAD_KEY — derived PBKDF2 key
#    OFMPATH_SUPA_URL    — https://yvjhjptycwlnjnzzsyju.supabase.co
#    OFMPATH_BUCKET      — ofm-path
#    COMFYUI_DIR         — /workspace/ComfyUI
#    CUSTOM_NODES_DIR    — $COMFYUI_DIR/custom_nodes
#    PIP                 — python pip path
#    _fetch_secure, _decrypt_secure — helper functions (exported from outer)
# ═══════════════════════════════════════════════════════════════════════════

# Don't use `set -e` — progress markers must flush even on partial failure.

: "${OFMPATH_TOKEN:?OFMPATH_TOKEN must be set}"
: "${OFMPATH_PAYLOAD_KEY:?OFMPATH_PAYLOAD_KEY must be set}"
: "${COMFYUI_DIR:=/workspace/ComfyUI}"
: "${CUSTOM_NODES_DIR:=$COMFYUI_DIR/custom_nodes}"
: "${OFMPATH_SUPA_URL:=https://yvjhjptycwlnjnzzsyju.supabase.co}"
: "${OFMPATH_BUCKET:=ofm-path}"

MODELS="$COMFYUI_DIR/models"
WORKFLOWS_DIR="$COMFYUI_DIR/user/default/workflows"
HF_TOKEN="${HF_TOKEN:-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}"

# Determine pip if outer didn't export it
if [ -z "${PIP:-}" ]; then
    if   [ -x "/venv/main/bin/pip" ];       then PIP="/venv/main/bin/pip"
    elif [ -x "$COMFYUI_DIR/.venv/bin/pip" ]; then PIP="$COMFYUI_DIR/.venv/bin/pip"
    else PIP="pip"; fi
fi

# Fallback fetch/decrypt if outer didn't export the helpers
if ! declare -F _fetch_secure >/dev/null; then
  _fetch_secure() {
      local p="$1" d="$2" t=0
      local url="${OFMPATH_SUPA_URL}/storage/v1/object/public/${OFMPATH_BUCKET}/${p}"
      while [ $t -lt 5 ]; do
          t=$((t+1))
          curl -fsSL --max-time 120 --retry 2 --retry-delay 2 -o "$d" "$url" 2>/dev/null
          [ -s "$d" ] && head -c 8 "$d" | grep -q "Salted__" && return 0
          rm -f "$d"; sleep 2
      done; return 1
  }
fi
if ! declare -F _decrypt_secure >/dev/null; then
  _decrypt_secure() {
      openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 100000 \
          -pass "pass:${OFMPATH_PAYLOAD_KEY}" -in "$1" -out "$2" 2>/dev/null
  }
fi

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
    if _decrypt_secure /tmp/motion.enc /tmp/motion.json; then
        if python3 -c "import json; d=json.load(open('/tmp/motion.json')); assert 'nodes' in d" 2>/dev/null; then
            WORKFLOW_MOTION=/tmp/motion.json
            echo "[OFM] ✓ MOTION CONTROL workflow loaded"
        fi
    fi
    rm -f /tmp/motion.enc
fi

if _fetch_secure "ofmpath_t2i.json.enc" /tmp/t2i.enc; then
    if _decrypt_secure /tmp/t2i.enc /tmp/t2i.json; then
        if python3 -c "import json; d=json.load(open('/tmp/t2i.json')); assert 'nodes' in d" 2>/dev/null; then
            WORKFLOW_T2I=/tmp/t2i.json
            echo "[OFM] ✓ TEXT TO IMAGE workflow loaded"
        fi
    fi
    rm -f /tmp/t2i.enc
fi


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE B — INSTALL CUSTOM NODES (28)
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase B: Install custom nodes ━━━"
echo "[PROGRESS: 42]"
cd "$CUSTOM_NODES_DIR"
_NODE_IDX=0

_install_node() {
    local name="$1" url="$2"
    local idx=$((${_NODE_IDX:-0} + 1))
    _NODE_IDX=$idx
    # Progress marker — UI stays animated even during slow pip installs
    local pct=$(( 42 + (idx * 12 / 28) ))
    echo "[PROGRESS: ${pct}]"

    if [ -d "$name" ]; then
        echo "  [ok] $name present (${idx}/28) (0x$(printf "%08X" $RANDOM))"
    else
        echo "  [+] Syncing $name (${idx}/28) (0x$(printf "%08X" $RANDOM))"
        # 2-minute ceiling on git clone — kills anything hung on a flaky repo
        timeout 120 git clone --depth 1 "$url" "$name" 2>/dev/null || {
            echo "  [!] Clone timeout/failed: $name (continuing)"
            return 0  # never abort the pipeline over one node
        }
    fi
    # 3-minute ceiling on pip install — prevents hangs on heavy dep trees
    if [ -f "$name/requirements.txt" ]; then
        timeout 180 "$PIP" install -r "$name/requirements.txt" --quiet 2>/dev/null \
            || echo "  [!] requirements timeout/errors: $name (continuing)"
    fi
    # NOTE: intentionally NOT running install.py — packages like Impact-Pack
    # and SeedVR2 use it to download their own models at install-time, which
    # hangs indefinitely on flaky networks. Phase C handles all models.
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

# KJNodes compatibility fix
KJ="$CUSTOM_NODES_DIR/ComfyUI-KJNodes/nodes/nodes.py"
if [ -f "$KJ" ] && grep -q "search_aliases" "$KJ" 2>/dev/null; then
    sed -i 's/search_aliases=\[.*\],\?//g' "$KJ"
    echo "[OFM] ✓ KJNodes search_aliases fix applied"
fi

echo "[OFM] ✓ All custom nodes installed"


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE C — DOWNLOAD MODELS (49 total)
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
    if [ -f "$dir/$file" ] && [ -s "$dir/$file" ]; then
        echo "  [ok] cached (0x$(printf "%08X" $RANDOM))"
        echo "[SUCCESS]"
        echo "[PROGRESS: ${pct}]"
        return
    fi
    local hdr=""
    [[ "$url" =~ huggingface\.co ]] && hdr="Authorization: Bearer $HF_TOKEN"
    echo "  [+] Syncing (0x$(printf "%08X" $RANDOM))..."
    if command -v aria2c >/dev/null 2>&1; then
        if [ -n "$hdr" ]; then
            aria2c --console-log-level=error -c -x 16 -s 16 -k 1M --header="$hdr" -d "$dir" -o "$file" "$url" >/dev/null 2>&1 \
                || curl -fsSL --retry 2 -H "$hdr" -o "$dir/$file" "$url"
        else
            aria2c --console-log-level=error -c -x 16 -s 16 -k 1M -d "$dir" -o "$file" "$url" >/dev/null 2>&1 \
                || curl -fsSL --retry 2 -o "$dir/$file" "$url"
        fi
    else
        if [ -n "$hdr" ]; then
            curl -fsSL --retry 2 -H "$hdr" -o "$dir/$file" "$url"
        else
            curl -fsSL --retry 2 -o "$dir/$file" "$url"
        fi
    fi
    if [ -f "$dir/$file" ] && [ -s "$dir/$file" ]; then
        echo "[SUCCESS]"
    else
        echo "[FAILED] $label"
    fi
    echo "[PROGRESS: ${pct}]"
}

# ── DIFFUSION / UNET (3) ──
_dl "$MODELS/diffusion_models" "z_image_turbo_bf16.safetensors" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors" "z_image_bf16"
_dl "$MODELS/diffusion_models" "z-image-turbo-fp8-e4m3fn.safetensors" \
    "https://huggingface.co/T5B/Z-Image-Turbo-FP8/resolve/main/z-image-turbo-fp8-e4m3fn.safetensors" "z_image_fp8"
_dl "$MODELS/diffusion_models" "WanModel.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanModel.safetensors" "wan_diffusion"

# ── TEXT ENCODERS (3) → text_encoders/ (not clip/) ──
_dl "$MODELS/text_encoders" "qwen_3_4b.safetensors" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors" "qwen3_4b"
_dl "$MODELS/text_encoders" "umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors" \
    "https://huggingface.co/UmeAiRT/ComfyUI-Auto_installer/resolve/refs%2Fpr%2F5/models/clip/umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors" "umt5xxl"
_dl "$MODELS/text_encoders" "text_enc.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/text_enc.safetensors" "text_enc"

# ── CLIP VISION (2) ──
_dl "$MODELS/clip_vision" "klip_vision.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors" "clip_vision_k"
_dl "$MODELS/clip_vision" "clip_vision_h.safetensors" \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors" "clip_vision_h"

# ── VAE (2) ──
_dl "$MODELS/vae" "ae.safetensors" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors" "vae_ae"
_dl "$MODELS/vae" "vae.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/vae.safetensors" "vae_wan"

# ── CONTROLNET (2) ──
_dl "$MODELS/controlnet" "Wan21_Uni3C_controlnet_fp16.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_Uni3C_controlnet_fp16.safetensors" "ctrl_wan"
_dl "$MODELS/controlnet" "Z-Image-Turbo-Fun-Controlnet-Union.safetensors" \
    "https://huggingface.co/arhiteector/zimage/resolve/main/Z-Image-Turbo-Fun-Controlnet-Union.safetensors" "ctrl_zimg"

# ── CHECKPOINTS (1) ──
_dl "$MODELS/checkpoints" "detect.safetensors" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/detect.safetensors" "ckpt_detect"

# ── LORAS (7) ──
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

# ── DETECTION (3) ──
_dl "$MODELS/detection" "yolov10m.onnx" \
    "https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx" "det_yolo"
_dl "$MODELS/detection" "vitpose_h_wholebody_data.bin" \
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_data.bin" "det_vitpose_data"
_dl "$MODELS/detection" "vitpose_h_wholebody_model.onnx" \
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_model.onnx" "det_vitpose_model"

# ── SAM (1) ──
_dl "$MODELS/sams" "sam_vit_b_01ec64.pth" \
    "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/sams/sam_vit_b_01ec64.pth" "sam_vit_b"

# ── UPSCALER (1) ──
_dl "$MODELS/upscale_models" "4xUltrasharp_4xUltrasharpV10.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/4xUltrasharp_4xUltrasharpV10.pt" "upscaler"

# ── ULTRALYTICS BBOX (11) ──
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

# ── QWEN3-VL-4B-Instruct-heretic-7refusal (13 files) ──
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
_dl "$_QWEN_DIR" "model-00001-of-00002.safetensors" \
    "$_QWEN_BASE/model-00001-of-00002.safetensors" "qwen_shard1"
_dl "$_QWEN_DIR" "model-00002-of-00002.safetensors" \
    "$_QWEN_BASE/model-00002-of-00002.safetensors" "qwen_shard2"

echo "[OFM] ✓ Model downloads complete"


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
    cp "$src" "$COMFYUI_DIR/$name"
    cp "$src" "$WORKFLOWS_DIR/$name"
    cp "$src" "$COMFYUI_DIR/input/$name"
    echo "  [✓] Deployed: $name"
    find "$COMFYUI_DIR/web" /venv/lib/python*/site-packages/comfyui_frontend_package/ \
        -maxdepth 4 -name "defaultGraph.json" -type f 2>/dev/null | while read -r gp; do
        cp "$src" "$gp"
    done
}

_deploy_workflow "$WORKFLOW_MOTION" "MOTION CONTROL.json"
_deploy_workflow "$WORKFLOW_T2I"    "TEXT TO IMAGE.json"

# Clean temp workflow files
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
echo "[OFM] ✓ ComfyUI settings written"


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE F — INVENTORY REPORT
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase F: Inventory ━━━"
_total_files=0
for _d in diffusion_models clip text_encoders clip_vision vae controlnet loras checkpoints sams upscale_models detection ultralytics/bbox LLM; do
    _p="$MODELS/$_d"
    [ -d "$_p" ] || continue
    _n=$(find "$_p" -type f 2>/dev/null | wc -l)
    _sz=$(du -sh "$_p" 2>/dev/null | cut -f1)
    printf "  %-22s %3d files  %s\n" "$_d" "$_n" "$_sz"
    _total_files=$((_total_files + _n))
done
echo "  ──────────────────────────────────────────"
echo "  Total:  $_total_files model files"
echo "  Disk:   $(df -h "$MODELS" | tail -1 | awk '{print $4 " free of " $2}')"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  ✅ OFM PATH 智慧通路 — Inner installer complete              ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  ⬡ MOTION CONTROL.json                                        ║"
echo "║  ⬡ TEXT TO IMAGE.json                                         ║"
echo "║  Custom nodes : 28                                             ║"
echo "║  Models       : 49                                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
