from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from typing import Dict, Any
import requests
import json
import os
import re
import math
import time
import random
from dotenv import load_dotenv

load_dotenv()
GROQ_API_KEY = os.getenv("GROQ_API_KEY")
GOOGLE_MAPS_API_KEY = os.getenv("GOOGLE_MAPS_API_KEY")
# Fotoğraf proxy'sinin kendine işaret edebilmesi için (yayında kendi alan adınla değiştir)
BACKEND_BASE_URL = os.getenv("BACKEND_BASE_URL", "http://localhost:8000")

app = FastAPI(title="ShouldAI API - Centroid ve Fallback Destekli Üretim Sürümü")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

ALLOWED_GOOGLE_TYPES = {
    "restaurant", "food", "cafe", "bakery", "meal_takeaway", "meal_delivery", "bar", "pub",
    "lodging", "gas_station"
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

# 🚨 ÇÖZÜM 1: URL ENCODING HATALARI GİDERİLDİ (params KULLANILDI)
def geocode_address(address: str):
    if not GOOGLE_MAPS_API_KEY: return None
    # "/" gibi işaretler API'yi bozmasın diye temizleniyor
    clean_addr = address.replace("/", " ") + ", Ankara, Turkey"
    url = "https://maps.googleapis.com/maps/api/geocode/json"
    params = {"address": clean_addr, "key": GOOGLE_MAPS_API_KEY}
    
    try:
        resp = requests.get(url, params=params, timeout=10)
        data = resp.json()
        if data.get("status") == "OK":
            loc = data["results"][0]["geometry"]["location"]
            return loc["lat"], loc["lng"]
    except Exception as e:
        print(f"🚨 Geocode Hatası: {e}")
    return None

def fetch_real_places_from_google(lat: float, lng: float, radius_km: float, keyword: str) -> list:
    if not GOOGLE_MAPS_API_KEY:
        print("🚨 Places API: GOOGLE_MAPS_API_KEY tanımlı değil (.env dosyasını kontrol et).")
        return []

    radius_meters = int(radius_km * 1000)
    url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
    params = {
        "location": f"{lat},{lng}",
        "radius": radius_meters,
        "keyword": keyword,
        "key": GOOGLE_MAPS_API_KEY
    }

    # 🚨 ÖNEMLİ: Google, hata durumunda bile HTTP 200 döndürür.
    # Gerçek durum cevabın gövdesindeki "status" alanındadır. Onu kontrol etmezsek
    # kota aşımı / faturalama kapalı gibi hatalar sessizce boş listeye dönüşür.
    # OVER_QUERY_LIMIT geçicidir (tekrar denenir); REQUEST_DENIED / INVALID_REQUEST kalıcıdır.
    for attempt in range(2):
        try:
            response = requests.get(url, params=params, timeout=10)
        except Exception as e:
            print(f"🚨 Places API ağ hatası (deneme {attempt + 1}/2): {e}")
            continue

        if response.status_code != 200:
            print(f"🚨 Places API beklenmedik HTTP kodu: {response.status_code}")
            continue

        data = response.json()
        api_status = data.get("status", "UNKNOWN")

        # Başarılı: mekanları ayrıştır ve dön
        if api_status == "OK":
            results = data.get("results", [])
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

        # Hata değil: o bölgede gerçekten sonuç yok
        if api_status == "ZERO_RESULTS":
            print(f"ℹ️ Places API: '{keyword}' için bu bölgede mekan bulunamadı (ZERO_RESULTS).")
            return []

        # Buraya düşüyorsak gerçek bir sorun var. error_message Google'ın açıklamasıdır.
        error_msg = data.get("error_message", "Ek açıklama yok.")
        print(f"🚨 Places API durumu: {api_status} | {error_msg}")

        # Geçici kota aşımı: kısa bekleme sonrası tekrar dene
        if api_status == "OVER_QUERY_LIMIT":
            time.sleep(1)
            continue

        # REQUEST_DENIED (faturalama kapalı / anahtar kısıtlı) veya INVALID_REQUEST:
        # tekrar denemek anlamsız, döngüyü kır.
        break

    return []

# 🚨 GOOGLE GİBİ ARAMA: Text Search, metni anlamsal olarak yorumlar (marka/isim farkındalığı).
# Nearby Search keyword'ü "prominence" (popülerlik) ile sıralayıp marka çakışması yaratırken,
# Text Search sonuçları "alaka düzeyine" göre sıralar — tıpkı Google Haritalar'da aratır gibi.
def text_search_places(query: str, lat: float, lng: float, radius_km: float, language: str = "tr") -> list:
    if not GOOGLE_MAPS_API_KEY:
        print("🚨 Text Search: GOOGLE_MAPS_API_KEY tanımlı değil.")
        return []

    url = "https://maps.googleapis.com/maps/api/place/textsearch/json"
    params = {
        "query": query,
        "location": f"{lat},{lng}",
        "radius": int(radius_km * 1000),
        "language": language,
        "region": "tr",
        "key": GOOGLE_MAPS_API_KEY,
    }

    for attempt in range(2):
        try:
            response = requests.get(url, params=params, timeout=10)
        except Exception as e:
            print(f"🚨 Text Search ağ hatası (deneme {attempt + 1}/2): {e}")
            continue

        if response.status_code != 200:
            print(f"🚨 Text Search beklenmedik HTTP kodu: {response.status_code}")
            continue

        data = response.json()
        api_status = data.get("status", "UNKNOWN")

        if api_status == "OK":
            out = []
            for p in data.get("results", []):
                # Geçici/kalıcı kapalı yerleri eleme
                if p.get("business_status") in ("CLOSED_TEMPORARILY", "CLOSED_PERMANENTLY"):
                    continue
                photo_ref = None
                if p.get("photos") and len(p["photos"]) > 0:
                    photo_ref = p["photos"][0].get("photo_reference")
                out.append({
                    "name": p.get("name"),
                    "rating": float(p.get("rating", 0.0)),
                    "reviews_count": int(p.get("user_ratings_total", 0)),
                    "lat": p.get("geometry", {}).get("location", {}).get("lat"),
                    "lng": p.get("geometry", {}).get("location", {}).get("lng"),
                    # Text Search 'vicinity' yerine 'formatted_address' döndürür
                    "address": p.get("formatted_address") or p.get("vicinity"),
                    "photo_reference": photo_ref,
                    "google_types": p.get("types", []),
                })
            return out

        if api_status == "ZERO_RESULTS":
            print(f"ℹ️ Text Search: '{query}' için sonuç yok (ZERO_RESULTS).")
            return []

        error_msg = data.get("error_message", "Ek açıklama yok.")
        print(f"🚨 Text Search durumu: {api_status} | {error_msg}")
        if api_status == "OVER_QUERY_LIMIT":
            time.sleep(1)
            continue
        break

    return []


# 🚨 MARKA İÇİN EN YAKINI: rankby=distance sonuçları MESAFEYE göre sıralar (alakaya değil).
# Böylece "Hatayca" arandığında en yakın şube ilk sırada gelir. radius parametresi
# rankby=distance ile KULLANILAMAZ; yarıçap sınırını biz kendimiz uyguluyoruz.
def nearby_search_by_distance(keyword: str, lat: float, lng: float, language: str = "tr") -> list:
    if not GOOGLE_MAPS_API_KEY:
        print("🚨 Nearby(distance): GOOGLE_MAPS_API_KEY tanımlı değil.")
        return []

    url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
    params = {
        "location": f"{lat},{lng}",
        "rankby": "distance",
        "keyword": keyword,
        "language": language,
        "key": GOOGLE_MAPS_API_KEY,
    }

    for attempt in range(2):
        try:
            response = requests.get(url, params=params, timeout=10)
        except Exception as e:
            print(f"🚨 Nearby(distance) ağ hatası (deneme {attempt + 1}/2): {e}")
            continue
        if response.status_code != 200:
            print(f"🚨 Nearby(distance) beklenmedik HTTP kodu: {response.status_code}")
            continue

        data = response.json()
        api_status = data.get("status", "UNKNOWN")
        if api_status == "OK":
            out = []
            for p in data.get("results", []):  # zaten en yakından uzağa sıralı gelir
                if p.get("business_status") in ("CLOSED_TEMPORARILY", "CLOSED_PERMANENTLY"):
                    continue
                photo_ref = None
                if p.get("photos") and len(p["photos"]) > 0:
                    photo_ref = p["photos"][0].get("photo_reference")
                out.append({
                    "name": p.get("name"),
                    "rating": float(p.get("rating", 0.0)),
                    "reviews_count": int(p.get("user_ratings_total", 0)),
                    "lat": p.get("geometry", {}).get("location", {}).get("lat"),
                    "lng": p.get("geometry", {}).get("location", {}).get("lng"),
                    "address": p.get("vicinity"),
                    "photo_reference": photo_ref,
                    "google_types": p.get("types", []),
                })
            return out
        if api_status == "ZERO_RESULTS":
            return []
        print(f"🚨 Nearby(distance) durumu: {api_status} | {data.get('error_message', '')}")
        if api_status == "OVER_QUERY_LIMIT":
            time.sleep(1)
            continue
        break
    return []


def _normalize_text(s: str) -> str:
    # Türkçe karakterleri sadeleştirip küçük harfe çevirerek isim karşılaştırması yapar
    if not s:
        return ""
    table = str.maketrans("çğıöşüâîû", "cgiosuaiu")
    s = s.lower().translate(table)
    return "".join(ch for ch in s if ch.isalnum() or ch.isspace()).strip()


# Mutfak etiketlerini eşleştirmek için ufak sözlük: etiketten aranacak anahtar köklere.
_CUISINE_SYNONYMS = {
    "kebap": ["kebap", "kebab", "ocakbasi", "izgara", "mangal"],
    "izgara": ["izgara", "mangal", "steak"],
    "lokanta": ["lokanta", "ev yemek", "esnaf"],
    "pide": ["pide", "lahmacun", "pideci"],
    "lahmacun": ["lahmacun", "pide"],
    "doner": ["doner", "dürüm", "durum"],
    "burger": ["burger", "hamburger"],
    "pizza": ["pizza", "pizzeria", "pizzacı", "domino", "pizza hut", "little caesars"],
    "italyan": ["italyan", "italian", "pizza", "pasta", "makarna"],
    "uzakdogu": ["sushi", "asian", "uzakdogu", "noodle", "wok", "japon", "cin"],
    "sushi": ["sushi", "japon", "asian"],
    "deniz": ["balik", "deniz", "fish", "seafood"],
    "tatli": ["tatli", "pastane", "patisserie", "dessert", "baklava", "kunefe", "waffle", "cikolata"],
    "pastane": ["pastane", "patisserie", "firin", "bakery"],
    "kahve": ["kahve", "coffee", "cafe", "kafe", "espresso", "starbucks"],
    "cafe": ["cafe", "kafe", "coffee", "kahve"],
    "kahvalti": ["kahvalti", "breakfast", "serpme"],
    "cig kofte": ["cig kofte", "cigkofte", "komagene"],
    "tavuk": ["tavuk", "chicken", "kfc", "pilic", "kanat"],
    "vejetaryen": ["vegan", "vejetaryen", "vegetarian", "salata", "salad"],
    "vegan": ["vegan", "vejetaryen", "salata"],
    "sokak": ["sokak", "street", "tantuni", "kokorec", "midye"],
}


def _term_keywords(term: str) -> list:
    # "Kebap / Izgara" -> ["kebap", "izgara"] + sözlükteki eş anlamlılar
    norm = _normalize_text(term)
    raw_tokens = [t for t in norm.replace("/", " ").split() if len(t) >= 3]
    keys = set(raw_tokens)
    for tok in list(raw_tokens):
        for syn_key, syns in _CUISINE_SYNONYMS.items():
            if tok in syn_key or syn_key in tok:
                keys.update(_normalize_text(s) for s in syns)
    return [k for k in keys if len(k) >= 3]


def _cuisine_matches(terms: list, place: dict) -> bool:
    # Bir mekan, verilen mutfak etiketlerinden HERHANGİ biriyle eşleşiyor mu?
    name = _normalize_text(place.get("name", ""))
    types = " ".join(_normalize_text(t) for t in place.get("google_types", []))
    haystack = f"{name} {types}"
    for term in terms:
        for kw in _term_keywords(term):
            if kw in haystack:
                return True
    return False


def brand_match_score(user_query: str, place_name: str) -> float:
    # Kullanıcının yazdığı marka/isim, mekan adıyla ne kadar örtüşüyor? (0.0 - 1.0)
    q = _normalize_text(user_query)
    n = _normalize_text(place_name)
    if not q or not n:
        return 0.0
    if q == n:
        return 1.0          # birebir aynı isim
    if q in n:
        return 0.85         # "hatayca" -> "hatayca kunefe cankaya" gibi marka içermesi
    # Boşluk farklarını yoksay: "big chefs" -> "bigchefs armada"
    if q.replace(" ", "") in n.replace(" ", ""):
        return 0.85
    q_tokens = set(q.split())
    n_tokens = set(n.split())
    if q_tokens and q_tokens.issubset(n_tokens):
        return 0.7          # tüm kelimeler mekan adında geçiyor
    if q_tokens:
        return (len(q_tokens & n_tokens) / len(q_tokens)) * 0.5  # kısmi örtüşme
    return 0.0


# 🚨 ÇÖZÜM 2: GELİŞMİŞ JSON TEMİZLEYİCİ VE YÜKSEK TIMEOUT
def ask_llama_to_decide(prompt: str) -> dict:
    if not GROQ_API_KEY:
        return {"status": "error", "message": "API anahtarı eksik."}

    url = "https://api.groq.com/openai/v1/chat/completions"
    headers = {"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"}
    
    payload = {
        "model": "llama-3.1-8b-instant",
        "messages": [
            {"role": "system", "content": "Sen sadece JSON döndüren bir asistansın. JSON harici hiçbir karakter üretme."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.1 # AI'ın daha stabil ve matematiksel çalışmasını sağlar
    }
    
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=20)
        response.raise_for_status()
        raw_text = response.json()['choices'][0]['message']['content'].strip()
        
        # Eğer AI inatla markdown kullanırsa onu kesip çıkarıyoruz
        if "```" in raw_text:
            parts = raw_text.split("```")
            for part in parts:
                if "{" in part and "}" in part:
                    raw_text = part
                    if raw_text.startswith("json"):
                        raw_text = raw_text[4:]
                    break
                    
        match = re.search(r'\{.*\}', raw_text, re.DOTALL)
        if match: return json.loads(match.group(0))
        return json.loads(raw_text)
    except Exception as e:
        return {"status": "error", "message": "Yapay zeka veriyi ayrıştıramadı."}

def _build_image_url(place: dict) -> str:
    # Mekanın fotoğrafı varsa KENDİ backend proxy'mizden çekiyoruz.
    # (Google'ın place/photo ucu web'de CORS başlığı göndermediği için
    #  doğrudan Image.network ile yüklenemiyor; proxy bunu çözüyor.)
    ref = place.get("photo_reference")
    if ref:
        return f"{BACKEND_BASE_URL}/api/place_photo?photo_reference={ref}&maxwidth=600"
    return "https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=600"


@app.post("/api/single_recommendation")
@app.post("/api/category_recommendation")
def get_recommendation(request: Dict[str, Any]):
    user_input = request.get("preference", request.get("category", "Restoran")).strip()
    rad_val = request.get("radius_km")
    lat_val = request.get("current_lat")
    lng_val = request.get("current_lng")
    dest_lat = request.get("dest_lat") 
    dest_lng = request.get("dest_lng") 

    # Kullanıcının kişisel damak zevki (üyelik tercih ekranından gelir; opsiyonel)
    liked_cuisines = request.get("liked_cuisines") or []
    disliked_cuisines = request.get("disliked_cuisines") or []
    # Öneri modu: "default" (Akıllı Öneri) veya "selective" (Katı Kurallar)
    rec_mode = str(request.get("mode") or "default").strip().lower()
    pref_clause = ""
    _pref_norm = _normalize_text(user_input)
    _is_restaurant_pref = ("restoran" in _pref_norm or "restaurant" in _pref_norm)
    # Damak zevki bilgisini LLM'e SADECE restoran aramalarında ver.
    # (Kafe/benzinlik aramasında verirsek açıklamada "lahmacun tercihine uygun" gibi alakasız ifadeler çıkıyor.)
    if _is_restaurant_pref and (liked_cuisines or disliked_cuisines):
        pref_clause = (
            f"\n    Kullanıcının SEVDİĞİ türler: {', '.join(liked_cuisines) or 'belirtilmemiş'}."
            f"\n    Kullanıcının SEVMEDİĞİ türler: {', '.join(disliked_cuisines) or 'belirtilmemiş'}."
            f"\n    Mümkünse sevdiklerine uyan, sevmediklerinden kaçınan bir seçim yap."
        )

    radius_km_selection = float(rad_val) if rad_val is not None else 2.0
    lat = float(lat_val) if lat_val is not None else 39.92077
    lng = float(lng_val) if lng_val is not None else 32.85411

    search_radius = 25.0 if radius_km_selection >= 50.0 else radius_km_selection

    local_whitelist = ["lokanta", "esnaf", "kebap", "aspava", "pide", "pizza", "burger", "cafe", "kafe", "kahve", "restoran", "restaurant", "otel", "pansiyon", "opet", "shell", "petrol", "benzin", "yemek", "döner", "köfte", "çorba", "tatlı", "benzinlik", "akaryakıt", "bp", "total", "lukoil", "aytemiz", "enerji"]
    is_whitelisted = any(word in user_input.lower() for word in local_whitelist)

    # Whitelist'te DEĞİLSE muhtemelen belirli bir isim/marka (ör. "Hatayca").
    # Önce hem yeme-içme mi diye doğrula, sonra marka olarak en yakın şubeyi ara.
    if not is_whitelisted:
        validation_prompt = f"""
        Kullanıcının girdiği arama terimi: "{user_input}"
        Bu uygulama sadece ticari yemek/otel/benzinlik sektörlerine hizmet eder.
        Bir RESTORAN, KAFE, MARKA ZİNCİRİ veya işletme adı olabilir; bu durumda true döndür.
        Sadece yazılan şey kişi adı, Üniversite, Okul, Kampüs, Hastane, Eczane, Şirket, Teknoloji Firması, Cami, Müze gibi YEME-İÇME DIŞI kurumsal yerlerse false döndür.
        Yanıtı SADECE şu JSON formatında ver: {{"uygun": true veya false}}
        """
        validation_res = ask_llama_to_decide(validation_prompt)
        if not validation_res.get("uygun", True):
            return {"status": "error", "message": "İşlev sınırları dışında bir tercih girilmiştir."}

        # 🚨 MARKA NİYETİ: mesafeye göre sıralı ara, gerçek markayı + yarıçapı ZORLA.
        brand_candidates = nearby_search_by_distance(user_input, lat, lng)
        brand_hits = []
        for p in brand_candidates:
            if p.get("lat") is None or p.get("lng") is None:
                continue
            d = calculate_real_distance(lat, lng, float(p["lat"]), float(p["lng"]))
            if brand_match_score(user_input, p.get("name", "")) >= 0.85 and d <= search_radius:
                # Navigasyon sırasında: hedeften uzaklaştıran şubeyi alma
                if dest_lat is not None and dest_lng is not None:
                    c2d = calculate_real_distance(lat, lng, float(dest_lat), float(dest_lng))
                    p2d = calculate_real_distance(
                        float(p["lat"]), float(p["lng"]), float(dest_lat), float(dest_lng))
                    if p2d > c2d + 1.0:
                        continue
                p["_distance_km"] = d
                brand_hits.append(p)

        if brand_hits:
            brand_hits.sort(key=lambda x: x["_distance_km"])  # EN YAKIN şube
            final_venue = brand_hits[0]
            final_venue["image_url"] = _build_image_url(final_venue)
            reason_prompt = f"""
            Kullanıcı "{user_input}" aradı ve "{final_venue['name']}" şubesi seçildi.
            Bu mekan için samimi, kısa (1 cümle) bir öneri açıklaması yaz. 'Puanı yüksek' deme.
            Yanıtı SADECE şu JSON formatında ver: {{"sebep": "tek cümlelik samimi açıklama"}}
            """
            reason_res = ask_llama_to_decide(reason_prompt)
            sebep = reason_res.get("sebep") if isinstance(reason_res, dict) else None
            return {
                "status": "success",
                "mekan_adi": final_venue["name"],
                "puan": str(final_venue["rating"]),
                "lat": final_venue["lat"],
                "lng": final_venue["lng"],
                "image_url": final_venue["image_url"],
                "sebep": sebep or f"Aradığın {user_input} için en yakın şube burası.",
            }
        # Marka yarıçap içinde bulunamadıysa kategori aramasına düş (aşağıda).

    # 🚨 KATEGORİ / HEVES ARAMASI: Text Search (alaka) + KATI yarıçap + LLM seçim.
    raw_places = text_search_places(user_input, lat, lng, search_radius)
    if not raw_places:
        keyword = "aspava" if "aspava" in user_input.lower() else user_input
        raw_places = fetch_real_places_from_google(lat, lng, search_radius, keyword)

    in_radius = []
    forward = []
    for place in raw_places:
        if place.get("lat") is None or place.get("lng") is None:
            continue
        place_lat = float(place["lat"])
        place_lng = float(place["lng"])
        d = calculate_real_distance(lat, lng, place_lat, place_lng)
        if d > search_radius:        # 🚨 KATI SINIR: yarıçap dışını asla alma
            continue
        place["_distance_km"] = d
        place_tags = set(place.get("google_types", []))
        if place_tags.intersection(ALLOWED_GOOGLE_TYPES):
            in_radius.append(place)
            if dest_lat is not None and dest_lng is not None:
                current_to_dest = calculate_real_distance(lat, lng, float(dest_lat), float(dest_lng))
                place_to_dest = calculate_real_distance(place_lat, place_lng, float(dest_lat), float(dest_lng))
                if place_to_dest <= (current_to_dest + 1.0):
                    forward.append(place)

    candidates = forward if len(forward) > 0 else in_radius
    if not candidates:
        return {
            "status": "error",
            "message": f"{search_radius:.0f} km içinde uygun mekan bulunamadı. Yarıçapı artırmayı deneyebilirsin.",
        }

    # YEŞİL HAVUZU GÜÇLENDİR: sevilen mutfakları DOĞRUDAN Google'da ara.
    # (Bir pizzacının Google adı/türü "pizza" içermeyebilir; "pizza" araması yine de getirir.)
    # ÖNEMLİ: Mutfak kişiselleştirmesi YALNIZCA restoran aramalarında geçerli.
    # Kafe/benzinlik aramasında devreye girmemeli (yoksa kafe ararken kebapçı çıkar).
    _norm_input = _normalize_text(user_input)
    is_gas_search = ("benzinlik" in _norm_input or "akaryakit" in _norm_input)
    is_cafe_search = ("kafe" in _norm_input or "cafe" in _norm_input)
    is_restaurant_search = ("restoran" in _norm_input or "restaurant" in _norm_input)
    # Mutfak (yeşil/gri) kişiselleştirmesi YALNIZCA restoran aramalarında geçerli.
    cuisine_personalization = bool(liked_cuisines) and is_restaurant_search

    if cuisine_personalization:
        liked_query = " ".join(liked_cuisines[:4])
        liked_raw = text_search_places(liked_query, lat, lng, search_radius)
        existing = {_normalize_text(p.get("name", "")): p for p in candidates}
        for place in liked_raw:
            if place.get("lat") is None or place.get("lng") is None:
                continue
            pl = float(place["lat"])
            pg = float(place["lng"])
            d = calculate_real_distance(lat, lng, pl, pg)
            if d > search_radius:
                continue
            # Navigasyon sırasında: hedeften belirgin uzaklaştıran yeri alma
            if dest_lat is not None and dest_lng is not None:
                c2d = calculate_real_distance(lat, lng, float(dest_lat), float(dest_lng))
                p2d = calculate_real_distance(pl, pg, float(dest_lat), float(dest_lng))
                if p2d > c2d + 1.0:
                    continue
            nm = _normalize_text(place.get("name", ""))
            if nm in existing:
                existing[nm]["_liked_match"] = True  # mevcut adayı yeşile çevir
            else:
                place["_distance_km"] = d
                place["_liked_match"] = True
                candidates.append(place)
                existing[nm] = place

    # "Tekrar Dene" için: daha önce önerilenleri (exclude) listeden çıkar
    exclude_names = [_normalize_text(x) for x in (request.get("exclude") or [])]
    if exclude_names:
        kept = [
            p for p in candidates
            if _normalize_text(p.get("name", "")) not in exclude_names
        ]
        candidates = kept if kept else candidates

    # Dislike filtresi: kullanıcının sevmediği kategoriler hiçbir zaman önerilmez
    if disliked_cuisines:
        filtered = [p for p in candidates if not _cuisine_matches(disliked_cuisines, p)]
        candidates = filtered if filtered else candidates

    # Kategori-tipi zorlaması: kafe aranıyorsa kafe-tipi, restoran aranıyorsa
    # restoran-tipi yerleri tut. Uygun tip yoksa havuzu bırak (en azından bir şey öner).
    if is_cafe_search:
        cafe_types = {"cafe", "bakery", "coffee_shop"}
        typed = [p for p in candidates if cafe_types & set(p.get("google_types", []))]
        candidates = typed if typed else candidates
    elif is_restaurant_search:
        rest_types = {"restaurant", "food", "meal_takeaway", "meal_delivery"}
        typed = [p for p in candidates if rest_types & set(p.get("google_types", []))]
        candidates = typed if typed else candidates

    # 50 yorum minimumu (çok az yorum varsa güvenilirlik düşük)
    well_reviewed = [p for p in candidates if p.get("reviews_count", 0) >= 50]
    reviewed_pool = well_reviewed if well_reviewed else candidates

    # YEŞİL/GRİ SINIFLANDIRMA + MOD MANTIĞI
    # Yeşil = kullanıcının sevdiği türle eşleşen VEYA sevilen mutfak aramasından gelen mekan.
    fallback_note = ""
    note_text = (
        "Tercihlerine göre arama yaptık fakat çevrendeki mekânlar pek "
        "başarılı görünmüyordu, o sebeple çevredeki en iyi mekânı önerdik!"
    )
    if cuisine_personalization:
        def _is_green(p):
            return p.get("_liked_match", False) or _cuisine_matches(liked_cuisines, p)

        greens = [p for p in reviewed_pool if _is_green(p)]
        grays = [p for p in reviewed_pool if not _is_green(p)]

        def _best_rating(lst):
            return max((float(p.get("rating", 0.0)) for p in lst), default=0.0)

        if rec_mode == "selective":
            # Katı Kurallar: bölgede yeşil varsa puan farkına bakmadan yeşil, yoksa gri.
            if greens:
                chosen_pool = greens
            else:
                chosen_pool = grays
                fallback_note = note_text
        else:
            # default (Akıllı Öneri)
            if not greens:
                chosen_pool = grays
                fallback_note = note_text
            else:
                bg = _best_rating(greens)
                bgr = _best_rating(grays) if grays else 0.0
                if not grays or bg >= bgr:
                    chosen_pool = greens  # yeşil yüksek veya eşit → yeşil
                elif (bgr - bg) > 0.5:
                    chosen_pool = grays  # gri, yeşilden 0.5'ten fazla yüksek → gri
                    fallback_note = note_text
                else:
                    chosen_pool = greens  # fark 0.5 ve altı → yeşil
        pool = chosen_pool if chosen_pool else reviewed_pool
    else:
        pool = reviewed_pool

    pool.sort(key=lambda x: (round(x.get("rating", 0.0)), x.get("reviews_count", 0)), reverse=True)
    validated_places = pool[:5]

    for place in validated_places:
        place["image_url"] = _build_image_url(place)

    groq_safe_list = [
        {"name": p["name"], "rating": p["rating"], "reviews_count": p["reviews_count"]}
        for p in validated_places
    ]

    prompt = f"""
    Kullanıcının aradığı: "{user_input}"
    Mekanlar Listesi: {json.dumps(groq_safe_list, ensure_ascii=False)}{pref_clause}
    Görev: Kullanıcının niyetine EN UYGUN mekanı seç (listedeki adı birebir kullan).
    Eğer kullanıcı belirli bir mutfak/tür yazdıysa (ör. tatlı, kahve, kebap) ona uyanı seç.
    Açıklamada asla 'puanı yüksek' lafı kurma. Mekanın türüne göre mantıklı, samimi 1 cümle yaz.
    Yanıtı SADECE aşağıdaki JSON formatında ver:
    {{"secilen_mekan_adi": "Seçilen Mekanın Adı", "sebep": "Mekan türüne tam uyan samimi açıklama cümlesi."}}
    """

    # 🚨 DAYANIKLILIK: AI bazen bozuk JSON döndürüyor. 2 kez dene; yine olmazsa
    # hata verme — en kaliteli adayı yedek olarak seç (kullanıcı hep sonuç alsın).
    chosen_name = None
    sebep = None
    for _ in range(2):
        llama_decision = ask_llama_to_decide(prompt)
        if llama_decision.get("status") != "error":
            chosen_name = llama_decision.get("secilen_mekan_adi")
            sebep = llama_decision.get("sebep")
            if chosen_name:
                break

    final_venue = next(
        (p for p in validated_places if p["name"] == chosen_name),
        validated_places[0],
    )

    return {
        "status": "success",
        "mekan_adi": final_venue["name"],
        "puan": str(final_venue["rating"]),
        "lat": final_venue["lat"],
        "lng": final_venue["lng"],
        "image_url": final_venue["image_url"],
        "sebep": sebep or f"Aradığın '{user_input}' için öne çıkan bir seçenek burası.",
        "fallback_note": fallback_note,
    }

# 🚨 ÇÖZÜM 3: TAM ORTAYI BULAN VE PES ETMEYEN GRUP MOTORU
@app.post("/api/get_recommendation")
def get_group_recommendation(request: Dict[str, Any]):
    users = request.get("users", [])
    
    lats = []
    lngs = []
    users_info = ""
    group_prefs = []  # her üyenin bireysel tercihini listele
    user_pref_info = []  # LLM prompt'u için isim→tercih eşleşmesi

    # 1. Aşama: Herkesin Konumunu ve Tercihini Al
    for u in users:
        name = u.get("name", "Bilinmeyen")
        loc_str = u.get("location", "")
        pref = u.get("preference", "").strip()

        if pref and pref.lower() not in [p.lower() for p in group_prefs]:
            group_prefs.append(pref)
        user_pref_info.append(f"{name}: {pref}" if pref else name)

        # Kullanıcı haritadan tam adres seçtiyse koordinat hazır gelir (en güvenilir).
        u_lat = u.get("lat")
        u_lng = u.get("lng")
        if u_lat is not None and u_lng is not None:
            lats.append(float(u_lat))
            lngs.append(float(u_lng))
            users_info += f"- {name}: {loc_str}{', tercih: ' + pref if pref else ''}\n"
            continue

        # Koordinat yoksa adres metnini geocode etmeyi dene (yedek yol).
        coords = geocode_address(loc_str)
        if coords:
            lats.append(coords[0])
            lngs.append(coords[1])
        users_info += f"- {name}: {loc_str}{', tercih: ' + pref if pref else ''}\n"
            
    # 2. Aşama: Kusursuz Kesişim Merkezini (Centroid) Hesapla
    if len(lats) > 0:
        center_lat = sum(lats) / len(lats)
        center_lng = sum(lngs) / len(lngs)
    else:
        center_lat = float(request.get("current_lat") or 39.92077)
        center_lng = float(request.get("current_lng") or 32.85411)
    
    # 3. Aşama: Merkezdeki Yerleri Bul
    GROUP_RADIUS_KM = 8.0
    category = str(request.get("category") or "").strip().lower()
    base_cat = category if category in ("kafe", "restoran", "cafe", "restaurant") else "restoran kafe"
    # Arama sorgusunda kategori + tüm bireysel tercihleri kullan
    prefs_query = " ".join(group_prefs) if group_prefs else ""
    search_query = f"{base_cat} {prefs_query}".strip()

    real_places = text_search_places(search_query, center_lat, center_lng, GROUP_RADIUS_KM)

    # Boşsa sırasıyla daha genel sorgulara düş
    if not real_places:
        real_places = text_search_places("restoran kafe", center_lat, center_lng, GROUP_RADIUS_KM)
    if not real_places:
        real_places = fetch_real_places_from_google(center_lat, center_lng, 10.0, "yemek")

    if not real_places:
        return {"status": "error", "message": "Girdiğiniz konumların kesişim noktasında hiçbir uygun mekan bulunamadı."}

    # Üyelerin gerçek koordinatları (adalet hesabı için)
    member_points = list(zip(lats, lngs))

    # 🚨 ADİL ORTA NOKTA: her aday için HER ÜYENİN mesafesini ölç.
    # Amaç centroid'e yakınlık değil; en uzaktaki kişinin yolunu kısaltmak (minimax).
    scored = []
    for p in real_places:
        if p.get("lat") is None or p.get("lng") is None:
            continue
        d_center = calculate_real_distance(center_lat, center_lng, float(p["lat"]), float(p["lng"]))
        if d_center > GROUP_RADIUS_KM:
            continue
        if member_points:
            dists = [
                calculate_real_distance(mlat, mlng, float(p["lat"]), float(p["lng"]))
                for (mlat, mlng) in member_points
            ]
            p["_max_member_km"] = max(dists)            # en uzaktaki üyenin mesafesi
            p["_spread_km"] = max(dists) - min(dists)   # mesafe dengesizliği
        else:
            p["_max_member_km"] = d_center
            p["_spread_km"] = 0.0
        p["_center_dist_km"] = d_center
        scored.append(p)

    # Yarıçap içinde aday kalmadıysa kapsama güvencesi
    if not scored:
        for p in real_places:
            if p.get("lat") is None:
                continue
            if member_points:
                dists = [
                    calculate_real_distance(mlat, mlng, float(p["lat"]), float(p["lng"]))
                    for (mlat, mlng) in member_points
                ]
                p["_max_member_km"] = max(dists)
            else:
                p["_max_member_km"] = 0.0
            scored.append(p)

    # Kategori zorlaması: kafe seçiliyse kafe-tipi, restoran seçiliyse restoran-tipi yerler
    if category in ("kafe", "cafe"):
        cat_types = {"cafe", "bakery", "coffee_shop"}
        typed = [p for p in scored if cat_types & set(p.get("google_types", []))]
        scored = typed if typed else scored
    elif category in ("restoran", "restaurant"):
        cat_types = {"restaurant", "food", "meal_takeaway", "meal_delivery"}
        typed = [p for p in scored if cat_types & set(p.get("google_types", []))]
        scored = typed if typed else scored

    # Tercih uygunluğu: üyelerin istediği yemeklere uyan yerleri öne al.
    # (Arama sorgusu zaten tercihleri içeriyor; burada isim/tür eşleşmesini garantiliyoruz.)
    # Hiç uyan yoksa havuzu olduğu gibi bırakırız → en yüksek puanlı "emin" yere düşeriz.
    if group_prefs:
        relevant = [p for p in scored if _cuisine_matches(group_prefs, p)]
        scored = relevant if relevant else scored

    # "Tekrar Dene" için: daha önce önerilenleri havuzdan çıkar
    grp_exclude = [_normalize_text(x) for x in (request.get("exclude") or [])]
    if grp_exclude:
        kept = [p for p in scored if _normalize_text(p.get("name", "")) not in grp_exclude]
        scored = kept if kept else scored

    # Dislike filtresi: kullanıcının sevmediği kategorileri havuzdan çıkar
    group_disliked = request.get("disliked_cuisines") or []
    if group_disliked:
        scored = [p for p in scored if not _cuisine_matches(group_disliked, p)] or scored

    # 50 yorum minimumu — çok az yorumlu yerleri havuzdan çıkar (yedek kalmazsa tümünü kullan)
    reviewed = [p for p in scored if p.get("reviews_count", 0) >= 50]
    scored = reviewed if reviewed else scored

    # ADALET ÖNCE (minimax): en uzaktaki üyeyi en aza indiren adayları öne al;
    # eşitlikte daha dengeli (düşük spread) ve daha kaliteli olanı tercih et.
    scored.sort(key=lambda x: (
        round(x.get("_max_member_km", 0), 1),
        round(x.get("_spread_km", 0), 1),
        -float(x.get("rating", 0) or 0),
    ))
    fair_pool = scored[:12]  # en adil 12 aday

    # Kalite + çeşitlilik: adil havuzu kaliteye göre sırala, karıştır, 5'ini AI'a sun.
    # Konumlar değişince fair_pool değişir; aynı konumda tekrar sorulunca karıştırma çeşitlilik verir.
    fair_pool.sort(key=lambda x: (x.get("reviews_count", 0), x.get("rating", 0.0)), reverse=True)
    top = fair_pool[:8]
    random.shuffle(top)
    pool = top[:5] if len(top) >= 5 else top
    safe_places = [{"name": p["name"], "rating": p["rating"], "lat": p["lat"], "lng": p["lng"]} for p in pool]

    candidates = scored
    real_places = candidates  # aşağıdaki foto/seçim mantığı bu listeyi kullanıyor
    
    # Bireysel tercihleri prompt için özetle
    pref_summary = ""
    if any(u.get("preference", "").strip() for u in users):
        pref_summary = (
            "\n    ÜYE TERCİHLERİ (herkese uyacak yer seç):\n"
            + "\n".join(f"    - {p}" for p in user_pref_info)
            + "\n"
        )

    prompt = f"""
    Grup Üyeleri: 
    {users_info}
    {pref_summary}
    GERÇEK MEKANLAR (Grubun Tam Orta Noktasındaki En İyi Yerler): 
    {json.dumps(safe_places, ensure_ascii=False)}
    
    Görev: Listeden 1 mekan seç. Önceliğin HERKESİN yiyebileceği, tüm bireysel tercihleri
    karşılayan veya uzlaşma sağlayan yer olsun. Eğer birinin tercihi diğerini dışlamıyorsa
    her ikisini de sunan mekanı tercih et.
    Yanıtı SADECE aşağıdaki JSON formatında ver, ekstra metin ekleme:
    {{"status": "success", "mekan_adi": "Seçilen Yer (Listeden Birebir Aynı Ad)", "sebep": "Neden bu mekanın seçildiğini ve kimin tercihini nasıl karşıladığını açıklayan samimi 1-2 cümle."}}
    """
    
    # 🚨 4. Aşama: YAPAY ZEKA PES ETME DÖNGÜSÜ (3 KERE DENER)
    for attempt in range(3):
        llama_decision = ask_llama_to_decide(prompt)
        
        if llama_decision.get("status") != "error" and "mekan_adi" in llama_decision:
            chosen_name = llama_decision.get("mekan_adi")
            final_venue = next((p for p in real_places if p["name"] == chosen_name), real_places[0])

            image_url = _build_image_url(final_venue)
                
            return {
                "status": "success",
                "mekan_adi": final_venue["name"],
                "puan": str(final_venue["rating"]),
                "lat": final_venue["lat"],
                "lng": final_venue["lng"],
                "kisa_ozet": final_venue["address"],
                "image_url": image_url,
                "sebep": llama_decision.get("sebep", "Grubun kesişim merkezi için en adil mekan.")
            }
            
    return {"status": "error", "message": "Yapay zeka defalarca denemesine rağmen karar veremedi. Tekrar deneyin."}

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


# 🚨 ARAMA ÇUBUĞU: Google Places Autocomplete — yazdıkça tahmin üretir (tarayıcı/Google gibi).
# Flutter tarafında debounce (~400 ms) ile çağrılmalı; her tuş vuruşunda değil.
@app.get("/api/autocomplete")
def autocomplete(input: str, lat: float = 39.92077, lng: float = 32.85411):
    if not GOOGLE_MAPS_API_KEY:
        return {"status": "error", "predictions": []}
    if not input or len(input.strip()) < 2:
        return {"status": "OK", "predictions": []}

    url = "https://maps.googleapis.com/maps/api/place/autocomplete/json"
    params = {
        "input": input,
        "location": f"{lat},{lng}",
        "radius": 30000,            # konuma yakın tahminleri öne çıkar
        "components": "country:tr",  # sadece Türkiye
        "language": "tr",
        "key": GOOGLE_MAPS_API_KEY,
    }
    try:
        resp = requests.get(url, params=params, timeout=10)
        data = resp.json()
        api_status = data.get("status", "UNKNOWN")
        if api_status not in ("OK", "ZERO_RESULTS"):
            print(f"🚨 Autocomplete durumu: {api_status} | {data.get('error_message', '')}")
            return {"status": api_status, "predictions": []}
        predictions = [
            {
                "place_id": p.get("place_id"),
                "main_text": p.get("structured_formatting", {}).get("main_text", p.get("description")),
                "secondary_text": p.get("structured_formatting", {}).get("secondary_text", ""),
                "description": p.get("description"),
            }
            for p in data.get("predictions", [])
        ]
        return {"status": "OK", "predictions": predictions}
    except Exception as e:
        print(f"🚨 Autocomplete ağ hatası: {e}")
        return {"status": "error", "predictions": []}


# 🚨 Bir tahmin seçilince koordinatını çözmek için (Autocomplete koordinat vermez).
@app.get("/api/place_details")
def place_details(place_id: str):
    if not GOOGLE_MAPS_API_KEY:
        return {"status": "error"}
    url = "https://maps.googleapis.com/maps/api/place/details/json"
    params = {
        "place_id": place_id,
        "fields": "name,geometry,formatted_address",
        "language": "tr",
        "key": GOOGLE_MAPS_API_KEY,
    }
    try:
        resp = requests.get(url, params=params, timeout=10)
        data = resp.json()
        if data.get("status") == "OK":
            r = data["result"]
            loc = r.get("geometry", {}).get("location", {})
            return {
                "status": "success",
                "name": r.get("name"),
                "address": r.get("formatted_address"),
                "lat": loc.get("lat"),
                "lng": loc.get("lng"),
            }
        print(f"🚨 Place Details durumu: {data.get('status')} | {data.get('error_message', '')}")
    except Exception as e:
        print(f"🚨 Place Details ağ hatası: {e}")
    return {"status": "error"}

# 🚨 FOTOĞRAF PROXY'Sİ: Google place/photo web'de CORS başlığı göndermediği için
# tarayıcı doğrudan yüklemeyi engelliyor. Sunucu tarafında çekip kendi (CORS açık)
# backend'imizden bytes olarak döndürüyoruz; frontend bu URL'i Image.network ile kullanır.
@app.get("/api/place_photo")
def place_photo(photo_reference: str, maxwidth: int = 600):
    if not GOOGLE_MAPS_API_KEY or not photo_reference:
        return Response(status_code=404)
    url = "https://maps.googleapis.com/maps/api/place/photo"
    params = {
        "photo_reference": photo_reference,
        "maxwidth": maxwidth,
        "key": GOOGLE_MAPS_API_KEY,
    }
    try:
        # requests 302 yönlendirmesini otomatik takip eder, gerçek görsele ulaşır
        r = requests.get(url, params=params, timeout=10)
        if r.status_code == 200:
            content_type = r.headers.get("Content-Type", "image/jpeg")
            return Response(content=r.content, media_type=content_type)
        print(f"🚨 place_photo beklenmedik kod: {r.status_code}")
    except Exception as e:
        print(f"🚨 place_photo ağ hatası: {e}")
    return Response(status_code=404)