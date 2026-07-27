#!/bin/bash
set -e

# === 1. ПОДГОТОВКА ОКРУЖЕНИЯ ===
if [ -f "/venv/main/bin/activate" ]; then
    source /venv/main/bin/activate
elif [ -f "/opt/venv/bin/activate" ]; then
    source /opt/venv/bin/activate
fi

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

echo "=== Запуск установки X-MODE (Protected) ==="

# === 2. АВТОРИЗАЦИЯ И ЗАЩИТА ОТ СЛИВА (SUPABASE) ===
if [ -z "$XMODE_TOKEN" ] || [ "$XMODE_TOKEN" == "INSERT_TOKEN_HERE" ]; then
    echo "КРИТИЧЕСКАЯ ОШИБКА: Вы не ввели XMODE_TOKEN в настройках Vast.ai!"

fi

PUBLIC_IP=$(curl -s ifconfig.me)
SUPABASE_URL="https://tzaxkiiohwxcuclfryru.supabase.co/rest/v1/rpc/verify_client_token"
SUPABASE_KEY="sb_publishable_pNKPlnhllScFgXV3_dA-LA_u5NjNqbT"

RESPONSE=$(curl -s -X POST "$SUPABASE_URL" \
    -H "apikey: $SUPABASE_KEY" \
    -H "Authorization: Bearer $SUPABASE_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"p_token\": \"${XMODE_TOKEN}\", \"p_ip\": \"${PUBLIC_IP}\"}")

if [[ "$RESPONSE" == "true" ]]; then
    # Выводим только это, остальное скрыто
    echo "=========================================================="
    echo "✅🔐 Ваш токен подтверждён ofmhub"
    echo "⏳ Газик начал загрузку файлов, ожидание минут 15-30..."
    echo "=========================================================="
else
    echo "=========================================================="
    echo "❌ ОШИБКА ДОСТУПА: Токен недействителен, либо заблокирован!"
    echo "Возможно, сработала защита от слива (превышен лимит IP)."
    echo "Скрипт остановлен. обратитесь к ofmhub"
    echo "=========================================================="
fi


