#!/bin/bash
set -e

# Мы в папке /app, где лежит FastAPI воркер
cd /app

# ОПРЕДЕЛЯЕМ ПЕРЕМЕННЫЕ
COMFYUI_DIR="/workspace/runpod-slim/ComfyUI"
VENV_DIR="$COMFYUI_DIR/.venv-cu128"

if [ -d "$COMFYUI_DIR" ]; then
    echo "Found ComfyUI directory at $COMFYUI_DIR"
    cd $COMFYUI_DIR

    # АКТИВИРУЕМ ВАШ СОБСТВЕННЫЙ VENV! (Я убрал код, который переименовывал/игнорировал ваши venv)
    if [ -d "$VENV_DIR" ]; then
        source "$VENV_DIR/bin/activate"
        echo "Activated user's venv: $VENV_DIR"
    elif [ -d "venv" ]; then
        source "venv/bin/activate"
        echo "Activated user's default venv: venv"
    else
        echo "Warning: VENV_DIR not found, using system python"
    fi

    # Устанавливаем зависимости для WAS Node Suite (в частности numba), которых не хватает в вашем venv
    echo "Checking WAS Node Suite requirements..."
    if [ -f "custom_nodes/was-node-suite-comfyui/requirements.txt" ]; then
        pip install -r custom_nodes/was-node-suite-comfyui/requirements.txt
    else
        pip install numba
    fi

    echo "Starting ComfyUI..."
    python -u main.py --listen 0.0.0.0 --port 8188 > /comfyui.log 2>&1 &

    # Выходим из venv, чтобы запустить FastAPI хендлер системным питоном (где мы установили библиотеки для API)
    deactivate 2>/dev/null || true
else
    echo "Warning: ComfyUI directory $COMFYUI_DIR not found!"
    echo "Make sure your Network Volume is mounted to /workspace and contains runpod-slim/ComfyUI"
fi

# Ждем, пока ComfyUI запустится (оставляем таймер, чтобы API не крашилось раньше времени)
echo "Waiting for ComfyUI to be ready..."
ATTEMPTS=0
MAX_ATTEMPTS=300 # Ждать максимум 10 минут (300 * 2s)

while ! curl -s --fail http://127.0.0.1:8188/system_stats > /dev/null; do
    ATTEMPTS=$((ATTEMPTS+1))
    if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
        echo "ComfyUI failed to start in time. Proceeding to start FastAPI anyway..."
        break
    fi
    sleep 2
done

echo "ComfyUI is ready!"

# Возвращаемся в папку с нашим API
cd /app

echo "=== Starting Upscale API Worker on port 8000 ==="
# Запускаем FastAPI через системный python
exec uvicorn upscale_api:app --host 0.0.0.0 --port 8000
