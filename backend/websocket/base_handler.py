"""
Base Task Handler - Abstract base class for all backend-controlled tasks

Provides common WebSocket infrastructure while allowing full customization
of task-specific scripts, LLM evaluation prompts, and flow logic.
"""
import asyncio
import base64
import json
from abc import ABC, abstractmethod
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


class BaseTaskHandler(ABC):
    """Abstract base class for backend-controlled task handlers"""
    
    def __init__(self, websocket: WebSocket, session_id: str):
        self.websocket = websocket
        self.session_id = session_id
        self.tts_service = TTSService()
        
        # Task state (can be customized by subclasses)
        self.current_phase = "waiting"
        self.evaluation_results: list[EvaluationResult] = []
    
    async def handle_connection(self):
        """Main connection handler - handles WebSocket lifecycle and message routing"""
        await self.websocket.accept()
        await self.send_debug(f"Connected to task (Session: {self.session_id})")
        
        # Send session ID to client so it can include it in uploads
        await self.send_debug(f"Session ID: {self.session_id}")
        
        await self.send_task_state("listening", None, "Waiting to start...")
        
        # Wait for start_task event before beginning
        task_started = False
        
        # Main message loop
        try:
            while True:
                data = await self.websocket.receive_text()
                message = json.loads(data)
                client_msg = ClientMessage(**message)
                
                # Handle events
                if client_msg.type == "event":
                    from models.messages import Event
                    event = client_msg.data
                    if isinstance(event, Event):
                        if event.action == "start_task":
                            if not task_started:
                                task_started = True
                                await self.send_debug("Task start received, beginning scripted flow...")
                                await self._start_task()
                                continue
                        
                        elif event.action == "end_session":
                            await self.send_debug("Session ended by client")
                            break
                        
                        elif event.action == "audio_complete":
                            # Delegate to subclass to handle audio_complete
                            await self._handle_audio_complete()
                            continue
                    
        except WebSocketDisconnect:
            print("Client disconnected normally")
        except Exception as e:
            print(f"WebSocket error: {e}")
            import traceback
            traceback.print_exc()
            try:
                await self.send_debug(f"Error: {e}")
            except:
                pass
        finally:
            try:
                await self.websocket.close()
            except:
                pass
    
    # Abstract methods - must be implemented by subclasses
    
    @abstractmethod
    async def _start_task(self):
        """Start the task-specific flow. Called when start_task event is received."""
        pass
    
    @abstractmethod
    async def _handle_audio_upload(self, trial_number: int, audio_bytes: bytes):
        """
        Handle audio upload. Called from HTTP upload endpoint.
        
        Args:
            trial_number: The trial number (0 for instruction, 1+ for actual trials)
            audio_bytes: The uploaded audio data (empty for trial 0)
        
        Should:
        - Determine next phase/trial based on task logic
        - Send next TTS audio if needed
        - Trigger completion if task is done
        """
        pass
    
    async def _handle_audio_complete(self):
        """
        Handle audio_complete event from client.
        Default implementation: signal the audio_complete_event if waiting.
        Subclasses can override for custom behavior.
        """
        if hasattr(self, 'audio_complete_event'):
            self.audio_complete_event.set()
            if hasattr(self, 'waiting_for_audio_complete'):
                self.waiting_for_audio_complete = False
    
    # Concrete helper methods - shared across all tasks
    
    async def send_tts_audio(self, text: str, trial_number: Optional[int] = None):
        """
        Generate TTS audio and send to client.
        
        Args:
            text: Text to convert to speech
            trial_number: Optional trial number (0 for instruction, 1+ for trials)
        """
        try:
            audio_bytes = self.tts_service.generate_audio(text)
            audio_base64 = base64.b64encode(audio_bytes).decode('utf-8')
            
            message = ServerMessage(
                type="tts_audio",
                data=TTSMessage(audio=audio_base64, trial_number=trial_number)
            )
            await self.websocket.send_text(message.model_dump_json())
        except Exception as e:
            print(f"Error sending TTS audio: {e}")
            import traceback
            traceback.print_exc()
    
    async def send_task_state(self, state: str, trial_number: Optional[int], message: Optional[str] = None):
        """Send task state update to client"""
        try:
            task_state = TaskState(
                state=state,
                trial_number=trial_number,
                message=message
            )
            server_msg = ServerMessage(
                type="task_state",
                data=task_state
            )
            await self.websocket.send_text(server_msg.model_dump_json())
        except Exception as e:
            print(f"Error sending task state: {e}")
    
    async def send_debug(self, message: str):
        """Send debug message to client"""
        try:
            debug_msg = ServerMessage(
                type="debug",
                data=DebugMessage(message=message)
            )
            await self.websocket.send_text(debug_msg.model_dump_json())
        except Exception as e:
            print(f"Error sending debug: {e}")
    
    async def send_evaluation_result(self, result: EvaluationResult):
        """Send individual evaluation result to client"""
        try:
            server_msg = ServerMessage(
                type="evaluation_result",
                data=result
            )
            await self.websocket.send_text(server_msg.model_dump_json())
        except Exception as e:
            print(f"Error sending evaluation result: {e}")
    
    async def send_all_results(self):
        """Send all evaluation results and completion message"""
        self.current_phase = "complete"
        await self.send_task_state("complete", None, "Task completed!")
        
        try:
            server_msg = ServerMessage(
                type="all_results",
                data=self.evaluation_results
            )
            await self.websocket.send_text(server_msg.model_dump_json())
            print(f"📊 Backend: Sent all {len(self.evaluation_results)} evaluation results")
        except Exception as e:
            print(f"Error sending all results: {e}")
        
        print("✅ Backend: Task completed")
    
    def add_evaluation_result(self, result: EvaluationResult):
        """Store an evaluation result (does not send to client)"""
        self.evaluation_results.append(result)

