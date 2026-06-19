import json
from cryptography.fernet import Fernet
from backend.config import settings

class BiometricEncryption:
    """
    Encrypts and decrypts biometric facial embeddings to comply with security standards.
    Uses AES-256 Fernet symmetric keys.
    """
    def __init__(self):
        # Initialize Fernet with the encryption key from config
        self.fernet = Fernet(settings.ENCRYPTION_KEY.encode())

    def encrypt_embedding(self, embedding: list[float]) -> str:
        """
        Encrypts a 512-dimension float array.
        1. Converts the list of floats into a JSON-serialized string.
        2. Encrypts the string bytes using AES-256.
        3. Decodes the output bytes into a secure base64 string for database storage.
        """
        try:
            # Serialize the float list
            serialized = json.dumps(embedding)
            # Encrypt
            encrypted_bytes = self.fernet.encrypt(serialized.encode('utf-8'))
            # Return as string
            return encrypted_bytes.decode('utf-8')
        except Exception as e:
            raise ValueError(f"Biometric encryption failed: {str(e)}")

    def decrypt_embedding(self, encrypted_data: str) -> list[float]:
        """
        Decrypts base64 bytes into a list of floats.
        1. Decrypts the database text using AES-256.
        2. Loads the resulting JSON bytes into a Python list of floats.
        """
        try:
            # Decrypt
            decrypted_bytes = self.fernet.decrypt(encrypted_data.encode('utf-8'))
            # Deserialize
            return json.loads(decrypted_bytes.decode('utf-8'))
        except Exception as e:
            raise ValueError(f"Biometric decryption failed: {str(e)}")

# Instantiate global encryption utility
biometric_encryptor = BiometricEncryption()
