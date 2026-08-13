from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_DIR))

from verify_appcast_entry import verify_appcast_entry


SHORT_VERSION = "0.11.13-fire.10.8"
BUILD_VERSION = "1181"
SIGNATURE = "signed-value"
LENGTH = "12345"
URL = "https://example.test/Fire.dmg"


def appcast_item(*, length: str = LENGTH) -> str:
    return f"""
      <item>
        <sparkle:version>{BUILD_VERSION}</sparkle:version>
        <sparkle:shortVersionString>{SHORT_VERSION}</sparkle:shortVersionString>
        <enclosure url="{URL}" length="{length}"
          sparkle:edSignature="{SIGNATURE}" />
      </item>
    """


class VerifyAppcastEntryTests(unittest.TestCase):
    def write_appcast(self, items: str) -> Path:
        directory = Path(self.enterContext(tempfile.TemporaryDirectory()))
        path = directory / "appcast.xml"
        path.write_text(
            f"""<?xml version="1.0" encoding="utf-8"?>
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>{items}</channel>
            </rss>
            """,
            encoding="utf-8",
        )
        return path

    def verify(self, path: Path) -> None:
        verify_appcast_entry(
            path,
            SHORT_VERSION,
            BUILD_VERSION,
            SIGNATURE,
            LENGTH,
            URL,
        )

    def test_accepts_one_exact_match(self) -> None:
        self.verify(self.write_appcast(appcast_item()))

    def test_rejects_release_metadata_mismatch(self) -> None:
        path = self.write_appcast(appcast_item(length="999"))
        with self.assertRaisesRegex(ValueError, "length"):
            self.verify(path)

    def test_rejects_duplicate_version_entries(self) -> None:
        path = self.write_appcast(appcast_item() + appcast_item())
        with self.assertRaisesRegex(ValueError, "found 2"):
            self.verify(path)


if __name__ == "__main__":
    unittest.main()
