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
import queue
import shutil

OUTPUT_DIR = os.path.expanduser("~/Desktop/Experiment")
current_recording_process = None
current_recording_filepath = None
detection_model = None
detection_active = False
detection_thread = None
latest_detections = []
detection_lock = threading.Lock()

# Video stream analysis variables
video_recording_process = None
video_recording_filepath = None
frame_queue = queue.Queue(maxsize=5)
analysis_thread = None

# Detection logging variables
detection_session_data = []
detection_session_lock = threading.Lock()
detection_start_time = None
detection_ready_time = None 
system_initialized = False


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

def initialize_yolo_model():
    """Initialize YOLO model for object detection"""
    global detection_model
    if YOLO_AVAILABLE and detection_model is None:
        try:
            detection_model = YOLO('yolov8l.pt')
            print("YOLO model initialized successfully")
            return True
        except Exception as e:
            print(f"Failed to initialize YOLO model: {e}")
            return False
    return YOLO_AVAILABLE

def start_video_recording_and_analysis():
    """Start single video recording that saves to file AND provides frames for analysis"""
    global video_recording_process, video_recording_filepath, frame_queue, detection_ready_time, system_initialized
    
    try:
        # Wait for system to be fully initialized before starting recording
        initialization_time = 8 # static 8 seconds (TODO - make this dynamic)
        print("Initializing detection system...")
        time.sleep(initialization_time)
        
        # Start recording 
        detection_ready_time = time.time()
        system_initialized = True
        print("Detection system ready - starting video recording")
        
        # Create filename for video recording
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        video_recording_filepath = os.path.join(tempfile.gettempdir(), f"object_detection_recording_{timestamp}.mp4")
        
        # FFmpeg process
        cmd = [
            'ffmpeg',
            '-f', 'avfoundation',
            '-i', '1',
            '-vf', 'crop=iw:ih*0.865:0:ih*0.085',
            
            # Output recording to file
            '-map', '0:v',
            '-vf', 'crop=iw:ih*0.865:0:ih*0.085,scale=1920:1080',
            '-r', '30',
            '-vcodec', 'libx264',
            '-preset', 'medium',
            '-crf', '18',
            '-pix_fmt', 'yuv420p',
            '-y', video_recording_filepath,
            
            # Output frames for analysis
            '-map', '0:v',
            '-vf', 'crop=iw:ih*0.865:0:ih*0.085,scale=1280:720',
            '-r', '5', 
            '-f', 'rawvideo',
            '-pix_fmt', 'bgr24',
            '-'
        ]
        
        video_recording_process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=10**8
        )
        
        print(f"Video recording started: {video_recording_filepath}")
        
        # Read frames from stdout for analysis
        frame_width, frame_height = 1280, 720
        frame_size = frame_width * frame_height * 3 
        
        while detection_active and video_recording_process:
            try:
                # Read one frame from stdout
                raw_frame = video_recording_process.stdout.read(frame_size)
                
                if len(raw_frame) != frame_size:
                    break
                
                # Convert raw bytes to numpy array
                frame = np.frombuffer(raw_frame, dtype=np.uint8)
                frame = frame.reshape((frame_height, frame_width, 3))
                
                # Add frame to queue for analysis 
                if not frame_queue.full():
                    frame_queue.put(frame)
                
            except Exception as e:
                print(f"Error reading analysis frame: {e}")
                break
                
    except Exception as e:
        print(f"Error starting video recording and analysis: {e}")

def stop_video_recording():
    """Stop video recording and return the saved file path"""
    global video_recording_process, video_recording_filepath
    
    if video_recording_process:
        try:
            video_recording_process.terminate()
            video_recording_process.wait(timeout=10)
            print("Video recording stopped")
            return video_recording_filepath
        except:
            video_recording_process.kill()
            return video_recording_filepath
        finally:
            video_recording_process = None
    
    return video_recording_filepath

def save_recorded_video_to_desktop(user_data):
    """Move the recorded video to desktop with proper naming"""
    global video_recording_filepath
    
    if not video_recording_filepath or not os.path.exists(video_recording_filepath):
        print("No recorded video file found")
        return None
    
    try:
        # Create output directory
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        
        # Generate filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        user_name = user_data.get('user_name', 'unknown_user').replace(' ', '_')
        video_filename = f"{user_name}_object_detection_{timestamp}.mp4"
        final_video_path = os.path.join(OUTPUT_DIR, video_filename)
        
        # Move the recorded video to the final location
        shutil.move(video_recording_filepath, final_video_path)
        
        print(f"Video saved to: {final_video_path}")
        return final_video_path
        
    except Exception as e:
        print(f"Error saving recorded video: {e}")
        return None

