import matplotlib
matplotlib.use('Agg')
import numpy as np
from flask import Flask, request, send_file, jsonify
from flask_cors import CORS
import cv2
import tempfile
import os
import json
import subprocess
import time
from datetime import datetime
import threading
import socket
from zeroconf import ServiceInfo, Zeroconf
import uuid
from zeroconf import ServiceInfo, Zeroconf
from zeroconf._exceptions import NonUniqueNameException


# Object detection imports
try:
    import torch
    from ultralytics import YOLO
    YOLO_AVAILABLE = True
    print("YOLO model loaded successfully")
except ImportError:
    YOLO_AVAILABLE = False
    print("YOLO not available. Install ultralytics: pip install ultralytics")

app = Flask(__name__)
CORS(app)

current_recording_process = None
current_recording_filepath = None
detection_model = None
detection_active = False
OUTPUT_DIR = os.path.expanduser("~/Desktop/HeatmapRecordings")

def initialize_yolo_model():
    """Initialize YOLO model for object detection"""
    global detection_model
    if YOLO_AVAILABLE and detection_model is None:
        try:
            # Download and load YOLOv8 model (can use yolov8n.pt, yolov8s.pt, yolov8m.pt, yolov8l.pt, yolov8x.pt)
            detection_model = YOLO('yolov8n.pt')  # nano version for faster detection
            print("YOLO model initialized successfully")
            return True
        except Exception as e:
            print(f"Failed to initialize YOLO model: {e}")
            return False
    return YOLO_AVAILABLE

def capture_screen_region(x_percent, y_percent, region_size=400):
    """Capture a region around the click coordinates"""
    try:
        # Take a screenshot using ffmpeg
        temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
        cmd = ['ffmpeg', '-f', 'avfoundation', '-i', '1', '-frames:v', '1', 
               '-vf', 'crop=iw:ih*0.865:0:ih*0.085', '-y', temp_screenshot.name]
        
        result = subprocess.run(cmd, capture_output=True, timeout=10)
        
        if result.returncode == 0:
            # Read the captured image
            image = cv2.imread(temp_screenshot.name)
            if image is not None:
                h, w = image.shape[:2]
                
                # Calculate click position in pixel coordinates
                click_x = int(x_percent * w)
                click_y = int(y_percent * h)
                
                # Define region around click
                half_region = region_size // 2
                x1 = max(0, click_x - half_region)
                y1 = max(0, click_y - half_region)
                x2 = min(w, click_x + half_region)
                y2 = min(h, click_y + half_region)
                
                # Extract region
                region = image[y1:y2, x1:x2]
                
                # Clean up temp file
                os.unlink(temp_screenshot.name)
                
                return region, (x1, y1, x2, y2), (w, h)
        
        # Clean up temp file if it exists
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)
            
    except Exception as e:
        print(f"Error capturing screen region: {e}")
    
    return None, None, None

def detect_objects_in_region(image_region, region_coords, screen_size):
    """Detect objects in the given image region using YOLO"""
    global detection_model
    
    if not YOLO_AVAILABLE or detection_model is None:
        return []
    
    try:
        # Run YOLO detection
        results = detection_model(image_region, conf=0.3)  # confidence threshold
        
        detections = []
        region_x1, region_y1, region_x2, region_y2 = region_coords
        screen_w, screen_h = screen_size
        region_w = region_x2 - region_x1
        region_h = region_y2 - region_y1
        
        for result in results:
            boxes = result.boxes
            if boxes is not None:
                for box in boxes:
                    # Get class name and confidence
                    class_id = int(box.cls[0])
                    class_name = detection_model.names[class_id]
                    confidence = float(box.conf[0])
                    
                    # Get bounding box coordinates (x_center, y_center, width, height) in normalized coordinates
                    x_center, y_center, bbox_w, bbox_h = box.xywhn[0].tolist()
                    
                    # Convert from region-relative coordinates to screen-relative coordinates
                    # First convert to pixel coordinates within the region
                    region_x_center = x_center * region_w
                    region_y_center = y_center * region_h
                    region_bbox_w = bbox_w * region_w
                    region_bbox_h = bbox_h * region_h
                    
                    # Then convert to screen coordinates
                    screen_x_center = (region_x1 + region_x_center) / screen_w
                    screen_y_center = (region_y1 + region_y_center) / screen_h
                    screen_bbox_w = region_bbox_w / screen_w
                    screen_bbox_h = region_bbox_h / screen_h
                    
                    # Convert center coordinates to top-left coordinates
                    screen_x = screen_x_center - (screen_bbox_w / 2)
                    screen_y = screen_y_center - (screen_bbox_h / 2)
                    
                    detections.append({
                        "name": class_name,
                        "confidence": confidence,
                        "bbox": {
                            "x": max(0.0, min(1.0, screen_x)),
                            "y": max(0.0, min(1.0, screen_y)),
                            "width": max(0.0, min(1.0, screen_bbox_w)),
                            "height": max(0.0, min(1.0, screen_bbox_h))
                        }
                    })
                    
                    print(f"Detected: {class_name} (confidence: {confidence:.2f}) at bbox: ({screen_x:.3f}, {screen_y:.3f}, {screen_bbox_w:.3f}, {screen_bbox_h:.3f})")
        
        # Sort by confidence
        detections.sort(key=lambda x: x['confidence'], reverse=True)
        
        # Return top 5 detections
        return detections[:5]
        
    except Exception as e:
        print(f"Error in object detection: {e}")
        return []

