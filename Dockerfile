# Используем стабильный базовый образ
FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

# Отключаем интерактивные диалоги apt-get
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

# Обновляем систему и ставим базовые утилиты + Python 3.10
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    git \
    unzip \
    dos2unix \
    ffmpeg \
    libgl1-mesa-glx \
    libglib2.0-0 \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Делаем python3 командой по умолчанию для python
RUN ln -s /usr/bin/python3 /usr/bin/python

# Ставим новейший PyTorch Nightly (CUDA 12.8), который знает про RTX 5090, но работает с драйверами RunPod (12.8)
RUN pip3 install --no-cache-dir --pre torch torchvision torchaudio "numpy<2" --index-url https://download.pytorch.org/whl/nightly/cu128

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
