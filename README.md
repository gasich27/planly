<<<<<<< HEAD
# PLANLY (AI Planner)
=======
# PLANLY
>>>>>>> 43eaff1 (total update)

AI-first planner with a FastAPI/Ollama backend and Flutter client for Android and iOS.

## Requirements

- Python 3.11+
- Flutter 3.22+
- Ollama
- An Ollama model stored in `D:/Ollama/Models`

## Ollama

Set the model directory once, restart Ollama, and download the default model:

```powershell
[Environment]::SetEnvironmentVariable("OLLAMA_MODELS", "D:\Ollama\Models", "User")
ollama pull qwen2.5:7b
```

Ollama must be running while the backend generates or edits plans. LM Studio and OpenAI-compatible endpoints are not used.

## Backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python api.py
```

The API listens on `http://0.0.0.0:8000`. Swagger is available at `http://127.0.0.1:8000/docs`.

Optional `backend/.env` values:

```env
OLLAMA_BASE_URL=http://127.0.0.1:11434
OLLAMA_MODEL=qwen2.5:7b
OLLAMA_MODELS=D:/Ollama/Models
WHISPER_MODEL=base
WHISPER_LANGUAGE=ru
DB_PATH=planner.db
```

## Mobile

Set the backend address in `mobile/lib/config/api_config.dart`. For a physical phone, use the PC address in the same Wi-Fi network.

```powershell
cd mobile
flutter pub get
flutter run
```

Useful checks:

```powershell
flutter analyze --no-fatal-infos
flutter test
```

Android permits local cleartext HTTP for development. iOS includes microphone and local HTTP permissions. Use HTTPS and restrictive network policies before production distribution.
