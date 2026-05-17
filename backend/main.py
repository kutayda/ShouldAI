from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import requests
import random
import math

app = FastAPI(title="ShouldAI API - Gerçekçi Simülasyon Modu")

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
    current_lat: float
    current_lng: float


class CategoryRequest(BaseModel):
    category: str
    radius_km: float
    current_lat: float
    current_lng: float


# --- GERÇEK ANKARA MEKANLARI VERİ TABANI ---
PLACES_DB = {
    "otel": [
        {"adi": "Sheraton Hotel & Convention Center", "puan": "4.8",
            "ozet": "Kavaklıdere'de Ankara manzaralı, ikonik ve lüks otel.", "sebep": "Yüksek hizmet standartları ve merkezi konumu."},
        {"adi": "JW Marriott Hotel Ankara", "puan": "4.9", "ozet": "Söğütözü'nde iş ve lüksü bir araya getiren prestijli tesis.",
            "sebep": "Konforlu odaları ve geniş spa olanakları."},
        {"adi": "Divan Ankara", "puan": "4.7", "ozet": "Tunalı Hilmi Caddesi'ne yürüme mesafesinde butik ve şık.",
            "sebep": "Hem sakin hem de şehrin tam kalbinde olması."},
        {"adi": "Point Hotel Ankara", "puan": "4.6", "ozet": "Modern mimarisiyle dikkat çeken sanat ve konaklama merkezi.",
            "sebep": "Gelişmiş teknolojik altyapısı ve modern tasarımı."}
    ],
    "kafe": [
        {"adi": "Fika Coffee House", "puan": "4.6", "ozet": "Bahçelievler'in en huzurlu 3. nesil kahvecisi.",
            "sebep": "Nitelikli kahve çekirdekleri ve sessiz ortamı."},
        {"adi": "Arabica Coffee House", "puan": "4.4", "ozet": "Arkadaş buluşmaları için ideal, ferah kahveci.",
            "sebep": "Geniş oturma alanları ve zengin tatlı menüsü."},
        {"adi": "Coffee Lab", "puan": "4.5", "ozet": "Bilgisayarla çalışmaya uygun modern kafe.",
            "sebep": "Hızlı interneti ve odaklanmaya uygun tasarımı."},
        {"adi": "Aylak Madam", "puan": "4.3", "ozet": "Vintage dekorasyonlu, samimi mekan.",
            "sebep": "Sıcak atmosferi ve farklı bitki çayı çeşitleri."}
    ],
    "restoran": [
        {"adi": "Trilye Restoran", "puan": "4.9", "ozet": "Ankara'nın en ünlü deniz ürünleri restoranı.",
            "sebep": "Özel misafirlerinizi ağırlamak için eşsiz menüsü."},
        {"adi": "Düveroğlu Kebap", "puan": "4.7", "ozet": "Efsaneleşmiş Antep mutfağı ve kebap kültürü.",
            "sebep": "Yıllardır değişmeyen lahmacun ve et kalitesi."},
        {"adi": "Gülçimen Aspava", "puan": "4.8", "ozet": "Sınırsız ikramlarıyla meşhur Ankara klasiği.",
            "sebep": "Doyurucu porsiyonları ve efsanevi soslu dürümü."},
        {"adi": "Tavacı Recep Usta", "puan": "4.6", "ozet": "Geniş ve ferah ortamıyla bilinen et lokantası.",
            "sebep": "Fırınlanmış özel lezzetleri ve hızlı servisi."}
    ],
    "lokanta": [
        {"adi": "Boğaziçi Lokantası", "puan": "4.7", "ozet": "Yarım asırlık esnaf lokantası geleneği.",
            "sebep": "Günlük çıkan taze ev yemekleri ve meşhur Ankara tavası."},
        {"adi": "Çiçek Lokantası", "puan": "4.5", "ozet": "Şık ve modern esnaf lokantası konsepti.",
            "sebep": "Geniş yemek çeşitliliği ve nezih ortamı."},
        {"adi": "Konyalı Hacıbey", "puan": "4.6", "ozet": "Etli ekmek ve fırın kebabı ustası.",
            "sebep": "Konya mutfağını Ankara'da en iyi temsil eden yerlerden biri."}
    ]
}

