import 'package:firebase_ai/firebase_ai.dart';

class AiDescriptionRequest {
  const AiDescriptionRequest({
    required this.localeCode,
    required this.professions,
    required this.years,
    required this.specialties,
    required this.serviceStyle,
    required this.thingsYouDo,
    required this.thingsYouDontDo,
    this.town,
  });

  final String localeCode;
  final List<String> professions;
  final String years;
  final String specialties;
  final String serviceStyle;
  final String thingsYouDo;
  final String thingsYouDontDo;
  final String? town;
}

class AiJobRequestDescriptionRequest {
  const AiJobRequestDescriptionRequest({
    required this.localeCode,
    required this.professionName,
    required this.mainNeed,
    required this.problemOrPlace,
    required this.sizeOrUrgency,
    required this.importantDetails,
    this.town,
  });

  final String localeCode;
  final String professionName;
  final String mainNeed;
  final String problemOrPlace;
  final String sizeOrUrgency;
  final String importantDetails;
  final String? town;
}

class AiDescriptionService {
  static final GenerativeModel _model = FirebaseAI.googleAI().generativeModel(
    model: 'gemini-2.5-flash',
  );

  static Future<String> generateDescription(
    AiDescriptionRequest request,
  ) async {
    final language = request.localeCode == 'he' ? 'Hebrew' : 'English';
    final professionText = request.professions.isEmpty
        ? (request.localeCode == 'he' ? 'בעל/ת מקצוע' : 'service professional')
        : request.professions.join(', ');
    final townText = (request.town ?? '').trim().isEmpty
        ? (request.localeCode == 'he'
              ? 'No city was provided.'
              : 'No city was provided.')
        : (request.localeCode == 'he'
              ? 'City/area: ${request.town!.trim()}.'
              : 'City/area: ${request.town!.trim()}.');

    final prompt =
        '''
Write one polished profile description for a worker profile app.

Requirements:
- Output language: $language
- Write in first person.
- Return only the final description with no title, no bullets, no markdown.
- Keep it concise, natural, and trustworthy.
- Mention experience, specialties, what I do, what I do not do, and service style.
- If city/area exists, mention it naturally.
- Do not invent certifications, guarantees, or services that were not provided.
- Avoid repetition and exaggerated marketing language.
- Length target: 70 to 120 words.

Worker details:
- Profession(s): $professionText
- Years of experience: ${request.years}
- Specialties: ${request.specialties}
- Service style: ${request.serviceStyle}
- Things I do: ${request.thingsYouDo}
- Things I do not do: ${request.thingsYouDontDo}
- $townText
''';

    final response = await _model.generateContent([Content.text(prompt)]);
    final text = response.text?.trim() ?? '';
    if (text.isEmpty) {
      throw StateError('AI returned an empty description.');
    }
    return text;
  }

  static Future<String> generateJobRequestDescription(
    AiJobRequestDescriptionRequest request,
  ) async {
    final language = request.localeCode == 'he'
        ? 'Hebrew'
        : request.localeCode == 'ar'
        ? 'Arabic'
        : 'English';
    final townText = (request.town ?? '').trim().isEmpty
        ? 'No city/area was provided.'
        : 'City/area: ${request.town!.trim()}.';

    final prompt =
        '''
Write one clear job description for a customer who already selected a specific professional in a service marketplace app.

Requirements:
- Output language: $language
- Write in first person.
- Return only the final description with no title, no bullets, no markdown.
- Keep it concise, clear, and practical.
- Use only the details that were actually provided.
- If some fields are empty, ignore them naturally.
- Mention what I need, the problem or place, size/urgency, and important details when available.
- Write it so the selected professional can quickly understand what I need.
- Do not write it like I am searching for a professional.
- Avoid phrases like "I need a $language professional", "I am looking for", or "request type".
- Focus on the actual job, issue, place, urgency, and practical details.
- Do not mention the profession name unless it helps the description sound natural.
- Do not invent facts, dimensions, materials, or timing that were not provided.
- Length target: 60 to 110 words.

Request details:
- Profession: ${request.professionName}
- Main need: ${request.mainNeed}
- Problem or place: ${request.problemOrPlace}
- Size or urgency: ${request.sizeOrUrgency}
- Important details: ${request.importantDetails}
- $townText
''';

    final response = await _model.generateContent([Content.text(prompt)]);
    final text = response.text?.trim() ?? '';
    if (text.isEmpty) {
      throw StateError('AI returned an empty job request description.');
    }
    return text;
  }
}