# === СПИСКИ ПАКЕТОВ И МОДЕЛЕЙ ===
NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/kijai/ComfyUI-WanVideoWrapper"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
    "https://github.com/chflame163/ComfyUI_LayerStyle"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/yolain/ComfyUI-Easy-Use"
    "https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/ClownsharkBatwing/RES4LYF"
    "https://github.com/chrisgoringe/cg-use-everywhere"
    "https://github.com/ltdrdata/ComfyUI-Impact-Subpack"
    "https://github.com/Smirnov75/ComfyUI-mxToolkit"
    "https://github.com/TheLustriVA/ComfyUI-Image-Size-Tools"
    "https://github.com/ZhiHui6/zhihui_nodes_comfyui"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/crystian/ComfyUI-Crystools"
    "https://github.com/jnxmx/ComfyUI_HuggingFace_Downloader"
    "https://github.com/plugcrypt/CRT-Nodes"
    "https://github.com/EllangoK/ComfyUI-post-processing-nodes"
    "https://github.com/Fannovel16/comfyui_controlnet_aux"
    "https://github.com/teskor-hub/comfyui-teskors-utils.git"
    "https://github.com/Azornes/Comfyui-Resolution-Master"
)
WRAPER=("https://raw.githubusercontent.com/slonik228/nospacelesft/refs/heads/main/xmode.json")
CLIP_MODELS=("https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors")
CKPT_MODELS=("https://huggingface.co/gazsuv/sudoku/resolve/main/detect.safetensors")
FUN_MODELS=("https://huggingface.co/arhiteector/zimage/resolve/main/Z-Image-Turbo-Fun-Controlnet-Union.safetensors")
TEXT_ENCODERS=("https://huggingface.co/UmeAiRT/ComfyUI-Auto_installer/resolve/refs%2Fpr%2F5/models/clip/umt5-xxl-encoder-fp8-e4m3fn-scaled.safetensors")
UNET_MODELS=("https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors")
VAE_MODELS=("https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors")
DIFFUSION_MODELS=("https://huggingface.co/T5B/Z-Image-Turbo-FP8/resolve/main/z-image-turbo-fp8-e4m3fn.safetensors")
BBOX_0=("https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/face_yolov8s.pt")
BBOX_1=("https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/femaleBodyDetection_yolo26.pt")
BBOX_2=("https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/female_breast-v4.2.pt")
BBOX_3=("https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/nipples_yolov8s.pt")
BBOX_4=("https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/vagina-v4.2.pt")
BBOX_5=("https://huggingface.co/gazsuv/xmode/resolve/main/assdetailer.pt")
SAM_PTH=("https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/sams/sam_vit_b_01ec64.pth")
BBOX_6=("https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/Eyeful_v2-Paired.pt")
BBOX_7=("https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/Eyes.pt")
BBOX_8=("https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/FacesV1.pt")
BBOX_9=("https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/hand_yolov8s.pt")
BBOX_10=("https://huggingface.co/AunyMoons/loras-pack/blob/main/foot-yolov8l.pt")
QWEN3VL_1=(
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/added_tokens.json"
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/chat_template.jinja"
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/config.json"
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/generation_config.json"
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/merges.txt"
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/model.safetensors.index.json"
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/preprocessor_config.json"
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/special_tokens_map.json"
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/tokenizer.json"
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/tokenizer_config.json"
    "https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/vocab.json"
)
QWEN3VL_2=("https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/model-00001-of-00002.safetensors")
QWEN3VL_3=("https://huggingface.co/svjack/Qwen3-VL-4B-Instruct-heretic-7refusal/resolve/main/model-00002-of-00002.safetensors")
UPSCALER_MODELS=("https://huggingface.co/gazsuv/pussydetectorv4/resolve/main/4xUltrasharp_4xUltrasharpV10.pt")
LORAS=(
    "https://huggingface.co/gazsuv/sudoku/resolve/main/real.safetensors"
    "https://huggingface.co/gazsuv/sudoku/resolve/main/XXX.safetensors"
    "https://huggingface.co/gazsuv/sudoku/resolve/main/gpu.safetensors"   
)