def detect_objects_in_frame(frame):
    """Detect objects in a single video frame using YOLO"""
    global detection_model, detection_session_data, detection_session_lock, detection_ready_time, system_initialized
    
    if not YOLO_AVAILABLE or detection_model is None or not system_initialized:
        return []
    
    try:
        # Run YOLO detection
        results = detection_model(frame, conf=0.25, iou=0.45, verbose=False)
        
        detections = []
        frame_h, frame_w = frame.shape[:2]
        current_time = time.time()
        
        # Calculate video timestamp 
        video_timestamp = current_time - detection_ready_time if detection_ready_time else 0
        
        for result in results:
            boxes = result.boxes
            if boxes is not None:
                for box in boxes:
                    # Get class name and confidence
                    class_id = int(box.cls[0])
                    class_name = detection_model.names[class_id]
                    confidence = float(box.conf[0])
                    
                    # Get bounding box coordinates in normalized coordinates
                    x_center, y_center, bbox_w, bbox_h = box.xywhn[0].tolist()
                    
                    # Convert center coordinates to top-left coordinates
                    screen_x = x_center - (bbox_w / 2)
                    screen_y = y_center - (bbox_h / 2)
                    
                    # Ensure bounding boxes are within bounds
                    screen_x = max(0.0, min(1.0, screen_x))
                    screen_y = max(0.0, min(1.0, screen_y))
                    bbox_w = max(0.0, min(1.0 - screen_x, bbox_w))
                    bbox_h = max(0.0, min(1.0 - screen_y, bbox_h))
                    
                    # Only include detections with reasonable size
                    min_size = 0.01 
                    if bbox_w >= min_size and bbox_h >= min_size:
                        detection_data = {
                            "name": class_name,
                            "confidence": confidence,
                            "bbox": {
                                "x": screen_x,
                                "y": screen_y,
                                "width": bbox_w,
                                "height": bbox_h
                            }
                        }
                        detections.append(detection_data)
                        
                        # Log detection session data for the json file
                        with detection_session_lock:
                            detection_session_data.append({
                                "object_name": class_name,
                                "confidence": confidence,
                                "timestamp": round(video_timestamp, 2),
                                "bounding_box": {
                                    "x": screen_x,
                                    "y": screen_y,
                                    "width": bbox_w,
                                    "height": bbox_h
                                }
                            })
        
        # Sort by confidence and return top detections
        detections.sort(key=lambda x: x['confidence'], reverse=True)
        return detections[:15]
        
    except Exception as e:
        print(f"Error in object detection: {e}")
        return []

def continuous_video_analysis():
    """Continuously analyze video frames for object detection"""
    global detection_active, latest_detections, detection_lock, frame_queue
    
    print("Starting continuous video analysis...")
    
    while detection_active:
        try:
            # Get the latest frame from queue
            if not frame_queue.empty():
                # Get the most recent frame, discard older ones
                frame = None
                while not frame_queue.empty():
                    frame = frame_queue.get()
                
                if frame is not None:
                    # Detect objects in the frame
                    detections = detect_objects_in_frame(frame)
                    
                    # Update latest detections
                    with detection_lock:
                        latest_detections = detections
                    
                    if system_initialized:
                        print(f"Video frame analysis: {len(detections)} objects found")
            else:
                # No frames available, wait a bit
                time.sleep(0.1)
                
        except Exception as e:
            print(f"Error in video analysis: {e}")
            time.sleep(1.0)

def get_unique_objects(detection_data):
    """Get unique object names from detection session data"""
    unique_objects = set()
    for detection in detection_data:
        unique_objects.add(detection["object_name"])
    return list(unique_objects)

def save_detection_session_data(user_data, video_path):
    """Save comprehensive detection session data"""
    global detection_session_data, detection_session_lock
    
    try:
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        
        # Get session data for the json file
        with detection_session_lock:
            session_detections = detection_session_data.copy()
        
        # Get unique objects
        unique_objects = get_unique_objects(session_detections)
        
        # Create simplified session data
        session_data = {
            "detection_type": "object_detection",
            "user_name": user_data.get('user_name', 'unknown_user'),
            "user_gender": user_data.get('user_gender', 'Unknown'),
            "user_age": user_data.get('user_age', 0),
            "timestamp": datetime.now().strftime("%Y%m%d_%H%M%S"),
            "unique_objects": unique_objects,
            "detected_objects": session_detections
        }
        
        # Save to JSON file 
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        user_name = user_data.get('user_name', 'unknown_user').replace(' ', '_')
        json_filename = f"{user_name}_object_detection_{timestamp}.json"
        json_path = os.path.join(OUTPUT_DIR, json_filename)
        
        with open(json_path, 'w') as f:
            json.dump(session_data, f, indent=2)
        
        print(f"Detection session data saved to: {json_path}")
        return json_path
        
    except Exception as e:
        print(f"Error saving detection session data: {e}")
        return None
    
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
        
        local_ip = get_local_ip()
        hostname = socket.gethostname()
        
        unique_id = str(uuid.uuid4())[:8]
        service_name = f"Vision Pro Server {unique_id}"
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

