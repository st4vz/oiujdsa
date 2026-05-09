#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
#  OFM PATH 智慧通路 — Inner Installer  (v3.1 — parallelized + tuned)
#  Fetched + decrypted by ofmpath_main.sh from Supabase bucket.
#
#  Speed optimizations vs v2:
#    1. Parallel git clones in Phase B (max 6 concurrent)
#    2. Parallel pip installs in Phase B (max 4 concurrent)
#    3. Parallel model downloads in Phase C (max 6 concurrent)
#    4. hf_transfer enabled for HuggingFace URLs (~2-3× faster on HF specifically)
#    5. Phase C-2 verifies critical models landed, retries up to 3× if missing
#  Tuned in v3.1:
#    - aria2c chunks per file: 8 → 16 (faster on huge weights)
#    - Pre-installed pkg filter strips already-satisfied deps from requirements.txt
#    - --no-deps for filtered req files (skips resolver chain walks)
#    - git clone --filter=blob:none --depth 1 (faster for repos with large history)
#
#  Total expected boot time: ~5-8 min on fast hosts.
# ═══════════════════════════════════════════════════════════════════════════

# No `set -e` — we need to survive partial failures.

# ═══ SELF-DELETE ═══
# Bash has already loaded this entire script into memory by the time we reach this
# line, so deleting the on-disk copy doesn't affect execution. This makes casual
# extraction (`cat /tmp/ofmpath_install.sh`) impossible after the first ~20ms of
# the boot. A determined attacker with inotifywait could still race us, but the
# bar is meaningfully higher than leaving the file sitting there for the duration
# of the install.
if [ -f "$0" ] && [ "$0" != "bash" ] && [ "$0" != "/bin/bash" ]; then
    rm -f "$0" 2>/dev/null && echo "[OFM-INNER] Self-deleted on-disk copy ($0)"
fi

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
fi
: "${COMFYUI_DIR:=/workspace/ComfyUI}"
: "${CUSTOM_NODES_DIR:=$COMFYUI_DIR/custom_nodes}"
: "${OFMPATH_SUPA_URL:=https://yvjhjptycwlnjnzzsyju.supabase.co}"
: "${OFMPATH_BUCKET:=ofm-path}"

MODELS="$COMFYUI_DIR/models"
WORKFLOWS_DIR="$COMFYUI_DIR/user/default/workflows"
HF_TOKEN="${HF_TOKEN:-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}"

# Concurrency limits (tuned for Vast.ai NVMe + 1Gbps+ uplink)
NODE_CLONE_CONCURRENCY=6      # GitHub doesn't throttle below ~10 parallel
NODE_PIP_CONCURRENCY=4        # Pip is CPU-heavy on dependency resolution
MODEL_DL_CONCURRENCY=6        # 6 × ~150MB/s ≈ 900MB/s, still under 2-3GB/s NVMe write

if [ -z "${PIP:-}" ]; then
    if   [ -x "/venv/main/bin/pip" ];       then PIP="/venv/main/bin/pip"
    elif [ -x "$COMFYUI_DIR/.venv/bin/pip" ]; then PIP="$COMFYUI_DIR/.venv/bin/pip"
    else PIP="pip"; fi
    echo "[OFM-INNER] Detected PIP=$PIP"
fi

# ═══ Install hf_transfer + huggingface_hub for fast HF downloads ═══
echo "[OFM-INNER] Installing hf_transfer accelerator..."
"$PIP" install --quiet --upgrade hf_transfer 'huggingface_hub[cli]>=0.20' 2>&1 | tail -2 || true
export HF_HUB_ENABLE_HF_TRANSFER=1
export HF_TOKEN

# Locate huggingface-cli
HF_CLI=""
if command -v huggingface-cli >/dev/null 2>&1; then
    HF_CLI="$(command -v huggingface-cli)"
elif [ -x "/venv/main/bin/huggingface-cli" ]; then
    HF_CLI="/venv/main/bin/huggingface-cli"
fi
echo "[OFM-INNER] HF_CLI=${HF_CLI:-not_found}"

# Define fetch/decrypt helpers
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
echo "║  OFM PATH 智慧通路  v1 — Inner Installer (parallelized)        ║"
echo "║  IMG GEN + LIPSYNC + MOTION                                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE A — FETCH + DECRYPT WORKFLOWS
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase A: Fetch workflows ━━━"
echo "[PROGRESS: 35]"

