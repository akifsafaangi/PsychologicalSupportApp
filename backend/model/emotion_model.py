from transformers import BertTokenizer, BertForSequenceClassification, pipeline

class GoEmotionsModel:
    def __init__(self):
        self.tokenizer = BertTokenizer.from_pretrained("monologg/bert-base-cased-goemotions-original")
        self.model = BertForSequenceClassification.from_pretrained("monologg/bert-base-cased-goemotions-original")
        self.goemotions = pipeline("text-classification", model=self.model, tokenizer=self.tokenizer)

    def predict(self, text):
        return self.goemotions(text)