#!/bin/bash
# Wan 2.1 Provisioning Script - Official Vast.ai Format
# Based on: https://raw.githubusercontent.com/vast-ai/base-image/refs/heads/main/derivatives/pytorch/derivatives/comfyui/provisioning_scripts/default.sh

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# System packages (if needed)
APT_PACKAGES=(
    # Add any system packages here
)

# Python packages
PIP_PACKAGES=(
    # Add any additional pip packages here
)

# Custom nodes for Wan 2.1
NODES=(
    "https://github.com/city96/ComfyUI-GGUF"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/Kosinkadink/ComfyUI-Advanced-ControlNet"
)

# Workflows (Wan 2.2 I2V workflow)
WORKFLOWS=(
    "https://raw.githubusercontent.com/daraskme/MyVastaiComfyui4Wan22/main/Wan2.2_I2V.json"
)

# Main checkpoint models
CHECKPOINT_MODELS=(
    # Add main checkpoints here if needed
)

# UNet models (GGUF format for Wan 2.1)
UNET_MODELS=(
    "https://huggingface.co/datasets/darask0/own4wan2.2/resolve/main/wan2.2_i2v_high_noise_14B_Q4_K_S.gguf"
    "https://huggingface.co/datasets/darask0/own4wan2.2/resolve/main/wan2.2_i2v_low_noise_14B_Q4_K_S.gguf"
)

# LoRA models
LORA_MODELS=(
    "https://huggingface.co/datasets/darask0/own4wan2.2/resolve/main/Wan21_I2V_14B_lightx2v_cfg_step_distill_lora_rank64.safetensors"
    "https://huggingface.co/datasets/darask0/own4wan2.2/resolve/main/NSFW-22-H-e8.safetensors"
    "https://huggingface.co/datasets/darask0/own4wan2.2/resolve/main/NSFW-22-L-e8.safetensors"
)

# VAE models
VAE_MODELS=(
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors"
)

# Upscale models (ESRGAN format)
ESRGAN_MODELS=(
    "https://huggingface.co/datasets/darask0/own4wan2.2/resolve/main/4xLexicaHAT.pth"
)

# ControlNet models (if needed)
CONTROLNET_MODELS=(
    # Add ControlNet models here if needed
)

# Text encoders (custom directory)
TEXT_ENCODER_MODELS=(
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_get_nodes
    provisioning_get_pip_packages
    provisioning_get_files \
        "${COMFYUI_DIR}/models/checkpoints" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/unet" \
        "${UNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/loras" \
        "${LORA_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/upscale_models" \
        "${ESRGAN_MODELS[@]}"
    # Custom: Text encoders
    provisioning_get_files \
        "${COMFYUI_DIR}/models/text_encoders" \
        "${TEXT_ENCODER_MODELS[@]}"
    # Custom: Workflows
    provisioning_get_files \
        "${COMFYUI_DIR}" \
        "${WORKFLOWS[@]}"
    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
            sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ -n $PIP_PACKAGES ]]; then
            pip install --no-cache-dir ${PIP_PACKAGES[@]}
    fi
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}/custom_nodes/${dir}"
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then
                printf "Updating node: %s...\n" "${repo}"
                ( cd "$path" && git pull )
                if [[ -e $requirements ]]; then
                   pip install --no-cache-dir -r "$requirements"
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            if [[ -e $requirements ]]; then
                pip install --no-cache-dir -r "${requirements}"
            fi
        fi
    done
}

function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi
    
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning Wan 2.1             #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nWan 2.1 Provisioning complete: ComfyUI will start now\n\n"
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    url="https://huggingface.co/api/whoami-v2"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1
    url="https://civitai.com/api/v1/models?hidden=1&limit=1"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

# Download from $1 URL to $2 file path
function provisioning_download() {
    if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif 
        [[ -n $CIVITAI_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi
    if [[ -n $auth_token ]];then
        wget --header="Authorization: Bearer $auth_token" -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    else
        wget -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    fi
}

# Allow user to disable provisioning if they started with a script they didn't want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
