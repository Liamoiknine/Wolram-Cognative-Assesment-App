import json
from typing import Dict, List, Optional, Tuple
from openai import OpenAI
import os
from dotenv import load_dotenv

load_dotenv()


class LLMService:
    """LLM service for decision making using GPT-4o"""
    
    def __init__(self):
        self.client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
        self.model = os.getenv("LLM_MODEL", "gpt-4o")
        
    async def evaluate_abstraction_response(
        self,
        word1: str,
        word2: str,
        transcript: str
    ) -> Dict[str, any]:
        """
        Evaluate an abstraction task response asynchronously.
        
        Args:
            word1: First word in the pair
            word2: Second word in the pair
            transcript: User's transcribed response (may contain extra words, filler, etc.)
            
        Returns:
            {
                "category": str,  # The category the user identified (or "none" if incorrect)
                "is_correct": bool,  # Whether the response is correct
                "confidence": float,  # Confidence score 0.0-1.0
                "notes": str  # Additional notes about the evaluation
            }
        """
        # Handle empty/silent responses
        if not transcript or transcript.strip() == "":
            return {
                "category": "none",
                "is_correct": False,
                "confidence": 1.0,
                "notes": "No response detected - user remained silent"
            }
        
        prompt = f"""You are conducting the MoCA blind exam on a patietn and are currently evaluating answers for the abstraction section. In this section, the patient has been given two related words, and asked to name the category that unites them.

IMPORTANT: The transcript may contain extra words, filler speech, or background noise. Your job is to EXTRACT the actual answer the user gave, even if it's mixed with other words.

For example:
- "Train" and "Bicycle" → Correct answers include: "transportation", "vehicles", "modes of travel", etc.
- "Banana" and "Orange" → Correct answers include: "fruits", "fruit", etc.

EVALUATION RULES:
1. Look for ANY mention of a valid category, even if surrounded by other words
2. Accept synonyms and related terms (e.g., "fruit" = "fruits", "transport" = "transportation")
3. Be lenient - if the user clearly identified the category, mark it correct even if the transcript has extra words or the meaning was implicit
4. Only mark incorrect if NO valid category is mentioned and you get the sense the user doesn't understand the connection
5. If the transcript appears to be hallucinated text with no relevant category, mark as incorrect

Respond in JSON format with:
- "category": The category word/phrase you extracted from the transcript (or "none" if no valid category found)
- "is_correct": true if a valid category was identified, false otherwise
- "confidence": A float between 0.0 and 1.0 indicating confidence in the evaluation
- "notes": Brief explanation of what you found in the transcript and why it's correct/incorrect

Example responses:
{{"category": "transportation", "is_correct": true, "confidence": 0.95, "notes": "User said 'transportation' - clearly correct"}}
{{"category": "fruit", "is_correct": true, "confidence": 0.9, "notes": "User said 'fruit' even though transcript has other words - this is correct"}}
{{"category": "none", "is_correct": false, "confidence": 0.8, "notes": "No valid category mentioned in transcript"}}

Now that you understand the task, please evaluate the user's entry to this trial:
The word pair provided: "{word1}" and "{word2}"
The User's transcribed response: "{transcript}"
"""
        
        try:
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": "You are a neurologist assessing the cognitive function of a patient via an automated exam. Extract the actual answer from transcripts that may contain extra words an evaluate according to the contents and rules provided. Respond only with valid JSON."},
                    {"role": "user", "content": prompt}
                ],
                temperature=0.2,  # Lower temperature for more consistent extraction
                response_format={"type": "json_object"}
            )
            
            result = json.loads(response.choices[0].message.content)
            return {
                "category": result.get("category", "none"),
                "is_correct": result.get("is_correct", False),
                "confidence": float(result.get("confidence", 0.0)),
                "notes": result.get("notes", "")
            }
        except Exception as e:
            print(f"❌ LLMService: Error evaluating response: {e}")
            # Return default evaluation on error
            return {
                "category": "none",
                "is_correct": False,
                "confidence": 0.0,
                "notes": f"Evaluation error: {e}"
            }
    
    async def evaluate_working_memory_response(
        self,
        words: List[str],
        transcript: str
    ) -> Dict[str, any]:
        """
        Evaluate a working memory task response asynchronously.
        
        Args:
            words: List of expected words (e.g., ["chair", "book", "hand", "road", "cloud"])
            transcript: User's transcribed response (may contain extra words, filler, etc.)
            
        Returns:
            {
                "correct_words": List[str],  # Words correctly recalled (order doesn't matter)
                "score": float,  # Fraction: correct_words / total_words (0.0-1.0)
                "is_correct": bool,  # Whether all words were recalled (order doesn't matter)
                "confidence": float,  # Confidence score 0.0-1.0
                "notes": str  # Additional notes about the evaluation
            }
        """
        # Handle empty/silent responses
        if not transcript or transcript.strip() == "":
            return {
                "correct_words": [],
                "score": 0.0,
                "is_correct": False,
                "confidence": 1.0,
                "notes": "No response detected - user remained silent"
            }
        
        prompt = f"""You are conducting the MoCA blind exam on a patient and are currently evaluating answers for the working memory section. In this section, the patient has been given 5 words and asked to repeat them back.

IMPORTANT: The transcript may contain extra words, filler speech, or background noise. Your job is to EXTRACT the actual words the user said and check if they match the expected words. Order does NOT matter - you only need to check if the words were said, not the order they were said in.

EVALUATION RULES:
1. Extract words from the transcript, ignoring filler words like "um", "uh", "like", "you know", etc.
2. Check if extracted words match any of the expected words (order does not matter)
3. Be lenient with variations, like plurals or slight mispronunciations
4. Handle plurals and slight mispronunciations (e.g., "chairs" might be intended as "chair")
5. Score: Count how many of the expected words were said (regardless of order), divide by total expected words (e.g., 3 words said out of 5 = 0.6)
6. The "correct_words" array should contain all expected words that were found in the transcript (order doesn't matter)
7. Mark as correct (is_correct: true) only if ALL expected words were said (order doesn't matter)

Respond in JSON format with:
- "correct_words": Array of expected words that were found in the transcript (e.g., ["chair", "book", "hand"] if those 3 were said, regardless of order)
- "score": A float between 0.0 and 1.0 representing the fraction of expected words that were said (e.g., 3 out of 5 = 0.6)
- "is_correct": true if ALL expected words were said (order doesn't matter), false otherwise
- "confidence": A float between 0.0 and 1.0 indicating confidence in the evaluation
- "notes": Brief explanation of what you found in the transcript and why it's correct/incorrect

Example responses:
{{"correct_words": ["chair", "book", "hand", "road", "cloud"], "score": 1.0, "is_correct": true, "confidence": 0.95, "notes": "All 5 words were said"}}
{{"correct_words": ["chair", "book", "hand"], "score": 0.6, "is_correct": false, "confidence": 0.9, "notes": "Only 3 out of 5 words were said"}}
{{"correct_words": [], "score": 0.0, "is_correct": false, "confidence": 0.8, "notes": "No matching words found in transcript"}}

Now that you understand the task, please evaluate the user's entry to this trial:
Expected words: {', '.join(words)}
The User's transcribed response: "{transcript}"
"""
        
        try:
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": "You are a neurologist assessing the cognitive function of a patient via an automated exam. Extract words from transcripts that may contain extra words and evaluate accuracy according to the contents and rules provided. Order does not matter - only check if words were said. Respond only with valid JSON."},
                    {"role": "user", "content": prompt}
                ],
                temperature=0.2,  # Lower temperature for more consistent extraction
                response_format={"type": "json_object"}
            )
            
            result = json.loads(response.choices[0].message.content)
            return {
                "correct_words": result.get("correct_words", []),
                "score": float(result.get("score", 0.0)),
                "is_correct": result.get("is_correct", False),
                "confidence": float(result.get("confidence", 0.0)),
                "notes": result.get("notes", "")
            }
        except Exception as e:
            print(f"❌ LLMService: Error evaluating working memory response: {e}")
            # Return default evaluation on error
            return {
                "correct_words": [],
                "score": 0.0,
                "is_correct": False,
                "confidence": 0.0,
                "notes": f"Evaluation error: {e}"
            }

