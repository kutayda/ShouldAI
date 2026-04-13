from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import os
import requests
from dotenv import load_dotenv

# .env dosyasını zorla bulmasını sağlıyoruz
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), ".env"))

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

# --- 1. TEKLİ ÖNERİ SİSTEMİ (SUNUM İÇİN DUMMY VERİ) ---
@app.post("/api/single_recommendation")
def get_single_recommendation(request: SingleUserRequest):
    # Kullanıcının girdisini küçük harfe çeviriyoruz (Büyük/Küçük harf duyarsız)
    pref = request.preference.lower()

    # DUMMY VERİ MANTIĞI
    if "hamburger" in pref:
        return {
            "status": "success",
            "mekan_adi": "Burger King - Maltepe",
            "puan": "4.2",
            "lat": 39.9272,
            "lng": 32.8465,
            "kisa_ozet": "Hızlı ve doyurucu bir hamburger menüsü.",
            "sebep": "Canın hamburger çektiği için bölgedeki en hızlı ve bilindik seçenek."
        }
    elif "kebap" in pref:
        return {
            "status": "success",
            "mekan_adi": "Düveroğlu - Maltepe",
            "puan": "4.8",
            "lat": 39.9275,
            "lng": 32.8440,
            "kisa_ozet": "Ankara'nın en meşhur kebapçılarından biri.",
            "sebep": "Kaliteli et ve lezzetli mezeler aradığın için en doğru adres."
        }
    elif "döner" in pref:
        return {
            "status": "success",
            "mekan_adi": "Hatayca - Kızılay",
            "puan": "4.5",
            "lat": 39.9212,
            "lng": 32.8540,
            "kisa_ozet": "Bol soslu Antakya usulü dürüm döner.",
            "sebep": "Soslu döner krizine Kızılay'daki en iyi çözüm burası."
        }
    else:
        # Eğer bu üçü dışında bir şey yazılırsa joker bir mekan dönsün (Hata vermesin)
        return {
            "status": "success",
            "mekan_adi": "Gülçimen Aspava - Emek",
            "puan": "4.7",
            "lat": 39.9165,
            "lng": 32.8220,
            "kisa_ozet": "Ankara'nın vazgeçilmez Aspava kültürü.",
            "sebep": "Ne yiyeceğine tam karar veremediğin için ikramı bol garantili bir yer."
        }

# --- 2. NAVİGASYON VE ADRES SORGULAMA (GERÇEK ÇALIŞIYOR) ---
@app.get("/api/get_route")
def get_route(origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float):
    route_url = f"http://router.project-osrm.org/route/v1/driving/{origin_lng},{origin_lat};{dest_lng},{dest_lat}?overview=full&geometries=geojson"
    address_url = f"https://nominatim.openstreetmap.org/reverse?lat={dest_lat}&lon={dest_lng}&format=json"
    headers = {'User-Agent': 'ShouldAI_App'}

    try:
        route_res = requests.get(route_url).json()
        addr_res = requests.get(address_url, headers=headers).json()
        
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