import re
import unittest
from pathlib import Path


UI_DIR = Path(__file__).resolve().parents[1] / "ui"


class CleanUiTest(unittest.TestCase):
    def test_ui_avoids_banned_generated_patterns(self) -> None:
        combined = "\n".join(path.read_text(encoding="utf-8") for path in UI_DIR.iterdir())

        banned = [
            "font-extrabold",
            "font-black",
            "font-weight: 800",
            "font-weight: 900",
            "shadow-xl",
            "shadow-2xl",
            "tracking-[0.18em]",
            "tracking-[0.2em]",
            "tracking-[0.24em]",
        ]
        for token in banned:
            self.assertNotIn(token, combined)

    def test_frontend_has_loading_content_and_empty_states(self) -> None:
        html = (UI_DIR / "index.html").read_text(encoding="utf-8")
        script = (UI_DIR / "app.js").read_text(encoding="utf-8")

        self.assertIn("Checking backend", html)
        self.assertIn("No image selected", html)
        self.assertIn("No result yet", html)
        self.assertRegex(script, re.compile(r"setBusy\(true\)"))
        self.assertRegex(script, re.compile(r"setBusy\(false\)"))


if __name__ == "__main__":
    unittest.main()
