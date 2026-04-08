from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from google import genai
from google.genai import types as genai_types 
import json
import os
from dotenv import load_dotenv

load_dotenv()

client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))

app = FastAPI(title="Grup Mekan Çöpçatanı API")

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
    2. Herkesi tatmin edecek menüye sahip 1 adet OTANTİK ve BAĞIMSIZ mekan öner. (AVM KESİNLİKLE YASAK).
    3. Bu mekanın puanını belirt.
    4. YENİ GÖREV: 'kisa_ozet' alanına kişi isimlerini KESİNLİKLE kullanmadan, SADECE istenilen ürünleri vurgulayan, MAKSİMUM 10-15 KELİMELİK çok kısa bir cümle yaz. (Örn: "Suşi, çıtır tavuk ve sosisliyi aynı sokakta buluşturan, otoparklı harika bir nokta!").
    5. 'sebep' kısmında ise mekanın neden seçildiğini uzun uzun detaylandır.
    
    Yanıtını aşağıdaki JSON formatında ver:
    {{
      "mekan_adi": "Mekanın Adı ve Semti",
      "puan": "4.5",
      "kisa_ozet": "Kısa ve öz, isim içermeyen 10 kelimelik özet.",
      "sebep": "Neden burayı seçtiğini anlatan uzun detaylı açıklama."
    }}
    """
    
    try:
        response = client.models.generate_content(
            model='gemini-2.5-flash',
            contents=prompt,
            config=genai_types.GenerateContentConfig(
                response_mime_type="application/json",
            ),
        )
        
        ai_data = json.loads(response.text)
        
        return {
            "status": "success", 
            "mekan_adi": ai_data.get("mekan_adi", "Mekan Bulunamadı"),
            "puan": str(ai_data.get("puan", "-")),
            "kisa_ozet": ai_data.get("kisa_ozet", "Sizin için en ideal ortak nokta!"),
            "sebep": ai_data.get("sebep", "Sebep belirtilmedi.")
        }
    except Exception as e:
        return {"status": "error", "message": f"Backend AI Hatası: {str(e)}"}