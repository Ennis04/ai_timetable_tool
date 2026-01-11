import google.generativeai as genai
import os
from dotenv import load_dotenv

load_dotenv()
api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")

if not api_key:
    print("❌ Error: No API Key found.")
else:
    genai.configure(api_key=api_key)
    print("SEARCHING for available models...")
    try:
        count = 0
        for m in genai.list_models():
            if 'generateContent' in m.supported_generation_methods:
                print(f"✅ FOUND: {m.name}")
                count += 1
        if count == 0:
            print("❌ No models found. Your API Key might be invalid or inactive.")
    except Exception as e:
        print(f"❌ Error connecting to Google: {e}")