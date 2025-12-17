from typing import Literal, Union, Optional, List
from pydantic import BaseModel


# Client → Backend Messages
class AudioChunk(BaseModel):
    audio: str  # base64 encoded PCM
    sample_rate: int  # 16000
    format: str  # "pcm_16bit_mono"


class Event(BaseModel):
    action: Literal["start_task", "end_session", "audio_complete"]


class ClientMessage(BaseModel):
    type: Literal["audio_chunk", "event"]
    data: Union[AudioChunk, Event]


# Backend → Client Messages
class TTSMessage(BaseModel):
    audio: str  # base64-encoded audio bytes (as string for JSON)
    trial_number: Optional[int] = None  # Trial number (0 for instruction, 1-2 for trials)


class TaskState(BaseModel):
    state: Literal["listening", "complete"]
    trial_number: Optional[int] = None
    message: Optional[str] = None  # Optional UI message


class StateTransition(BaseModel):
    """Explicit state transition message for Working Memory task"""
    phase: Literal[
        "instruction_display",  # Show instruction text
        "instruction_playing",  # Playing instruction audio
        "trial_intro_playing",  # Playing trial 2 intro (trial 2 only)
        "words_displaying",  # Displaying words on screen
        "words_playing",  # Playing words audio
        "prompt_playing",  # Playing "Now you repeat them" prompt
        "beep_start",  # Play start beep
        "recording",  # Recording user response
        "beep_end",  # Play end beep
        "recording_complete",  # Recording finished, waiting for upload
        "completion_playing",  # Playing completion audio
        "complete"  # Task is complete
    ]
    trial_number: Optional[int] = None  # Trial number (0 for instruction, 1-2 for trials)
    message: Optional[str] = None  # Optional message for UI


class DebugMessage(BaseModel):
    message: str


class WordDisplayMessage(BaseModel):
    word: str  # Word to display
    trial_number: int  # Which trial
    word_index: int  # Position in sequence: 1-5


class EvaluationResult(BaseModel):
    trial_number: int
    # Abstraction task fields (optional for Working Memory)
    word1: Optional[str] = None
    word2: Optional[str] = None
    category: Optional[str] = None
    # Working Memory task fields (optional for Abstraction)
    words: Optional[List[str]] = None  # Expected words for trial
    correct_words: Optional[List[str]] = None  # Correctly recalled words in order
    score: Optional[float] = None  # Fraction: correct_words / total_words
    # Common fields
    transcript: str
    is_correct: bool
    confidence: float
    notes: str


class ServerMessage(BaseModel):
    type: Literal["tts_text", "tts_audio", "task_state", "debug", "evaluation_result", "all_results", "word_display", "state_transition"]
    data: Union[TTSMessage, TaskState, DebugMessage, EvaluationResult, list[EvaluationResult], WordDisplayMessage, StateTransition]

