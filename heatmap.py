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
import queue
import shutil

# Configuration
OUTPUT_DIR = os.path.expanduser("~/Desktop/Random")

# Global state
app = Flask(__name__)
CORS(app)

class ObjectDetectionSystem:
    def __init__(self):
        self.recording_process = None
        self.recording_filepath = None
        self.detection_model = None
        self.detection_active = False
        self.frame_queue = queue.Queue(maxsize=5)
        self.analysis_thread = None
        self.latest_detections = []
        self.detection_lock = threading.Lock()
        self.session_data = []
        self.session_lock = threading.Lock()
        self.start_time = None
        self.ready_time = None
        self.system_initialized = False
        
        self._initialize_yolo()
    
    def _initialize_yolo(self):
        """Initialize YOLO model for object detection"""
        try:
            import torch
            from ultralytics import YOLO
            self.detection_model = YOLO('yolov8l.pt')
            print("YOLO model initialized successfully")
            return True
        except ImportError:
            print("YOLO not available. Install ultralytics: pip install ultralytics")
            return False
        except Exception as e:
            print(f"Failed to initialize YOLO model: {e}")
            return False
    
    def start_detection(self):
        """Start object detection system"""
        if self.detection_active:
            return True
        
        if self.detection_model is None:
            return False
        
        self.detection_active = True
        self.start_time = time.time()
        self.system_initialized = False
        
        # Clear previous data
        with self.session_lock:
            self.session_data.clear()
        self._clear_frame_queue()
        
        # Start recording and analysis
        recording_thread = threading.Thread(target=self._record_and_analyze, daemon=True)
        recording_thread.start()
        
        self.analysis_thread = threading.Thread(target=self._analyze_frames, daemon=True)
        self.analysis_thread.start()
        
        return True
    
    def stop_detection(self):
        """Stop object detection and return video path"""
        self.detection_active = False
        self.system_initialized = False
        
        # Stop recording
        video_path = self._stop_recording()
        
        # Clear state
        with self.detection_lock:
            self.latest_detections = []
        self._clear_frame_queue()
        
        return video_path
    
    def get_detections(self):
        """Get current detections"""
        with self.detection_lock:
            return self.latest_detections.copy()
    
    def get_session_data(self):
        """Get complete session data"""
        with self.session_lock:
            return self.session_data.copy()
    
    def _record_and_analyze(self):
        """Record video and provide frames for analysis"""
        try:
            # Wait for initialization
            time.sleep(8)  # Static 8 seconds
            
            self.ready_time = time.time()
            self.system_initialized = True
            print("Detection system ready - starting video recording")
            
            # Create recording file
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            self.recording_filepath = os.path.join(tempfile.gettempdir(), f"object_detection_{timestamp}.mp4")
            
            # FFmpeg command for recording and frame extraction
            cmd = [
                'ffmpeg',
                '-f', 'avfoundation',
                '-i', '1',
                '-vf', 'crop=iw:ih*0.865:0:ih*0.085',
                
                # Save to file
                '-map', '0:v',
                '-vf', 'crop=iw:ih*0.865:0:ih*0.085,scale=1920:1080',
                '-r', '30',
                '-vcodec', 'libx264',
                '-preset', 'medium',
                '-crf', '18',
                '-pix_fmt', 'yuv420p',
                '-y', self.recording_filepath,
                
                # Extract frames for analysis
                '-map', '0:v',
                '-vf', 'crop=iw:ih*0.865:0:ih*0.085,scale=1280:720',
                '-r', '5',
                '-f', 'rawvideo',
                '-pix_fmt', 'bgr24',
                '-'
            ]
            
            self.recording_process = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=10**8
            )
            
            # Read frames for analysis
            frame_size = 1280 * 720 * 3
            while self.detection_active and self.recording_process:
                try:
                    raw_frame = self.recording_process.stdout.read(frame_size)
                    if len(raw_frame) != frame_size:
                        break
                    
                    frame = np.frombuffer(raw_frame, dtype=np.uint8).reshape((720, 1280, 3))
                    
                    if not self.frame_queue.full():
                        self.frame_queue.put(frame)
                        
                except Exception as e:
                    print(f"Error reading frame: {e}")
                    break
                    
        except Exception as e:
            print(f"Error in recording: {e}")
    
    def _analyze_frames(self):
        """Analyze frames for object detection"""
        while self.detection_active:
            try:
                if not self.frame_queue.empty():
                    # Get latest frame
                    frame = None
                    while not self.frame_queue.empty():
                        frame = self.frame_queue.get()
                    
                    if frame is not None and self.system_initialized:
                        detections = self._detect_objects(frame)
                        with self.detection_lock:
                            self.latest_detections = detections
                else:
                    time.sleep(0.1)
                    
            except Exception as e:
                print(f"Error in analysis: {e}")
                time.sleep(1.0)
    
    def _detect_objects(self, frame):
        """Detect objects in frame using YOLO"""
        if self.detection_model is None or not self.system_initialized:
            return []
        
        try:
            results = self.detection_model(frame, conf=0.5, iou=0.45, verbose=False)
            detections = []
            current_time = time.time()
            video_timestamp = current_time - self.ready_time if self.ready_time else 0
            
            for result in results:
                boxes = result.boxes
                if boxes is not None:
                    for box in boxes:
                        class_id = int(box.cls[0])
                        class_name = self.detection_model.names[class_id]
                        confidence = float(box.conf[0])
                        
                        # Get normalized coordinates
                        x_center, y_center, bbox_w, bbox_h = box.xywhn[0].tolist()
                        screen_x = max(0.0, min(1.0, x_center - bbox_w / 2))
                        screen_y = max(0.0, min(1.0, y_center - bbox_h / 2))
                        bbox_w = max(0.0, min(1.0 - screen_x, bbox_w))
                        bbox_h = max(0.0, min(1.0 - screen_y, bbox_h))
                        
                        if bbox_w >= 0.01 and bbox_h >= 0.01:  # Minimum size filter
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
                            
                            # Log to session data
                            with self.session_lock:
                                self.session_data.append({
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
            
            return sorted(detections, key=lambda x: x['confidence'], reverse=True)[:15]
            
        except Exception as e:
            print(f"Error in object detection: {e}")
            return []
    
    def _stop_recording(self):
        """Stop recording and return video path"""
        if self.recording_process:
            try:
                self.recording_process.terminate()
                self.recording_process.wait(timeout=10)
            except:
                self.recording_process.kill()
            finally:
                self.recording_process = None
        
        return self.recording_filepath
    
    def _clear_frame_queue(self):
        """Clear frame queue"""
        while not self.frame_queue.empty():
            try:
                self.frame_queue.get_nowait()
            except:
                break
    
    def save_session_data(self, user_data, video_path):
        """Save session data to JSON file"""
        try:
            os.makedirs(OUTPUT_DIR, exist_ok=True)
            
            session_detections = self.get_session_data()
            unique_objects = list(set(d["object_name"] for d in session_detections))
            
            session_data = {
                "tracking_type": "object_detection",
                "user_name": user_data.get('user_name', 'unknown_user'),
                "user_gender": user_data.get('user_gender', 'Unknown'),
                "user_age": user_data.get('user_age', 0),
                "timestamp": datetime.now().strftime("%Y%m%d_%H%M%S"),
                "unique_objects": unique_objects,
                "detected_objects": session_detections
            }
            
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            user_name = user_data.get('user_name', 'unknown_user').replace(' ', '_')
            json_filename = f"{user_name}_object_detection_{timestamp}.json"
            json_path = os.path.join(OUTPUT_DIR, json_filename)
            
            with open(json_path, 'w') as f:
                json.dump(session_data, f, indent=2)
            
            print(f"Session data saved: {json_path}")
            return json_path
            
        except Exception as e:
            print(f"Error saving session data: {e}")
            return None
    
    def save_video_to_desktop(self, user_data):
        """Save recorded video to desktop"""
        if not self.recording_filepath or not os.path.exists(self.recording_filepath):
            return None
        
        try:
            os.makedirs(OUTPUT_DIR, exist_ok=True)
            
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            user_name = user_data.get('user_name', 'unknown_user').replace(' ', '_')
            video_filename = f"{user_name}_object_detection_{timestamp}.mp4"
            final_path = os.path.join(OUTPUT_DIR, video_filename)
            
            shutil.move(self.recording_filepath, final_path)
            print(f"Video saved: {final_path}")
            return final_path
            
        except Exception as e:
            print(f"Error saving video: {e}")
            return None

# Global detection system instance
detection_system = ObjectDetectionSystem()

def reduce_video_quality(input_path, max_width=1280, max_height=720, crf=28):
    try:
        cap = cv2.VideoCapture(input_path)
        w, h = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        cap.release()
        
        scale = min(min(max_width / w, max_height / h), 1.0)
        new_w, new_h = int(w * scale) & ~1, int(h * scale) & ~1
        
        if scale >= 0.95: 
            return input_path, 1.0, 1.0
        
        reduced_path = input_path.replace('.mp4', '_reduced.mp4')
        cmd = ['ffmpeg', '-i', input_path, '-vf', f'scale={new_w}:{new_h}',
               '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', str(crf), '-an', '-y', reduced_path]
        
        if subprocess.run(cmd, capture_output=True).returncode == 0:
            return reduced_path, new_w / w, new_h / h
        return input_path, 1.0, 1.0
    except:
        return input_path, 1.0, 1.0

def create_heatmap_overlay(brightness_grid, video_width, video_height, base_sigma=40, base_resolution=1920):
    if np.sum(brightness_grid) == 0: 
        return None
    
    resolution_scale = video_width / base_resolution
    scaled_sigma = max(base_sigma * resolution_scale, 5.0)
    
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
        if not cap.isOpened(): 
            return None
        
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
        
        # Add final heatmap frame
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
            try: 
                os.unlink(reduced_path)
            except: 
                pass
        
        print("Heatmap generation completed")
        return output_path
        
    except Exception as e:
        print(f"Error generating heatmap: {e}")
        return None


def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"

def register_service():
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
        print(f"Failed to register service: {e}")
        return None, None


@app.route('/start_detection', methods=['POST'])
def start_detection():
    if detection_system.start_detection():
        return jsonify({"status": "success", "message": "Detection started"})
    else:
        return jsonify({"status": "error", "message": "Object detection not available"}), 500

@app.route('/stop_detection', methods=['POST'])
def stop_detection():
    # Stop detection system
    recorded_video_path = detection_system.stop_detection()
    
    # Get request data
    try:
        data = request.get_json()
        tracking_data = data.get('tracking_data', {})
        return_video = data.get('return_video', False)
    except:
        tracking_data = {}
        return_video = False
    
    # Save video and session data
    saved_video_path = detection_system.save_video_to_desktop(tracking_data)
    session_json_path = detection_system.save_session_data(tracking_data, saved_video_path)
    
    if return_video and saved_video_path and os.path.exists(saved_video_path):
        # Return video file with session data in headers
        session_data = {}
        if session_json_path and os.path.exists(session_json_path):
            try:
                with open(session_json_path, 'r') as f:
                    session_data = json.load(f)
            except:
                pass
        
        response = send_file(saved_video_path, mimetype='video/mp4', download_name='object_detection_video.mp4')
        
        if session_data:
            response.headers['X-Session-Data'] = json.dumps(session_data)
        
        return response
    else:
        return jsonify({
            "status": "success",
            "message": "Detection stopped and video saved",
            "video_path": saved_video_path,
            "session_data_path": session_json_path
        })

@app.route('/get_detections', methods=['GET'])
def get_detections():
    if not detection_system.detection_active:
        return jsonify({"status": "error", "message": "Detection not active"}), 400
    
    detections = detection_system.get_detections()
    return jsonify({
        "status": "success",
        "detections": detections,
        "timestamp": time.time()
    })

current_recording_process = None
current_recording_filepath = None

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
    zeroconf, service_info = register_service()
    
    try:
        print(f"Server starting on {get_local_ip()}:5555")
        app.run(host='0.0.0.0', port=5555, debug=True)
    finally:
        if zeroconf and service_info:
            zeroconf.unregister_service(service_info)
            zeroconf.close()