#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
#  OFM PATH 智慧通路 — Inner Installer  (hardened v2 + LIPSYNC)
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
        else echo "[OFM-INNER] ✗ MOTION JSON invalid after decrypt"; fi
    else echo "[OFM-INNER] ✗ MOTION decrypt failed (wrong key?)"; fi
    rm -f /tmp/motion.enc
else echo "[OFM-INNER] ✗ MOTION fetch failed"; fi

if _fetch_secure "ofmpath_t2i.json.enc" /tmp/t2i.enc; then
    echo "[OFM-INNER] Fetched t2i ($(stat -c%s /tmp/t2i.enc) bytes)"
    if _decrypt_secure /tmp/t2i.enc /tmp/t2i.json; then
        if python3 -c "import json; d=json.load(open('/tmp/t2i.json')); assert 'nodes' in d" 2>/dev/null; then
            WORKFLOW_T2I=/tmp/t2i.json
            echo "[OFM-INNER] ✓ OFMPATH T2I workflow decrypted + validated"
        else echo "[OFM-INNER] ✗ T2I JSON invalid after decrypt"; fi
    else echo "[OFM-INNER] ✗ T2I decrypt failed"; fi
    rm -f /tmp/t2i.enc
else echo "[OFM-INNER] ✗ T2I fetch failed"; fi

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
#  PHASE B — INSTALL CUSTOM NODES (29)
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase B: Install custom nodes ━━━"
echo "[PROGRESS: 42]"

mkdir -p "$CUSTOM_NODES_DIR"
if ! cd "$CUSTOM_NODES_DIR"; then
    echo "[OFM-INNER] CRITICAL: cannot cd into $CUSTOM_NODES_DIR"
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

    KJ="$CUSTOM_NODES_DIR/ComfyUI-KJNodes/nodes/nodes.py"
    if [ -f "$KJ" ] && grep -q "search_aliases" "$KJ" 2>/dev/null; then
        sed -i 's/search_aliases=\[.*\],\?//g' "$KJ"
        echo "[OFM-INNER] ✓ KJNodes search_aliases fix applied"
    fi

    INSTALLED_NODES=$(ls -1 "$CUSTOM_NODES_DIR" 2>/dev/null | wc -l)
    echo "[OFM-INNER] ✓ Phase B done: $INSTALLED_NODES nodes in $CUSTOM_NODES_DIR"
fi


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE C — DOWNLOAD MODELS
#  Using wget -nc --content-disposition (same method as reference scripts)
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase C: Download models ━━━"
echo "[PROGRESS: 55]"

_dl_files() {
    local dir="$1"; shift
    mkdir -p "$dir"
    for url in "$@"; do
        local file=$(basename "$url" | sed 's/?.*//')
        if [ -f "$dir/$file" ] && [ -s "$dir/$file" ]; then
            echo "  [ok] $file"
            continue
        fi
        echo "  [dl] $file"
        wget -q -nc --content-disposition -P "$dir" "$url" 2>/dev/null || true
    done
}

echo "[OFM-INNER] Downloading T2I models..."
# T2I: clip
_dl_files "$MODELS/clip" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors"
# T2I: text_encoders
_dl_files "$MODELS/text_encoders" \
    "https://huggingface.co/UmeAiRT/ComfyUI-Auto_installer/resolve/refs%2Fpr%2F5/models/clip/umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors"
# T2I: unet
_dl_files "$MODELS/unet" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
# T2I: vae
_dl_files "$MODELS/vae" \
    "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors"
# T2I: ckpt
_dl_files "$MODELS/ckpt" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/detect.safetensors"
# T2I: model_patches (controlnet union)
_dl_files "$MODELS/model_patches" \
    "https://huggingface.co/arhiteector/zimage/resolve/main/Z-Image-Turbo-Fun-Controlnet-Union.safetensors"
# T2I: diffusion_models
_dl_files "$MODELS/diffusion_models" \
    "https://huggingface.co/T5B/Z-Image-Turbo-FP8/resolve/main/z-image-turbo-fp8-e4m3fn.safetensors"
# T2I: bbox detectors (ALL from gazsuv — no Bingsu XET problems)
_dl_files "$MODELS/ultralytics/bbox" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/face_yolov8s.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/femaleBodyDetection_yolo26.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/female_breast-v4.2.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/nipples_yolov8s.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/vagina-v4.2.pt" \
    "https://huggingface.co/gazsuv/xmode/resolve/main/assdetailer.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/Eyeful_v2-Paired.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/Eyes.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/FacesV1.pt" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/hand_yolov8s.pt" \
    "https://huggingface.co/AunyMoons/loras-pack/blob/main/foot-yolov8l.pt"
