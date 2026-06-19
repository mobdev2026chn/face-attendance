import sys
import json
import base64
import numpy as np
import cv2
import os

# Dynamically ensure local face_recognition package is findable if running nested
sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'integrated-face-attendance', 'face-attendance-system'))

# Set up local paths and optional anti-spoofing (liveness detection)
anti_spoof_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'integrated-face-attendance', 'face-attendance-system', 'Silent-Face-Anti-Spoofing'))
if os.path.isdir(anti_spoof_path):
    sys.path.insert(0, anti_spoof_path)

try:
    from test import test as test_fn
    HAS_ANTI_SPOOFING = True
except Exception as e:
    HAS_ANTI_SPOOFING = False

try:
    import face_recognition
except ImportError:
    import face_recognition

def main():
    try:
        # Read base64 image data from stdin
        input_data = sys.stdin.read().strip()
        if not input_data:
            print(json.dumps({"error": "No image data received from Node.js."}))
            return

        # Handle base64 padding or prefixes (e.g. data:image/jpeg;base64,...)
        if ',' in input_data:
            input_data = input_data.split(',')[1]
            
        img_bytes = base64.b64decode(input_data)
        nparr = np.frombuffer(img_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if img is None:
            print(json.dumps({"error": "Failed to decode camera frame bytes."}))
            return

        # Resize image to standard size (e.g. max width 640px) to optimize processing speed!
        h, w, _ = img.shape
        max_w = 640
        if w > max_w:
            scale = max_w / w
            img = cv2.resize(img, (0, 0), fx=scale, fy=scale)

        # 1. Face Locations Detection
        face_locations = face_recognition.face_locations(img)
        if len(face_locations) == 0:
            print(json.dumps({"error": "No face detected in feed. Please align your face inside the guide."}))
            return
        elif len(face_locations) > 1:
            print(json.dumps({"error": "Multiple faces detected! Only one person is allowed."}))
            return

        # 2. Strict Position & Proximity Checks
        top, right, bottom, left = face_locations[0]
        face_width = right - left
        face_height = bottom - top
        face_center_x = left + face_width // 2
        face_center_y = top + face_height // 2

        target_center_x = img.shape[1] // 2
        target_center_y = img.shape[0] // 2

        # Verify centering - Made highly lenient (280px) for robust mobile captures
        if abs(face_center_x - target_center_x) > 280:
            print(json.dumps({"error": "Face off-center horizontally. Align with guide."}))
            return
        if abs(face_center_y - target_center_y) > 280:
            print(json.dumps({"error": "Face off-center vertically. Align with guide."}))
            return

        # Verify size/proximity bounds
        if face_width < 120:
            print(json.dumps({"error": "You are too far. Please move closer."}))
            return
        elif face_width > 340:
            print(json.dumps({"error": "You are too close. Step back slightly."}))
            return

        # 3. Symmetry Frontal Posture Checks
        landmarks_list = face_recognition.face_landmarks(img, face_locations)
        if landmarks_list:
            landmarks = landmarks_list[0]
            nose_bridge_pts = landmarks.get('nose_bridge', [])
            nose_x = sum([pt[0] for pt in nose_bridge_pts]) / len(nose_bridge_pts) if nose_bridge_pts else face_center_x

            left_eye_pts = landmarks.get('left_eye', [])
            right_eye_pts = landmarks.get('right_eye', [])
            
            if left_eye_pts and right_eye_pts:
                left_eye_x = sum([pt[0] for pt in left_eye_pts]) / len(left_eye_pts)
                right_eye_x = sum([pt[0] for pt in right_eye_pts]) / len(right_eye_pts)
                
                dist_left = nose_x - left_eye_x
                dist_right = right_eye_x - nose_x
                total_dist = dist_left + dist_right
                
                if total_dist > 0:
                    ratio = dist_left / total_dist
                    if ratio < 0.36 or ratio > 0.64:
                        print(json.dumps({"error": "Look straight at the camera. Side angles are not allowed."}))
                        return

        # 3.5. Anti-Spoofing (Liveness Check)
        if HAS_ANTI_SPOOFING:
            try:
                model_dir = os.path.join(anti_spoof_path, 'resources', 'anti_spoof_models')
                label = test_fn(img, model_dir, 0)
                if label != 1:
                    print(json.dumps({"error": "Spoof Alert! Digital screens or printed photos are not allowed."}))
                    return
            except Exception as ase:
                print(json.dumps({"error": f"Liveness check error: {str(ase)}"}))
                return

        # 4. Generate Face Descriptor Vector (Fast & Highly Accurate!)
        encodings = face_recognition.face_encodings(img, face_locations)
        if len(encodings) == 0:
            print(json.dumps({"error": "Could not extract face biometrics. Please try again."}))
            return

        encoding = encodings[0].tolist()
        print(json.dumps({"embedding": encoding}))

    except Exception as e:
        print(json.dumps({"error": f"Internal biometric extraction crash: {str(e)}"}))

if __name__ == '__main__':
    main()
