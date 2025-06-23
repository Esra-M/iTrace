# Vision Pro Heatmap Server

This project provides a Flask-based server and command-line tool for generating heatmaps and processing object detection data from Apple Vision Pro sessions. It supports video recording (with audio), object detection using YOLO, and heatmap overlay generation for user interaction analysis.

## Features
- Record video with audio from macOS using FFmpeg and AVFoundation
- Object detection using YOLOv8 (Ultralytics)
- Generate heatmap overlays on videos based on click or detection data
- Save session data and processed videos to a configurable output directory
- REST API endpoints for starting/stopping detection, recording, and generating heatmaps
- Zeroconf service registration for easy network discovery
- Command-line batch processing for folders of session data

## Requirements
- Python 3.8+
- macOS (uses AVFoundation for video/audio capture)
- FFmpeg and FFprobe installed and available in PATH

## Python Dependencies
See `requirements.txt` for all required packages. To set up a virtual environment and install dependencies, run:

```bash
make setup
```

This will create a `venv` directory and install all requirements inside it.

## Usage

### 1. Start the Server
```bash
make run
```
This will run the server inside the virtual environment. The server will start on port 5555 and register itself on the local network.

### 2. Process a Folder of Data
```bash
make folder FOLDER=/path/to/folder
```
This will process all JSON and video files in the folder to generate an averaged heatmap, using the virtual environment.

### 3. API Endpoints
- `POST /start_detection` — Start object detection
- `POST /stop_detection` — Stop detection and save video/session data
- `GET /get_detections` — Get current detections
- `POST /start_recording` — Start video/audio recording
- `POST /stop_recording` — Stop recording and generate heatmap
- `POST /generate_heatmap` — Upload a video and tracking data to generate a heatmap

### 4. Output
- All processed videos and session data are saved to `~/Desktop/Random` by default.

## Notes
- For object detection, YOLOv8 and the `yolov8l.pt` model file are required. Download from Ultralytics if not present.
- FFmpeg must be installed and accessible from the command line.
- The system is designed for macOS and may require adaptation for other platforms.

## License
MIT License
