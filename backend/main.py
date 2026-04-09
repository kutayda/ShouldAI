from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from google import genai
from google.genai import types as genai_types 
import json
import os
import time
import requests
from dotenv import load_dotenv

# .env dosyasını zorla bulmasını sağlıyoruz
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), ".env"))

client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))

app = FastAPI(title="ShouldAI API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class SingleUserRequest(BaseModel):
    preference: str
    time_limit_mins: int
    current_lat: float = None
    current_lng: float = None

# --- 1. TEKLİ ÖNERİ SİSTEMİ (DÜZELTİLDİ) ---
@app.post("/api/single_recommendation")
def get_single_recommendation(request: SingleUserRequest):
    # Promptu biraz daha netleştirdik
    prompt = f"""
    Sen Ankara'da bir yerel rehbersin. 
    Kullanıcı Koordinatı: [{request.current_lat}, {request.current_lng}]
    İsteği: {request.preference} ({request.time_limit_mins} dakika mesafede olmalı)
    
    Görev: Ankara sokaklarını analiz et ve bu koordinata yakın en iyi mekanı bul.
    Mekanın gerçek koordinatlarını (lat, lng) tam ver.
    Yanıtı SADECE bu JSON formatında döndür:
    {{
      "status": "success",
      "mekan_adi": "Mekan Adı", 
      "puan": "4.9", 
      "lat": 39.9, 
      "lng": 32.8,
      "kisa_ozet": "Özet metin.", 
      "sebep": "Neden burası seçildi?"
    }}
    """
    
    # Hatalara karşı 3 deneme mekanizması
    for deneme in range(3):
        try:
            response = client.models.generate_content(
                model='gemini-2.0-flash', # DOĞRU MODEL ADI BUDUR
                contents=prompt,
                config=genai_types.GenerateContentConfig(response_mime_type="application/json"),
            )
            # Dönen cevabı temizce alalım
            ai_data = json.loads(response.text)
            print(f"✅ Öneri Başarılı: {ai_data.get('mekan_adi')}")
            return ai_data
            
        except Exception as e:
            # HATA DEDEKTİFİ: Terminale hatayı basar ki ne olduğunu anlayalım
            print(f"💥 AI DENEME {deneme+1} HATASI: {e}")
            if deneme < 2:
                time.sleep(3) # 3 saniye bekle ve tekrar dene
                continue
            return {"status": "error", "message": f"Yapay zeka hatası: {str(e)}"}

# --- 2. NAVİGASYON VE ADRES SORGULAMA ---
@app.get("/api/get_route")
def get_route(origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float):
    route_url = f"http://router.project-osrm.org/route/v1/driving/{origin_lng},{origin_lat};{dest_lng},{dest_lat}?overview=full&geometries=geojson"
    address_url = f"https://nominatim.openstreetmap.org/reverse?lat={dest_lat}&lon={dest_lng}&format=json"
    headers = {'User-Agent': 'ShouldAI_App'}

    try:
        route_res = requests.get(route_url).json()
        addr_res = requests.get(address_url, headers=headers).json()
        
        # Adres ayıklama
        address_full = addr_res.get("display_name", "Bilinmeyen Adres")
        address_parts = address_full.split(",")
        address_text = ", ".join(address_parts[0:2]) if len(address_parts) > 1 else address_full

        if route_res["code"] == "Ok":
            route = route_res["routes"][0]
            coordinates = route["geometry"]["coordinates"]
            points = [[p[1], p[0]] for p in coordinates]
            distance_km = round(route["distance"] / 1000, 1)
            duration_min = round(route["duration"] / 60)
            
            return {
                "status": "success", 
                "points": points,
                "distance": f"{distance_km} km",
                "duration": f"{duration_min} dk",
                "address": address_text
            }
    except Exception as e:
        print(f"🚗 Rota Hatası: {e}")
    
    return {"status": "error", "points": [], "distance": "0 km", "duration": "0 dk", "address": "Adres bulunamadı"}

# --- 3. GRUP ÖNERİSİ ---
class UserData(BaseModel):
    name: str
    location: str
    preference: str
    has_car: bool = False

class GroupRequest(BaseModel):
    users: list[UserData]
    current_lat: float = None
    current_lng: float = None

@app.post("/api/get_recommendation")
def get_recommendation(request: GroupRequest):
    return {"status": "success", "mekan_adi": "Örnek Grup Mekanı", "puan": "4.5", "sebep": "Ortak nokta."}