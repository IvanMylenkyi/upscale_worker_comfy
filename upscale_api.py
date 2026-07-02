import os
import time
import requests
import json
import zipfile
import urllib.request
import random
from fastapi import FastAPI, BackgroundTasks
from pydantic import BaseModel
import uvicorn

app = FastAPI(title="Upscale API worker (Static Pod)")

COMFY_URL = "http://127.0.0.1:8188"
INPUT_DIR = "/workspace/runpod-slim/ComfyUI/input/upscale_input"
OUTPUT_DIR = "/workspace/runpod-slim/ComfyUI/output/upscale_output"

class UpscaleRequest(BaseModel):
    job_id: str
    input_zip_url: str
    output_put_url: str
    webhook_url: str
    image_count: int
    workflow_json: dict

def ensure_dirs():
    os.makedirs(INPUT_DIR, exist_ok=True)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    # Очистка папок перед началом работы
    for f in os.listdir(INPUT_DIR):
        file_path = os.path.join(INPUT_DIR, f)
        if os.path.isfile(file_path): os.remove(file_path)
    for f in os.listdir(OUTPUT_DIR):
        file_path = os.path.join(OUTPUT_DIR, f)
        if os.path.isfile(file_path): os.remove(file_path)

def download_file(url, dest):
    print(f"[Worker] Downloading zip to {dest}...")
    urllib.request.urlretrieve(url, dest)
    print(f"[Worker] Downloaded.")

def extract_zip(zip_path, extract_to):
    print(f"[Worker] Extracting {zip_path}...")
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall(extract_to)
    print(f"[Worker] Extracted.")

def create_zip(source_dir, zip_path):
    print(f"[Worker] Creating zip {zip_path} from {source_dir}...")
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, _, files in os.walk(source_dir):
            for file in files:
                file_path = os.path.join(root, file)
                arcname = os.path.relpath(file_path, source_dir)
                zipf.write(file_path, arcname)
    print(f"[Worker] Created zip.")

def upload_file(file_path, put_url):
    print(f"[Worker] Uploading {file_path} to S3...")
    with open(file_path, 'rb') as f:
        r = requests.put(put_url, data=f)
    if r.status_code not in (200, 201):
        raise Exception(f"Failed to upload: {r.status_code} {r.text}")
    print(f"[Worker] Uploaded successfully.")

def strip_metadata(source_dir):
    try:
        from PIL import Image, PngImagePlugin
        print("[Worker] Stripping metadata from output images...")
        for root, _, files in os.walk(source_dir):
            for file in files:
                if file.lower().endswith(('.png', '.jpg', '.jpeg', '.webp', '.bmp')):
                    file_path = os.path.join(root, file)
                    try:
                        with Image.open(file_path) as img:
                            if file.lower().endswith('.png'):
                                meta = PngImagePlugin.PngInfo()
                                img.save(file_path, "PNG", pnginfo=meta)
                            elif file.lower().endswith(('.jpg', '.jpeg')):
                                img.save(file_path, "JPEG", quality=100)
                            elif file.lower().endswith('.webp'):
                                img.save(file_path, "WEBP", quality=100)
                            else:
                                img.save(file_path)
                    except Exception as e:
                        print(f"[Worker] Failed to strip metadata for {file}: {e}")
    except ImportError:
        print("[Worker] PIL not found, skipping metadata strip.")

def send_webhook(webhook_url, payload):
    try:
        requests.post(webhook_url, json=payload, timeout=10)
    except Exception as e:
        print(f"[Worker] Webhook failed: {e}")

def send_progress(webhook_url, job_id, message):
    send_webhook(webhook_url, {"job_id": job_id, "status": "processing", "error": message})

def run_comfyui_workflow(workflow_json, client_id):
    print("[Worker] Queuing workflow to ComfyUI...")
    payload = {"prompt": workflow_json, "client_id": client_id}
    r = requests.post(f"{COMFY_URL}/prompt", json=payload)
    if r.status_code != 200:
        raise Exception(f"Failed to queue: {r.text}")
    return r.json()["prompt_id"]

