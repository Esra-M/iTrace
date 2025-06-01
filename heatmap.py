import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from flask import Flask, request, send_file, jsonify
from flask_cors import CORS
from io import BytesIO
from scipy.ndimage import gaussian_filter
import cv2
import tempfile
import os
import json
import subprocess
import time
from datetime import datetime
import threading

app = Flask(__name__)
CORS(app)

# Global variables
current_recording_process = None
current_recording_filepath = None
OUTPUT_DIR = os.path.expanduser("~/Desktop/HeatmapRecordings")

@app.route('/start_recording', methods=['POST'])
def start_recording():
    global current_recording_process, current_recording_filepath
    
    try:
        # Start screen recording
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        current_recording_filepath = os.path.join(tempfile.gettempdir(), f"temp_recording_{timestamp}.mp4")
        
        def start_recording_thread():
            global current_recording_process
            cmd = ['ffmpeg', '-f', 'avfoundation', '-i', '1', '-r', '20', '-vf', 'scale=1280:720',
                  '-vcodec', 'libx264', '-preset', 'veryfast', '-crf', '25', '-pix_fmt', 'yuv420p',
                  '-y', current_recording_filepath]
            current_recording_process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        
        threading.Thread(target=start_recording_thread).start()
        return jsonify({"status": "success", "message": "Recording started"})
        
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/stop_recording', methods=['POST'])
def stop_recording():
    global current_recording_process, current_recording_filepath
    
    try:
        data = request.get_json()
        click_data = data.get('click_data', [])
        frame_width = data.get('frame_width', 1920)
        frame_height = data.get('frame_height', 1080)
        
        # Stop recording
        if current_recording_process:
            current_recording_process.terminate()
            current_recording_process.wait()
            current_recording_process = None
            time.sleep(2)
            
            if current_recording_filepath and os.path.exists(current_recording_filepath):
                # Generate heatmap
                heatmap_filepath = generate_heatmap(current_recording_filepath, click_data, frame_width, frame_height)
                os.unlink(current_recording_filepath)
                
                # Return heatmap video
                if heatmap_filepath:
                    return send_file(heatmap_filepath, mimetype='video/mp4', download_name='heatmap.mp4')
                else:
                    return jsonify({"status": "error", "message": "Failed to generate heatmap"}), 500
            else:
                return jsonify({"status": "error", "message": "Recording file not found"}), 500
        else:
            return jsonify({"status": "error", "message": "No active recording"}), 400
            
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/generate_heatmap', methods=['POST'])
def generate_heatmap():
    try:
        # Get uploaded video and parameters
        video_file = request.files['video']
        clicks = json.loads(request.form.get('clicks'))
        width = int(request.form.get('width'))
        height = int(request.form.get('height'))

        # Save uploaded video temporarily
        temp_input = tempfile.NamedTemporaryFile(delete=False, suffix=".mp4")
        video_file.save(temp_input.name)
        
        # Generate heatmap
        heatmap_filepath = generate_heatmap(temp_input.name, clicks, width, height)
        os.unlink(temp_input.name)
        
        # Return heatmap video
        if heatmap_filepath:
            return send_file(heatmap_filepath, mimetype='video/mp4', download_name='heatmap.mp4')
        else:
            return jsonify({"status": "error", "message": "Failed to generate heatmap"}), 500
            
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

