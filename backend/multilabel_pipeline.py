import numpy as np
from transformers import Pipeline
import torch
import torch.nn.functional as F

class MultiLabelPipeline(Pipeline):
    def __init__(
        self,
        model,
        tokenizer,
        threshold=0.3
    ):
        super().__init__(
            model=model,
            tokenizer=tokenizer,
            device=-1 if not torch.cuda.is_available() else 0,
        )
        self.threshold = threshold

    def __call__(self, texts, **kwargs):
        inputs = self.tokenizer(
            texts,
            return_tensors="pt",
            padding=True,
            truncation=True,
        ).to(self.device)

        outputs = self.model(**inputs)
        logits = outputs[0]
        probs = F.sigmoid(logits)

        # Tek bir metin için liste formatına dönüştür
        if not isinstance(texts, list):
            texts = [texts]
            probs = probs.unsqueeze(0)

        predictions = []
        for prob in probs:
            # Threshold üzerindeki etiketleri seç
            mask = prob > self.threshold
            labels = []
            scores = []

            for idx, (label, score) in enumerate(zip(mask.nonzero().squeeze(1).tolist(), prob[mask].tolist())):
                labels.append(self.model.config.id2label[label])
                scores.append(score)

            predictions.append({"labels": labels, "scores": scores})

        return predictions if len(predictions) > 1 else predictions[0]
