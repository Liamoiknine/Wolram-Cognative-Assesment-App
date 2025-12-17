"""
Working Memory Task Handler - Scripted Flow

Backend-controlled working memory task:
- Backend generates ElevenLabs TTS audio for words and prompts
- iOS plays audio and displays words on screen
- iOS records fixed-duration responses
- Backend evaluates responses asynchronously (server-side only)
"""
import asyncio
import base64
import json
import random
from typing import Optional, List
from fastapi import WebSocket
from fastapi.websockets import WebSocketDisconnect
import sys
from pathlib import Path

# Add backend to path for imports
backend_path = Path(__file__).parent.parent
sys.path.insert(0, str(backend_path))

from models.messages import (
    ClientMessage, ServerMessage, TTSMessage, TaskState, DebugMessage, EvaluationResult, WordDisplayMessage, StateTransition
)
from services.tts_service import TTSService
from websocket.base_handler import BaseTaskHandler

# Word bank for Working Memory Task
# High-frequency words (18)
HIGH_FREQUENCY_WORDS = [
    "chair", "book", "hand", "house", "bread", "light",
    "phone", "table", "clock", "door", "cup", "shoe",
    "bed", "car", "tree", "dog", "ball", "rain"
]

# Medium-frequency words (12)
MEDIUM_FREQUENCY_WORDS = [
    "cloud", "stone", "road", "field", "bridge", "lake",
    "grass", "coat", "leaf", "key", "fence", "hill"
]

# Scripted prompts - editable in backend only
WORKING_MEMORY_SCRIPT = {
    "instruction": "We'll start with the Working Memory Task. For this task, I will read you 5 words. After I finish, I want you to repeat these words back to me in the same order that you heard them. We will repeat this for two trials., and you'll have 10 seconds to respond each time. Here are the words:",
    "trial_2_intro": "Well done, now let's do that one more time. Again, you'll have 10 seconds to respond. Here are the words:",
    "prompt": "Now you repeat them.",
    "completion": "Great job! You've completed the working memory task."
}


