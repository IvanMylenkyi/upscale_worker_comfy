#!/bin/bash
# Убрали set -e, чтобы скрипт не падал при малейшей ошибке (например, в pip)

# Убеждаемся, что мы в нужной директории для запуска API
cd /app

# Если на примонтированном диске (Network Volume) есть ComfyUI, запускаем его в фоне.
# Путь /workspace - стандартная точка монтирования в RunPod.
COMFYUI_DIR="/workspace/runpod-slim/ComfyUI"

if [ -d "$COMFYUI_DIR" ]; then
    echo "Found ComfyUI directory at $COMFYUI_DIR, starting it in background..."
    cd $COMFYUI_DIR

    # Устанавливаем зависимости для ComfyUI в ГЛОБАЛЬНОЕ окружение контейнера
    if [ -f "requirements.txt" ]; then
        echo "Installing ComfyUI dependencies into the global environment..."
        # Используем глобальный pip3 и принудительно устанавливаем sqlalchemy
        # Убрали --no-cache-dir, чтобы если под перезапускается, не качать всё заново (если кэш сохранился)
        pip3 install sqlalchemy "numpy<2" -r requirements.txt || echo "Pip install failed, but continuing..."
    fi

    # Устанавливаем зависимости для WAS Node Suite если он есть
    if [ -d "custom_nodes/was-node-suite-comfyui" ]; then
        echo "Installing WAS Node Suite dependencies..."
        pip3 install sqlalchemy "numpy<2" -r custom_nodes/was-node-suite-comfyui/requirements.txt || echo "WAS Node Suite requirements failed to install, but continuing..."
    fi

    # Временно переименовываем venv, чтобы ComfyUI не пытался его использовать
    if [ -d "venv" ]; then
        echo "Temporarily disabling ComfyUI's venv to use global environment..."
        mv venv venv_disabled
    fi

    echo "Starting ComfyUI using the container's global python..."
    # Запускаем ComfyUI, используя глобальный python3, чтобы он нашел установленные зависимости.
    python3 main.py --listen 0.0.0.0 --port 8188 &

else
    echo "Warning: ComfyUI directory $COMFYUI_DIR not found!"
    echo "Make sure your Network Volume is mounted to /workspace and contains runpod-slim/ComfyUI"
fi

# Ждем, пока ComfyUI запустится и будет готов принимать запросы
echo "Waiting for ComfyUI to be ready..."

ATTEMPTS=0
MAX_ATTEMPTS=300 # Ждать максимум 10 минут (300 * 2s)

while ! curl -s --fail http://127.0.0.1:8188/system_stats > /dev/null; do
    ATTEMPTS=$((ATTEMPTS+1))
    if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
        echo "ComfyUI failed to start in time. Proceeding to start FastAPI anyway so the container doesn't crash-loop."
        break
    fi
    sleep 2
done

echo "ComfyUI is ready!"

# Возвращаемся в папку с нашим API
cd /app

echo "Starting Upscale API Worker on port 8000..."
# Запускаем FastAPI через uvicorn
exec uvicorn upscale_api:app --host 0.0.0.0 --port 8000