def get_local_ip():
    """Get the local IP address of the Mac"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"

def register_service():
    """Register the Flask service with Bonjour/mDNS with error handling"""
    try:
        zeroconf = Zeroconf()
        
        # Get local IP and hostname
        local_ip = get_local_ip()
        hostname = socket.gethostname()
        
        # Create unique service name with UUID
        unique_id = str(uuid.uuid4())[:8]
        service_name = f"Vision Pro Heatmap Server {unique_id}"
        service_type = "_visionpro._tcp.local."
        service_port = 5555
        
        info = ServiceInfo(
            service_type,
            f"{service_name}.{service_type}",
            addresses=[socket.inet_aton(local_ip)],
            port=service_port,
            properties={
                'description': 'Apple Vision Pro Heatmap Generation Server',
                'hostname': hostname,
                'unique_id': unique_id
            }
        )
        
        zeroconf.register_service(info)
        print(f"Service registered: {service_name} at {local_ip}:{service_port}")
        return zeroconf, info
        
    
    except Exception as e:
        print(f"Failed to register Zeroconf service: {e}")
        print("Continuing without service discovery...")
        return None, None


def reduce_video_quality(input_path, max_width=1280, max_height=720, crf=28):
    try:
        cap = cv2.VideoCapture(input_path)
        w, h = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        cap.release()
        
        scale = min(min(max_width / w, max_height / h), 1.0)
        new_w, new_h = int(w * scale) & ~1, int(h * scale) & ~1
        
        if scale >= 0.95: return input_path, 1.0, 1.0
        
        reduced_path = input_path.replace('.mp4', '_reduced.mp4')
        cmd = ['ffmpeg', '-i', input_path, '-vf', f'scale={new_w}:{new_h}',
               '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', str(crf), '-an', '-y', reduced_path]
        
        if subprocess.run(cmd, capture_output=True).returncode == 0:
            return reduced_path, new_w / w, new_h / h
        return input_path, 1.0, 1.0
    except:
        return input_path, 1.0, 1.0

def create_heatmap_overlay(brightness_grid, video_width, video_height, base_sigma=40, base_resolution=1920):
    if np.sum(brightness_grid) == 0: return None
    
    resolution_scale = video_width / base_resolution
    scaled_sigma = base_sigma * resolution_scale
    scaled_sigma = max(scaled_sigma, 5.0)
    
    blurred = cv2.GaussianBlur(brightness_grid.astype(np.float32), (0, 0), scaled_sigma)
    if np.max(blurred) > 0:
        blurred = (blurred / np.max(blurred) * 255).astype(np.uint8)
    return cv2.applyColorMap(blurred, cv2.COLORMAP_INFERNO)

def generate_filename(tracking_data, suffix=""):
    timestamp = tracking_data.get('timestamp', datetime.now().strftime("%Y%m%d_%H%M%S"))
    user_name = tracking_data.get('user_name', 'unknown_user').replace(' ', '_')
    tracking_type = tracking_data.get('tracking_type', 'unknown')
    
    if tracking_data.get('video_name'):
        video_name = os.path.splitext(tracking_data['video_name'])[0].replace(' ', '_')
        base_name = f"{user_name}_{video_name}_{tracking_type}_{timestamp}"
    else:
        base_name = f"{user_name}_{tracking_type}_{timestamp}"
    
    return f"{base_name}{suffix}"

def save_tracking_data(tracking_data, filename_base):
    try:
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        json_path = os.path.join(OUTPUT_DIR, f"{filename_base}_data.json")
        
        with open(json_path, 'w') as f:
            json.dump(tracking_data, f, indent=2)
        
        return json_path
    except Exception as e:
        print(f"Error saving tracking data: {e}")
        return None

def generate_heatmap(video_path, tracking_data):
    try:
        reduced_path, scale_x, scale_y = reduce_video_quality(video_path)
        
        filename_base = generate_filename(tracking_data)
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        output_path = os.path.join(OUTPUT_DIR, f"{filename_base}_heatmap.mp4")
        
        save_tracking_data(tracking_data, filename_base)
        
        cap = cv2.VideoCapture(reduced_path)
        if not cap.isOpened(): return None
        
        fps = cap.get(cv2.CAP_PROP_FPS)
        w, h = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        
        out = cv2.VideoWriter(output_path, cv2.VideoWriter_fourcc(*'mp4v'), fps, (w, h))
        fade_duration = int(fps * 0.3)
        
        click_data = tracking_data.get('click_data', [])
        brightness_per_frame = np.zeros((frame_count, h, w), dtype=np.float32)
        
        for click in click_data:
            x, y = int(float(click["x"]) * w), int(float(click["y"]) * h)
            x, y = min(max(x, 0), w - 1), min(max(y, 0), h - 1)
            
            start_frame = max(0, int((click["timestamp"] * fps) - fade_duration))
            end_frame = min(start_frame + fade_duration * 2, frame_count)
            
            frame_range = np.arange(start_frame, end_frame)
            fade_in = frame_range < start_frame + fade_duration
            fade_out = frame_range >= end_frame - fade_duration
            
            brightness = np.ones_like(frame_range, dtype=np.float32)
            brightness[fade_in] = (frame_range[fade_in] - start_frame) / fade_duration
            brightness[fade_out] = (end_frame - frame_range[fade_out]) / fade_duration
            
            brightness_per_frame[frame_range, y, x] += brightness
        
        max_brightness = np.max(brightness_per_frame)
        if max_brightness > 1.0:
            brightness_per_frame = np.sqrt(brightness_per_frame / max_brightness)
        
        batch_size = 50 if w * h < 1000000 else 25
        for i in range(0, frame_count, batch_size):
            batch_end = min(i + batch_size, frame_count)
            progress = int((i / frame_count) * 100)
            print(f"Video generation: {progress}%")
            
            for j in range(i, batch_end):
                ret, frame = cap.read()
                if not ret: break
                
                darkened = cv2.addWeighted(frame, 0.5, np.zeros_like(frame), 0.5, 0)
                heatmap = create_heatmap_overlay(brightness_per_frame[j], w, h)
                
                if heatmap is not None:
                    result = cv2.addWeighted(darkened, 1.0, heatmap, 0.8, 0)
                else:
                    result = darkened
                
                out.write(result)
        
        final_grid = np.zeros((h, w), dtype=np.float32)
        for click in click_data:
            x, y = int(float(click["x"]) * w), int(float(click["y"]) * h)
            if 0 <= x < w and 0 <= y < h:
                final_grid[y, x] += 1
        
        if np.sum(final_grid) > 0:
            if np.max(final_grid) > 1.0:
                final_grid = np.sqrt(final_grid / np.max(final_grid))
            final_heatmap = create_heatmap_overlay(final_grid, w, h)
            if final_heatmap is not None:
                black = np.zeros((h, w, 3), dtype=np.uint8)
                final_frame = cv2.addWeighted(black, 1.0, final_heatmap, 1.0, 0)
                out.write(final_frame)
        
        cap.release()
        out.release()
        
        if reduced_path != video_path:
            try: os.unlink(reduced_path)
            except: pass
        
        print("Heatmap generation completed")
        return output_path
        
    except Exception as e:
        print(f"Error: {e}")
        return None

# New detection endpoints
@app.route('/start_detection', methods=['POST'])
def start_detection():
    global detection_active
    
    if not initialize_yolo_model():
        return jsonify({"status": "error", "message": "Object detection not available"}), 500
    
    detection_active = True
    print("Real-time detection mode activated")
    return jsonify({"status": "success", "message": "Detection started"})

@app.route('/stop_detection', methods=['POST'])
def stop_detection():
    global detection_active
    detection_active = False
    print("Real-time detection mode deactivated")
    return jsonify({"status": "success", "message": "Detection stopped"})

@app.route('/detect_object', methods=['POST'])
def detect_object():
    global detection_active
    
    if not detection_active:
        return jsonify({"status": "error", "message": "Detection not active"}), 400
    
    if not YOLO_AVAILABLE or detection_model is None:
        return jsonify({"status": "error", "message": "Object detection not available"}), 500
    
    try:
        data = request.get_json()
        x = data.get('x', 0.5)
        y = data.get('y', 0.5)
        timestamp = data.get('timestamp', time.time())
        
        print(f"Detection request at ({x:.3f}, {y:.3f})")
        
        # Capture screen region around click
        image_region, region_coords, screen_size = capture_screen_region(x, y)
        
        if image_region is None:
            return jsonify({
                "status": "error", 
                "message": "Failed to capture screen region",
                "detections": []
            }), 500
        
        # Detect objects in the region
        detections = detect_objects_in_region(image_region, region_coords, screen_size)
        
        # Log detections
        if detections:
            print(f"Detections found: {[d['name'] for d in detections]}")
        else:
            print("No objects detected in region")
        
        return jsonify({
            "status": "success",
            "detections": detections,
            "region_coords": region_coords,
            "screen_size": screen_size
        })
        
    except Exception as e:
        print(f"Error in object detection: {e}")
        return jsonify({
            "status": "error", 
            "message": str(e),
            "detections": []
        }), 500

# Existing endpoints
@app.route('/start_recording', methods=['POST'])
def start_recording():
    global current_recording_process, current_recording_filepath

    if current_recording_process:
            current_recording_process.terminate()
            current_recording_process.wait()
            current_recording_process = None    
    try:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        current_recording_filepath = os.path.join(tempfile.gettempdir(), f"temp_recording_{timestamp}.mp4")
        
        def record():
            global current_recording_process
            cmd = ['ffmpeg', '-f', 'avfoundation', '-i', '1', '-r', '20', 
                  '-vf', 'crop=iw:ih*0.865:0:ih*0.085,scale=1280:720',
                  '-vcodec', 'libx264', '-preset', 'veryfast', '-crf', '25', 
                  '-pix_fmt', 'yuv420p', '-y', current_recording_filepath]
            current_recording_process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        
        threading.Thread(target=record).start()
        return jsonify({"status": "success", "message": "Recording started"})
        
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/stop_recording', methods=['POST'])
def stop_recording():
    global current_recording_process, current_recording_filepath
    
    try:
        data = request.get_json()
        tracking_data = data.get('tracking_data', {})
                
        if current_recording_process:
            current_recording_process.terminate()
            current_recording_process.wait()
            current_recording_process = None
            time.sleep(2)
            
            if current_recording_filepath and os.path.exists(current_recording_filepath):
                heatmap_path = generate_heatmap(current_recording_filepath, tracking_data)
                os.unlink(current_recording_filepath)
                
                if heatmap_path:
                    return send_file(heatmap_path, mimetype='video/mp4', download_name='heatmap.mp4')
                else:
                    return jsonify({"status": "error", "message": "Failed to generate heatmap"}), 500
            else:
                return jsonify({"status": "error", "message": "Recording file not found"}), 500
        else:
            return jsonify({"status": "error", "message": "No active recording"}), 400
            
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/generate_heatmap', methods=['POST'])
def generate_heatmap_endpoint():
    try:
        video_file = request.files['video']
        tracking_data = json.loads(request.form.get('tracking_data'))
    
        temp_input = tempfile.NamedTemporaryFile(delete=False, suffix=".mp4")
        video_file.save(temp_input.name)
        
        heatmap_path = generate_heatmap(temp_input.name, tracking_data)
        os.unlink(temp_input.name)
        
        if heatmap_path:
            return send_file(heatmap_path, mimetype='video/mp4', download_name='heatmap.mp4')
        else:
            return jsonify({"status": "error", "message": "Failed to generate heatmap"}), 500
            
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == "__main__":
    # Initialize YOLO model on startup
    print("Initializing object detection model...")
    initialize_yolo_model()
    
    # Register the service with Bonjour
    zeroconf, service_info = register_service()
    
    try:
        print(f"Server starting on {get_local_ip()}:5555")
        app.run(host='0.0.0.0', port=5555, debug=True)
    finally:
        # Cleanup
        zeroconf.unregister_service(service_info)
        zeroconf.close()