### ─────────────────────────────────────────────
### ФУНКЦИИ УСТАНОВКИ
### ─────────────────────────────────────────────

 function provisioning_start() {
    provisioning_clone_comfyui
    provisioning_install_base_reqs
    provisioning_get_nodes
    provisioning_inject_hardcore_security 

    # ВАЖНО: Качаем wraperx.json прямо в папку web, чтобы кнопка могла его мгновенно получить
    provisioning_get_files "${COMFYUI_DIR}/web"                       "${WRAPER[@]}"
    provisioning_get_files "${COMFYUI_DIR}/user/default/workflows"    "${WRAPER[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip"               "${CLIP_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/text_encoders"     "${TEXT_ENCODERS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/unet"               "${UNET_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae"                "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/ckpt"               "${CKPT_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/model_patches"      "${FUN_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models"   "${DIFFUSION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/ultralytics/bbox"   "${BBOX_0[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/ultralytics/bbox"   "${BBOX_1[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/ultralytics/bbox"   "${BBOX_2[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/ultralytics/bbox"   "${BBOX_3[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/ultralytics/bbox"   "${BBOX_4[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/ultralytics/bbox"   "${BBOX_5[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/ultralytics/bbox"   "${BBOX_6[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/ultralytics/bbox"   "${BBOX_7[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/ultralytics/bbox"   "${BBOX_8[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/ultralytics/bbox"   "${BBOX_9[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/ultralytics/bbox"   "${BBOX_10[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/sams"               "${SAM_PTH[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/loras"              "${LORAS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/prompt_generator/Qwen3-VL-4B-Instruct-heretic-7refusal"   "${QWEN3VL_1[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/prompt_generator/Qwen3-VL-4B-Instruct-heretic-7refusal"   "${QWEN3VL_2[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/prompt_generator/Qwen3-VL-4B-Instruct-heretic-7refusal"   "${QWEN3VL_3[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/upscale_models"     "${UPSCALER_MODELS[@]}"

	echo "====================================="
	echo "====================================="
	echo "======✅ Газик настроил комфи.======="
	echo "====================================="
	echo "====================================="
}
# === ЖЕСТКАЯ ВЫРЕЗКА ИНТЕРФЕЙСА + ДИЗАЙН ===
function provisioning_inject_hardcore_security() {
    export LOGO_URL="https://lh3.googleusercontent.com/rd-d/ALs6j_EPmV3VSppU0GrZ6GUzTIHCwI9mydp6fJxQHEL4eAVXp2Iap69Zpd7RGK0OAhS2J810wfTcqjfdfo0TJX_joYy8sQRNHPQL_eAUZ3aWjh_BLb08H2AoMmjClTyQE0NrJtLQYuY3XXYHUtrluwj7Xrexd6xnPU0DOtXHzaPYiCCGDhGMpjtvl259OAM78iP8UhKKLyXpMv5hRD-UbP4dhpoTKTIAeDc9e3rL_28QOh1MXDRw5Bj3QtJUN6YUvbbeqWufPmcvzfSrhTrpTJUmNvXEqKV9QspZKf9HnOhesNWqhg74xSZmv4KMzUH50HiVnR76KAxQ0HRc1CGhJ4FZ82c4JxQmjmtUtuK123PuuNaej1xjBQe-5vP6ZiZi-Lh9N7dykgJ7vXHeUbeUVbieCx1OoHXzD3yQsyygD6l74QklsIsjVQSlOQWJH_3bX3ht-qqDPKv51e6E7ffIbjSW4lEUEhFzQZNJ7Ztg_rLyJB7DPm8327rBUNLZ5UnxcVQiIbG3QbDigzWzhhPDonBuRZ2y7BTlpKr4lkeXn7PTLVNcEi2I94YdeY6_3-J228q36sCH63aYYvt6UdEikBlvynE4PWVqEomlFABzA0Gw95vmxg1DSohd21wQgLuIke4AdhWXP1WUySeQJiTVaMjA8tXsFNzznhA_34StmYpnhrlqFxckSaaOE2QxXXvOMGkFZnuwnt0cGrJECokW8Mb-m7pazejxxCy5aAtn9r0gRk0_6_2LKnmU3WIU-ilJpJ8vlTGqTnkvHCjQ2B-X_JPnad42QERw_By8idciIjMpAq0CPgbf9jGtuBpRdLkRDd2zjrn7GSnvbD70qJTDDBNYSDBqN-xJRl8l9M_hcBV-V7cf4jtY7rvBtd_rQ6Oq-dOBbgvuusGKM7TclHlH1BJe2mTFyvzjRYtgTU74ijska0Pb_rSKtCLjXJjzxaeBm7PGAKrAu-pMrDHXr8OKrZZT15-MS7JmB7kEewece_8UYH7SnNouHDNfS1hBSdlyuXxS-7fmchN4NfXHqzdHpVhmAv_IsjdD78Z9ERro38uIbZSQEtMy-y1MfnuuJR__h-EexTODbjegWq2NpMWF8KlKEJpHsqQzwLNa652QPh360-nP7WKV9TRUePPmXE2J2kIy8YDLyDgM8M4e2fMKago=w2560-h1358?auditContext=prefetch"
    export BG_URL="https://lh3.googleusercontent.com/rd-d/ALs6j_E_5sfsEdBUsnvj6YX4QGZy6FuKmTShfeZGLjXPRCC_lDGBI-jdPvvY2acT9_EzUjSI-qtxNjpf4YzYMXxEk6khcPJKQUKSbPzMs-IztL5CL15V9dRTLgMWIvGuxLTqgSDQ8AijIC3fRRViW7htGaxmnzZPhp6RhgbmA_0oGz5cdJdKXfctqYieiREUzce8ySuCy9_Jw95S0aorSi8MgR9ucKopT516flJmrkeUAd5E0nJSK3joWemb36tulx3cRVvAR2alCT6wTb268VmZB7KSEcV82Z-FmGTxi0C_hgdGY5Vkty-lXqQo2eFDmJqU_IZmrhcsWBcu3UKsTJKVNNTdxgeOiFZYdrBidYbrmvFkU5RHtkk5WIn3iqdetM8sdbEnTMg-yyG0HQy4REV7ei20J9B5pWoBbugaQ0ZUSu38c9fTtWYusYeeT4ccMz6LurgUzCv5GzVs7TjtPBMv2GuEStg7GEgtYh1waWguMdKiCFMfVRlRBRDoaB_cwguD3pyl6C26oGtRQOtVZ2QekbPMPZ9pCego8KqcPlQCabZXZjL3OZkUxF7K9UEtGBq8SYfFO6c44mH3TCtuUIOPgZhLxFMSemcUoU-lpU18ivRJf4fNchJYI6MD4Ok61olm8u71GL1jDIuv281iMMyL3ZnGOuwvlnpPlnW-16T0vErVj-RDBg3-7Dsid7UQLJr6u1XKb7modrR4uTlLPANgaaE-vr0WMpiLvIMukXiSltfOYoSox_CCNuImLr08ACWMIsIqIaVu7rjcThrWzdZlgINRwO2HpPmhupWtuKqtEsS-9oshnT4zJC0lvaKMNKZXO6_71BDMxroNY8-BpE0sMxejf-W9yAaFz8pJze5irFW3ARP8sj1n0PC77TkbScZy5uN1LMuHQty5c1DDpuzRoNnrDQO3pzfVKhtk6PtVHupmNFolsBAdoOOGjR5uLj8x6K0pbdGslmcgsgejdjL6F6w32rNTy4g69CkqgGt6rBuXeye9EO8KDP67XPD7oQsS5Rexrr9JdsbP25gQf93VAFgTF_aA1dUMIasY8JMi9KFGs1J76s381d3SqNEOwPBzjN9Q8Za8lYAjv6E8xq1EkYPzZRLEW9V5G2a2UAiV9C99ZP-HD69ekPlhDdibYWLD5Un1Np37BysvM-dzG-4=w2560-h1358?auditContext=prefetch"

    # Патчим системный интерфейс ComfyUI (Frontend V2 + LiteGraph)
    python -c '
import os
import site

logo_url = os.environ.get("LOGO_URL")
bg_url = os.environ.get("BG_URL")

paths_to_check = []
for sp in site.getsitepackages():
    paths_to_check.append(os.path.join(sp, "comfyui_frontend_package", "static", "index.html"))
paths_to_check.append("/workspace/ComfyUI/web/index.html")

patch_code = f"""
<!-- XMODE NATIVE UI TWEAKS -->
<style>
  /* Кастомный фон */
  body, #app, .comfy-app-main, .graph-canvas-container {{
      background-image: url("{bg_url}") !important;
      background-size: cover !important;
      background-position: center !important;
      background-attachment: fixed !important;
  }}
  
  /* Стеклянный эффект */
  canvas.litegraph, canvas.lgraphcanvas {{
      opacity: 0.88 !important; 
  }}
  
  /* ЖЕСТКО ГЛУШИМ ЛОГОТИПЫ И КНОПКУ МЕНЮ */
  .comfy-logo, .comfyui-logo, svg[class*="comfyui-logo"],
  [aria-label="Menu"], [aria-label="Меню"],
  [data-pr-tooltip="Menu"], [data-pr-tooltip="Меню"],
  [data-pc-section="menuicon"] {{ display: none !important; }}

  /* СТРАХОВОЧНЫЙ CSS ОТ ВСПЛЫВАЮЩИХ ОКОН СВОЙСТВ И ПОИСКА */
  .p-sidebar-right, .p-dialog-right, 
  [data-pc-name="sidebar"][class*="right"],
  .lite-searchbox, .comfyui-node-search, [class*="node-search"] {{
      display: none !important;
  }}

  /* УБИВАЕМ COMFYUI MANAGER НА УРОВНЕ CSS */
  #cm-manager-btn,
  button[id*="manager" i],
  [data-pr-tooltip*="Manager" i],
  [title*="Manager" i],
  [aria-label*="Manager" i] {{
      display: none !important;
  }}
</style>

<script>
  // 1. АБСОЛЮТНАЯ БЛОКИРОВКА ДВОЙНОГО КЛИКА (Убивает поиск нод)
  window.addEventListener("dblclick", e => {{
      if (e.target.tagName.toLowerCase() === "canvas" || e.target.closest("canvas")) {{
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
      }}
  }}, true);

  // 2. БЛОКИРОВКА ГОРЯЧИХ КЛАВИШ КОДА
  window.addEventListener("keydown", e => {{
    if (e.key === "F12") {{ e.preventDefault(); e.stopPropagation(); }}
    if (e.ctrlKey && e.shiftKey && ["I", "J", "C", "i", "j", "c"].includes(e.key)) {{ e.preventDefault(); e.stopPropagation(); }}
    if (e.ctrlKey && ["u", "U", "s", "S", "c", "C", "v", "V"].includes(e.key)) {{ e.preventDefault(); e.stopPropagation(); }}
  }}, true);

  // 3. ХИРУРГИЧЕСКАЯ ВЫРЕЗКА ПУНКТОВ (ОБНОВЛЕНО ДЛЯ MANAGER)
  const observer = new MutationObserver(() => {{
    const killWords = [
        // Системные
        "ассеты", "assets", "узлы", "nodes", "models", "модели", "nodesmap", 
        "шаблоны", "справка", "консоль", "настройки", "settings", "перевод", 
        "translate", "save", "export", "download", "сохранить", "экспорт", 
        "скачать", "menu", "меню", 
        
        // MANAGER И ОПАСНЫЕ КНОПКИ ВЕРХНЕГО БАРА
        "менеджер", "manager", "workspace manager", "comfyui manager",
        "experiments", "share", "поделиться",
        
        // ЧЕРНОЕ МЕНЮ ПКМ ПО НОДЕ И ФОНУ
        "свойства", "properties", "панель свойств", "properties panel", 
        "добавить узел", "add node", "преобразовать в подграф", "convert to group",
        "клонировать", "clone", "node help", "add ue broadcasting", "поиск"
    ];
    
    // ДОБАВЛЕНО: header, .p-toolbar, .top-bar - теперь ищем и в верхней панели (где сидит Manager)
    const menuSelectors = "header, .p-toolbar, [class*=\u0027topbar\u0027], [class*=\u0027top-bar\u0027], .litecontextmenu, .comfy-menu, .p-menubar, .p-menu, .p-panelmenu, .p-sidebar, .p-tieredmenu, .p-contextmenu, nav, aside, [class*=\u0027comfyui-menu\u0027]";
    
    document.querySelectorAll(menuSelectors).forEach(container => {{
        container.querySelectorAll("li, a, button, .p-menuitem, .litemenu-entry, .p-button").forEach(el => {{
          const txt = (el.innerText || el.textContent || "").trim().toLowerCase();
          const aria = (el.getAttribute("aria-label") || "").toLowerCase();
          const tooltip = (el.getAttribute("data-pr-tooltip") || "").toLowerCase();
          const title = (el.getAttribute("title") || "").toLowerCase();
          const id = (el.getAttribute("id") || "").toLowerCase(); // Ищем даже по скрытому ID
          
          const combinedText = txt + " " + aria + " " + tooltip + " " + title + " " + id;

          // Прячем меню
          if (combinedText.includes("меню") || combinedText.includes("menu")) {{
              if (!combinedText.includes("рабочие") && !combinedText.includes("workflow")) {{
                  el.style.display = "none";
              }}
          }}

          // Прячем запрещенные пункты (Manager, Свойства, Клон и тд)
          if (killWords.some(w => combinedText === w || combinedText.includes(w))) {{
              if (!combinedText.includes("рабочие") && !combinedText.includes("workflow")) {{
                  el.style.display = "none";
              }}
          }}
        }});
    }});
  }});
  
  document.addEventListener("DOMContentLoaded", () => {{
    observer.observe(document.body, {{ 
        childList: true, 
        subtree: true, 
        characterData: true, 
        attributes: true, 
        attributeFilter: ["data-pr-tooltip", "aria-label", "title", "id"] 
    }});

    // Логотип
    const logo = document.createElement("img");
    logo.src = "{logo_url}";
    logo.style.cssText = "position: fixed; top: 15px; right: 30px; height: 50px; z-index: 10000; pointer-events: none; filter: drop-shadow(0px 4px 6px rgba(0,0,0,0.5));";
    document.body.appendChild(logo);
  }});

  // 4. ВЗЛОМ ЯДРА LITEGRAPH: ОТКЛЮЧАЕМ ПОИСК ИЗНУТРИ
  const overrideLiteGraph = setInterval(() => {{
      if (window.LiteGraph && window.LGraphCanvas) {{
          window.LGraphCanvas.prototype.showSearchBox = function() {{ return false; }};
          clearInterval(overrideLiteGraph);
      }}
  }}, 500);
</script>
<!-- /XMODE NATIVE UI TWEAKS -->
"""

for path in paths_to_check:
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        
        if "XMODE NATIVE UI TWEAKS" not in content:
            patched_content = content.replace("</head>", patch_code + "\n</head>")
            with open(path, "w", encoding="utf-8") as f:
                f.write(patched_content)
'
}
# Клонируем тихо (-q)
function provisioning_clone_comfyui() {
    if [[ ! -d "${COMFYUI_DIR}" ]]; then
        git clone -q https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}" > /dev/null 2>&1
    fi
    cd "${COMFYUI_DIR}"
}

