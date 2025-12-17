# Cognitive Assessment Backend

Backend server for controlling cognitive assessment tasks via WebSocket.

## Setup

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Create `.env` file from `.env.example`:
```bash
cp .env.example .env
```

3. Add your API keys to `.env`:
```
OPENAI_API_KEY=your_openai_api_key_here
ELEVENLABS_API_KEY=your_elevenlabs_api_key_here
```

**Required API Keys:**
- `OPENAI_API_KEY`: Used for speech-to-text (Whisper) and LLM evaluation
- `ELEVENLABS_API_KEY`: Used for text-to-speech generation

**Optional:**
- `ELEVENLABS_VOICE_ID`: Custom voice ID (defaults to Rachel voice)

## Running

Start the server:
```bash
python main.py
```

Or with uvicorn directly:
```bash
uvicorn main:app --host localhost --port 8000
```

The server will be available at `ws://localhost:8000/ws/abstraction-session`

## Testing

You can test the WebSocket connection using a tool like `websocat`:
```bash
websocat ws://localhost:8000/ws/abstraction-session
```

## Architecture

- `main.py`: FastAPI app with WebSocket endpoint
- `websocket/abstraction_handler.py`: Handles Abstraction task flow
- `services/stt_service.py`: Speech-to-text service
- `services/llm_service.py`: LLM decision engine
- `services/tts_service.py`: Text-to-speech service (optional)
- `models/messages.py`: WebSocket message schemas