mkdir -p "$WORKFLOWS_DIR" "$COMFYUI_DIR/input"

WORKFLOW_IMG_GEN=""
WORKFLOW_LIPSYNC=""
WORKFLOW_MOTION=""

# Fetch all 3 workflows in parallel (they're small and independent)
_fetch_workflow() {
    local enc_name="$1" tmp_enc="$2" tmp_json="$3" ok_marker="$4"
    if _fetch_secure "$enc_name" "$tmp_enc"; then
        if _decrypt_secure "$tmp_enc" "$tmp_json"; then
            python3 -c "import json; d=json.load(open('$tmp_json')); assert 'nodes' in d" 2>/dev/null \
                && touch "$ok_marker"
        fi
        rm -f "$tmp_enc"
    fi
}

_fetch_workflow "OFMPATH_IMG_GEN.json.enc"  /tmp/img_gen.enc  /tmp/img_gen.json  /tmp/.img_gen_ok  &
_fetch_workflow "OFMPATH_LIPSYNC.json.enc"  /tmp/lipsync.enc  /tmp/lipsync.json  /tmp/.lipsync_ok  &
_fetch_workflow "OFMPATH_MOTION.json.enc" /tmp/motion.enc /tmp/motion.json /tmp/.motion_ok &
wait

[ -f /tmp/.img_gen_ok ]  && WORKFLOW_IMG_GEN=/tmp/img_gen.json   && echo "[OFM-INNER] ✓ OFMPATH_IMG_GEN workflow loaded"
[ -f /tmp/.lipsync_ok ]  && WORKFLOW_LIPSYNC=/tmp/lipsync.json   && echo "[OFM-INNER] ✓ OFMPATH_LIPSYNC workflow loaded"
[ -f /tmp/.motion_ok ] && WORKFLOW_MOTION=/tmp/motion.json && echo "[OFM-INNER] ✓ OFMPATH_MOTION workflow loaded"
rm -f /tmp/.img_gen_ok /tmp/.lipsync_ok /tmp/.motion_ok


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE B — INSTALL CUSTOM NODES (27, parallelized)
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase B: Install custom nodes (parallel) ━━━"
echo "[PROGRESS: 42]"

mkdir -p "$CUSTOM_NODES_DIR"
if ! cd "$CUSTOM_NODES_DIR"; then
    echo "[OFM-INNER] CRITICAL: cannot cd into $CUSTOM_NODES_DIR"
    echo "[OFM-INNER] Aborting Phase B"
