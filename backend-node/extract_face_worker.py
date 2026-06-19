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

# Speed knobs (default OFF = fast ~1s). Re-enable per deployment via env if needed:
#   FACE_FRONTAL_CHECK=1  -> require frontal pose (extra landmarks pass)
#   FACE_LIVENESS=1       -> run anti-spoofing model (slow)
FRONTAL_CHECK = os.environ.get('FACE_FRONTAL_CHECK', '0') == '1'
LIVENESS_CHECK = os.environ.get('FACE_LIVENESS', '0') == '1'

def _decode_b64_image(input_data):
    if ',' in input_data:
        input_data = input_data.split(',')[1]
    img_bytes = base64.b64decode(input_data)
    nparr = np.frombuffer(img_bytes, np.uint8)
    return cv2.imdecode(nparr, cv2.IMREAD_COLOR)


def _rotate(img, angle):
    if angle == 0:
        return img
    if angle == 90:
        return cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE)
    if angle == 180:
        return cv2.rotate(img, cv2.ROTATE_180)
    if angle == 270:
        return cv2.rotate(img, cv2.ROTATE_90_COUNTERCLOCKWISE)
    return img


def enroll_image(input_data):
    """Lenient enrollment from a STORED photo (avatar / punch selfie). Skips the
    kiosk-only guards (centering/proximity/frontal/liveness) and retries rotations
    to handle EHRMS selfies stored upside-down/sideways. Returns the largest face."""
    try:
        img = _decode_b64_image(input_data)
        if img is None:
            return {"error": "Failed to decode image bytes."}

        # Normalize size for the detector.
        h, w = img.shape[:2]
        max_w = 640
        if w > max_w:
            scale = max_w / w
            img = cv2.resize(img, (0, 0), fx=scale, fy=scale)

        for angle in (0, 180, 90, 270):
            rimg = _rotate(img, angle)
            locs = face_recognition.face_locations(rimg)
            if not locs:
                continue
            # Largest detected face.
            loc = max(locs, key=lambda l: (l[2] - l[0]) * (l[1] - l[3]))
            encs = face_recognition.face_encodings(rimg, [loc], num_jitters=1)
            if encs:
                return {"embedding": encs[0].tolist(), "rotation": angle}
        return {"error": "No face detected in the stored image (after rotation retries)."}
    except Exception as e:
        return {"error": f"Enroll extraction crash: {str(e)}"}


def process_image(input_data):
    try:
        # Handle base64 padding or prefixes (e.g. data:image/jpeg;base64,...)
        if ',' in input_data:
            input_data = input_data.split(',')[1]

        img_bytes = base64.b64decode(input_data)
        nparr = np.frombuffer(img_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if img is None:
            return {"error": "Failed to decode camera frame bytes."}

        # Resize for fast detection (smaller = faster; 480px keeps a face detectable).
        h, w, _ = img.shape
        max_w = 480
        if w > max_w:
            scale = max_w / w
            img = cv2.resize(img, (0, 0), fx=scale, fy=scale)

        # 1. Face Locations Detection
        face_locations = face_recognition.face_locations(img)
        if len(face_locations) == 0:
            return {"error": "No face detected in feed. Please align your face inside the guide."}
        elif len(face_locations) > 1:
            return {"error": "Multiple faces detected! Only one person is allowed."}

        # 2. Strict Position & Proximity Checks
        top, right, bottom, left = face_locations[0]
        face_width = right - left
        face_height = bottom - top
        face_center_x = left + face_width // 2
        face_center_y = top + face_height // 2

        target_center_x = img.shape[1] // 2
        target_center_y = img.shape[0] // 2

        # Verify centering (thresholds scaled for the 480px detection image)
        if abs(face_center_x - target_center_x) > 210:
            return {"error": "Face off-center horizontally. Align with guide."}
        if abs(face_center_y - target_center_y) > 210:
            return {"error": "Face off-center vertically. Align with guide."}

        # Verify size/proximity bounds
        if face_width < 90:
            return {"error": "You are too far. Please move closer."}
        elif face_width > 260:
            return {"error": "You are too close. Step back slightly."}

        # 3. Symmetry Frontal Posture Check (optional — off by default for speed).
        if FRONTAL_CHECK:
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
                            return {"error": "Look straight at the camera. Side angles are not allowed."}

        # 3.5. Anti-Spoofing (Liveness Check) — passive single-image model
        # (Silent-Face / MiniFASNet) that rejects printed photos & phone screens.
        # Enabled via FACE_LIVENESS=1. IMPORTANT: only a genuine spoof verdict
        # (label != 1) blocks. A model load/run error FAILS OPEN (logs to stderr,
        # lets the punch through) so a missing/broken model never bricks the kiosk.
        if LIVENESS_CHECK and HAS_ANTI_SPOOFING:
            try:
                model_dir = os.path.join(anti_spoof_path, 'resources', 'anti_spoof_models')
                label = test_fn(img, model_dir, 0)
                if label != 1:
                    return {"error": "Spoof Alert! Digital screens or printed photos are not allowed."}
            except Exception as ase:
                sys.stderr.write(f"[liveness] check skipped (fail-open): {ase}\n")
                sys.stderr.flush()
        elif LIVENESS_CHECK and not HAS_ANTI_SPOOFING:
            sys.stderr.write("[liveness] FACE_LIVENESS=1 but anti-spoof model unavailable "
                             "(torch not installed?) — failing open.\n")
            sys.stderr.flush()

        # 4. Generate Face Descriptor Vector (num_jitters=1 for speed; 2 was ~2x slower)
        encodings = face_recognition.face_encodings(img, face_locations, num_jitters=1)
        if len(encodings) == 0:
            return {"error": "Could not extract face biometrics. Please try again."}

        encoding = encodings[0].tolist()
        return {"embedding": encoding}

    except Exception as e:
        return {"error": f"Internal biometric extraction crash: {str(e)}"}

def main():
    # Warm up / preload models
    # This is run once on start!
    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break
            line = line.strip()
            if not line:
                continue

            # JSON command -> lenient enroll mode; raw base64 -> strict live scan.
            if line[0] == '{':
                try:
                    cmd = json.loads(line)
                except Exception:
                    cmd = None
                if cmd and cmd.get('mode') == 'enroll':
                    result = enroll_image(cmd.get('image', ''))
                else:
                    result = process_image(line)
            else:
                result = process_image(line)
            sys.stdout.write(json.dumps(result) + '\n')
            sys.stdout.flush()
        except Exception as e:
            sys.stdout.write(json.dumps({"error": str(e)}) + '\n')
            sys.stdout.flush()

if __name__ == '__main__':
    main()
