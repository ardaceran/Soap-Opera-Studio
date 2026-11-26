"""Screenshots of the published web app for the weekly progress report.

    python tools/report_shots.py <app url> <out dir>

Opens the app like a phone, takes the login screen, then "Browse as guest" and the
home / series screens. Flutter draws on a canvas, so it turns on Flutter's
accessibility tree to find buttons by their text.
"""
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

url, out = sys.argv[1], Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)


def shot(page, name):
    page.wait_for_timeout(2500)
    page.screenshot(path=str(out / f"{name}.png"))
    print("saved", name)


def enable_semantics(page):
    try:
        page.locator("flt-semantics-placeholder").click(force=True, timeout=5000)
        page.wait_for_timeout(800)
    except Exception as e:
        print("semantics:", e)


def tap(page, text):
    try:
        page.get_by_role("button", name=text).first.click(timeout=8000)
        return True
    except Exception:
        try:
            page.get_by_text(text).first.click(timeout=5000)
            return True
        except Exception as e:
            print("could not tap", text, e)
            return False


with sync_playwright() as p:
    b = p.chromium.launch()
    page = b.new_page(viewport={"width": 390, "height": 844}, device_scale_factor=2)
    page.goto(url, wait_until="networkidle", timeout=90000)
    page.wait_for_timeout(6000)
    shot(page, "01_login")
    enable_semantics(page)
    ok = tap(page, "Browse as guest")
    if not ok:
        # Flutter draws on a canvas: tap where the button is on a 390x844 screen.
        page.mouse.click(195, 576)
        ok = True
    if ok:
        page.wait_for_timeout(5000)
        shot(page, "02_home")
        # open the first series card, if any
        # open the first series card (upper part of the list)
        page.mouse.click(195, 260)
        page.wait_for_timeout(6000)
        shot(page, "03_series")
        page.mouse.wheel(0, 500)
        shot(page, "04_series_scrolled")
    b.close()
