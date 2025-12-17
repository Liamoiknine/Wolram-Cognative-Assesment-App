from fastapi import FastAPI, WebSocket, WebSocketDisconnect, UploadFile, File, Form
from fastapi.responses import JSONResponse
import sys
from pathlib import Path
import uuid
import asyncio
from typing import TYPE_CHECKING

# Add backend to path for imports
backend_path = Path(__file__).parent
sys.path.insert(0, str(backend_path))

import uvicorn
import os
from dotenv import load_dotenv

load_dotenv()

# Type checking imports
if TYPE_CHECKING:
    from websocket.abstraction_handler import AbstractionTaskHandler
    from websocket.working_memory_handler import WorkingMemoryTaskHandler

app = FastAPI(title="Cognitive Assessment Backend")

# Store active WebSocket handlers by session ID
active_abstraction_handlers: dict[str, 'AbstractionTaskHandler'] = {}
active_working_memory_handlers: dict[str, 'WorkingMemoryTaskHandler'] = {}


@app.get("/")
async def root():
    return {
        "message": "Cognitive Assessment Backend API",
        "handler_mode": "scripted"
    }


@app.get("/health")
async def health():
    return {"status": "healthy"}


@app.websocket("/ws/abstraction-session")
async def websocket_abstraction(websocket: WebSocket):
    """WebSocket endpoint for Abstraction task"""
    from websocket.abstraction_handler import AbstractionTaskHandler
    print("🚀 Using SCRIPTED handler (ElevenLabs TTS, deterministic flow)")
    
    # Generate session ID
    session_id = str(uuid.uuid4())
    
    handler = AbstractionTaskHandler(websocket, session_id)
    active_abstraction_handlers[session_id] = handler
    
    try:
        await handler.handle_connection()
    finally:
        # Clean up handler when connection closes
        if session_id in active_abstraction_handlers:
            del active_abstraction_handlers[session_id]
        print(f"🧹 Cleaned up handler for session {session_id}")


@app.post("/abstraction/upload_audio")
async def upload_abstraction_audio(
    audio: UploadFile = File(...),
    trial_number: int = Form(...),
    session_id: str = Form(...)
):
    """
    HTTP endpoint for uploading recorded audio.
    Reads audio, sends next trial immediately, then processes in background.
    Returns quickly after reading audio (before processing).
    """
    try:
        # Get handler for this session
        handler = active_abstraction_handlers.get(session_id)
        if not handler:
            return JSONResponse(
                status_code=404,
                content={"status": "error", "message": "Session not found"}
            )
        
        # Read audio bytes FIRST (must happen before response is returned, or file closes)
        # For trial 0 (instruction), audio_bytes will be empty, which is fine
        audio_bytes = await audio.read()
        
        # Delegate to handler's upload handling method (determines next trial/completion)
        asyncio.create_task(handler._handle_audio_upload(trial_number, audio_bytes))
        
        # Process audio in background (transcribe + evaluate)
        # This runs independently after response is returned
        asyncio.create_task(_process_audio_async(
            audio_bytes, trial_number, session_id, handler
        ))
        
        # Return success immediately after reading audio
        # Next trial audio and processing happen in background
        return JSONResponse(content={"status": "success"})
        
    except Exception as e:
        print(f"❌ Error uploading audio: {e}")
        import traceback
        traceback.print_exc()
        return JSONResponse(
            status_code=500,
            content={"status": "error", "message": str(e)}
        )




async def _process_audio_async(
    audio_bytes: bytes,
    trial_number: int,
    session_id: str,
    handler: 'AbstractionTaskHandler'
):
    """Process audio: evaluate in background (next trial already sent)"""
    from websocket.abstraction_handler import ABSTRACTION_SCRIPT
    
    try:
        # Handle instruction phase (trial_number = 0) - no audio to process
        if trial_number == 0:
            print(f"📝 Session {session_id}: Instruction phase complete")
            return
        
        # Process the audio in background (transcribe → evaluate → log)
        # Next trial audio was already sent immediately in upload endpoint
        asyncio.create_task(_evaluate_audio_background(
            audio_bytes, trial_number, session_id, handler
        ))
            
    except Exception as e:
        print(f"❌ Error processing audio asynchronously: {e}")
        import traceback
        traceback.print_exc()