@app.route('/start_detection', methods=['POST'])
def start_detection():
    global detection_active, analysis_thread, frame_queue, detection_session_data, detection_start_time, detection_ready_time, system_initialized
    
    if not initialize_yolo_model():
        return jsonify({"status": "error", "message": "Object detection not available"}), 500
    
    if not detection_active:
        detection_active = True
        detection_start_time = time.time()
        detection_ready_time = None
        system_initialized = False
        
        # Clear detection session data
        with detection_session_lock:
            detection_session_data.clear()
        
        # Clear the frame queue
        while not frame_queue.empty():
            try:
                frame_queue.get_nowait()
            except:
                break
        
        # Start single process for recording and analysis
        recording_thread = threading.Thread(target=start_video_recording_and_analysis, daemon=True)
        recording_thread.start()
        
        # Start video analysis thread
        analysis_thread = threading.Thread(target=continuous_video_analysis, daemon=True)
        analysis_thread.start()
        
        print("Detection initialization started")
    
    return jsonify({"status": "success", "message": "Detection started"})


@app.route('/stop_detection', methods=['POST'])
def stop_detection():
    global detection_active, latest_detections, detection_lock, detection_start_time, detection_ready_time, system_initialized
    
    detection_active = False
    system_initialized = False
    
    # Stop video recording process
    recorded_video_path = stop_video_recording()
    
    # Clear live detections
    with detection_lock:
        latest_detections = []
    
    # Clear frame queue
    while not frame_queue.empty():
        try:
            frame_queue.get_nowait()
        except:
            break
    
    # Get user data from request
    try:
        data = request.get_json()
        tracking_data = data.get('tracking_data', {})
        return_video = data.get('return_video', False)
    except:
        tracking_data = {}
        return_video = False
    
    # Always save the recorded video to desktop first
    saved_video_path = save_recorded_video_to_desktop(tracking_data)
    
    # Save detection session data
    session_json_path = save_detection_session_data(tracking_data, saved_video_path)
    
    print("Video recording and analysis stopped")
    
    # If return_video is True, return the video file directly
    if return_video and saved_video_path and os.path.exists(saved_video_path):
        # Read session data to include in response headers
        session_data = {}
        if session_json_path and os.path.exists(session_json_path):
            try:
                with open(session_json_path, 'r') as f:
                    session_data = json.load(f)
            except:
                pass
        
        # Create a response with the video file
        response = send_file(
            saved_video_path, 
            mimetype='video/mp4', 
            download_name='object_detection_video.mp4'
        )
        
        # Add session data as a custom header
        if session_data:
            response.headers['X-Session-Data'] = json.dumps(session_data)
        
        return response
    else:
        #return paths in JSON
        response_data = {
            "status": "success", 
            "message": "Detection stopped and video saved"
        }
        
        if saved_video_path:
            response_data["video_path"] = saved_video_path
            response_data["video_filename"] = os.path.basename(saved_video_path)
        
        if session_json_path:
            response_data["session_data_path"] = session_json_path
        
        # Reset session variables
        detection_start_time = None
        detection_ready_time = None
        
        return jsonify(response_data)

def save_detection_session_data(user_data, video_path):
    """Save comprehensive detection session data"""
    global detection_session_data, detection_session_lock
    
    try:
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        
        # Get session data
        with detection_session_lock:
            session_detections = detection_session_data.copy()
        
        # Get unique objects
        unique_objects = get_unique_objects(session_detections)
        
        # Create simplified session data
        session_data = {
            "tracking_type": "object_detection",
            "user_name": user_data.get('user_name', 'unknown_user'),
            "user_gender": user_data.get('user_gender', 'Unknown'),
            "user_age": user_data.get('user_age', 0),
            "timestamp": datetime.now().strftime("%Y%m%d_%H%M%S"),
            "unique_objects": unique_objects,
            "detected_objects": session_detections
        }
        
        # Save to JSON file
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        user_name = user_data.get('user_name', 'unknown_user').replace(' ', '_')
        json_filename = f"{user_name}_object_detection_{timestamp}.json"
        json_path = os.path.join(OUTPUT_DIR, json_filename)
        
        with open(json_path, 'w') as f:
            json.dump(session_data, f, indent=2)
        
        print(f"Detection session data saved to: {json_path}")
        return json_path
        
    except Exception as e:
        print(f"Error saving detection session data: {e}")
        return None
    
@app.route('/get_detections', methods=['GET'])
def get_detections():
    """Get the latest detections from video analysis"""
    global latest_detections, detection_lock
    
    if not detection_active:
        return jsonify({"status": "error", "message": "Detection not active"}), 400
    
    with detection_lock:
        detections = latest_detections.copy()
    
    return jsonify({
        "status": "success",
        "detections": detections,
        "timestamp": time.time()
    })

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
    initialize_yolo_model()
    
    zeroconf, service_info = register_service()
    
    try:
        print(f"Server starting on {get_local_ip()}:5555")
        app.run(host='0.0.0.0', port=5555, debug=True)
    finally:
        if zeroconf and service_info:
            zeroconf.unregister_service(service_info)
            zeroconf.close()