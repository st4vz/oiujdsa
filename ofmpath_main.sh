#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
#  OFMPATH — Main Script Patcher
#  Applies product-awareness to ofmpath_main.sh
#  Usage: bash patch_main.sh ofmpath_main.sh
# ═══════════════════════════════════════════════════════════════════════════
set -e

FILE="${1:?Usage: bash patch_main.sh <path-to-ofmpath_main.sh>}"
[ -f "$FILE" ] || { echo "File not found: $FILE"; exit 1; }

cp "$FILE" "${FILE}.bak"
echo "Backed up to ${FILE}.bak"

# ═══════════════════════════════════════════════════════════════════════════
#  PATCH 1: Add product detection block after OFMPATH_BUCKET line
# ═══════════════════════════════════════════════════════════════════════════
sed -i '/^export OFMPATH_BUCKET="ofm-path"$/a\
\
# ── Product detection (set by launcher-img \/ launcher-vid) ──\
OFMPATH_PRODUCT="${OFMPATH_PRODUCT:-all}"\
case "$OFMPATH_PRODUCT" in\
    img) PRODUCT_LABEL="IMAGE TOOLS"; TOTAL_MODELS=42; TOTAL_NODES=21 ;;\
    vid) PRODUCT_LABEL="VIDEO TOOLS"; TOTAL_MODELS=26; TOTAL_NODES=26 ;;\
    *)   PRODUCT_LABEL="OFM PATH";    TOTAL_MODELS=57; TOTAL_NODES=28 ;;\
esac\
export OFMPATH_PRODUCT' "$FILE"

echo "  ✓ PATCH 1: Product detection block"

# ═══════════════════════════════════════════════════════════════════════════
#  PATCH 2: Inject product values into preloader HTML after writing it
#  Insert sed commands right before the `cd /tmp/ofmpath_loading` line
# ═══════════════════════════════════════════════════════════════════════════
sed -i '/^    cd \/tmp\/ofmpath_loading || { echo "\[OFM\]/i\
    # ── Inject product-specific values into preloader ──\
    sed -i "s/const TOTAL_MODELS = 57/const TOTAL_MODELS = ${TOTAL_MODELS}/" /tmp/ofmpath_loading/index.html\
    sed -i "s/models-total\\">57/models-total\\">${TOTAL_MODELS}/" /tmp/ofmpath_loading/index.html\
    sed -i "s/nodes-total\\">28/nodes-total\\">${TOTAL_NODES}/" /tmp/ofmpath_loading/index.html\
    sed -i "s|V1 · OFM PATH|V1 · OFMPATH ${PRODUCT_LABEL}|" /tmp/ofmpath_loading/index.html\
    sed -i "s|OFM PATH — Initializing|OFMPATH ${PRODUCT_LABEL} — Initializing|" /tmp/ofmpath_loading/index.html\
' "$FILE"

echo "  ✓ PATCH 2: Preloader HTML product injection"

# ═══════════════════════════════════════════════════════════════════════════
#  PATCH 3: Product-specific installer key in _deploy_stack
# ═══════════════════════════════════════════════════════════════════════════
sed -i 's|echo "\[OFM\] Fetching ofmpath_install.sh.enc from bucket..."|# ── Product-specific installer ──\
    local INSTALLER_KEY\
    case "${OFMPATH_PRODUCT}" in\
        img) INSTALLER_KEY="ofmpath_install_img.sh.enc" ;;\
        vid) INSTALLER_KEY="ofmpath_install_vid.sh.enc" ;;\
        *)   INSTALLER_KEY="ofmpath_install.sh.enc" ;;\
    esac\
    echo "[OFM] Fetching ${INSTALLER_KEY} from bucket..."|' "$FILE"

sed -i 's|_fetch_secure "ofmpath_install.sh.enc"|_fetch_secure "${INSTALLER_KEY}"|' "$FILE"

echo "  ✓ PATCH 3: Product-specific installer key"

# ═══════════════════════════════════════════════════════════════════════════
#  PATCH 4: Product-specific fallback URL
# ═══════════════════════════════════════════════════════════════════════════
sed -i 's|local URL="https://raw.githubusercontent.com/st4vz/oiujdsa/refs/heads/main/ofmpath_install.sh"|local FALLBACK_NAME\
    case "${OFMPATH_PRODUCT}" in\
        img) FALLBACK_NAME="ofmpath_install_img.sh" ;;\
        vid) FALLBACK_NAME="ofmpath_install_vid.sh" ;;\
        *)   FALLBACK_NAME="ofmpath_install.sh" ;;\
    esac\
    local URL="https://raw.githubusercontent.com/st4vz/oiujdsa/refs/heads/main/${FALLBACK_NAME}"|' "$FILE"

echo "  ✓ PATCH 4: Product-specific fallback URL"

# ═══════════════════════════════════════════════════════════════════════════
#  PATCH 5: Pass OFMPATH_PRODUCT + OFMPATH_SUPA_KEY to inner installer
#  Uses perl for indentation-aware replacement (matches leading whitespace)
# ═══════════════════════════════════════════════════════════════════════════
perl -i -pe 's{^(\s+)(OFMPATH_BUCKET="\$OFMPATH_BUCKET" \\)$}{${1}OFMPATH_SUPA_KEY="\$OFMPATH_SUPA_KEY" \\\n${1}${2}\n${1}OFMPATH_PRODUCT="\$OFMPATH_PRODUCT" \\}' "$FILE"

echo "  ✓ PATCH 5: Product + key passthrough to inner installer"

# ═══════════════════════════════════════════════════════════════════════════
#  PATCH 6: Allow Ctrl+V (paste) in lockdown — remove "v","V" from blocked keys
# ═══════════════════════════════════════════════════════════════════════════
# The lockdown JS blocks: u,U,s,S,c,C,v,V,p,P,a,A,o,O,e,E
# We keep everything except v,V so users can paste into input fields
sed -i 's/"v","V",//g' "$FILE"

echo "  ✓ PATCH 6: Ctrl+V allowed (paste unblocked in lockdown)"

# ═══════════════════════════════════════════════════════════════════════════
#  Verify
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "Verification:"
bash -n "$FILE" && echo "  ✓ Syntax OK" || echo "  ✗ SYNTAX ERROR"

grep -c 'OFMPATH_PRODUCT' "$FILE" | xargs -I{} echo "  OFMPATH_PRODUCT refs: {}"
grep -c 'PRODUCT_LABEL' "$FILE"   | xargs -I{} echo "  PRODUCT_LABEL refs: {}"
grep -c 'INSTALLER_KEY' "$FILE"   | xargs -I{} echo "  INSTALLER_KEY refs: {}"
grep -c 'FALLBACK_NAME' "$FILE"   | xargs -I{} echo "  FALLBACK_NAME refs: {}"

echo ""
echo "Done. Patched file: $FILE"
echo "Backup: ${FILE}.bak"
