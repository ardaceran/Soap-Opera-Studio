"""Job handlers: what the worker does for each job type.

    season_plan -> script (episode 1) -> assemble (video of episode 1)
    poll closes -> script (episode 2, follows the winning option) -> assemble ...

After each job, `self.last` holds what the worker writes back to the jobs row:
the provider(s) used, the cost in USD and the episode the job belongs to.
"""

import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

from . import http, media, story, video


class Pipeline:
    def __init__(self, db, llm, poll_hours: int, images=None, voice=None,
                 video_height: int = 1920, max_scenes: int = 0, prices=(3.0, 15.0),
                 poll_minutes: int = 0):
        self.db = db
        self.llm = llm
        self.poll_hours = poll_hours
        self.images = images or media.FakeImages()
        self.voice = voice or media.FakeVoice()
        self.video_height = video_height
        self.max_scenes = max_scenes
        self.prices = prices  # Claude USD per million tokens (input, output)
        # How long a vote stays open once the episode video is ready.
        self.poll_window = timedelta(minutes=poll_minutes or poll_hours * 60)
        self.last = {}

    def run(self, job: dict) -> None:
        self.last = {"provider": self.llm.name, "cost": 0.0, "episode_id": None}
        kind = job["type"]
        if kind == "season_plan":
            self.season_plan(job)
        elif kind == "script":
            self.script(job)
        elif kind == "assemble":
            self.assemble(job)
        else:
            raise NotImplementedError(f"job type '{kind}' is not supported yet")
        model = getattr(self.llm, "last_model", None)
        if kind != "assemble" and isinstance(model, str):
            self.last["provider"] = f"{self.llm.name}:{model}"  # e.g. a backup model answered

    def _llm_cost(self) -> float:
        usage = getattr(self.llm, "last_usage", None) or {}
        p_in, p_out = self.prices
        return (usage.get("input_tokens", 0) * p_in
                + usage.get("output_tokens", 0) * p_out) / 1e6

    # Season plan -> save it, then queue the script of episode 1.
    def season_plan(self, job: dict) -> None:
        series = self.db.get_series(job["series_id"])
        raw = self.llm.generate_json(
            story.SYSTEM, story.season_plan_prompt(series), "season_plan")
        self.last["cost"] = self._llm_cost()
        plan = story.validate_plan(raw)
        self.db.save_season_plan(series["id"], plan)
        # Characters the owner did not describe get the look the writer fixed for them.
        looks = {k.lower(): v for k, v in (plan.get("looks") or {}).items()}
        for c in series.get("characters") or []:
            look = looks.get(c["name"].lower())
            if look and not c.get("description") and c.get("id"):
                self.db.update_character(c["id"], {"description": look})
        # Start after any episodes the owner already wrote by hand, never over them.
        first = 1
        while self.db.episode_exists(series["id"], first):
            first += 1
        self.db.enqueue(series["id"], "script", {"episode": first})

    # Episode script -> publish episode + scenes + poll in one transaction,
    # then queue the video.
    def script(self, job: dict) -> None:
        number = int((job.get("payload") or {}).get("episode", 1))
        series = self.db.get_series(job["series_id"])
        previous = [e for e in self.db.episode_summaries(series["id"])
                    if e["number"] < number]
        winner = self.db.poll_winner(series["id"], number - 1) if number > 1 else None
        last_scenes = (self.db.episode_scenes(series["id"], number - 1)
                       if number > 1 and hasattr(self.db, "episode_scenes") else [])
        raw = self.llm.generate_json(
            story.SYSTEM,
            story.episode_prompt(series, number, previous, winner, last_scenes),
            "episode",
        )
        self.last["cost"] = self._llm_cost()
        names = [c["name"] for c in series.get("characters") or []]
        plan = series.get("season_plan") or {}
        ep = story.validate_episode(raw, names, list((plan.get("sets") or {}).keys()))
        episode_id = self.db.publish_episode(
            series["id"], number, ep["title"], ep["summary"],
            ep["scenes"], ep["poll_options"], self.poll_hours)
        self.last["episode_id"] = episode_id
        self.db.enqueue(series["id"], "assemble", {"episode": number},
                        episode_id=episode_id)

    # Images + voice for every scene, then FFmpeg -> MP4 in Storage.
    def assemble(self, job: dict) -> None:
        ep = self.db.get_episode_for_render(job["episode_id"])
        series = ep["series"]
        self.last.update(provider=f"{self.images.name}+{self.voice.name}",
                         episode_id=ep["id"])
        cost = 0.0
        sid, eid = series["id"], ep["id"]

        # 1. Every character keeps one voice and one reference portrait for the whole series.
        chars = {c["name"]: c for c in series.get("characters") or []}
        used = {c["voice_id"] for c in chars.values()
                if c.get("voice_id") and self.voice.valid_voice(c["voice_id"])}
        portraits = {}  # name -> jpeg bytes made in this run
        for i, c in enumerate(chars.values()):
            # A voice from another provider (e.g. ElevenLabs id, now Cloudflare) is replaced.
            if not (c.get("voice_id") and self.voice.valid_voice(c["voice_id"])):
                c["voice_id"] = media.pick_voice(c, used, self.voice, i)
                used.add(c["voice_id"])
                self.db.update_character(c["id"], {"voice_id": c["voice_id"]})
            if not c.get("ref_image_paths"):
                try:
                    img, usd = self.images.reference(c, series)
                except media.ContentFlagged:
                    # A refused portrait must not stop the episode: a plain placeholder.
                    img, usd = media.FakeImages().reference(c, series)
                cost += usd
                portraits[c["name"]] = img
                path = self.db.upload("character-refs",
                                      f"{series['owner_id']}/{sid}/{c['id']}.jpg",
                                      img, "image/jpeg")
                c["ref_image_paths"] = [path]
                self.db.update_character(c["id"], {"ref_image_paths": [path]})

        scenes = ep["scenes"][: self.max_scenes] if self.max_scenes else ep["scenes"]
        set_pics = {}  # set name -> reference picture bytes (keeps backgrounds the same)
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            parts = []
            for s in scenes:
                speaker, line = split_dialogue(s.get("dialogue") or "")
                c = chars.get(speaker)
                ref = (self._portrait_ref(c, portraits)
                       if c and media.use_portrait(s.get("visual_prompt") or "", speaker, series)
                       else None)
                set_ref, usd = self._set_ref(series, s.get("visual_prompt") or "", set_pics)
                cost += usd
                try:
                    extra = {"set_ref": set_ref} if set_ref else {}
                    img, usd = self.images.scene(s.get("visual_prompt") or line, speaker,
                                                 series, ref, **extra)
                except media.ContentFlagged:
                    # One refused picture must not sink the whole episode.
                    img, usd = media.FakeImages().scene(line, speaker, series, None)
                cost += usd
                mp3, usd = self.voice.speak(line, c["voice_id"] if c else self.voice.narrator)
                cost += usd
                n = f"{s['idx']:03d}"
                (work / f"img{n}.jpg").write_bytes(img)
                (work / f"aud{n}.mp3").write_bytes(mp3)
                self.db.update_scene(s["id"], {
                    "image_path": self.db.upload("scene-media", f"{sid}/{eid}/{n}.jpg",
                                                 img, "image/jpeg"),
                    "audio_path": self.db.upload("scene-media", f"{sid}/{eid}/{n}.mp3",
                                                 mp3, "audio/mpeg"),
                })
                parts.append({"image": f"img{n}.jpg", "audio": f"aud{n}.mp3",
                              "speaker": speaker, "line": line})

            mp4 = video.assemble(work, parts, ep.get("title") or "", ep["number"],
                                 ep.get("poll_options") or [], self.video_height)
            path = self.db.upload("episodes", f"{sid}/{eid}.mp4", mp4.read_bytes(),
                                  "video/mp4")
        self.db.set_episode_video(eid, path)
        # Viewers can only vote after watching, so the vote clock starts now.
        self.db.set_poll_closes(eid, _iso(_now() + self.poll_window))
        self.last["cost"] = cost

    def _set_ref(self, series: dict, visual: str, set_pics: dict):
        """(reference picture of the scene's set, cost). Made once per set and series,
        saved in Storage and listed in season_plan["set_refs"]."""
        if getattr(self.images, "ref_kind", None) != "bytes" or not hasattr(self.images, "set_reference"):
            return None, 0.0
        name = media.split_set(visual)[1]
        desc = media.set_description(name, series)
        if not desc:
            return None, 0.0
        if name in set_pics:
            return set_pics[name], 0.0
        plan = series.get("season_plan") or {}
        refs = plan.setdefault("set_refs", {})
        if refs.get(name):
            link = self.db.signed_url("character-refs", refs[name])
            set_pics[name] = http.download(link)
            return set_pics[name], 0.0
        try:
            img, usd = self.images.set_reference(name, desc, series)
        except media.ContentFlagged:
            return None, 0.0
        slug = "".join(ch if ch.isalnum() else "-" for ch in name.lower()).strip("-")[:40]
        path = self.db.upload("character-refs",
                              f"{series['owner_id']}/{series['id']}/set-{slug}.jpg",
                              img, "image/jpeg")
        refs[name] = path
        self.db.save_season_plan(series["id"], plan)
        set_pics[name] = img
        return img, usd

    def _portrait_ref(self, c: dict, portraits: dict):
        """The speaker's portrait in the form the image provider wants (link or bytes)."""
        kind = getattr(self.images, "ref_kind", None)
        if kind == "url":
            return self.db.signed_url("character-refs", c["ref_image_paths"][0])
        if kind == "bytes":
            if c["name"] not in portraits:
                link = self.db.signed_url("character-refs", c["ref_image_paths"][0])
                portraits[c["name"]] = http.download(link)
            return portraits[c["name"]]
        return None

    # Finished votes -> winner -> script job for the next episode.
    def close_due_polls(self, now=None) -> list:
        """Returns [(series_id, next episode number, winning label)] for each vote closed."""
        closed = []
        for poll in self.db.due_polls(_iso(now or _now())):
            ep = poll.get("episodes") or {}
            options = poll.get("poll_options") or []
            if not options or not ep:
                continue
            counts = self.db.vote_counts(poll["id"])
            # Most votes wins; a tie (or no votes) goes to the option listed first.
            best = max(options, key=lambda o: (counts.get(o["id"], 0), -options.index(o)))
            if not self.db.set_winner(poll["id"], best["id"]):
                continue  # another worker closed it a moment ago
            sid, nxt = ep["series_id"], int(ep["number"]) + 1
            if nxt <= self.season_length(sid) and not self.db.episode_exists(sid, nxt):
                self.db.enqueue(sid, "script", {"episode": nxt})
                closed.append((sid, nxt, best["label"]))
            else:
                closed.append((sid, None, best["label"]))  # season finished
        return closed

    def season_length(self, series_id: str) -> int:
        plan = (self.db.get_series(series_id) or {}).get("season_plan") or {}
        return len(plan.get("episodes") or []) or 5


def _now():
    return datetime.now(timezone.utc)


def _iso(t) -> str:
    return t.isoformat().replace("+00:00", "Z")


def split_dialogue(dialogue: str):
    """'Defne: I knew it.' -> ('Defne', 'I knew it.'); no name -> Narrator."""
    if ": " in dialogue:
        speaker, line = dialogue.split(": ", 1)
        if 0 < len(speaker) <= 40:
            return speaker.strip(), line.strip()
    return "Narrator", dialogue.strip()
