# Вы были абсолютно правы! Просто берем рабочий образ RunPod. Никаких ручных PyTorch!
FROM runpod/comfyui:cuda12.8

WORKDIR /app

# Копируем наши требования для API (FastAPI, uvicorn и т.д.)
COPY requirements.txt .

# Устанавливаем только библиотеки для API (не трогая PyTorch)
RUN pip3 install --no-cache-dir -r requirements.txt

# Копируем скрипты воркера
COPY upscale_api.py /app/upscale_api.py

# КРИТИЧЕСКИ ВАЖНО: Мы ДОЛЖНЫ перезаписать системный /start.sh от RunPod!
# Иначе RunPod запустит свой скрипт, проигнорирует наши аргументы и запустит Jupyter/Filebrowser
COPY start.sh /start.sh
RUN sed -i 's/\r$//' /start.sh && chmod +x /start.sh

# Открываем порты API и Comfy
EXPOSE 8000 8188

# Запускаем наш переопределенный скрипт
CMD ["/start.sh"]