# T2I: SAM
_dl_files "$MODELS/sams" \
    "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/sams/sam_vit_b_01ec64.pth"
# T2I: loras
_dl_files "$MODELS/loras" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/real.safetensors" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/XXX.safetensors" \
    "https://huggingface.co/gazsuv/sudoku/resolve/main/gpu.safetensors"
# T2I: Qwen3 VL
_dl_files "$MODELS/prompt_generator/Qwen3-VL-4B-Instruct-heretic-7refusal" \
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/added_tokens.json" \
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/chat_template.jinja" \
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/config.json" \
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/generation_config.json" \
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/merges.txt" \
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/model.safetensors.index.json" \
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/preprocessor_config.json" \
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/special_tokens_map.json" \
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/tokenizer.json" \
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/tokenizer_config.json" \
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/vocab.json"
_dl_files "$MODELS/prompt_generator/Qwen3-VL-4B-Instruct-heretic-7refusal" \
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/model-00001-of-00002.safetensors" \
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/model-00002-of-00002.safetensors"
# T2I: upscaler
_dl_files "$MODELS/upscale_models" \
    "https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/4xUltrasharp_4xUltrasharpV10.pt"
# T2I: SeedVR2
_dl_files "$MODELS/SEEDVR2" \
    "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_7b_sharp_fp16.safetensors" \
    "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors"

echo "[PROGRESS: 70]"
echo "[OFM-INNER] Downloading ANIMATOR models..."
# ANIMATOR: clip + clip_vision
_dl_files "$MODELS/clip" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors"
_dl_files "$MODELS/clip_vision" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors" \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"
# ANIMATOR: text_encoders
_dl_files "$MODELS/text_encoders" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/text_enc.safetensors"
# ANIMATOR: vae
_dl_files "$MODELS/vae" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/vae.safetensors"
# ANIMATOR: diffusion_models
_dl_files "$MODELS/diffusion_models" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanModel.safetensors"
# ANIMATOR: detection
_dl_files "$MODELS/detection" \
    "https://huggingface.co/st4vz/process_checkpoint/resolve/main/yolov10m.onnx" \
    "https://huggingface.co/st4vz/process_checkpoint/resolve/main/vitpose_h_wholebody_data.bin" \
    "https://huggingface.co/st4vz/process_checkpoint/resolve/main/vitpose_h_wholebody_model.onnx"
# ANIMATOR: loras (includes controlnet)
_dl_files "$MODELS/loras" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanFun.reworked.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/light.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanPusa.safetensors" \
    "https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/wan.reworked.safetensors"
# ANIMATOR: controlnet
_dl_files "$MODELS/controlnet" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_Uni3C_controlnet_fp16.safetensors"

echo "[PROGRESS: 80]"
echo "[OFM-INNER] Downloading LIPSYNC models..."
# LIPSYNC: loras
_dl_files "$MODELS/loras" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_T2V_14B_cfg_step_distill_v2_lora_rank128_bf16.safetensors" \
    "https://huggingface.co/Kijai/Wan2.1-Fun-Reward-LoRAs-comfy/resolve/main/Wan2.1-Fun-14B-InP-HPS2.1_reward_lora_comfy.safetensors"
# LIPSYNC: text_encoders
_dl_files "$MODELS/text_encoders" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/umt5-xxl-enc-fp8_e4m3fn.safetensors"
# LIPSYNC: vae
_dl_files "$MODELS/vae" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1_VAE_bf16.safetensors"
# LIPSYNC: diffusion_models
_dl_files "$MODELS/diffusion_models" \
    "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/I2V/Wan2_1-I2V-14B-480p_fp8_e4m3fn_scaled_KJ.safetensors"
_dl_files "$MODELS/diffusion_models/InfiniteTalk" \
    "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/InfiniteTalk/Wan2_1-InfiniteTalk-Single_fp8_e4m3fn_scaled_KJ.safetensors"

echo "[PROGRESS: 88]"
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
for _d in diffusion_models diffusion_models/InfiniteTalk text_encoders clip clip_vision vae controlnet loras ckpt sams upscale_models detection ultralytics/bbox unet model_patches prompt_generator SEEDVR2; do
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
echo "║  ✅ OFM PATH 智慧通路 — Inner installer complete              ║"
echo "╠════════════════════════════════════════════════════════════════╣"
printf "║  Models: %-3d · Nodes: %-3d · Workflows: %-2d                      ║\n" "$_total_files" "$CUSTOM_NODE_COUNT" "$WF_COUNT"
echo "╚════════════════════════════════════════════════════════════════╝"

exit 0
