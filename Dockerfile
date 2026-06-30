# Вы были абсолютно правы! Просто берем рабочий образ RunPod. Никаких ручных PyTorch!
FROM runpod/comfyui:main

WORKDIR /app

# Копируем наши требования для API (FastAPI, uvicorn и т.д.)
COPY requirements.txt .

# Устанавливаем только библиотеки для API (не трогая PyTorch)
RUN pip3 install --no-cache-dir -r requirements.txt

# Копируем скрипты воркера
COPY upscale_api.py .
COPY start.sh .

# Делаем скрипт исполняемым
RUN chmod +x start.sh

# Открываем порты API и Comfy
EXPOSE 8000 8188

CMD ["./start.sh"]


