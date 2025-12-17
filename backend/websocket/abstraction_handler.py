"""
Abstraction Task Handler - Scripted Flow

Simple, deterministic scripted interaction:
- Backend generates ElevenLabs TTS audio for prompts
- iOS plays audio and records fixed-duration responses
- Backend evaluates responses asynchronously (server-side only)
"""
import asyncio
import base64
import json
from typing import Optional
from fastapi import WebSocket
from fastapi.websockets import WebSocketDisconnect
import sys
from pathlib import Path

# Add backend to path for imports
backend_path = Path(__file__).parent.parent
sys.path.insert(0, str(backend_path))

from models.messages import (
    ClientMessage, ServerMessage, TTSMessage, TaskState, DebugMessage, EvaluationResult
)
from services.tts_service import TTSService
from websocket.base_handler import BaseTaskHandler

# Scripted prompts - editable in backend only
ABSTRACTION_SCRIPT = {
    "instruction": "For this task, I'm going to say two words that are related in some way. I want you to respond with what category these words both belong to. We'll do this twice, and you'll have 10 seconds to respond each time.",
    "trials": [
    {"word1": "Train", "word2": "Bicycle"},
    {"word1": "Banana", "word2": "Orange"}
]
}


class AbstractionTaskHandler(BaseTaskHandler):
    """WebSocket handler for scripted Abstraction task"""
    
    def __init__(self, websocket: WebSocket, session_id: str):
        super().__init__(websocket, session_id)
        
        # Task-specific state
        self.trial_number = 0
    
    async def _start_task(self):
        """Start the scripted task flow"""
        try:
            # Phase 1: Send instruction
            await self._send_instruction()
            
        except Exception as e:
            print(f"❌ Error starting task: {e}")
            import traceback
            traceback.print_exc()
            await self.send_debug(f"Failed to start task: {e}")
    
    async def _handle_audio_upload(self, trial_number: int, audio_bytes: bytes):
        """
        Handle audio upload - determine next trial or completion.
        Called from HTTP upload endpoint.
        """
        # IMMEDIATELY send next trial audio in background (non-blocking)
        if trial_number == 0:
            # Instruction complete - send trial 1
            asyncio.create_task(self._send_next_trial_immediately(1))
        elif trial_number < len(ABSTRACTION_SCRIPT["trials"]):
            # Send next trial immediately
            asyncio.create_task(self._send_next_trial_immediately(trial_number + 1))
        else:
            # All trials complete
            asyncio.create_task(self._send_completion_immediately())
    
    async def _send_next_trial_immediately(self, trial_number: int):
        """Send next trial audio immediately without any delay"""
        try:
            await self.send_trial_audio(trial_number)
        except Exception as e:
            print(f"❌ Error sending next trial audio: {e}")
    
    async def _send_completion_immediately(self):
        """Send completion immediately"""
        try:
            await self._send_completion()
        except Exception as e:
            print(f"❌ Error sending completion: {e}")
    
    async def _send_instruction(self):
        """
        Send instruction audio only. Wait for client to finish playing before proceeding.
        
        Sequential flow:
        1. Send instruction → Client plays → Client signals ready → Send trial 1
        2. Send trial 1 → Client plays → Client records 15s → Uploads → Send trial 2
        3. Send trial 2 → Client plays → Client records 15s → Uploads → Send completion
        """
        self.current_phase = "instruction"
        instruction_text = ABSTRACTION_SCRIPT["instruction"]
        
        # Use base class method to send TTS audio
        await self.send_tts_audio(instruction_text, trial_number=0)
        
        await self.send_task_state("listening", 0, "Instruction")
        print(f"📋 Backend: Sent instruction audio - waiting for client to finish playing")
        
        # Do NOT send trial 1 here - wait for client to signal it's ready
        # The client will upload after instruction (even though we ignore it) to signal readiness
    
    async def send_trial_audio(self, trial_number: int):
        """
        Send trial audio (called after previous audio upload is received, or after instruction).
        
        Flow:
        1. Instruction plays → Client automatically proceeds to trial 1 (no upload needed)
        2. Trial 1 plays → Client records 10s → Uploads → Backend sends trial 2
        3. Trial 2 plays → Client records 10s → Uploads → Backend sends completion
        """
        if trial_number > len(ABSTRACTION_SCRIPT["trials"]):
            # All trials complete
            await self._send_completion()
            return
        
        self.current_phase = f"trial_{trial_number}"
        self.trial_number = trial_number
        
        trial = ABSTRACTION_SCRIPT["trials"][trial_number - 1]
        word1 = trial['word1']
        word2 = trial['word2']
        
        # Construct trial text based on trial number
        if trial_number == 1:
            # First trial: "The two words are X and Y. What category do they both belong to?"
            trial_text = f"The two words are {word1} and {word2}. What category do they both belong to?"
        else:
            # Second trial (and any subsequent): "Alright now let's do that one more time, again, you'll have 10 seconds to respond. This time your words are X and Y. What category do they both belong to?"
            trial_text = f"Alright now let's do that one more time, again, you'll have 10 seconds to respond. This time your words are {word1} and {word2}. What category do they both belong to?"
        
        # Use base class method to send TTS audio
        await self.send_tts_audio(trial_text, trial_number=trial_number)
        
        await self.send_task_state("listening", trial_number, f"Trial {trial_number}")
        print(f"📋 Backend: Sent trial {trial_number} audio: {trial_text}")
    
    async def add_evaluation_result(
        self,
        trial_number: int,
        word1: str,
        word2: str,
        transcript: str,
        category: str,
        is_correct: bool,
        confidence: float,
        notes: str
    ):
        """Add an evaluation result and send it to the client"""
        result = EvaluationResult(
            trial_number=trial_number,
            word1=word1,
            word2=word2,
            transcript=transcript,
            category=category,
            is_correct=is_correct,
            confidence=confidence,
            notes=notes
        )
        # Use base class method to store result
        super().add_evaluation_result(result)
        
        # Send individual result to client using base class method
        await self.send_evaluation_result(result)
        print(f"📊 Backend: Sent evaluation result for trial {trial_number}")
    
    async def _send_completion(self):
        """Send completion message and all results"""
        # Use base class method to send all results
        await self.send_all_results()
