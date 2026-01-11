import os
import json
import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from google import genai
from datetime import datetime
from zoneinfo import ZoneInfo
from typing import Optional

# 1. Load API Key
load_dotenv()
# The outer one used GEMINI_API_KEY, the inner one used GOOGLE_API_KEY. 
# We'll support both for compatibility, prioritizing GEMINI_API_KEY.
api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")

if not api_key:
    print("❌ ERROR: GEMINI_API_KEY or GOOGLE_API_KEY not found in .env!")

app = FastAPI()

# 2. Update Model to accept Image
class Prompt(BaseModel):
    text: str
    image: Optional[str] = None # Base64 string

SYSTEM_PROMPT = """
You are a scheduling assistant. 

Instructions:
1. Analyze the user's request AND any provided image (e.g., a flyer or timetable).
2. Extract all event details (Title, Start Time, End Time, Location).
3. Return a valid JSON object with an 'actions' list.
4. Do NOT use Markdown or explanations. Return ONLY the JSON.

JSON Schema:
{
  "actions": [
    {
      "type": "create",
      "title": "string",
      "start": "ISO8601 datetime (YYYY-MM-DDTHH:MM:SS)",
      "end": "ISO8601 datetime (YYYY-MM-DDTHH:MM:SS)",
      "location": "string",
      "repeat": "none|daily|weekly",
      "count": 1
    }
  ]
}

Rules:
- Use Asia/Kuala_Lumpur timezone.
- Interpret relative dates (e.g., "today", "tomorrow", "next Monday") using the provided current datetime.
- If end time missing, assume 1 hour duration.
- If location missing, use empty string.
- If repeat missing, use "none".
- If count missing, use 1.
"""

@app.post("/ai/parse")
def parse_prompt(prompt: Prompt):
    try:
        if not api_key:
            raise HTTPException(status_code=500, detail="API Key not configured")

        client = genai.Client(api_key=api_key)

        now = datetime.now(ZoneInfo("Asia/Kuala_Lumpur"))
        context = f"Current datetime is {now.isoformat()} (Asia/Kuala_Lumpur)."

        content_parts = [context + "\n\n" + SYSTEM_PROMPT + "\n\nUser Request: " + prompt.text]
        
        # If there is an image, add it to the prompt
        if prompt.image:
            image_part = {
                "mime_type": "image/jpeg",
                "data": prompt.image
            }
            content_parts.append(image_part)

        resp = client.models.generate_content(
            model="gemini-2.5-flash", # Using the latest recommended model
            contents=content_parts,
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
        print(f"❌ SERVER ERROR: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)