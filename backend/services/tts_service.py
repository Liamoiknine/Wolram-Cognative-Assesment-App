from typing import Optional
import os
import hashlib
import json
from pathlib import Path
from dotenv import load_dotenv
from elevenlabs.client import ElevenLabs
from elevenlabs import VoiceSettings

load_dotenv()


class TTSService:
    """Text-to-Speech service using ElevenLabs for high-quality, human-sounding voice"""
    
    def __init__(self):
        api_key = os.getenv("ELEVENLABS_API_KEY")
        if not api_key:
            raise ValueError("ELEVENLABS_API_KEY not found in environment")
        
        self.client = ElevenLabs(api_key=api_key)
        
        # Use a high-quality, human-sounding voice
        # Default voice ID for "Brian" - natural and clear
        # Can be changed via ELEVENLABS_VOICE_ID env var
        self.voice_id = os.getenv("ELEVENLABS_VOICE_ID", "nPczCjzI2devNBz1zQrb")  # Brian voice
        
        # Cache configuration
        backend_path = Path(__file__).parent.parent
        self.cache_dir = backend_path / "tts_cache"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        
        # Audio format and sample rate (defaults based on ElevenLabs output)
        self.audio_format = "mp3"  # ElevenLabs returns MP3 by default
        self.sample_rate = None  # Not explicitly configurable in current implementation
        self.model_id = "eleven_multilingual_v2"  # Default model
    
    def _normalize_text(self, text: str) -> str:
        """
        Normalize text before hashing to prevent cache misses from minor differences.
        
        Args:
            text: Raw text input
            
        Returns:
            Normalized text (trimmed, collapsed spaces, lowercased)
        """
        return " ".join(text.strip().lower().split())
    
    def _get_cache_key(self, text: str, voice_id: str, model_id: str, audio_format: str, sample_rate: Optional[int] = None) -> str:
        """
        Generate cache key hash from normalized text and audio parameters.
        
        Args:
            text: Text to convert (will be normalized)
            voice_id: Voice ID
            model_id: Model ID
            audio_format: Audio format (e.g., "mp3")
            sample_rate: Optional sample rate
            
        Returns:
            SHA256 hash as hex string
        """
        normalized_text = self._normalize_text(text)
        sample_rate_str = str(sample_rate) if sample_rate is not None else "default"
        cache_input = f"{normalized_text}|{voice_id}|{model_id}|{audio_format}|{sample_rate_str}"
        return hashlib.sha256(cache_input.encode('utf-8')).hexdigest()
    
    def _get_cache_path(self, cache_key: str, audio_format: str) -> Path:
        """
        Get cache file path with sharded subdirectory structure.
        
        Args:
            cache_key: SHA256 hash (hex string)
            audio_format: Audio file format (e.g., "mp3")
            
        Returns:
            Path to cache file in sharded directory structure
        """
        # Extract first 4 hex chars for sharding: ab/cd
        first_2 = cache_key[:2]
        next_2 = cache_key[2:4]
        
        # Create sharded subdirectory path
        shard_dir = self.cache_dir / first_2 / next_2
        shard_dir.mkdir(parents=True, exist_ok=True)
        
        return shard_dir / f"{cache_key}.{audio_format}"
    
    def _load_from_cache(self, cache_path: Path) -> Optional[bytes]:
        """
        Load audio from cache if it exists.
        
        Args:
            cache_path: Path to cached audio file
            
        Returns:
            Audio bytes if file exists, None otherwise
        """
        try:
            if cache_path.exists():
                audio_bytes = cache_path.read_bytes()
                return audio_bytes
            return None
        except Exception as e:
            print(f"⚠️ TTSService: Error loading from cache: {e}")
            return None
    
    def _save_to_cache(self, cache_path: Path, audio_bytes: bytes, metadata: Optional[dict] = None) -> None:
        """
        Save audio to cache with optional metadata.
        
        Args:
            cache_path: Path to save audio file
            audio_bytes: Audio data to save
            metadata: Optional metadata dict to save as JSON
        """
        try:
            # Save audio file
            cache_path.write_bytes(audio_bytes)
            
            # Optionally save metadata JSON for debugging
            if metadata is not None:
                metadata_path = cache_path.with_suffix('.json')
                metadata_path.write_text(json.dumps(metadata, indent=2))
        except Exception as e:
            print(f"⚠️ TTSService: Error saving to cache: {e}")
            # Don't fail - cache write errors shouldn't break TTS functionality
    
    def generate_audio(self, text: str, voice_id: Optional[str] = None) -> bytes:
        """
        Generate audio from text using ElevenLabs TTS with caching.
        
        Args:
            text: Text to convert to speech
            voice_id: Optional voice ID (defaults to configured voice)
            
        Returns:
            Audio bytes (MP3 format)
        """
        try:
            voice_id_to_use = voice_id or self.voice_id
            
            # Compute cache key
            cache_key = self._get_cache_key(
                text=text,
                voice_id=voice_id_to_use,
                model_id=self.model_id,
                audio_format=self.audio_format,
                sample_rate=self.sample_rate
            )
            
            # Get cache path
            cache_path = self._get_cache_path(cache_key, self.audio_format)
            
            # Check cache first
            cached_audio = self._load_from_cache(cache_path)
            if cached_audio is not None:
                print(f"✅ TTS cache hit: {cache_key}")
                return cached_audio
            
            # Cache miss - generate audio from ElevenLabs
            print(f"❌ TTS cache miss: {cache_key}")
            
            # Generate audio with high quality settings
            audio = self.client.text_to_speech.convert(
                voice_id=voice_id_to_use,
                text=text,
                model_id=self.model_id,
                voice_settings=VoiceSettings(
                    stability=0.5,
                    similarity_boost=0.75,
                    style=0.0,
                    use_speaker_boost=True
                )
            )
            
            # Convert generator to bytes
            audio_bytes = b"".join(audio)
            
            # Save to cache with metadata
            metadata = {
                "original_text": text,
                "normalized_text": self._normalize_text(text),
                "voice_id": voice_id_to_use,
                "model_id": self.model_id,
                "audio_format": self.audio_format,
                "sample_rate": self.sample_rate,
                "cache_key": cache_key
            }
            self._save_to_cache(cache_path, audio_bytes, metadata)
            
            return audio_bytes
        except Exception as e:
            print(f"❌ TTSService: Error generating audio: {e}")
            raise

