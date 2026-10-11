"""Exercise the actual HTTP boundary with disposable loopback servers."""
import json
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from bot import CleanerBot, make_handler


class WebhookTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.fail = False
        def transport(url, data, headers=None):
            self.calls.append((url, data, headers))
            if self.fail:
                raise OSError("fixture authority unavailable")
            if "/internal/" in url:
                return {"ads_enabled": False}
            return {"ok": True}
        self.bot = CleanerBot("fixture", "worker", True, transport,
                              authority_origin="http://ads:4352")
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.bot, "s" * 32))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.origin = "http://127.0.0.1:" + str(self.server.server_port)
        self.payment = {"message": {"chat": {"id": 42, "type": "private"}, "from": {"id": 42},
            "successful_payment": {"invoice_payload": "yeti3_ads_" + "a" * 32,
                "currency": "XTR", "total_amount": 50, "telegram_payment_charge_id": "fixture-charge"}}}

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join()

    def request(self, secret, value=None, path="/webhook"):
        request = Request(self.origin + path,
                          data=json.dumps(value or self.payment).encode(),
                          headers={"X-Telegram-Bot-Api-Secret-Token": secret,
                                   "Content-Type": "application/json"})
        try:
            with urlopen(request, timeout=2) as response:
                return response.status
        except HTTPError as error:
            return error.code

    def test_forged_secret_and_wrong_route_never_reach_payment(self):
        self.assertEqual(self.request("forged"), 403)
        self.assertEqual(self.request("s" * 32, path="/elsewhere"), 403)
        self.assertEqual(self.calls, [])

    def test_payment_acknowledged_only_after_internal_authority(self):
        self.assertEqual(self.request("s" * 32), 200)
        self.assertEqual(self.calls[0][0], "http://ads:4352/api/network/v1/internal/telegram/ads")
        self.assertEqual(self.calls[0][2], {"x-network-bot-token": "worker"})
        self.assertEqual(self.calls[0][1]["action"], "paid")
        self.assertTrue(self.calls[-1][0].endswith("/sendMessage"))

    def test_unavailable_authority_requests_retry_without_success_message(self):
        self.fail = True
        self.assertEqual(self.request("s" * 32), 503)
        self.assertEqual(len(self.calls), 1)
        self.assertIn("/internal/", self.calls[0][0])

    def test_health_contains_no_credentials_and_is_not_payment_proof(self):
        with urlopen(self.origin + "/health", timeout=2) as response:
            self.assertEqual(json.load(response), {"ready": True, "checkout_enabled": True})
        self.assertEqual(self.calls, [])

    def test_origin_cannot_smuggle_paths_or_credentials(self):
        for value in ("file:///tmp/test", "https://user:secret@example.org", "http://ads/api", "http://ads?key=x"):
            with self.assertRaises(ValueError):
                CleanerBot("fixture", "worker", authority_origin=value)


if __name__ == "__main__":
    unittest.main()
