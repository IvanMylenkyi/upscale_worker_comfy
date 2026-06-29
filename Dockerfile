# Используем официальный образ RunPod ComfyUI с CUDA 13.0 (идеально для RTX 5090 Blackwell)
FROM runpod/comfyui:cuda12.8

# Отключаем интерактивные диалоги apt-get
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

# Обновляем систему и ставим только необходимые утилиты (Python и так уже есть в базовом образе)
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    dos2unix \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# НЕ устанавливаем PyTorch вручную! Базовый образ уже содержит идеальный PyTorch для 5090.
# Просто фиксируем numpy<2, чтобы избежать крашей старых плагинов.
RUN pip3 install --no-cache-dir "numpy<2"

# Копируем список зависимостей
COPY requirements.txt .

# Устанавливаем зависимости Python
RUN pip3 install --no-cache-dir -r requirements.txt

# Копируем скрипты воркера
COPY upscale_api.py .
COPY start.sh .

# Делаем start.sh исполняемым и фиксим виндовые окончания строк (CRLF -> LF)
RUN dos2unix start.sh && chmod +x start.sh

# Открываем порты (8000 для нашего API, 8188 для ComfyUI)
EXPOSE 8000 8188

# Запускаем стартовый скрипт
CMD ["./start.sh"]
