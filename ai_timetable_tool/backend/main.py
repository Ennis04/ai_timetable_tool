import uvicorn
import os
import json
from fastapi import FastAPI
from pydantic import BaseModel
from datetime import datetime
from dotenv import load_dotenv

# --- CHANGE: Import the Standard SDK ---
import google.generativeai as genai

# 1. Load the API Key
load_dotenv()
api_key = os.getenv("GOOGLE_API_KEY")

if not api_key:
    print("❌ ERROR: GOOGLE_API_KEY not found in .env file!")
else:
    # --- CHANGE: Configure the Standard SDK ---
    genai.configure(api_key=api_key)

app = FastAPI()

class Prompt(BaseModel):
    text: str

def extract_json(text: str) -> str:
    """Helper to find JSON inside the AI's response"""
    try:
        # Find the first '{' and the last '}'
        start = text.find('{')
        end = text.rfind('}') + 1
        if start != -1 and end != -1:
            return text[start:end]
        return text
    except Exception:
        return text

@app.post("/ai/parse")
async def parse_prompt(prompt: Prompt):
    print(f"\n📩 User said: {prompt.text}")

    now = datetime.now()
    # Format date clearly so AI knows "next monday"
    current_time_str = now.strftime("%Y-%m-%d %H:%M:%S")
    
    system_instruction = f"""
    You are a scheduling assistant. Today is {current_time_str}.
    
    Instructions:
    1. Analyze the user's request.
    2. Return a valid JSON object with an 'actions' list.
    3. Do NOT use Markdown (no ```json).
    
    JSON Schema:
    {{
      "actions": [
        {{
          "type": "create",
          "title": "Event Title",
          "start": "YYYY-MM-DDTHH:MM:SS",
          "end": "YYYY-MM-DDTHH:MM:SS",
          "location": "Location (optional)",
          "repeat": "none" | "daily" | "weekly",
          "count": 1
        }}
      ]
    }}
    """

    try:
        # --- CHANGE: Use the GenerativeModel class ---
        # "gemini-1.5-flash" is the stable, fast, free-tier friendly model
        # Use the standard "gemini-pro" model which is available to everyone
        model = genai.GenerativeModel('gemini-2.5-flash')
        
        response = model.generate_content(
            f"{system_instruction}\n\nUser Request: {prompt.text}"
        )
        
        raw_text = response.text
        print(f"🤖 AI Raw Output: {raw_text}") 

        # Clean and Parse
        cleaned_text = extract_json(raw_text)
        parsed_json = json.loads(cleaned_text)
        
        print("✅ Parsed successfully!")
        return parsed_json

    except Exception as e:
        print(f"❌ SERVER ERROR: {e}")
        return {"error": str(e), "actions": []}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)