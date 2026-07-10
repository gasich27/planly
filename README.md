# AI Planner

Minimal backend for turning text or audio into a structured task plan.

## Project

- `backend/main.py` - CLI entry point
- `backend/api.py` - FastAPI server
- `backend/core/` - planning, speech-to-text, database and export logic

The Flutter/mobile UI is intentionally ignored by Git.

## Setup

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Optional `.env` values:

```env
OPENAI_API_BASE=http://127.0.0.1:1234/v1
OPENAI_API_KEY=dummy
WHISPER_MODEL=base
WHISPER_LANGUAGE=ru
DB_PATH=planner.db
```

## Usage

Run CLI:

```powershell
python main.py process path\to\audio.mp3 --period day
python main.py list
python main.py show 1
```

Run API:

```powershell
python api.py
```

API will start on `http://127.0.0.1:8000`.
