import math
from datetime import datetime, time
from backend.config import settings

class BiometricEngine:
    """
    Core business and math logic for biometric vector matching, late check-in
    detection, and work hour calculations.
    """
    
    @staticmethod
    def cosine_similarity(v1: list[float], v2: list[float]) -> float:
        """
        Calculates cosine similarity between two high-dimensional vectors.
        Formulas: A • B / (||A|| * ||B||)
        """
        if len(v1) != len(v2) or not v1:
            return 0.0
            
        dot_product = sum(a * b for a, b in zip(v1, v2))
        norm_a = math.sqrt(sum(a * a for a in v1))
        norm_b = math.sqrt(sum(b * b for b in v2))
        
        if norm_a == 0.0 or norm_b == 0.0:
            return 0.0
            
        return dot_product / (norm_a * norm_b)

    @staticmethod
    def match_face(
        live_embedding: list[float], 
        db_templates: list[dict], 
        threshold: float = None
    ) -> tuple[str, float]:
        """
        Compares a live scanned embedding against all registered templates.
        
        db_templates should be a list of dicts: 
        [{"employee_id": "EMP001", "embedding": [0.1, 0.2, ...]}, ...]
        
        Returns: (matched_employee_id, confidence_score) or (None, 0.0) if below threshold
        """
        if threshold is None:
            threshold = settings.SIMILARITY_THRESHOLD
            
        best_employee_id = None
        highest_score = 0.0
        
        for template in db_templates:
            score = BiometricEngine.cosine_similarity(live_embedding, template["embedding"])
            if score > highest_score:
                highest_score = score
                best_employee_id = template["employee_id"]
                
        if highest_score >= threshold:
            return best_employee_id, highest_score
            
        return None, highest_score

    @staticmethod
    def evaluate_attendance_status(check_in_time: datetime) -> str:
        """
        Determines if an employee is "Present" or "Late".
        Looks at SHIFT_START_TIME and LATE_GRACE_PERIOD_MINUTES.
        """
        # Parse official shift start
        try:
            start_hours, start_mins = map(int, settings.SHIFT_START_TIME.split(":"))
        except ValueError:
            start_hours, start_mins = 9, 0  # fallback
            
        shift_start = check_in_time.replace(hour=start_hours, minute=start_mins, second=0, microsecond=0)
        late_limit = shift_start + timedelta_minutes(settings.LATE_GRACE_PERIOD_MINUTES)
        
        if check_in_time > late_limit:
            return "Late"
        return "Present"

    @staticmethod
    def calculate_hours_and_overtime(
        check_in: datetime, 
        check_out: datetime
    ) -> tuple[float, float, str]:
        """
        Calculates working metrics.
        Returns: (total_hours, overtime_hours, final_attendance_status)
        """
        if not check_in or not check_out:
            return 0.0, 0.0, "Absent"
            
        duration = check_out - check_in
        total_hours = duration.total_seconds() / 3600.0
        total_hours = round(total_hours, 2)
        
        # Determine status (e.g. if employee checked in on time but left early)
        final_status = "Present"
        try:
            start_hours, start_mins = map(int, settings.SHIFT_START_TIME.split(":"))
        except ValueError:
            start_hours, start_mins = 9, 0
            
        shift_start = check_in.replace(hour=start_hours, minute=start_mins, second=0, microsecond=0)
        late_limit = shift_start + timedelta_minutes(settings.LATE_GRACE_PERIOD_MINUTES)
        
        if check_in > late_limit:
            final_status = "Late"
            
        # Half-day check
        if total_hours < settings.HALF_DAY_THRESHOLD_HOURS:
            final_status = "Half-Day"
            
        # Overtime check
        overtime = 0.0
        if total_hours > settings.OVERTIME_THRESHOLD_HOURS:
            overtime = round(total_hours - settings.OVERTIME_THRESHOLD_HOURS, 2)
            
        return total_hours, overtime, final_status

def timedelta_minutes(minutes: int):
    import datetime as dt
    return dt.timedelta(minutes=minutes)
