from flask import Flask, request, jsonify
from flask_cors import CORS
from transformers import BertTokenizer, BertForSequenceClassification
from deep_translator import GoogleTranslator
import torch
import openai
import whisper
import subprocess
import os
import logging

# ==== OpenAI API Anahtarı ====
#openai.api_key = "NOT_INCLUDED"

# ==== Flask Uygulaması ====
app = Flask(__name__)
CORS(app)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ==== Etiketler ====
labels = [
    "admiration", "amusement", "anger", "annoyance", "approval", "caring", "confusion",
    "curiosity", "desire", "disappointment", "disapproval", "disgust", "embarrassment",
    "excitement", "fear", "gratitude", "grief", "joy", "love", "nervousness", "optimism",
    "pride", "realization", "relief", "remorse", "sadness", "surprise", "neutral"
]

# ==== Model Yükleme ====
tokenizer = BertTokenizer.from_pretrained("monologg/bert-base-cased-goemotions-original")
model = BertForSequenceClassification.from_pretrained("monologg/bert-base-cased-goemotions-original", num_labels=28)
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model.to(device)

# ==== Whisper Modeli ====
whisper_model = whisper.load_model("small")

# ==== GPT Destek Mesajı ====
def get_emotional_support(message, primary_emotion, alternatives):
    alt_text = "\n".join([f"- {e['emotion']} (%{e['probability']:.1f})" for e in alternatives])
    prompt = f"""
Sen bir psikolojik destek asistanısın. Kullanıcının metni:
\"{message}\"

Algılanan ana duygu: {primary_emotion}
Diğer olası duygular:
{alt_text}

Bu kişiye anlayışlı, kısa ve destekleyici bir mesaj ver. Ayrıca müzik, film önerisi yap(Müzik,film izlemeni öneririm yazma. Film, müzik isimleri ver). Moral artırıcı aktivite öner.
"""
    try:
        response = openai.ChatCompletion.create(
            model="gpt-3.5-turbo",
            messages=[{"role": "user", "content": prompt}],
            max_tokens=400,
            temperature=0.7,
        )
        return response.choices[0].message["content"]
    except Exception as e:
        logger.error(f"GPT API hatası: {str(e)}")
        return "Şu anda duygusal destek verilemiyor. Lütfen tekrar deneyin."

# ==== SES DOSYASINI METNE ÇEVİR ====
@app.route("/transcribe", methods=["POST"])
def transcribe():
    if 'file' not in request.files:
        return jsonify({"error": "Dosya bulunamadı"}), 400

    file = request.files['file']
    input_path = f"temp_{file.filename}"
    output_path = "output.wav"

    file.save(input_path)

    subprocess.run([
        "ffmpeg", "-y", "-i", input_path,
        "-ar", "16000", "-ac", "1", output_path
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    result = whisper_model.transcribe(output_path, language="turkish")

    os.remove(input_path)
    os.remove(output_path)

    return jsonify({"text": result["text"]})

# ==== METNE GÖRE DUYGU ANALİZİ YAP ====
@app.route("/analyze", methods=["POST"])
def analyze():
    try:
        data = request.get_json()
        text = data.get("text", "")
        language = data.get("language", "en")

        if not text:
            return jsonify({"error": "Boş metin gönderildi"}), 400

        original_text = text
        if language == "tr":
            translator = GoogleTranslator(source="tr", target="en")
            translated_text = translator.translate(text.strip('"'))
            text = translated_text

        inputs = tokenizer(text, return_tensors="pt", padding=True, truncation=True).to(device)
        with torch.no_grad():
            outputs = model(**inputs)
            logits = outputs.logits
            predicted_class = torch.argmax(logits, dim=-1).item()
            probabilities = torch.nn.functional.softmax(logits, dim=-1)[0]
            probability_score = probabilities[predicted_class].item()

            top_k = 3
            top_probs, top_indices = torch.topk(probabilities, top_k)
            alternatives = []
            for idx, prob in zip(top_indices, top_probs):
                idx_val = idx.item()
                if idx_val != predicted_class:
                    alternatives.append({
                        "emotion": labels[idx_val],
                        "probability": prob.item() * 100
                    })
                if len(alternatives) >= 2:
                    break

        emotion = labels[predicted_class]
        support = get_emotional_support(original_text, emotion, alternatives)

        response = {
            "label": emotion,
            "probability": round(probability_score * 100, 2),
            "alternatives": alternatives,
            "support": support
        }

        if language == "tr":
            response["original_text"] = original_text
            response["translated_text"] = text

        return jsonify(response)

    except Exception as e:
        logger.error(f"Hata: {str(e)}")
        return jsonify({"error": str(e)}), 500

# ==== Sunucuyu Başlat ====
if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5002)
