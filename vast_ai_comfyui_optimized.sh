#!/bin/bash
# Vast.ai ComfyUI Optimized On-start Script
# Based on official Vast.ai ComfyUI image documentation
# Installs Wan 2.1 models and required custom nodes

# Exit on error
set -eo pipefail

# Activate the main virtual environment (as per Vast.ai docs)
. /venv/main/bin/activate

# Color codes for better logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a /var/log/portal/setup.log; }
log_success() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1" | tee -a /var/log/portal/setup.log; }
log_warning() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a /var/log/portal/setup.log; }
log_error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a /var/log/portal/setup.log; }

log_info "🚀 Starting Wan 2.1 provisioning for ComfyUI..."

# Check if we're in the correct environment
if [ ! -d "${WORKSPACE}/ComfyUI" ]; then
    log_error "ComfyUI not found in ${WORKSPACE}. This script requires the official Vast.ai ComfyUI image."
    exit 1
fi

# Navigate to ComfyUI directory
cd "${WORKSPACE}/ComfyUI"

log_info "📦 Installing required custom nodes..."

# Install custom nodes (checking if they exist first)
cd custom_nodes

declare -A custom_nodes=(
    ["ComfyUI-GGUF"]="https://github.com/city96/ComfyUI-GGUF.git"
    ["rgthree-comfy"]="https://github.com/rgthree/rgthree-comfy.git"
    ["ComfyUI-VideoHelperSuite"]="https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
    ["ComfyUI_essentials"]="https://github.com/cubiq/ComfyUI_essentials.git"
    ["ComfyUI-Advanced-ControlNet"]="https://github.com/Kosinkadink/ComfyUI-Advanced-ControlNet.git"
)

for node_name in "${!custom_nodes[@]}"; do
    repo_url="${custom_nodes[$node_name]}"
    
    if [ -d "$node_name" ]; then
        log_warning "$node_name already exists, updating..."
        cd "$node_name"
        git pull || log_warning "Failed to update $node_name"
        cd ..
    else
        log_info "Installing $node_name..."
        git clone "$repo_url" || log_error "Failed to clone $node_name"
    fi
    
    # Install requirements if they exist
    if [ -f "$node_name/requirements.txt" ]; then
        log_info "Installing requirements for $node_name..."
        cd "$node_name"
        pip install --no-cache-dir -r requirements.txt || log_warning "Failed to install requirements for $node_name"
        cd ..
    fi
done

log_success "Custom nodes installation completed"

# Create model directories (using Vast.ai workspace structure)
log_info "📁 Creating model directories..."
cd "${WORKSPACE}/ComfyUI"

declare -a model_dirs=(
    "models/loras"
    "models/unet" 
    "models/text_encoders"
    "models/clip_vision"
    "models/vae"
    "models/upscale_models"
)

for dir in "${model_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        log_success "Created: $dir"
    else
        log_info "Directory exists: $dir"
    fi
done

# Download models function with retry capability
download_model() {
    local url="$1"
    local target_dir="$2"
    local filename=$(basename "$url")
    local filepath="${target_dir}/${filename}"
    local max_retries=3
    local retry_count=0
    
    if [ -f "$filepath" ]; then
        log_warning "File already exists, skipping: $filename"
        return 0
    fi
    
    log_info "Downloading: $filename to $target_dir"
    cd "$target_dir"
    
    while [ $retry_count -lt $max_retries ]; do
        if wget --progress=bar:force:noscroll -c -t 3 -T 30 "$url"; then
            log_success "Downloaded: $filename"
            return 0
        else
            retry_count=$((retry_count + 1))
            log_warning "Download failed, retry $retry_count/$max_retries for: $filename"
            sleep 5
        fi
    done
    
    log_error "Failed to download after $max_retries attempts: $filename"
    return 1
}

