"""Job handlers: what the worker does for each job type."""

from . import story


class Pipeline:
    def __init__(self, db, llm, poll_hours: int):
        self.db = db
        self.llm = llm
        self.poll_hours = poll_hours

    def run(self, job: dict) -> None:
        kind = job["type"]
        if kind == "season_plan":
            self.season_plan(job)
        elif kind == "script":
            self.script(job)
        else:
            raise NotImplementedError(f"job type '{kind}' is not supported yet")

    # Season plan -> save it, then queue the script of episode 1.
    def season_plan(self, job: dict) -> None:
        series = self.db.get_series(job["series_id"])
        raw = self.llm.generate_json(
            story.SYSTEM, story.season_plan_prompt(series), "season_plan")
        plan = story.validate_plan(raw)
        self.db.save_season_plan(series["id"], plan)
        self.db.enqueue(series["id"], "script", {"episode": 1})

    # Episode script -> publish episode + scenes + poll in one transaction.
    def script(self, job: dict) -> None:
        number = int((job.get("payload") or {}).get("episode", 1))
        series = self.db.get_series(job["series_id"])
        previous = [e for e in self.db.episode_summaries(series["id"])
                    if e["number"] < number]
        winner = self.db.poll_winner(series["id"], number - 1) if number > 1 else None
        raw = self.llm.generate_json(
            story.SYSTEM,
            story.episode_prompt(series, number, previous, winner),
            "episode",
        )
        names = [c["name"] for c in series.get("characters") or []]
        ep = story.validate_episode(raw, names)
        self.db.publish_episode(
            series["id"], number, ep["title"], ep["summary"],
            ep["scenes"], ep["poll_options"], self.poll_hours)
