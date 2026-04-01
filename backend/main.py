from fastapi import FastAPI, types
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from google import genai
import json
import os
from dotenv import load_dotenv

# Gizli .env dosyasındaki verileri yükle
load_dotenv()

# API Anahtarını artık güvenli bir şekilde gizli dosyadan çekiyor
client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))

app = FastAPI(title="Grup Mekan Çöpçatanı API")
# ... Kodun geri kalanı tamamen aynı ...

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class UserData(BaseModel):
    name: str
    location: str
    preference: str
    has_car: bool = False

class GroupRequest(BaseModel):
    users: list[UserData]

@app.post("/api/get_recommendation")
def get_recommendation(request: GroupRequest):
    drivers = [u.name for u in request.users if u.has_car]
    driver_info = f"Araç sahibi: {', '.join(drivers)}." if drivers else "Grupta araç yok."

    user_details = "\n".join([f"- {u.name}: {u.location} konumunda. İstediği: {u.preference}" for u in request.users])
    
    prompt = f"""
    Sen Ankara'da gruplar için mekan krizlerini ve buluşma noktası sorunlarını çözen zeki bir asistansın.
    
    Grubun Anlık Konumları ve İstekleri:
    {user_details}
    
    Ulaşım Durumu: {driver_info}
    
    Görevlerin: 
    1. Mesafeleri ve ulaşım durumunu analiz et.
    2. Herkesi tatmin edecek menüye sahip 1 (bir) adet OTANTİK ve BAĞIMSIZ mekan öner. 
    3. KESİN KURAL: AVM (Alışveriş Merkezi), AVM yemek katı (Food Court) veya Plaza içi mekanlar KESİNLİKLE YASAKTIR. (Örn: Cepa, Kentpark, Ankamall, Armada gibi yerler yasak). 
    4. Bunun yerine Tunalı, Bahçelievler, Kızılay, Çayyolu gibi yerlerdeki sokak konseptli yerleri, geniş menülü bağımsız restoranları veya otantik pubları (Örn: IF Sokak vb.) seç.
    5. Bu mekanın Google Haritalar'daki tahmini puanını (örneğin 4.4, 4.7 gibi) belirt.
    
    Yanıtını aşağıdaki JSON formatında ver:
    {{
      "mekan_adi": "Mekanın Adı ve Semti",
      "puan": "4.5",
      "sebep": "Neden burayı seçtiğini anlatan açıklama."
    }}
    """
    
    try:
        response = client.models.generate_content(
            model='gemini-2.5-flash',
            contents=prompt,
            # YENİ: Gemini'ı kesinlikle sadece JSON vermeye zorluyoruz
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
            ),
        )
        
        # Artık replace yapmamıza gerek yok, doğrudan temiz JSON geliyor
        ai_data = json.loads(response.text)
        
        return {
            "status": "success", 
            "mekan_adi": ai_data.get("mekan_adi", "Mekan Bulunamadı"),
            "puan": str(ai_data.get("puan", "-")),
            "sebep": ai_data.get("sebep", "Sebep belirtilmedi.")
        }
    except Exception as e:
        # Hata olursa gerçek mesajı dönüyoruz
        return {"status": "error", "message": f"Backend AI Hatası: {str(e)}"}