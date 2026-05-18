from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from typing import Dict, Any
import requests
import json
import os
import re
import math
from dotenv import load_dotenv

load_dotenv()
GROQ_API_KEY = os.getenv("GROQ_API_KEY")
GOOGLE_MAPS_API_KEY = os.getenv("GOOGLE_MAPS_API_KEY")

app = FastAPI(title="ShouldAI API - Akıllı Esneme (Fallback) Sürümü")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

ALLOWED_GOOGLE_TYPES = {
    "restaurant", "food", "cafe", "bakery", "meal_takeaway", "meal_delivery", "bar", "pub",
    "lodging", 
    "gas_station" 
}

def calculate_real_distance(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6371.0 
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat / 2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlng / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def decode_google_polyline(polyline_str: str) -> list:
    index, lat, lng = 0, 0, 0
    coordinates = []
    while index < len(polyline_str):
        b, shift, result = 0, 0, 0
        while True:
            b = ord(polyline_str[index]) - 63
            index += 1
            result |= (b & 0x1f) << shift
            shift += 5
            if not (b & 0x20):
                break
        dlat = ~(result >> 1) if (result & 1) else (result >> 1)
        lat += dlat

        shift, result = 0, 0
        while True:
            b = ord(polyline_str[index]) - 63
            index += 1
            result |= (b & 0x1f) << shift
            shift += 5
            if not (b & 0x20):
                break
        dlng = ~(result >> 1) if (result & 1) else (result >> 1)
        lng += dlng
        coordinates.append([lat / 100000.0, lng / 100000.0])
    return coordinates

def fetch_real_places_from_google(lat: float, lng: float, radius_km: float, keyword: str) -> list:
    if not GOOGLE_MAPS_API_KEY:
        return []
        
    radius_meters = int(radius_km * 1000)
    url = f"https://maps.googleapis.com/maps/api/place/nearbysearch/json?location={lat},{lng}&radius={radius_meters}&keyword={keyword}&key={GOOGLE_MAPS_API_KEY}"
    
    try:
        response = requests.get(url)
        if response.status_code == 200:
            results = response.json().get("results", [])
            places_list = []
            for p in results:
                photo_ref = None
                if p.get("photos") and len(p["photos"]) > 0:
                    photo_ref = p["photos"][0].get("photo_reference")

                places_list.append({
                    "name": p.get("name"),
                    "rating": float(p.get("rating", 0.0)),
                    "reviews_count": int(p.get("user_ratings_total", 0)),
                    "lat": p.get("geometry", {}).get("location", {}).get("lat"),
                    "lng": p.get("geometry", {}).get("location", {}).get("lng"),
                    "address": p.get("vicinity"),
                    "photo_reference": photo_ref,
                    "google_types": p.get("types", [])
                })
            return places_list
    except Exception as e:
        print(f"🚨 Google Places Hatası: {e}")
    return []

def ask_llama_to_decide(prompt: str) -> dict:
    if not GROQ_API_KEY:
        return {"status": "error"}

    url = "https://api.groq.com/openai/v1/chat/completions"
    headers = {"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"}
    
    payload = {
        "model": "llama-3.1-8b-instant",
        "messages": [
            {"role": "system", "content": "Sen sadece JSON döndüren bir rotalama asistanısın."},
            {"role": "user", "content": prompt}
        ]
    }
    
    try:
        response = requests.post(url, headers=headers, json=payload)
        response.raise_for_status()
        raw_text = response.json()['choices'][0]['message']['content'].strip()
        match = re.search(r'\{.*\}', raw_text, re.DOTALL)
        if match: return json.loads(match.group(0))
        return json.loads(raw_text)
    except:
        return {"status": "error"}

@app.post("/api/single_recommendation")
@app.post("/api/category_recommendation")
def get_recommendation(request: Dict[str, Any]):
    user_input = request.get("preference", request.get("category", "Restoran")).strip()
    rad_val = request.get("radius_km")
    lat_val = request.get("current_lat")
    lng_val = request.get("current_lng")
    dest_lat = request.get("dest_lat") 
    dest_lng = request.get("dest_lng") 
    
    radius_km_selection = float(rad_val) if rad_val is not None else 2.0
    lat = float(lat_val) if lat_val is not None else 39.92077
    lng = float(lng_val) if lng_val is not None else 32.85411

    # 🚨 ÇÖZÜM 1: Çapı daraltmıyoruz, Flutter ne yolladıysa onu kullanıyoruz.
    search_radius = 25.0 if radius_km_selection >= 50.0 else radius_km_selection 
    google_search_keyword = "aspava" if "aspava" in user_input.lower() else user_input

    raw_places = fetch_real_places_from_google(lat, lng, search_radius, google_search_keyword)
    
    valid_places = []
    strict_forward_places = []
    
    for place in raw_places:
        place_lat = float(place["lat"])
        place_lng = float(place["lng"])
        actual_distance_km = calculate_real_distance(lat, lng, place_lat, place_lng)
        
        if actual_distance_km <= search_radius:
            place_tags = set(place.get("google_types", []))
            if place_tags.intersection(ALLOWED_GOOGLE_TYPES):
                valid_places.append(place)
                
                # 🚨 ÇÖZÜM 2: TERS YÖN AKILLI FİLTRESİ (Fallback destekli)
                if dest_lat is not None and dest_lng is not None:
                    current_to_dest = calculate_real_distance(lat, lng, float(dest_lat), float(dest_lng))
                    place_to_dest = calculate_real_distance(place_lat, place_lng, float(dest_lat), float(dest_lng))
                    
                    # 1.5 km tolerans ile ileri yönde olanları ayrıca topluyoruz
                    if place_to_dest <= (current_to_dest + 1.5):
                        strict_forward_places.append(place)

    # 🚨 EĞER ileri yönde mekan bulduysa onları kullan, BULAMADIYSA demo patlamasın diye çevredeki tüm uygunları kullan!
    final_candidates = strict_forward_places if len(strict_forward_places) > 0 else valid_places

    if not final_candidates:
        return {"status": "error", "message": "Uygun mekan bulunamadı."}

    # 100 yorum kuralı veya ilk 5
    validated_places = [p for p in final_candidates if p.get("reviews_count", 0) >= 100]

    if not validated_places:
        final_candidates.sort(key=lambda x: x.get('reviews_count', 0), reverse=True)
        validated_places = final_candidates[:5]
    else:
        validated_places.sort(key=lambda x: x.get('rating', 0.0), reverse=True)
        validated_places = validated_places[:5]

    for place in validated_places:
        if place.get("photo_reference"):
            place["image_url"] = f"https://maps.googleapis.com/maps/api/place/photo?maxwidth=500&photo_reference={place['photo_reference']}&key={GOOGLE_MAPS_API_KEY}"
        else:
            place["image_url"] = "https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=600"

    groq_safe_list = [{"name": p["name"], "rating": p["rating"], "reviews_count": p["reviews_count"]} for p in validated_places]

    prompt = f"""
    Aranan Tür: {user_input}
    Mekanlar Listesi: {json.dumps(groq_safe_list, ensure_ascii=False)}
    Görev: En iyi mekanı seç. Açıklamada asla 'puanı yüksek' lafı kurma. Mekanın türüne göre mantıklı samimi 1 cümle yaz.
    Yanıtı SADECE aşağıdaki JSON formatında ver:
    {{"secilen_mekan_adi": "Seçilen Mekanın Adı", "sebep": "Mekan türüne tam uyan samimi açıklama cümlesi."}}
    """
    
    llama_decision = ask_llama_to_decide(prompt)
    if llama_decision.get("status") == "error":
        return {"status": "error"}
        
    chosen_name = llama_decision.get("secilen_mekan_adi")
    final_venue = next((p for p in validated_places if p["name"] == chosen_name), validated_places[0])
    
    return {
        "status": "success",
        "mekan_adi": final_venue["name"],
        "puan": str(final_venue["rating"]),
        "lat": final_venue["lat"],
        "lng": final_venue["lng"],
        "image_url": final_venue["image_url"],
        "sebep": llama_decision.get("sebep", "Kalitesiyle öne çıkan harika bir mekan.")
    }

@app.post("/api/get_recommendation")
def get_group_recommendation(request: Dict[str, Any]):
    users = request.get("users", [])
    lat_val = request.get("current_lat")
    lng_val = request.get("current_lng")
    merkez_lat = float(lat_val) if lat_val is not None else 39.92077
    merkez_lng = float(lng_val) if lng_val is not None else 32.85411
    
    keyword = users[0].get("preference", "Restoran") if users else "Kafe"
    real_places = fetch_real_places_from_google(merkez_lat, merkez_lng, 5.0, keyword)
    users_info = "".join([f"- {u.get('name')}: Konum: {u.get('location')}, İstek: {u.get('preference')}\n" for u in users])

    prompt = f"""
    Grup Üyeleri: {users_info}
    GERÇEK MEKANLAR: {json.dumps(real_places, ensure_ascii=False)}
    Görev: En adil ortak noktayı seç ve JSON formatında yanıtla:
    {{"status": "success", "mekan_adi": "Seçilen Yer", "puan": "4.5", "lat": 39.92, "lng": 32.85, "kisa_ozet": "Özet", "sebep": "Neden"}}
    """
    return ask_llama_to_decide(prompt)

@app.get("/api/get_route")
def get_route(origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float):
    if not GOOGLE_MAPS_API_KEY: return {"status": "error"}
    url = f"https://maps.googleapis.com/maps/api/directions/json?origin={origin_lat},{origin_lng}&destination={dest_lat},{dest_lng}&mode=driving&language=tr&key={GOOGLE_MAPS_API_KEY}"
    try:
        response = requests.get(url)
        data = response.json()
        if data.get("status") == "OK":
            route = data["routes"][0]
            leg = route["legs"][0]
            return {"status": "success", "points": decode_google_polyline(route["overview_polyline"]["points"]), "distance": leg["distance"]["text"], "duration": leg["duration"]["text"], "address": leg["end_address"]}
    except: pass
    return {"status": "error"}