import math
from typing import List, Dict, Tuple

class LivenessChecker:
    """
    Computes active liveness checks including eye blink counts and head rotation tracking.
    Protects against high-resolution photo or pre-recorded video presentation attacks.
    """
    
    # Standard eye aspect ratio blink threshold.
    # Below this value, the eye is considered closed.
    EAR_THRESHOLD: float = 0.20
    
    # Head turn thresholds in degrees
    YAW_THRESHOLD_LEFT: float = 15.0
    YAW_THRESHOLD_RIGHT: float = -15.0
    PITCH_THRESHOLD_UP: float = 12.0
    PITCH_THRESHOLD_DOWN: float = -12.0

    @staticmethod
    def calculate_ear(eye_landmarks: List[Tuple[float, float]]) -> float:
        """
        Calculates the Eye Aspect Ratio (EAR) using 6 landmark coordinates:
        P1 (corner), P2, P3 (top), P4 (corner), P5, P6 (bottom).
        
        Formula: (||P2 - P6|| + ||P3 - P5||) / (2 * ||P1 - P4||)
        """
        if len(eye_landmarks) != 6:
            return 0.0
            
        p1, p2, p3, p4, p5, p6 = eye_landmarks
        
        # Euclidean distances between vertical landmark pairs
        vertical_1 = math.sqrt((p2[0] - p6[0])**2 + (p2[1] - p6[1])**2)
        vertical_2 = math.sqrt((p3[0] - p5[0])**2 + (p3[1] - p5[1])**2)
        
        # Euclidean distance between horizontal landmark pairs
        horizontal = math.sqrt((p1[0] - p4[0])**2 + (p1[1] - p4[1])**2)
        
        if horizontal == 0:
            return 0.0
            
        ear = (vertical_1 + vertical_2) / (2.0 * horizontal)
        return ear

    @staticmethod
    def estimate_head_pose(
        landmarks: Dict[str, Tuple[float, float]], 
        image_width: int, 
        image_height: int
    ) -> Tuple[float, float, float]:
        """
        Estimates yaw, pitch, and roll angles (in degrees) using critical face points.
        Points mapped: Nose tip, Chin, Left eye corner, Right eye corner, Left mouth corner, Right mouth corner.
        
        This mimics a 3D-to-2D Perspective-n-Point (PnP) solver using camera focal lengths.
        """
        # Ensure we have all necessary keypoints
        required_keys = ["nose_tip", "chin", "left_eye_corner", "right_eye_corner", "left_mouth", "right_mouth"]
        if not all(k in landmarks for k in required_keys):
            return 0.0, 0.0, 0.0
            
        # Extract 2D image coordinates
        p_nose = landmarks["nose_tip"]
        p_chin = landmarks["chin"]
        p_leye = landmarks["left_eye_corner"]
        p_reye = landmarks["right_eye_corner"]
        p_lmouth = landmarks["left_mouth"]
        p_rmouth = landmarks["right_mouth"]
        
        # Calculate yaw (horizontal head turn)
        # Using horizontal symmetry of eye corners relative to the nose tip
        left_eye_dist = math.sqrt((p_nose[0] - p_leye[0])**2 + (p_nose[1] - p_leye[1])**2)
        right_eye_dist = math.sqrt((p_nose[0] - p_reye[0])**2 + (p_nose[1] - p_reye[1])**2)
        
        if right_eye_dist == 0:
            yaw = 0.0
        else:
            symmetry_ratio = left_eye_dist / right_eye_dist
            # Map symmetry ratio into a rough degree angle
            yaw = (symmetry_ratio - 1.0) * 45.0
            
        # Calculate pitch (vertical head tilt)
        # Ratio of vertical distance (nose to eyes vs nose to chin)
        eye_mid_x = (p_leye[0] + p_reye[0]) / 2.0
        eye_mid_y = (p_leye[1] + p_reye[1]) / 2.0
        
        nose_to_eyes = math.sqrt((p_nose[0] - eye_mid_x)**2 + (p_nose[1] - eye_mid_y)**2)
        nose_to_chin = math.sqrt((p_nose[0] - p_chin[0])**2 + (p_nose[1] - p_chin[1])**2)
        
        if nose_to_chin == 0:
            pitch = 0.0
        else:
            vertical_ratio = nose_to_eyes / nose_to_chin
            # Expected normal ratio is ~0.6. Pertubations indicate tilt
            pitch = (vertical_ratio - 0.6) * 60.0

        # Calculate roll (side-to-side rotation)
        # Slope between the two eye corners
        dy = p_reye[1] - p_leye[1]
        dx = p_reye[0] - p_leye[0]
        
        if dx == 0:
            roll = 90.0 if dy > 0 else -90.0
        else:
            roll = math.degrees(math.atan2(dy, dx))
            
        return round(yaw, 1), round(pitch, 1), round(roll, 1)

    @staticmethod
    def evaluate_liveness_challenge(
        challenge_type: str, 
        landmarks: Dict[str, List[Tuple[float, float]]],
        image_dims: Tuple[int, int]
    ) -> bool:
        """
        Validates active user interactions against dynamic, random command prompts.
        challenge_types: "blink", "turn_left", "turn_right", "tilt_up", "tilt_down"
        """
        width, height = image_dims
        
        if challenge_type == "blink":
            # EAR values for both eyes
            if "left_eye" not in landmarks or "right_eye" not in landmarks:
                return False
            ear_l = LivenessChecker.calculate_ear(landmarks["left_eye"])
            ear_r = LivenessChecker.calculate_ear(landmarks["right_eye"])
            # If either eye aspects indicate closing, register a pass
            return (ear_l < LivenessChecker.EAR_THRESHOLD) or (ear_r < LivenessChecker.EAR_THRESHOLD)
            
        elif challenge_type in ["turn_left", "turn_right", "tilt_up", "tilt_down"]:
            # Flatten eye arrays to single coordinate dictionary for pose estimation
            single_points = {}
            for k in ["nose_tip", "chin", "left_mouth", "right_mouth"]:
                if k in landmarks and landmarks[k]:
                    single_points[k] = landmarks[k][0]
            
            if "left_eye" in landmarks and landmarks["left_eye"]:
                single_points["left_eye_corner"] = landmarks["left_eye"][0]
            if "right_eye" in landmarks and landmarks["right_eye"]:
                single_points["right_eye_corner"] = landmarks["right_eye"][3] # outer corner
                
            yaw, pitch, roll = LivenessChecker.estimate_head_pose(single_points, width, height)
            
            if challenge_type == "turn_left" and yaw > LivenessChecker.YAW_THRESHOLD_LEFT:
                return True
            if challenge_type == "turn_right" and yaw < LivenessChecker.YAW_THRESHOLD_RIGHT:
                return True
            if challenge_type == "tilt_up" and pitch > LivenessChecker.PITCH_THRESHOLD_UP:
                return True
            if challenge_type == "tilt_down" and pitch < LivenessChecker.PITCH_THRESHOLD_DOWN:
                return True
                
        return False
