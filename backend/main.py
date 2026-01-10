import os, json
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from google import genai
from datetime import datetime
from zoneinfo import ZoneInfo

load_dotenv()

app = FastAPI()

class CommandRequest(BaseModel):
    text: str

SYSTEM_PROMPT = """
You are a calendar assistant.

Convert the user's instruction into STRICT JSON ONLY (no markdown, no explanation).

Return exactly this shape:
{
  "actions": [
    {
      "type": "create",
      "title": "string",
      "start": "ISO8601 datetime with timezone offset",
      "end": "ISO8601 datetime with timezone offset",
      "location": "string",
      "repeat": "none|daily|weekly",
      "count": 1
    }
  ]
}

Rules:
- Use Asia/Kuala_Lumpur timezone.
- Interpret relative dates like "today", "tomorrow", "next Monday" using the provided current datetime.
- If end time missing, assume 1 hour duration.
- If location missing, use empty string.
- If repeat missing, use "none".
- If count missing, use 1.
- Only return JSON.
"""

@app.post("/ai/parse")
def parse_command(req: CommandRequest):
    try:
        key = os.getenv("GEMINI_API_KEY")
        if not key:
            raise HTTPException(status_code=500, detail="GEMINI_API_KEY not set in .env")

        client = genai.Client(api_key=key)

        now = datetime.now(ZoneInfo("Asia/Kuala_Lumpur"))
        context = f"Current datetime is {now.isoformat()} (Asia/Kuala_Lumpur)."

        resp = client.models.generate_content(
            model="models/gemini-flash-latest",
            contents=context + "\n\n" + SYSTEM_PROMPT + "\n\nUser: " + req.text,
            config={
                "temperature": 0.2,
                "response_mime_type": "application/json",
            },
        )

        text = (resp.text or "").strip()
        data = json.loads(text)

        if "actions" not in data or not isinstance(data["actions"], list):
            raise ValueError("Missing 'actions' list in JSON output")

        return data

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Gemini parse failed: {e}")