# Model download list (URL|target_directory)
declare -a models=(
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors|${WORKSPACE}/ComfyUI/models/text_encoders"
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors|${WORKSPACE}/ComfyUI/models/vae"
    "https://huggingface.co/datasets/darask0/own4wan2.2/resolve/main/Wan21_I2V_14B_lightx2v_cfg_step_distill_lora_rank64.safetensors|${WORKSPACE}/ComfyUI/models/loras"
    "https://huggingface.co/datasets/darask0/own4wan2.2/resolve/main/NSFW-22-H-e8.safetensors|${WORKSPACE}/ComfyUI/models/loras"
    "https://huggingface.co/datasets/darask0/own4wan2.2/resolve/main/NSFW-22-L-e8.safetensors|${WORKSPACE}/ComfyUI/models/loras"
    "https://huggingface.co/datasets/darask0/own4wan2.2/resolve/main/wan2.2_i2v_high_noise_14B_Q4_K_S.gguf|${WORKSPACE}/ComfyUI/models/unet"
    "https://huggingface.co/datasets/darask0/own4wan2.2/resolve/main/wan2.2_i2v_low_noise_14B_Q4_K_S.gguf|${WORKSPACE}/ComfyUI/models/unet"
    "https://huggingface.co/datasets/darask0/own4wan2.2/resolve/main/4xLexicaHAT.pth|${WORKSPACE}/ComfyUI/models/upscale_models"
)

log_info "📥 Starting model downloads (${#models[@]} files)..."

# Start downloads in background with limited concurrency
max_concurrent=3
current_jobs=0
pids=()

for model_info in "${models[@]}"; do
    IFS='|' read -r url target_dir <<< "$model_info"
    
    # Start download in background
    download_model "$url" "$target_dir" &
    pids+=($!)
    current_jobs=$((current_jobs + 1))
    
    # Limit concurrent downloads
    if [ $current_jobs -ge $max_concurrent ]; then
        wait "${pids[0]}"
        pids=("${pids[@]:1}")
        current_jobs=$((current_jobs - 1))
    fi
done

# Wait for remaining downloads
for pid in "${pids[@]}"; do
    wait "$pid"
done

log_success "All model downloads completed!"

# Verify downloads and show summary
log_info "📊 Download verification and summary:"
total_files=0
total_size=0

for model_info in "${models[@]}"; do
    IFS='|' read -r url target_dir <<< "$model_info"
    filename=$(basename "$url")
    filepath="${target_dir}/${filename}"
    
    if [ -f "$filepath" ]; then
        size=$(du -h "$filepath" | cut -f1)
        file_size_bytes=$(stat -f%z "$filepath" 2>/dev/null || stat -c%s "$filepath")
        total_size=$((total_size + file_size_bytes))
        total_files=$((total_files + 1))
        log_success "✓ $filename ($size)"
    else
        log_error "✗ Missing: $filename"
    fi
done

# Display total summary
total_size_human=$(numfmt --to=iec $total_size 2>/dev/null || echo "$(($total_size / 1024 / 1024))MB")
log_info "📈 Summary: $total_files files downloaded, total size: $total_size_human"

# Create a status file for monitoring
cat > "${WORKSPACE}/wan21_setup_status.txt" << EOF
Wan 2.1 Setup Status - $(date)
===============================
Files Downloaded: $total_files/${#models[@]}
Total Size: $total_size_human
Setup Completed: $(date)

Custom Nodes Installed:
- ComfyUI-GGUF (UnetLoaderGGUF)
- rgthree-comfy (Power Lora Loader)
- ComfyUI-VideoHelperSuite (VHS_VideoCombine)
- ComfyUI_essentials (Film Grain)
- ComfyUI-Advanced-ControlNet

Models Downloaded:
EOF

for model_info in "${models[@]}"; do
    IFS='|' read -r url target_dir <<< "$model_info"
    filename=$(basename "$url")
    echo "- $filename" >> "${WORKSPACE}/wan21_setup_status.txt"
done

log_success "✅ Wan 2.1 provisioning completed successfully!"
log_info "📋 Setup summary saved to: ${WORKSPACE}/wan21_setup_status.txt"
log_info "🎨 ComfyUI is ready with Wan 2.1 models and custom nodes"
log_info "🌐 Access ComfyUI via the 'Open' button or port 8188"

# Optional: Restart ComfyUI to ensure new nodes are loaded
if pgrep -f "python.*main.py" > /dev/null; then
    log_info "🔄 Restarting ComfyUI to load new custom nodes..."
    supervisorctl restart comfyui || log_warning "Could not restart ComfyUI via supervisor"
fi

log_info "🏁 Provisioning script completed. Ready to use!"
