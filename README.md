# Vision Pro Gaze & Object Tracking

An Apple Vision Pro project where you can track your gaze across videos and real-world environments, and detect objects in your surroundings. This project combines a visionOS app and a Python server to provide:

- ***Precision Test***: Measure how accurately users have set up their gaze.
- ***Clicking Speed Test***: Assess how quickly users can click, which will be used to retrieve gaze location for eye tracking.
- ***Eye Tracking***: Track gaze on videos and spatial environments to visualize where people have looked.
- ***Object Detection***: Detect and visualize objects in real time using YOLOv8l.
- ***Averaged Heatmap (Command Line)***: Generate an average heatmap video from multiple eye tracking sessions.

---

## Features

### Precision Test

A bullseye test where users focus their gaze on the center target and click to capture their accuracy. The average of 5 attempts determines the user's precision score, reflecting how accurately their gaze is calibrated on the Vision Pro.

### Clicking Speed Test
Clicking is required to access gaze data on the Vision Pro. The test measures how quickly users can click, which is essential for all eye tracking functionalities. Example clicking methods include:

- ***Hands***: The default Vision Pro gesture of pinching your index finger and thumb together to perform a click

- ***Dwell Control***: An accessibility feature that allows users to trigger clicks by simply looking at a point for a set amount of time, without any physical input. 
  - Enable from **Settings > Accessibility > Navigation > Dwell Control**
  - Adjust dwell time (e.g., 0.05s) for fastest response
  - Increase movement tolerance to the maximum for a broader range of gaze movement
  This enables fully gaze-driven interaction, making it possible to click just by looking, with no need for hand gestures or external devices.

- ***Bluetooth Gaming Controller***: Use a compatible controller (e.g., 8BitDo Pro 2) to trigger rapid clicking via a button press. This is especially useful for repeated or high-speed clicking. To set up the 8BitDo Pro 2 for turbo clicking on the Vision Pro:
  1. **Connect the controller to your computer via USB.**
  2. **Install the 8BitDo Ultimate software and configure:**
      - Remap the star button to "Turbo".
      - **(Optional) Remap any button for clicking:** By default, the A button is used for clicking on Apple Vision Pro. If you prefer, you can remap any other button to perform the same click functionality as the A button.
  3. **Save and sync the profile to the controller.**
  4. **Turn on the controller** by holding Start for 3 seconds.
  5. **Enter pairing mode** by pressing the pair button (next to the charging port) for 3 seconds.
  6. **Pair the controller with the Vision Pro** via Bluetooth settings on the Vision Pro.
  7. **Start turbo mode** by hold the clicking button (A by default, or whichever button you have assigned for clicking) and press the star button. Holding the clicking button will now trigger turbo clicking.
  8. **To turn turbo off** hold the clicking button and press the star button.
  9. **To turn off the controller** hold Start for 8 seconds.

Other click methods may also be used, however, using a controller is recommended because eye tracking will be more precise the more clicks there are.

### Video Eye Tracking
Tracks gaze while watching a video, with gaze points recorded each time the user clicks. After the video is over, the gaze data and the video are sent to the server, which generates a heatmap overlay on top of the video. Results include:
- ***Video***: The original video with a heatmap overlay showing gaze points.
- ***JSON***: A file containing detailed gaze data, including the video name, timestamp and coordinates for each gaze point, and user info.
Both the *video* and *JSON* are saved by default on your Mac, and are also sent to the Vision Pro where they are displayed and can be exported directly from the device.

### Spatial Eye Tracking
Tracks where the user is looking in their surrounding environment. To use this feature, the user must share their Vision Pro screen with the Mac using the screen sharing button on Vision Pro. The server records a video of the shared screen, and the Vision Pro records the eye tracking data. When the recording is stopped, the Vision Pro sends the gaze data to the server, which then generates a heatmap overlay on the recorded video. Results include:
- ***Video***: The recorded real-world view with a heatmap overlay showing gaze points.
- ***JSON***: A file containing detailed gaze data, including timestamp and coordinates for each gaze point, and user info.
Both the video and JSON are saved by default on your Mac, and are also sent to the Vision Pro where they are displayed and can be exported directly from the device.

### Object Detection
Detects and visualizes objects in real time from your Vision Pro using YOLOv8l. To use this feature, the user must share their Vision Pro screen with the Mac using the screen sharing button on the Vision Pro. The server records a video of the shared screen and runs object detection on each frame. When recording is stopped, results include:
- ***Video***: The recorded view with bounding boxes, object names, and confidence scores over each detected object, displayed in real time.
- ***JSON***: A file containing  user info, all unique objects detected in the video, each object's name, confidence score, bounding box location, and the timestamp of appearance in the video.
Both the video and JSON are saved by default on your Mac, and are also sent to the Vision Pro where they are displayed and can be exported directly from the device.

### Average Heatmap (Command Line)
Generate an average heatmap from a folder containing a video file and multiple JSON files with gaze data.
Results include:
- ***Video***: The original video with averaged heatmaps overlaid on each frame, showing the combined gaze data from all sessions.
- ***JSON***: A file including the name of the video, the count of the averaged JSON files, and the user info for each user whose data was included in the average.

## Requirements
- Apple Vision Pro device
- Mac to build the visionOS app and run the server
- Xcode
- Python 3.9+
- 8BitDo Pro 2 or similar controller (optional, for turbo clicking)

---

## Setup

### 1. Clone the Repository
```
git clone <repo-url>
cd AppleVisionPro
```

### 2. Setting Up the Vision Pro Device (only once)
- Install Xcode and open the project folder.
- Ensure Mac and Vision Pro are on the same Wi-Fi network.
- On the Vision Pro go to Settings > General > Remote Devices.
- In Xcode open Window > Devices and Simulators, select your device in the Discovered section in the Devices tab.
- Click Pair and enter the code shown on Vision Pro.
- On Vision Pro go to Settings > Privacy & Security > Developer Mode and toggle it on.
- In Xcode from the device list select your Vision Pro device and click the Play button to build/run the app.
- If you get a trust warning, on Vision Pro go to Settings > General > VPN & Device Management and trust the developer app.

---

### 3. Running the App
- **On Device:** In Xcode, select your Vision Pro device from the device list and click Play.
- **On Simulator:** In Xcode, select a Vision Pro simulator from the device list and click Play.

---

### 4. Running the Server
- Set up a virtual environment and install requirements (only once):
  ```
  make setup
  ```
- Start the server:
  ```
  make run
  ```
- Generate an average heatmap from a folder:
  ```
  make folder FOLDER=/path/to/folder
  ```