# --- AKILLI KOORDİNAT ÜRETİCİ (TRIGONOMETRİ) ---


def get_dynamic_coords(lat, lng, radius_km):
    # Seçilen çapın %70'i ile %95'i arasında rastgele bir uzaklık belirle (Tam sınırda çıkmaması için)
    actual_dist = radius_km * random.uniform(0.70, 0.95)

    # 0 ile 360 derece arasında rastgele bir açı seç (Haritanın her yönüne dağılması için)
    angle = random.uniform(0, 2 * math.pi)

    # 1 km yaklaşık 0.009 derece enlem/boylam farkına eşittir
    offset_lat = (actual_dist * 0.009) * math.cos(angle)
    offset_lng = (actual_dist * 0.009) * math.sin(angle)

    return lat + offset_lat, lng + offset_lng


def get_place_from_db(category_query):
    query = category_query.lower()
    if "otel" in query or "konaklama" in query:
        return random.choice(PLACES_DB["otel"])
    elif "kafe" in query or "kahve" in query or "tatlı" in query:
        return random.choice(PLACES_DB["kafe"])
    elif "lokanta" in query or "esnaf" in query or "çorba" in query:
        return random.choice(PLACES_DB["lokanta"])
    else:
        return random.choice(PLACES_DB["restoran"])

# --- 1. HIZLI ÖNERİ ---


@app.post("/api/single_recommendation")
def get_single_recommendation(request: SingleUserRequest):
    # Zaman kısıtlamasına göre mesafeyi (çapı) ayarla
    dist_km = 1.0 if request.time_limit_mins <= 15 else (
        2.5 if request.time_limit_mins <= 30 else 5.0)

    mekan_bilgisi = get_place_from_db(request.preference)
    new_lat, new_lng = get_dynamic_coords(
        request.current_lat, request.current_lng, dist_km)

    return {
        "status": "success",
        "mekan_adi": mekan_bilgisi["adi"],
        "puan": mekan_bilgisi["puan"],
        "lat": new_lat,
        "lng": new_lng,
        "kisa_ozet": f"({request.time_limit_mins} dk limitine uygun) {mekan_bilgisi['ozet']}",
        "sebep": mekan_bilgisi["sebep"]
    }

# --- 2. DETAYLI ARAMA ---


@app.post("/api/category_recommendation")
def get_category_recommendation(request: CategoryRequest):
    mekan_bilgisi = get_place_from_db(request.category)
    new_lat, new_lng = get_dynamic_coords(
        request.current_lat, request.current_lng, request.radius_km)

    return {
        "status": "success",
        "mekan_adi": mekan_bilgisi["adi"],
        "puan": mekan_bilgisi["puan"],
        "lat": new_lat,
        "lng": new_lng,
        "kisa_ozet": mekan_bilgisi["ozet"],
        "sebep": f"Seçtiğiniz {request.radius_km} km yarıçapı içerisinde en uygun olan yer: {mekan_bilgisi['sebep']}"
    }

# --- 3. NAVİGASYON (OSRM - GERÇEK ROTA) ---


@app.get("/api/get_route")
def get_route(origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float):
    route_url = f"http://router.project-osrm.org/route/v1/driving/{origin_lng},{origin_lat};{dest_lng},{dest_lat}?overview=full&geometries=geojson"
    headers = {'User-Agent': 'ShouldAI_App'}

    try:
        route_res = requests.get(route_url).json()
        if route_res["code"] == "Ok":
            route = route_res["routes"][0]
            points = [[p[1], p[0]] for p in route["geometry"]["coordinates"]]
            return {
                "status": "success",
                "points": points,
                "distance": f"{round(route['distance'] / 1000, 1)} km",
                "duration": f"{round(route['duration'] / 60)} dk",
                "address": "Navigasyon Rotası Çizildi"
            }
    except Exception as e:
        print(f"Rota Hatası: {e}")

    return {"status": "error", "distance": "0 km", "duration": "0 dk", "address": "Adres bulunamadı"}