# Ставим зависимости тихо (-q)
function provisioning_install_base_reqs() {
    if [[ -f requirements.txt ]]; then
        pip install -q --no-cache-dir -r requirements.txt > /dev/null 2>&1 || true
    fi
}

# Клонируем кастомные ноды тихо (-q)
function provisioning_get_nodes() {
    mkdir -p "${COMFYUI_DIR}/custom_nodes"
    cd "${COMFYUI_DIR}/custom_nodes"

    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="./${dir}"

        if [[ -d "$path" ]]; then
            (cd "$path" && git pull -q --ff-only > /dev/null 2>&1 || { git fetch -q > /dev/null 2>&1 && git reset -q --hard origin/main > /dev/null 2>&1; })
        else
            git clone -q "$repo" "$path" --recursive > /dev/null 2>&1 || true
        fi

        requirements="${path}/requirements.txt"
        if [[ -f "$requirements" ]]; then
            pip install -q --no-cache-dir -r "$requirements" > /dev/null 2>&1 || true
        fi
    done
}

# Качаем файлы тихо (-q)
function provisioning_get_files() {
    if [[ $# -lt 2 ]]; then return; fi
    local dir="$1"
    shift
    local files=("$@")

    mkdir -p "$dir"

    for url in "${files[@]}"; do
        if [[ -n "$HF_TOKEN" && "$url" =~ huggingface\.co ]]; then
            wget --header="Authorization: Bearer $HF_TOKEN" -q -nc --content-disposition -P "$dir" "$url" || true
        elif [[ -n "$CIVITAI_TOKEN" && "$url" =~ civitai\.com ]]; then
            wget --header="Authorization: Bearer $CIVITAI_TOKEN" -q -nc --content-disposition -P "$dir" "$url" || true
        else
            wget -q -nc --content-disposition -P "$dir" "$url" || true
        fi
    done
}

# Запуск provisioning
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi

echo "=========================================================="
echo "✅ Установка завершена! ComfyUI OFMHUB успешно запущен."
echo "=========================================================="
