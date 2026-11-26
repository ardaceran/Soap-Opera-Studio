"""Prompts and validation for the season plan and episode scripts."""

SYSTEM = (
    "You are the head writer of a short vertical-video soap opera for a mobile app. "
    "Write dramatic, family-friendly scenes: no explicit sex, no graphic violence, "
    "no hate, no real people. Every episode ends on a cliffhanger. "
    "Answer with JSON only, exactly in the requested shape."
)

MIN_SCENES, MAX_SCENES = 8, 20

# Shot types the writer picks from; the picture prompt turns each into framing words.
SHOTS = ["establishing", "wide", "medium", "close-up", "over-the-shoulder",
         "detail", "silhouette"]
MAX_LINE = 220


class StoryError(Exception):
    pass


def _cast(series: dict) -> str:
    lines = []
    for c in series.get("characters") or []:
        desc = f" - {c['description']}" if c.get("description") else ""
        lines.append(f"- {c['name']} ({c.get('role') or 'character'}){desc}")
    return "\n".join(lines)


def season_plan_prompt(series: dict) -> str:
    return f"""Plan a 5-episode season.

Series: {series['title']}
Genre: {series['genre']}
Setting: {series['setting']}
Characters:
{_cast(series)}

Also fix how each character looks, so every picture of the season shows the same
person: age, build, face, hair, and one outfit they keep wearing (one sentence each).
And fix one visual style for the whole season: colour palette, light, mood
(one sentence, e.g. "cold blue-grey palette, stormy night light, wet reflections").

Return JSON:
{{"logline": "one sentence",
  "visual_style": "one sentence",
  "looks": {{"<character name>": "how they look", ...}},
  "episodes": [{{"number": 1, "title": "...", "outline": "2-3 sentences"}}, ... 5 items]}}"""


def episode_prompt(series: dict, number: int, previous: list, winner,
                   last_scenes=None) -> str:
    plan = series.get("season_plan") or {}
    outline = ""
    for ep in plan.get("episodes") or []:
        if ep.get("number") == number:
            outline = ep.get("outline", "")
    story_so_far = "\n".join(
        f"- Episode {p['number']} \"{p.get('title') or ''}\": {p.get('summary') or ''}"
        for p in previous
    ) or "- (this is the first episode)"
    vote = f"\nViewers voted: {winner}\nThis episode MUST follow that choice.\n" if winner else ""
    last = ""
    if last_scenes:
        lines = "\n".join(f"  {i + 1}. {d}" for i, d in enumerate(last_scenes))
        last = (f"\nThe previous episode, scene by scene (continue exactly from its "
                f"last scene):\n{lines}\n")
    names = ", ".join(c["name"] for c in series.get("characters") or [])
    return f"""Write episode {number}.

Series: {series['title']} ({series['genre']}), set in {series['setting']}.
Season logline: {plan.get('logline', '')}
Planned outline for this episode: {outline or '(free)'}
Characters:
{_cast(series)}

Story so far:
{story_so_far}
{last}{vote}
Continuity (very important):
- This is the SAME story with the SAME people: never contradict earlier episodes.
- Keep where each character is, what they know and what happened to them; a fact
  revealed earlier stays true. Start where the previous episode ended.
- Describe each character in "visual" with their fixed look from the cast list.

Rules:
- 12 to 15 scenes, about 60-90 seconds in total; one short spoken line per scene (max 25 words).
- "speaker" is one of: {names}, Narrator.
- "shot" is one of: {", ".join(SHOTS)}. Vary it like a TV editor: never the same shot
  twice in a row, open with an establishing shot, use close-ups for strong emotions.
- "visual" describes the still image: name EVERY person who is visible (only people
  from the cast) and nobody else; where they are in the frame; place, light, mood.
  No text in the image.
- Narrator scenes show the place, the weather or an object (establishing, wide,
  detail or silhouette shots), not a character's face.
- End with a cliffhanger and give 3 short options for what happens next (viewers vote on them).

Return JSON:
{{"title": "...", "summary": "2 sentences for the series bible",
  "scenes": [{{"speaker": "...", "line": "...", "shot": "...", "visual": "..."}}],
  "poll_options": ["...", "...", "..."]}}"""


def validate_plan(plan: dict) -> dict:
    eps = plan.get("episodes")
    if not isinstance(eps, list) or not eps:
        raise StoryError("season plan has no episodes")
    looks = plan.get("looks") if isinstance(plan.get("looks"), dict) else {}
    return {
        "logline": str(plan.get("logline", ""))[:300],
        "visual_style": " ".join(str(plan.get("visual_style", "")).split())[:300],
        "looks": {str(k)[:60]: " ".join(str(v).split())[:300]
                  for k, v in looks.items() if str(v).strip()},
        "episodes": [
            {"number": int(e.get("number", i + 1)),
             "title": str(e.get("title", ""))[:120],
             "outline": str(e.get("outline", ""))[:600]}
            for i, e in enumerate(eps[:10])
        ],
    }


def validate_episode(ep: dict, character_names: list) -> dict:
    """Clean the model output into what the database function expects."""
    allowed = {n.lower(): n for n in character_names}
    allowed["narrator"] = "Narrator"
    scenes = []
    for s in ep.get("scenes") or []:
        line = " ".join(str(s.get("line", "")).split())[:MAX_LINE]
        if not line:
            continue
        speaker = allowed.get(str(s.get("speaker", "")).strip().lower(), "Narrator")
        shot = str(s.get("shot", "")).strip().lower()
        if shot not in SHOTS:
            shot = "establishing" if speaker == "Narrator" else "medium"
        visual = " ".join(str(s.get("visual", "")).split())[:400]
        scenes.append({
            "dialogue": f"{speaker}: {line}",
            # The shot travels inside the visual text ("Close-up: ..."): no schema change.
            "visual": f"{shot.capitalize()}: {visual}",
        })
    if len(scenes) < MIN_SCENES:
        raise StoryError(f"only {len(scenes)} usable scenes (need {MIN_SCENES})")
    options = [" ".join(str(o).split())[:80] for o in ep.get("poll_options") or []]
    options = [o for o in options if o][:4]
    if len(options) < 2:
        raise StoryError("episode needs at least 2 poll options")
    title = " ".join(str(ep.get("title", "")).split())[:120] or "Untitled"
    summary = " ".join(str(ep.get("summary", "")).split())[:600]
    return {"title": title, "summary": summary,
            "scenes": scenes[:MAX_SCENES], "poll_options": options}