else
    echo "[OFM-INNER] Working dir: $(pwd)"

    # ── Define the node list as a parallel-safe array ──
    # Format: "name|url"
    NODES=(
        "ComfyUI-Manager|https://github.com/ltdrdata/ComfyUI-Manager"
        "ComfyUI-WanVideoWrapper|https://github.com/kijai/ComfyUI-WanVideoWrapper"
        "ComfyUI-Impact-Pack|https://github.com/ltdrdata/ComfyUI-Impact-Pack"
        "ComfyUI-Custom-Scripts|https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
        "ComfyUI_LayerStyle|https://github.com/chflame163/ComfyUI_LayerStyle"
        "rgthree-comfy|https://github.com/rgthree/rgthree-comfy"
        "ComfyUI-Easy-Use|https://github.com/yolain/ComfyUI-Easy-Use"
        "ComfyUI-SeedVR2_VideoUpscaler|https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler"
        "ComfyUI_essentials|https://github.com/cubiq/ComfyUI_essentials"
        "RES4LYF|https://github.com/ClownsharkBatwing/RES4LYF"
        "cg-use-everywhere|https://github.com/chrisgoringe/cg-use-everywhere"
        "ComfyUI-Impact-Subpack|https://github.com/ltdrdata/ComfyUI-Impact-Subpack"
        "ComfyUI-mxToolkit|https://github.com/Smirnov75/ComfyUI-mxToolkit"
        "ComfyUI-Image-Size-Tools|https://github.com/TheLustriVA/ComfyUI-Image-Size-Tools"
        "zhihui_nodes_comfyui|https://github.com/ZhiHui6/zhihui_nodes_comfyui"
        "ComfyUI-KJNodes|https://github.com/kijai/ComfyUI-KJNodes"
        "ComfyUI_HuggingFace_Downloader|https://github.com/jnxmx/ComfyUI_HuggingFace_Downloader"
        "CRT-Nodes|https://github.com/plugcrypt/CRT-Nodes"
        "ComfyUI-post-processing-nodes|https://github.com/EllangoK/ComfyUI-post-processing-nodes"
        "comfyui_controlnet_aux|https://github.com/Fannovel16/comfyui_controlnet_aux"
        "comfyui-teskors-utils|https://github.com/teskor-hub/comfyui-teskors-utils"
        "Comfyui-Resolution-Master|https://github.com/Azornes/Comfyui-Resolution-Master"
        "ComfyUI-VideoHelperSuite|https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
        "ComfyUI-segment-anything-2|https://github.com/kijai/ComfyUI-segment-anything-2"
        "ComfyUI-ZMG-Nodes|https://github.com/fq393/ComfyUI-ZMG-Nodes"
        "ComfyUI-WanAnimatePreprocess|https://github.com/kijai/ComfyUI-WanAnimatePreprocess"
        "ComfyUI-SAM3|https://github.com/PozzettiAndrea/ComfyUI-SAM3"
    )
    NODE_TOTAL=${#NODES[@]}

    # Shared progress counter via lock-protected file
    NODE_PROGRESS_FILE="/tmp/ofmpath_node_progress"
    : > "$NODE_PROGRESS_FILE"

    _clone_one() {
        local entry="$1"
        local name="${entry%%|*}"
        local url="${entry##*|}"
        if [ -d "$name" ]; then
            echo "ok|$name" >> "$NODE_PROGRESS_FILE"
            return 0
        fi
        if timeout 120 git clone --filter=blob:none --depth 1 "$url" "$name" 2>/dev/null; then
            echo "ok|$name" >> "$NODE_PROGRESS_FILE"
        else
            echo "fail|$name" >> "$NODE_PROGRESS_FILE"
        fi
    }

    # Cache the set of already-installed packages once. Pre-Vast image ships with torch,
    # xformers, transformers, diffusers, accelerate, opencv, pillow, numpy, etc.
    # Filtering these out of each requirements.txt saves pip's resolver work.
    _PRE_INSTALLED_FILE="/tmp/ofmpath_preinstalled.txt"
    if [ ! -s "$_PRE_INSTALLED_FILE" ]; then
        "$PIP" list --format=freeze 2>/dev/null \
            | awk -F'==' '{print tolower($1)}' > "$_PRE_INSTALLED_FILE"
        echo "[OFM-INNER] Pre-installed package set: $(wc -l < "$_PRE_INSTALLED_FILE") pkgs"
    fi

    _filter_requirements() {
        # Read req file from $1, write filtered version to $2 (only packages NOT pre-installed).
        local infile="$1" outfile="$2"
        : > "$outfile"
        while IFS= read -r line; do
            # Strip comments and whitespace
            local clean="${line%%#*}"
            clean="${clean%%[[:space:]]}"
            [ -z "$clean" ] && continue
            # Extract package name (before ==, >=, <, ~, [, etc.)
            local pkg
            pkg=$(echo "$clean" | sed -E 's/[<>=!~\[].*//' | tr '[:upper:]' '[:lower:]' | tr '_' '-' | xargs)
            [ -z "$pkg" ] && continue
            # Keep if not pre-installed
            if ! grep -qxF "$pkg" "$_PRE_INSTALLED_FILE" && ! grep -qxF "${pkg//-/_}" "$_PRE_INSTALLED_FILE"; then
                echo "$line" >> "$outfile"
            fi
        done < "$infile"
    }

    _pip_one() {
        local name="$1"
        if [ -f "$name/requirements.txt" ]; then
            local filtered="/tmp/ofmpath_req_${name//\//_}.txt"
            _filter_requirements "$name/requirements.txt" "$filtered"
            local kept=$(wc -l < "$filtered" 2>/dev/null || echo 0)
            local total=$(wc -l < "$name/requirements.txt" 2>/dev/null || echo 0)
            if [ "$kept" -gt 0 ]; then
                # Use --no-deps when only a few packages remain — they're leaf deps
                # that won't pull in big chains. Speeds resolver up dramatically.
                timeout 180 "$PIP" install -r "$filtered" --quiet --no-deps 2>/dev/null || \
                    timeout 180 "$PIP" install -r "$filtered" --quiet 2>/dev/null || true
            fi
            rm -f "$filtered"
        fi
    }

    # ── Stage B.1: parallel git clones (max 6 concurrent) ──
    echo "[OFM-INNER] Stage B.1: cloning ${NODE_TOTAL} repos (max ${NODE_CLONE_CONCURRENCY} concurrent)..."
    _CLONE_START=$(date +%s)
    PIDS=()
    for entry in "${NODES[@]}"; do
        # Wait for an open slot
        while [ "$(jobs -r | wc -l)" -ge "$NODE_CLONE_CONCURRENCY" ]; do
            sleep 0.2
        done
        _clone_one "$entry" &
        PIDS+=($!)
    done
    # Wait for all clones, with progress polling
    while [ "$(jobs -r | wc -l)" -gt 0 ]; do
        sleep 1
        local_done=$(wc -l < "$NODE_PROGRESS_FILE" 2>/dev/null || echo 0)
        # Emit a per-node progress marker so the dashboard counter ticks
        for n in $(seq 1 $local_done); do :; done
        # Format: emit one (N/27) line per completion (only new ones)
        :
    done
    wait
    _CLONE_END=$(date +%s)
    NODE_OK=$(grep -c '^ok|' "$NODE_PROGRESS_FILE" 2>/dev/null || echo 0)
    NODE_FAIL=$(grep -c '^fail|' "$NODE_PROGRESS_FILE" 2>/dev/null || echo 0)
    echo "[OFM-INNER] ✓ Clones done: ${NODE_OK} ok, ${NODE_FAIL} failed in $((_CLONE_END - _CLONE_START))s"

    # Emit per-node markers for the dashboard parser (it counts (N/27))
    _IDX=0
    while IFS='|' read -r status name; do
        _IDX=$((_IDX+1))
        if [ "$status" = "ok" ]; then
            echo "  [ok] $name (${_IDX}/27)"
        else
            echo "  [!] FAILED $name (${_IDX}/27) — will retry once"
            # Single retry inline (the parallel batch missed this one)
            timeout 120 git clone --filter=blob:none --depth 1 "$(grep -F "${name}|" <<< "$(printf '%s\n' "${NODES[@]}")" | head -1 | cut -d'|' -f2)" "$name" 2>/dev/null \
                && echo "  [✓] retry succeeded for $name" \
                || echo "  [!] retry failed for $name"
        fi
        local pct=$(( 42 + (_IDX * 6 / 27) ))
        echo "[PROGRESS: ${pct}]"
    done < "$NODE_PROGRESS_FILE"

    # ── Stage B.2: parallel pip installs (max 4 concurrent) ──
    echo "[OFM-INNER] Stage B.2: installing requirements (max ${NODE_PIP_CONCURRENCY} concurrent)..."
    _PIP_START=$(date +%s)
    for entry in "${NODES[@]}"; do
        local_name="${entry%%|*}"
        [ -f "$local_name/requirements.txt" ] || continue
        while [ "$(jobs -r | wc -l)" -ge "$NODE_PIP_CONCURRENCY" ]; do
            sleep 0.3
        done
        _pip_one "$local_name" &
    done
    wait
    _PIP_END=$(date +%s)
    echo "[OFM-INNER] ✓ Pip installs done in $((_PIP_END - _PIP_START))s"
    echo "[PROGRESS: 53]"

    # KJNodes compat fix
    KJ="$CUSTOM_NODES_DIR/ComfyUI-KJNodes/nodes/nodes.py"
    if [ -f "$KJ" ] && grep -q "search_aliases" "$KJ" 2>/dev/null; then
        sed -i 's/search_aliases=\[.*\],\?//g' "$KJ"
        echo "[OFM-INNER] ✓ KJNodes search_aliases fix applied"
    fi

    INSTALLED_NODES=$(ls -1 "$CUSTOM_NODES_DIR" 2>/dev/null | wc -l)
    echo "[OFM-INNER] ✓ Phase B done: $INSTALLED_NODES nodes installed"
    rm -f "$NODE_PROGRESS_FILE"
fi


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE C — DOWNLOAD MODELS (49, parallelized + hf_transfer)
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase C: Download models (parallel) ━━━"
echo "[PROGRESS: 55]"
echo "Found 55 models to verify"

# Shared completion counter
DL_PROGRESS_FILE="/tmp/ofmpath_dl_progress"
: > "$DL_PROGRESS_FILE"
DL_LOCK="/tmp/ofmpath_dl.lock"

_dl_one() {
    local dir="$1" file="$2" url="$3" label="${4:-asset}"
    mkdir -p "$dir"

    # Cache check — skip if already complete
    if [ -f "$dir/$file" ] && [ "$(stat -c%s "$dir/$file" 2>/dev/null || echo 0)" -gt 1024 ]; then
        (flock 9; echo "ok|$label" >> "$DL_PROGRESS_FILE") 9>"$DL_LOCK"
        echo "[STARTING] '${label}'"
        echo "  [ok] cached ($(stat -c%s "$dir/$file") bytes)"
        echo "[SUCCESS]"
        return 0
    fi
    if [ -f "$dir/$file" ] && [ -s "$dir/$file" ] && [[ "$file" =~ \.(json|txt|jinja)$ ]]; then
        (flock 9; echo "ok|$label" >> "$DL_PROGRESS_FILE") 9>"$DL_LOCK"
        echo "[STARTING] '${label}'"
        echo "  [ok] cached (small file)"
        echo "[SUCCESS]"
        return 0
    fi

    echo "[STARTING] '${label}'"

    # ── Strategy 1: huggingface-cli download (with hf_transfer) for HF URLs ──
    # URL pattern: https://huggingface.co/{repo}/resolve/{rev}/{path}
    if [ -n "$HF_CLI" ] && [[ "$url" =~ ^https://huggingface\.co/([^/]+/[^/]+)/resolve/([^/]+)/(.+)$ ]]; then
        local hf_repo="${BASH_REMATCH[1]}"
        local hf_rev="${BASH_REMATCH[2]}"
        local hf_path="${BASH_REMATCH[3]}"
        # URL-decode just %2F → / for refs/pr/N style revs
        hf_rev="${hf_rev//%2F/\/}"
        if HF_HUB_ENABLE_HF_TRANSFER=1 timeout 1800 "$HF_CLI" download \
                "$hf_repo" "$hf_path" \
                --revision "$hf_rev" \
                --local-dir "$dir" \
                --local-dir-use-symlinks False \
                --quiet 2>/dev/null; then
            # huggingface-cli preserves subdirs from the repo path; move to expected filename
            local downloaded="$dir/$hf_path"
            if [ -f "$downloaded" ] && [ "$downloaded" != "$dir/$file" ]; then
                mv "$downloaded" "$dir/$file"
                # Clean up empty intermediate dirs
                find "$dir" -type d -empty -delete 2>/dev/null || true
            fi
            if [ -s "$dir/$file" ]; then
                (flock 9; echo "ok|$label" >> "$DL_PROGRESS_FILE") 9>"$DL_LOCK"
                echo "  [hf] $(stat -c%s "$dir/$file") bytes"
                echo "[SUCCESS]"
                return 0
            fi
        fi
        # hf_transfer failed — fall through to aria2c/curl
        rm -f "$dir/$file"
    fi

    # ── Strategy 2: aria2c (works for any URL, parallel chunks per file) ──
    local hdr=""
    [[ "$url" =~ huggingface\.co ]] && hdr="Authorization: Bearer $HF_TOKEN"

    if command -v aria2c >/dev/null 2>&1; then
        if [ -n "$hdr" ]; then
            timeout 1800 aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
                --file-allocation=none --header="$hdr" \
                -d "$dir" -o "$file" "$url" >/dev/null 2>&1
        else
            timeout 1800 aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
                --file-allocation=none \
                -d "$dir" -o "$file" "$url" >/dev/null 2>&1
        fi
    fi

    # ── Strategy 3: curl fallback ──
    if [ ! -s "$dir/$file" ]; then
        if [ -n "$hdr" ]; then
            timeout 1800 curl -fsSL --retry 2 -H "$hdr" -o "$dir/$file" "$url" 2>/dev/null
        else
            timeout 1800 curl -fsSL --retry 2 -o "$dir/$file" "$url" 2>/dev/null
        fi
    fi

    if [ -f "$dir/$file" ] && [ -s "$dir/$file" ]; then
        (flock 9; echo "ok|$label" >> "$DL_PROGRESS_FILE") 9>"$DL_LOCK"
        echo "  [dl] $(stat -c%s "$dir/$file") bytes"
        echo "[SUCCESS]"
    else
        (flock 9; echo "fail|$label" >> "$DL_PROGRESS_FILE") 9>"$DL_LOCK"
        rm -f "$dir/$file"
        echo "[FAILED] $label"
    fi
}

# ── Job queue runner ──
# Dispatches up to N parallel _dl_one calls, then waits.
_dl_queue() {
    while [ "$(jobs -r | wc -l)" -ge "$MODEL_DL_CONCURRENCY" ]; do
        sleep 0.3
    done
}

# Wrapper that emits [PROGRESS:NN] markers after each completion
_dl() {
    _dl_queue
    _dl_one "$@" &
}

# Launch all 49 downloads, queue limits to 4 concurrent
_DL_START=$(date +%s)

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

# LIPSYNC-SPECIFIC MODELS (6) — required by OFMPATH_LIPSYNC workflow
_dl "$MODELS/loras" "lightx2v_T2V_14B_cfg_step_distill_v2_lora_rank128_bf16.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_T2V_14B_cfg_step_distill_v2_lora_rank128_bf16.safetensors" "lora_lightx2v"
_dl "$MODELS/loras" "Wan2.1-Fun-14B-InP-HPS2.1_reward_lora_comfy.safetensors" \
    "https://huggingface.co/Kijai/Wan2.1-Fun-Reward-LoRAs-comfy/resolve/main/Wan2.1-Fun-14B-InP-HPS2.1_reward_lora_comfy.safetensors" "lora_funreward"
_dl "$MODELS/text_encoders" "umt5-xxl-enc-fp8_e4m3fn.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/umt5-xxl-enc-fp8_e4m3fn.safetensors" "umt5_kj_fp8"
_dl "$MODELS/vae" "Wan2_1_VAE_bf16.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1_VAE_bf16.safetensors" "vae_wan_bf16"
_dl "$MODELS/diffusion_models" "Wan2_1-I2V-14B-480p_fp8_e4m3fn_scaled_KJ.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/I2V/Wan2_1-I2V-14B-480p_fp8_e4m3fn_scaled_KJ.safetensors" "wan_i2v_480p"
_dl "$MODELS/diffusion_models/InfiniteTalk" "Wan2_1-InfiniteTalk-Single_fp8_e4m3fn_scaled_KJ.safetensors" \
    "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/InfiniteTalk/Wan2_1-InfiniteTalk-Single_fp8_e4m3fn_scaled_KJ.safetensors" "infinitetalk"

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

# ── Wait for all parallel downloads to finish ──
echo "[OFM-INNER] All download jobs queued, waiting for completion..."
wait
_DL_END=$(date +%s)

DL_OK=$(grep -c '^ok|' "$DL_PROGRESS_FILE" 2>/dev/null || echo 0)
DL_FAIL=$(grep -c '^fail|' "$DL_PROGRESS_FILE" 2>/dev/null || echo 0)
echo "[OFM-INNER] ✓ Phase C: ${DL_OK} ok, ${DL_FAIL} failed in $((_DL_END - _DL_START))s"
echo "[PROGRESS: 88]"
rm -f "$DL_PROGRESS_FILE" "$DL_LOCK"


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE C-2 — RETRY FAILED MODELS  (up to 3 attempts each)
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase C-2: Verify + retry failed models ━━━"

# Critical models — these MUST be present for either workflow to load.
# If any of these is missing after retries, we still continue but log loudly.
declare -A CRITICAL_MODELS=(
    ["$MODELS/diffusion_models/z_image_turbo_bf16.safetensors"]="https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors"
    ["$MODELS/diffusion_models/WanModel.safetensors"]="https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/WanModel.safetensors"
    ["$MODELS/text_encoders/qwen_3_4b.safetensors"]="https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors"
    ["$MODELS/text_encoders/umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors"]="https://huggingface.co/UmeAiRT/ComfyUI-Auto_installer/resolve/refs%2Fpr%2F5/models/clip/umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors"
    ["$MODELS/text_encoders/text_enc.safetensors"]="https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/text_enc.safetensors"
    ["$MODELS/vae/ae.safetensors"]="https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors"
    ["$MODELS/vae/vae.safetensors"]="https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/vae.safetensors"
    ["$MODELS/clip_vision/clip_vision_h.safetensors"]="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"
    ["$MODELS/clip_vision/klip_vision.safetensors"]="https://huggingface.co/wdsfdsdf/OFMHUB/resolve/main/klip_vision.safetensors"
)

CRITICAL_MISSING=0
for path in "${!CRITICAL_MODELS[@]}"; do
    if [ -f "$path" ] && [ "$(stat -c%s "$path" 2>/dev/null || echo 0)" -gt 1024 ]; then
        continue
    fi
    echo "[OFM-INNER] [!] Critical model missing: $(basename "$path") — retrying..."
    url="${CRITICAL_MODELS[$path]}"
    dir="$(dirname "$path")"
    file="$(basename "$path")"
    mkdir -p "$dir"
    success=0
    for attempt in 1 2 3; do
        echo "[OFM-INNER]   attempt $attempt/3 for $file"
        rm -f "$path"
        # Try aria2c with HF auth first
        if command -v aria2c >/dev/null 2>&1; then
            timeout 1200 aria2c --console-log-level=error -c -x 16 -s 16 -k 1M \
                --file-allocation=none \
                --header="Authorization: Bearer $HF_TOKEN" \
                -d "$dir" -o "$file" "$url" >/dev/null 2>&1
        fi
        if [ ! -s "$path" ]; then
            timeout 1200 curl -fsSL --retry 3 \
                -H "Authorization: Bearer $HF_TOKEN" \
                -o "$path" "$url" 2>/dev/null
        fi
        if [ -f "$path" ] && [ "$(stat -c%s "$path" 2>/dev/null || echo 0)" -gt 1024 ]; then
            echo "[OFM-INNER]   [✓] recovered: $file ($(stat -c%s "$path") bytes)"
            success=1
            break
        fi
        sleep 3
    done
    if [ "$success" = "0" ]; then
        echo "[OFM-INNER]   [✗] FAILED PERMANENTLY: $file — workflows requiring this will error"
        CRITICAL_MISSING=$((CRITICAL_MISSING + 1))
    fi
done

if [ "$CRITICAL_MISSING" -gt 0 ]; then
    echo "[OFM-INNER] ⚠ ⚠ ⚠ $CRITICAL_MISSING critical model(s) could not be downloaded"
    echo "[OFM-INNER] ⚠ Workflows may show 'missing model' errors when loaded"
else
    echo "[OFM-INNER] ✓ All critical models verified present"
fi
echo "[PROGRESS: 90]"


# ═══════════════════════════════════════════════════════════════════════════
#  PHASE D — DEPLOY WORKFLOWS
# ═══════════════════════════════════════════════════════════════════════════
echo -e "\n━━━ Phase D: Deploy workflows ━━━"

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

_deploy_workflow "$WORKFLOW_IMG_GEN"  "OFMPATH_IMG_GEN.json"
_deploy_workflow "$WORKFLOW_LIPSYNC"  "OFMPATH_LIPSYNC.json"
_deploy_workflow "$WORKFLOW_MOTION" "OFMPATH_MOTION.json"

rm -f /tmp/img_gen.json /tmp/lipsync.json /tmp/motion.json


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
for _d in diffusion_models diffusion_models/InfiniteTalk text_encoders clip_vision vae controlnet loras checkpoints sams upscale_models detection ultralytics/bbox LLM; do
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
echo "  Critical missing: $CRITICAL_MISSING"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  ✅ OFM PATH 智慧通路 — Inner installer complete              ║"
echo "╠════════════════════════════════════════════════════════════════╣"
printf "║  Models: %-3d · Nodes: %-3d · Workflows: %-2d · Critical missing: %-2d ║\n" "$_total_files" "$CUSTOM_NODE_COUNT" "$WF_COUNT" "$CRITICAL_MISSING"
echo "╚════════════════════════════════════════════════════════════════╝"

exit 0
