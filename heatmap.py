import matplotlib
matplotlib.use('Agg')  # Non-GUI backend

import matplotlib.pyplot as plt
import numpy as np
from flask import Flask, request, send_file
from io import BytesIO
from scipy.ndimage import gaussian_filter
import cv2
import tempfile
import os
import json

app = Flask(__name__)

@app.route('/generate_heatmap_video', methods=['POST'])
def generate_heatmap_video():
    video_file = request.files['video']
    clicks_json = request.form.get('clicks')
    clicks = json.loads(clicks_json)
    width = int(request.form.get('width'))
    height = int(request.form.get('height'))

    # Decode video
    temp_input = tempfile.NamedTemporaryFile(delete=False, suffix=".mp4")
    video_file.save(temp_input.name)
    cap = cv2.VideoCapture(temp_input.name)
    fps = cap.get(cv2.CAP_PROP_FPS)
    v_width, v_height = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    # Prepare output video
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix=".mp4")
    out = cv2.VideoWriter(temp_output.name, cv2.VideoWriter_fourcc(*'mp4v'), fps, (v_width, v_height))

    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = frame_count / fps

    fade_duration = int(fps * 0.3)
    visible_duration = int(fps * 0.5)
    total_duration = fade_duration * 2 + max(1, visible_duration - 2 * fade_duration)

    # Track dot appearance with fade
    dot_intervals = {}

    for click in clicks:
        x = int(click["x"])
        y = int(click["y"])
        y = v_height - 1 - y
        x = min(max(x, 0), v_width - 1)
        y = min(max(y, 0), v_height - 1)
        start_frame = max(0, int((click["timestamp"] * fps) - fade_duration))
        end_frame = start_frame + total_duration - 1

        if (x, y) not in dot_intervals:
            dot_intervals[(x, y)] = []
        dot_intervals[(x, y)].append((start_frame, end_frame))

    def merge_intervals(intervals):
        intervals.sort()
        merged = []
        for current in intervals:
            if not merged:
                merged.append(current)
            else:
                prev = merged[-1]
                if current[0] <= prev[1] + 1:
                    merged[-1] = (prev[0], max(prev[1], current[1]))
                else:
                    merged.append(current)
        return merged

    for key in dot_intervals:
        dot_intervals[key] = merge_intervals(dot_intervals[key])

    # Size of dots
    DOT_SIGMA = 40

    brightness_per_frame = np.zeros((frame_count, v_height, v_width), dtype=np.float32)

    for (x, y), intervals in dot_intervals.items():
        for (start, end) in intervals:
            for f in range(start, end + 1):
                if f >= frame_count:
                    break
                # Compute brightness fade-in/out
                if f < start + fade_duration:
                    brightness = (f - start) / fade_duration
                elif f > end - fade_duration:
                    brightness = (end - f) / fade_duration
                else:
                    brightness = 1.0
                brightness = max(0.0, min(1.0, brightness))
                brightness_per_frame[f, y, x] = max(brightness_per_frame[f, y, x], brightness)

    for i in range(frame_count):
        ret, frame = cap.read()
        if not ret:
            break

        black_layer = np.zeros_like(frame, dtype=np.uint8)
        frame = cv2.addWeighted(frame, 0.5, black_layer, 0.5, 0)

        click_grid = brightness_per_frame[i]
        if np.sum(click_grid) > 0:
            blurred = gaussian_filter(click_grid, sigma=DOT_SIGMA)
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

            frame = cv2.addWeighted(frame, 1.0, heatmap, 0.8, 0)

        out.write(frame)

    # Final full heatmap
    final_grid = np.zeros((v_height, v_width))
    for (x, y), intervals in dot_intervals.items():
        for (start, end) in intervals:
            if 0 <= x < v_width and 0 <= y < v_height:
                final_grid[y, x] += 1

    blurred = gaussian_filter(final_grid, sigma=DOT_SIGMA)
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

    for _ in range(int(fps)):
        out.write(final_frame)

    cap.release()
    out.release()
    os.unlink(temp_input.name)

    return send_file(temp_output.name, mimetype='video/mp4')

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5050, debug=True)