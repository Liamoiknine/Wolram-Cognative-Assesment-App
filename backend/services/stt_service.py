import asyncio
import base64
from typing import AsyncGenerator, Optional
from openai import OpenAI
import os
from dotenv import load_dotenv
import struct

load_dotenv()


class STTService:
    """Speech-to-Text service using OpenAI Whisper API for batch transcription"""
    
    def __init__(self):
        api_key = os.getenv("OPENAI_API_KEY")
        if not api_key:
            raise ValueError("OPENAI_API_KEY not found in environment")
        self.client = OpenAI(api_key=api_key)
    
    def _is_silent(self, audio_bytes: bytes, threshold: float = 0.002) -> bool:
        """
        Check if audio is essentially silent.
        
        Args:
            audio_bytes: PCM audio data (16-bit signed integers)
            threshold: RMS threshold below which audio is considered silent (0.0-1.0)
            
        Returns:
            True if audio appears to be silent
        """
        if len(audio_bytes) < 2:
            return True
        
        try:
            # Check if this might be a WAV file (starts with "RIFF")
            # If so, skip the header (first 44 bytes typically)
            if len(audio_bytes) > 4 and audio_bytes[:4] == b'RIFF':
                # This is a WAV file, extract PCM data (skip 44-byte header)
                if len(audio_bytes) < 44:
                    return True
                audio_bytes = audio_bytes[44:]
            
            # Must have even number of bytes for 16-bit samples
            if len(audio_bytes) % 2 != 0:
                print(f"⚠️ STTService: Audio data has odd length ({len(audio_bytes)}), truncating")
                audio_bytes = audio_bytes[:-1]
            
            if len(audio_bytes) < 2:
                return True
            
            # Convert bytes to 16-bit signed integers
            # Assuming little-endian 16-bit PCM
            num_samples = len(audio_bytes) // 2
            samples = struct.unpack(f'<{num_samples}h', audio_bytes)
            
            # Calculate RMS (Root Mean Square) to measure audio energy
            if len(samples) == 0:
                return True
            
            # Normalize to -1.0 to 1.0 range
            max_value = 32768.0
            normalized_samples = [abs(sample / max_value) for sample in samples]
            
            # Calculate RMS
            rms = (sum(s * s for s in normalized_samples) / len(normalized_samples)) ** 0.5
            
            # Debug output
            max_sample = max(abs(s) for s in samples) if samples else 0
            is_silent = rms < threshold
            print(f"🔍 STTService: Silence check - RMS: {rms:.6f}, Max sample: {max_sample}, Threshold: {threshold}, Samples: {len(samples)}, Is silent: {is_silent}")
            
            # Consider silent if RMS is below threshold (very low threshold - only truly silent)
            return is_silent
        except Exception as e:
            print(f"⚠️ STTService: Error checking silence: {e}")
            import traceback
            traceback.print_exc()
            # If we can't check, assume not silent to be safe
            return False
                    
    async def transcribe_audio(self, audio_bytes: bytes) -> str:
        """
        Transcribe audio bytes using OpenAI Whisper API.
        Returns empty string for silent audio to avoid hallucinated transcriptions.
        
        Args:
            audio_bytes: Audio data in PCM format (16kHz, 16-bit, mono)
            
        Returns:
            Transcribed text string, or empty string if audio is silent
        """
        try:
            # Check if audio is silent before transcribing
            # This prevents Whisper from hallucinating text from background noise
            if self._is_silent(audio_bytes):
                print("🔇 STTService: Audio appears to be silent, skipping transcription")
                return ""
            
            # Save audio to temporary file for Whisper API
            import tempfile
            import io
            
            # Whisper API expects audio file format (wav, mp3, etc.)
            # For PCM data, we'll write it as a WAV file
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp_file:
                # Write WAV header + PCM data
                # Simple WAV header for 16kHz, 16-bit, mono
                sample_rate = 16000
                num_channels = 1
                bits_per_sample = 16
                data_size = len(audio_bytes)
                file_size = 36 + data_size
                
                # WAV header
                wav_header = bytearray()
                wav_header.extend(b'RIFF')
                wav_header.extend(file_size.to_bytes(4, 'little'))
                wav_header.extend(b'WAVE')
                wav_header.extend(b'fmt ')
                wav_header.extend((16).to_bytes(4, 'little'))  # fmt chunk size
                wav_header.extend((1).to_bytes(2, 'little'))  # audio format (PCM)
                wav_header.extend(num_channels.to_bytes(2, 'little'))
                wav_header.extend(sample_rate.to_bytes(4, 'little'))
                wav_header.extend((sample_rate * num_channels * bits_per_sample // 8).to_bytes(4, 'little'))  # byte rate
                wav_header.extend((num_channels * bits_per_sample // 8).to_bytes(2, 'little'))  # block align
                wav_header.extend(bits_per_sample.to_bytes(2, 'little'))
                wav_header.extend(b'data')
                wav_header.extend(data_size.to_bytes(4, 'little'))
                
                tmp_file.write(wav_header)
                tmp_file.write(audio_bytes)
                tmp_file.flush()
                
                # Transcribe using Whisper API
                with open(tmp_file.name, 'rb') as audio_file:
                    transcript = self.client.audio.transcriptions.create(
                        model="whisper-1",
                        file=audio_file,
                        language="en"
                    )
                    
                # Clean up temp file
                os.unlink(tmp_file.name)
                
                return transcript.text
                
        except Exception as e:
            print(f"❌ STTService: Error transcribing audio: {e}")
            raise