def wait_for_completion(prompt_id, timeout=7200):
    print(f"[Worker] Waiting for prompt {prompt_id} to complete...")
    start = time.time()
    while time.time() - start < timeout:
        try:
            history = requests.get(f"{COMFY_URL}/history/{prompt_id}", timeout=5).json()
            if prompt_id in history:
                print(f"[Worker] Prompt {prompt_id} completed.")
                return True
        except Exception:
            pass
        time.sleep(2)
    raise Exception("Timeout waiting for ComfyUI generation")

def process_upscale_job(req: UpscaleRequest):
    job_id = req.job_id
    zip_path = f"/tmp/{job_id}_input.zip"
    out_zip_path = f"/tmp/{job_id}_output.zip"
    client_id = job_id
    
    try:
        send_progress(req.webhook_url, job_id, "Downloading and preparing images...")
        ensure_dirs()
        download_file(req.input_zip_url, zip_path)
        extract_zip(zip_path, INPUT_DIR)
        
        images = [f for f in os.listdir(INPUT_DIR) if f.lower().endswith(('.png', '.jpg', '.jpeg', '.webp', '.bmp'))]
        actual_count = len(images)
        print(f"[Worker] Found {actual_count} images in {INPUT_DIR}.")
        
        if actual_count == 0:
            print("[Worker] WARNING: No images found to process!")
            
        for i in range(actual_count):
            print(f"[Worker] Processing image {i+1}/{actual_count}...")
            send_progress(req.webhook_url, job_id, f"Upscaling image {i+1} of {actual_count}...")
            
            if '63' in req.workflow_json and 'inputs' in req.workflow_json['63']:
                req.workflow_json['63']['inputs']['index'] = i
                req.workflow_json['63']['inputs']['seed'] = random.randint(1, 1000000000)
                req.workflow_json['63']['inputs']['path'] = INPUT_DIR
                
            if '36' in req.workflow_json and 'inputs' in req.workflow_json['36']:
                req.workflow_json['36']['inputs']['seed'] = random.randint(1, 1000000000)
                
            if '72' in req.workflow_json and 'inputs' in req.workflow_json['72']:
                req.workflow_json['72']['inputs']['filename_prefix'] = f"upscale_output/upscale_{i}"
                
            prompt_id = run_comfyui_workflow(req.workflow_json, client_id)
            
            send_progress(req.webhook_url, job_id, f"Processing image {i+1}/{actual_count} (Running workflow)...")
            wait_for_completion(prompt_id)
        
        send_progress(req.webhook_url, job_id, "Stripping metadata...")
        strip_metadata(OUTPUT_DIR)
        
        send_progress(req.webhook_url, job_id, "Creating final ZIP archive...")
        create_zip(OUTPUT_DIR, out_zip_path)
        upload_file(out_zip_path, req.output_put_url)
        
        send_webhook(req.webhook_url, {"job_id": job_id, "status": "completed"})
    except Exception as e:
        print(f"[Worker] Job {job_id} failed: {e}")
        send_webhook(req.webhook_url, {"job_id": job_id, "status": "failed", "error": str(e)})
    finally:
        # Cleanup temp zip files
        if os.path.exists(zip_path): os.remove(zip_path)
        if os.path.exists(out_zip_path): os.remove(out_zip_path)
        
        # Глубокая очистка диска, чтобы не засорять Volume
        print("[Worker] Cleaning up volume directories...")
        if os.path.exists(INPUT_DIR):
            for f in os.listdir(INPUT_DIR):
                fp = os.path.join(INPUT_DIR, f)
                if os.path.isfile(fp): os.remove(fp)
        if os.path.exists(OUTPUT_DIR):
            for f in os.listdir(OUTPUT_DIR):
                fp = os.path.join(OUTPUT_DIR, f)
                if os.path.isfile(fp): os.remove(fp)

@app.post("/upscale")
def start_upscale(req: UpscaleRequest, background_tasks: BackgroundTasks):
    background_tasks.add_task(process_upscale_job, req)
    return {"status": "accepted", "job_id": req.job_id}

@app.get("/health")
def health():
    return {"status": "ok"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