class WorkingMemoryTaskHandler(BaseTaskHandler):
    """WebSocket handler for scripted Working Memory task"""
    
    def __init__(self, websocket: WebSocket, session_id: str):
        super().__init__(websocket, session_id)
        
        # Task-specific state
        self.trial_number = 0
        self.trial_words: List[List[str]] = []  # Store words for each trial
        self.word_pause_duration = 1.0  # 1 second pause between words
        self.completion_sent = False  # Guard to prevent duplicate completion messages
        
        # State machine for sequential flow control
        self.audio_complete_event = asyncio.Event()  # Signal that audio playback is complete
        self.waiting_for_audio_complete = False  # Track if we're waiting for audio complete signal
        
        # Guard to prevent duplicate LLM evaluations (max 2 trials)
        self.evaluated_trials: set[int] = set()  # Track which trials have been evaluated
    
    def _select_trial_words(self, trial_number: int) -> List[str]:
        """
        Select 5 words for a trial: 3 high-frequency + 2 medium-frequency
        TEMPORARILY: Same words for both trials (for rate limiting/caching)
        
        TODO: Reintroduce pooled words implementation later for different words per trial
        """
        # TEMPORARY: Fixed word set for both trials (for caching/rate limiting)
        # TODO: Reintroduce word pool logic later
        FIXED_WORDS = ["chair", "book", "hand", "road", "cloud"]
        return FIXED_WORDS.copy()
        
        # INACTIVE: Pooled words implementation (to be reintroduced later)
        # # Create a copy of word lists to avoid modifying originals
        # high_freq = HIGH_FREQUENCY_WORDS.copy()
        # medium_freq = MEDIUM_FREQUENCY_WORDS.copy()
        # 
        # # Remove words already used in previous trials
        # for used_words in self.trial_words:
        #     for word in used_words:
        #         if word in high_freq:
        #             high_freq.remove(word)
        #         if word in medium_freq:
        #             medium_freq.remove(word)
        # 
        # # If we've used too many words, reset (shouldn't happen with 2 trials)
        # if len(high_freq) < 3:
        #     high_freq = HIGH_FREQUENCY_WORDS.copy()
        # if len(medium_freq) < 2:
        #     medium_freq = MEDIUM_FREQUENCY_WORDS.copy()
        # 
        # # Select 3 high-frequency and 2 medium-frequency words
        # selected_high = random.sample(high_freq, 3)
        # selected_medium = random.sample(medium_freq, 2)
        # 
        # # Combine and shuffle to randomize order
        # selected_words = selected_high + selected_medium
        # random.shuffle(selected_words)
        # 
        # return selected_words
    
    async def _start_task(self):
        """Start the scripted task flow"""
        try:
            # Select the same words for both trials (for caching/rate limiting)
            selected_words = self._select_trial_words(1)
            self.trial_words = [
                selected_words.copy(),  # Trial 1
                selected_words.copy()   # Trial 2 (same words)
            ]
            
            print(f"📋 WorkingMemory: Selected words (same for both trials): {self.trial_words[0]}")
            
            # Phase 1: Send instruction
            await self._send_instruction()
            
        except Exception as e:
            print(f"❌ Error starting task: {e}")
            import traceback
            traceback.print_exc()
            await self.send_debug(f"Failed to start task: {e}")
    
    async def _handle_audio_upload(self, trial_number: int, audio_bytes: bytes):
        """
        Handle audio upload - determine next step (next trial or completion).
        Called from HTTP upload endpoint.
        """
        # Send beep_end and recording_complete state transitions
        if trial_number > 0:  # Only for actual recordings, not instruction signal
            await self._send_state_transition("beep_end", trial_number=trial_number)
            await asyncio.sleep(0.3)  # Wait for beep to play and signal to complete
            await self._send_state_transition("recording_complete", trial_number=trial_number)
            await asyncio.sleep(0.2)  # Wait for state update to propagate to client
        
        # Send next trial audio AFTER state transitions complete
        if trial_number == 0:
            # Instruction complete - send trial 1 words
            await self._send_trial_words(1)
        elif trial_number == 1:
            # Trial 1 complete - send trial 2 words
            await self._send_trial_words(2)
        else:
            # All trials complete
            await self._send_completion()
    
    async def send_tts_audio(self, text: str, trial_number: Optional[int] = None):
        """
        Override base class method to wait for audio_complete signal.
        Generate TTS audio and send to client, then wait for audio_complete signal.
        
        Args:
            text: Text to convert to speech
            trial_number: Optional trial number (0 for instruction, 1+ for trials)
        """
        try:
            # Reset the event before sending
            self.audio_complete_event.clear()
            self.waiting_for_audio_complete = True
            
            audio_bytes = self.tts_service.generate_audio(text)
            audio_base64 = base64.b64encode(audio_bytes).decode('utf-8')
            
            message = ServerMessage(
                type="tts_audio",
                data=TTSMessage(audio=audio_base64, trial_number=trial_number)
            )
            await self.websocket.send_text(message.model_dump_json())
            print(f"🔊 Backend: Sent TTS audio (trial: {trial_number}), waiting for audio_complete...")
            
            # Wait for client to signal audio playback is complete (with timeout)
            try:
                await asyncio.wait_for(self.audio_complete_event.wait(), timeout=30.0)
                print(f"✅ Backend: Received audio_complete signal")
            except asyncio.TimeoutError:
                print(f"⚠️ Backend: Timeout waiting for audio_complete, proceeding anyway")
                self.waiting_for_audio_complete = False
        except Exception as e:
            print(f"Error sending TTS audio: {e}")
            import traceback
            traceback.print_exc()
            self.waiting_for_audio_complete = False
    
    async def _send_state_transition(self, phase: str, trial_number: Optional[int] = None, message: Optional[str] = None):
        """Send explicit state transition to client"""
        try:
            transition = StateTransition(
                phase=phase,
                trial_number=trial_number,
                message=message
            )
            server_msg = ServerMessage(
                type="state_transition",
                data=transition
            )
            await self.websocket.send_text(server_msg.model_dump_json())
            print(f"🔄 Backend: Sent state transition: {phase} (trial: {trial_number})")
        except Exception as e:
            print(f"❌ Error sending state transition: {e}")
    
    async def _send_instruction(self):
        """
        Send instruction audio and text. Wait for explicit audio_complete signal.
        """
        self.current_phase = "instruction"
        instruction_text = WORKING_MEMORY_SCRIPT["instruction"]
        
        # Step 1: Send state transition for instruction display (with message text)
        await self._send_state_transition("instruction_display", trial_number=0, message=instruction_text)
        await asyncio.sleep(0.1)  # Brief delay for UI update
        
        # Step 2: Send state transition for instruction playing
        await self._send_state_transition("instruction_playing", trial_number=0)
        
        # Step 3: Send TTS audio and wait for audio_complete signal
        await self.send_tts_audio(instruction_text, trial_number=0)
        # send_tts_audio now waits for audio_complete internally
        print(f"📋 Backend: Instruction audio complete - ready for trial 1")
    
    async def _send_trial_words(self, trial_number: int):
        """
        Send trial words sequentially with state-based flow control.
        Each step waits for explicit audio_complete signal from client.
        
        Flow:
        1. Send trial announcement (if trial 2) → wait for audio_complete
        2. Send word display messages (for UI)
        3. Send words TTS audio → wait for audio_complete
        4. Clear word display
        5. Send prompt → wait for audio_complete
        6. Update task state to listening (triggers beep + recording on client)
        """
        if trial_number > len(self.trial_words):
            # All trials complete
            await self._send_completion()
            return
        
        self.current_phase = f"trial_{trial_number}"
        self.trial_number = trial_number
        
        words = self.trial_words[trial_number - 1]
        
        # Trial 2: Send intro separately, then words, then prompt (strictly sequential)
        if trial_number == 2:
            # Step 1: Send state transition for trial intro playing (with message text)
            intro_text = WORKING_MEMORY_SCRIPT["trial_2_intro"]
            await self._send_state_transition("trial_intro_playing", trial_number=trial_number, message=intro_text)
            await asyncio.sleep(0.1)  # Brief delay for UI update
            
            # Step 2: Send intro TTS audio → wait for audio_complete
            print(f"  📋 Backend: Sending trial 2 intro: '{intro_text}'")
            await self.send_tts_audio(intro_text, trial_number=trial_number)
            # send_tts_audio now waits for audio_complete internally
            print(f"  ✅ Backend: Intro audio complete")
        
        # Step 3: Send state transition for words displaying
        await self._send_state_transition("words_displaying", trial_number=trial_number)
        
        # Step 4: Send word display messages (for UI)
        for word_index, word in enumerate(words, start=1):
            await self._send_word_display(word, trial_number, word_index)
            await asyncio.sleep(0.05)  # Small delay between display messages for UI updates
        
        # Brief delay to allow UI to update
        await asyncio.sleep(0.2)
        
        # Step 5: Send state transition for words playing
        await self._send_state_transition("words_playing", trial_number=trial_number)
        
        # Step 6: Send words TTS audio → wait for audio_complete
        # Use periods instead of commas for longer pauses between words
        words_text = ". ".join(words) + "."
        print(f"  📋 Backend: Sending words TTS: '{words_text}'")
        await self.send_tts_audio(words_text, trial_number=trial_number)
        # send_tts_audio now waits for audio_complete internally
        print(f"  ✅ Backend: Words audio complete")
        
        # Step 7: Clear word display (signals word presentation is complete)
        await self._send_word_display("", trial_number, 0)
        await asyncio.sleep(0.2)  # Brief pause to ensure state is updated on client
        
        # Step 8: Send state transition for prompt playing (with message text)
        prompt_text = WORKING_MEMORY_SCRIPT["prompt"]
        await self._send_state_transition("prompt_playing", trial_number=trial_number, message=prompt_text)
        await asyncio.sleep(0.1)  # Brief delay for UI update
        
        # Step 9: Send prompt → wait for audio_complete
        print(f"  📋 Backend: Sending prompt: '{prompt_text}'")
        await self.send_tts_audio(prompt_text, trial_number=trial_number)
        # send_tts_audio now waits for audio_complete internally
        print(f"  ✅ Backend: Prompt audio complete")
        
        # Step 10: Send state transition for beep start
        await self._send_state_transition("beep_start", trial_number=trial_number)
        await asyncio.sleep(0.1)  # Brief delay for state update
        
        # Step 11: Send state transition for recording
        await self._send_state_transition("recording", trial_number=trial_number)
        print(f"📋 Backend: Trial {trial_number} ready for recording")
    
    async def _send_word_display(self, word: str, trial_number: int, word_index: int):
        """Send word display message to client"""
        try:
            word_display = WordDisplayMessage(
                word=word,
                trial_number=trial_number,
                word_index=word_index
            )
            message = ServerMessage(
                type="word_display",
                data=word_display
            )
            await self.websocket.send_text(message.model_dump_json())
            if word:
                print(f"📺 Backend: Sent word display: '{word}' (trial {trial_number}, index {word_index})")
        except Exception as e:
            print(f"❌ Error sending word display: {e}")
    
    async def add_evaluation_result(
        self,
        trial_number: int,
        words: List[str],
        transcript: str,
        correct_words: List[str],
        score: float,
        is_correct: bool,
        confidence: float,
        notes: str
    ):
        """Add an evaluation result and send it to the client"""
        # Guard: Only allow evaluation for trials 1 and 2, and only once per trial
        if trial_number not in [1, 2]:
            print(f"⚠️ Backend: Invalid trial number for evaluation: {trial_number}")
            return
        
        if trial_number in self.evaluated_trials:
            print(f"⚠️ Backend: Trial {trial_number} already evaluated, skipping duplicate")
            return
        
        # Mark this trial as evaluated
        self.evaluated_trials.add(trial_number)
        
        result = EvaluationResult(
            trial_number=trial_number,
            words=words,
            transcript=transcript,
            correct_words=correct_words,
            score=score,
            is_correct=is_correct,
            confidence=confidence,
            notes=notes
        )
        # Use base class method to store result
        super().add_evaluation_result(result)
        
        # Send individual result to client using base class method
        await self.send_evaluation_result(result)
        print(f"📊 Backend: Sent evaluation result for trial {trial_number} (total evaluated: {len(self.evaluated_trials)})")
    
    async def _send_completion(self):
        """Send completion message and all results"""
        # Guard against duplicate completion messages
        if self.completion_sent:
            print("⚠️ Backend: Completion already sent, skipping duplicate")
            return
        
        self.completion_sent = True
        
        # Send state transition for completion playing (with message text)
        completion_text = WORKING_MEMORY_SCRIPT["completion"]
        await self._send_state_transition("completion_playing", trial_number=None, message=completion_text)
        await asyncio.sleep(0.1)  # Brief delay for UI update
        
        # Send completion audio and wait for audio_complete signal
        await self.send_tts_audio(completion_text, trial_number=None)
        # send_tts_audio now waits for audio_complete internally
        
        # Send state transition for complete
        await self._send_state_transition("complete", trial_number=None)
        
        # Use base class method to send all results
        await self.send_all_results()