async def _evaluate_audio_background(
    audio_bytes: bytes,
    trial_number: int,
    session_id: str,
    handler: 'AbstractionTaskHandler'
):
    """Evaluate audio in background: transcribe → evaluate → send result"""
    from services.stt_service import STTService
    from services.llm_service import LLMService
    from websocket.abstraction_handler import ABSTRACTION_SCRIPT
    
    try:
        # Transcribe the audio
        stt_service = STTService()
        transcript = await stt_service.transcribe_audio(audio_bytes)
        
        # Log transcript (or indicate silence)
        if transcript:
            print(f"📝 Session {session_id}, Trial {trial_number}: Transcript: {transcript}")
        else:
            print(f"🔇 Session {session_id}, Trial {trial_number}: No speech detected (silent)")
        
        # Get trial words
        if trial_number > 0 and trial_number <= len(ABSTRACTION_SCRIPT["trials"]):
            trial = ABSTRACTION_SCRIPT["trials"][trial_number - 1]
            word1 = trial["word1"]
            word2 = trial["word2"]
            
            # Evaluate with LLM
            llm_service = LLMService()
            evaluation = await llm_service.evaluate_abstraction_response(
                word1, word2, transcript
            )
            
            # Log results server-side
            print(f"📊 Session {session_id}, Trial {trial_number} Evaluation:")
            print(f"   Category: {evaluation['category']}")
            print(f"   Correct: {evaluation['is_correct']}")
            print(f"   Confidence: {evaluation['confidence']}")
            print(f"   Notes: {evaluation['notes']}")
            
            # Store and send result to client
            await handler.add_evaluation_result(
                trial_number=trial_number,
                word1=word1,
                word2=word2,
                transcript=transcript,
                category=evaluation['category'],
                is_correct=evaluation['is_correct'],
                confidence=evaluation['confidence'],
                notes=evaluation['notes']
            )
    except Exception as e:
        print(f"❌ Error evaluating audio in background: {e}")
        import traceback
        traceback.print_exc()


@app.websocket("/ws/working-memory-session")
async def websocket_working_memory(websocket: WebSocket):
    """WebSocket endpoint for Working Memory task"""
    from websocket.working_memory_handler import WorkingMemoryTaskHandler
    print("🚀 Using SCRIPTED handler for Working Memory (ElevenLabs TTS, deterministic flow)")
    
    # Generate session ID
    session_id = str(uuid.uuid4())
    
    handler = WorkingMemoryTaskHandler(websocket, session_id)
    active_working_memory_handlers[session_id] = handler
    
    try:
        await handler.handle_connection()
    finally:
        # Clean up handler when connection closes
        if session_id in active_working_memory_handlers:
            del active_working_memory_handlers[session_id]
        print(f"🧹 Cleaned up handler for session {session_id}")


@app.post("/working_memory/upload_audio")
async def upload_working_memory_audio(
    audio: UploadFile = File(...),
    trial_number: int = Form(...),
    session_id: str = Form(...)
):
    """
    HTTP endpoint for uploading recorded audio for Working Memory task.
    Reads audio, sends next trial immediately, then processes in background.
    Returns quickly after reading audio (before processing).
    """
    try:
        # Get handler for this session
        handler = active_working_memory_handlers.get(session_id)
        if not handler:
            return JSONResponse(
                status_code=404,
                content={"status": "error", "message": "Session not found"}
            )
        
        # Read audio bytes FIRST (must happen before response is returned, or file closes)
        # For trial 0 (instruction), audio_bytes will be empty, which is fine
        audio_bytes = await audio.read()
        
        # Delegate to handler's upload handling method (determines next trial/completion)
        asyncio.create_task(handler._handle_audio_upload(trial_number, audio_bytes))
        
        # Process audio in background (transcribe + evaluate)
        # This runs independently after response is returned
        asyncio.create_task(_process_working_memory_audio_async(
            audio_bytes, trial_number, session_id, handler
        ))
        
        # Return success immediately after reading audio
        # Next trial audio and processing happen in background
        return JSONResponse(content={"status": "success"})
        
    except Exception as e:
        print(f"❌ Error uploading audio: {e}")
        import traceback
        traceback.print_exc()
        return JSONResponse(
            status_code=500,
            content={"status": "error", "message": str(e)}
        )