def generate_heatmap(video_path, click_data, original_width, original_height):
    try:
        # Setup output file
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        heatmap_filepath = os.path.join(OUTPUT_DIR, f"heatmap_{timestamp}.mp4")
        
        # Open video
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            return None
        
        # Get video properties
        fps = cap.get(cv2.CAP_PROP_FPS)
        v_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        v_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        
        # Setup video writer
        out = cv2.VideoWriter(heatmap_filepath, cv2.VideoWriter_fourcc(*'mp4v'), fps, (v_width, v_height))
        
        # Process clicks into frame intervals
        fade_duration = int(fps * 0.3)
        dot_intervals = {}
        
        for click in click_data:
            # Scale click coordinates to video dimensions
            x = int(float(click["x"]) * v_width / original_width)
            y = v_height - 1 - int(float(click["y"]) * v_height / original_height)
            x = min(max(x, 0), v_width - 1)
            y = min(max(y, 0), v_height - 1)
            
            # Calculate frame range for this click
            start_frame = max(0, int((click["timestamp"] * fps) - fade_duration))
            end_frame = start_frame + fade_duration * 2
            
            if (x, y) not in dot_intervals:
                dot_intervals[(x, y)] = []
            dot_intervals[(x, y)].append((start_frame, end_frame))
        
        # Pre-calculate brightness for each frame
        brightness_per_frame = np.zeros((frame_count, v_height, v_width), dtype=np.float32)
        
        for (x, y), intervals in dot_intervals.items():
            for (start, end) in intervals:
                for f in range(start, min(end + 1, frame_count)):
                    # Calculate fade effect
                    if f < start + fade_duration:
                        brightness = (f - start) / fade_duration
                    elif f > end - fade_duration:
                        brightness = (end - f) / fade_duration
                    else:
                        brightness = 1.0
                    brightness_per_frame[f, y, x] = max(brightness_per_frame[f, y, x], brightness)
        
        # Process each frame
        for i in range(frame_count):
            ret, frame = cap.read()
            if not ret:
                break
            
            # Darken frame
            frame = cv2.addWeighted(frame, 0.5, np.zeros_like(frame), 0.5, 0)
            
            # Add heatmap if there are clicks
            if np.sum(brightness_per_frame[i]) > 0:
                blurred = gaussian_filter(brightness_per_frame[i], sigma=40)
                
                # Create heatmap overlay
                fig, ax = plt.subplots(figsize=(v_width / 100, v_height / 100), dpi=100)
                ax.imshow(blurred, cmap='inferno', interpolation='bicubic', origin='lower',
                         extent=[0, v_width, 0, v_height], aspect='auto')
                ax.axis('off')
                plt.tight_layout(pad=0)
                
                # Convert to image
                buf = BytesIO()
                plt.savefig(buf, format='png', bbox_inches='tight', pad_inches=0)
                plt.close(fig)
                buf.seek(0)
                
                heatmap = cv2.imdecode(np.frombuffer(buf.getvalue(), dtype=np.uint8), 1)
                heatmap = cv2.resize(heatmap, (v_width, v_height))
                frame = cv2.addWeighted(frame, 1.0, heatmap, 0.8, 0)
            
            out.write(frame)
        
        # Add final static heatmap frame showing all clicks
        final_grid = np.zeros((v_height, v_width))
        for (x, y), intervals in dot_intervals.items():
            if 0 <= x < v_width and 0 <= y < v_height:
                final_grid[y, x] += 1
        
        if np.sum(final_grid) > 0:
            blurred = gaussian_filter(final_grid, sigma=40)
            fig, ax = plt.subplots(figsize=(v_width / 100, v_height / 100), dpi=100)
            ax.imshow(blurred, cmap='inferno', interpolation='bicubic', origin='lower',
                     extent=[0, v_width, 0, v_height], aspect='auto')
            ax.axis('off')
            plt.tight_layout(pad=0)
            buf = BytesIO()
            plt.savefig(buf, format='png', bbox_inches='tight', pad_inches=0)
            plt.close(fig)
            buf.seek(0)
            heatmap = cv2.imdecode(np.frombuffer(buf.getvalue(), dtype=np.uint8), 1)
            heatmap = cv2.resize(heatmap, (v_width, v_height))
            black = np.zeros((v_height, v_width, 3), dtype=np.uint8)
            final_frame = cv2.addWeighted(black, 1.0, heatmap, 1.0, 0)
            out.write(final_frame)
        
        cap.release()
        out.release()
        return heatmap_filepath
        
    except Exception as e:
        print(f"Error generating heatmap: {e}")
        return None

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5050, debug=True)