async def _process_working_memory_audio_async(
    audio_bytes: bytes,
    trial_number: int,
    session_id: str,
    handler: 'WorkingMemoryTaskHandler'
):
    """Process audio: evaluate in background (next trial already sent)"""
    try:
        # Handle instruction phase (trial_number = 0) - no audio to process
        if trial_number == 0:
            print(f"📝 Session {session_id}: Instruction phase complete")
            return
        
        # Process the audio in background (transcribe → evaluate → log)
        # Next trial audio was already sent immediately in upload endpoint
        asyncio.create_task(_evaluate_working_memory_audio_background(
            audio_bytes, trial_number, session_id, handler
        ))
            
    except Exception as e:
        print(f"❌ Error processing audio asynchronously: {e}")
        import traceback
        traceback.print_exc()


async def _evaluate_working_memory_audio_background(
    audio_bytes: bytes,
    trial_number: int,
    session_id: str,
    handler: 'WorkingMemoryTaskHandler'
):
    """Evaluate audio in background: transcribe → evaluate → send result"""
    from services.stt_service import STTService
    from services.llm_service import LLMService
    
    try:
        # Guard: Only evaluate trials 1 and 2, and only once per trial
        if trial_number not in [1, 2]:
            print(f"⚠️ Session {session_id}: Skipping LLM evaluation for invalid trial number: {trial_number}")
            return
        
        if trial_number in handler.evaluated_trials:
            print(f"⚠️ Session {session_id}: Trial {trial_number} already evaluated, skipping duplicate LLM call")
            return
        
        # Transcribe the audio
        stt_service = STTService()
        transcript = await stt_service.transcribe_audio(audio_bytes)
        
        # Log transcript (or indicate silence)
        if transcript:
            print(f"📝 Session {session_id}, Trial {trial_number}: Transcript: {transcript}")
        else:
            print(f"🔇 Session {session_id}, Trial {trial_number}: No speech detected (silent)")
        
        # Get trial words
        if trial_number > 0 and trial_number <= len(handler.trial_words):
            words = handler.trial_words[trial_number - 1]
            
            # Evaluate with LLM (only if not already evaluated)
            if trial_number not in handler.evaluated_trials:
                llm_service = LLMService()
                evaluation = await llm_service.evaluate_working_memory_response(
                    words, transcript
                )
                
                # Log results server-side
                print(f"📊 Session {session_id}, Trial {trial_number} Evaluation:")
                print(f"   Correct words: {evaluation['correct_words']}")
                print(f"   Score: {evaluation['score']}")
                print(f"   Correct: {evaluation['is_correct']}")
                print(f"   Confidence: {evaluation['confidence']}")
                print(f"   Notes: {evaluation['notes']}")
                
                # Store and send result to client (add_evaluation_result has its own guard)
                await handler.add_evaluation_result(
                    trial_number=trial_number,
                    words=words,
                    transcript=transcript,
                    correct_words=evaluation['correct_words'],
                    score=evaluation['score'],
                    is_correct=evaluation['is_correct'],
                    confidence=evaluation['confidence'],
                    notes=evaluation['notes']
                )
            else:
                print(f"⚠️ Session {session_id}: Trial {trial_number} evaluation skipped (already in progress or completed)")
    except Exception as e:
        print(f"❌ Error evaluating audio in background: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    host = os.getenv("BACKEND_HOST", "localhost")
    port = int(os.getenv("BACKEND_PORT", 8000))
    uvicorn.run(app, host=host, port=port)

