"""YETI3 Cleaner bot. No credentials or payment ledger are stored locally.
Deploy behind TLS; Telegram webhook secret and licensing worker credential required.
"""
from __future__ import annotations
import hmac
import json
import os
import re
import socket
import ssl
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import Request, urlopen
from urllib.parse import urlsplit

DURATIONS = (1, 2, 3, 6, 12, 24, 36)
ORDER = re.compile(r"yeti3_ads_([0-9a-f]{32})\Z")


def post(url, payload, headers=None, timeout=4):
    parsed = urlsplit(url)
    relay = os.environ.get("CLEANER_TELEGRAM_RELAY")
    if relay and parsed.scheme == "https" and parsed.netloc == "api.telegram.org":
        # Reuse the origin's TCP relay; TLS and hostname validation remain
        # end-to-end with Telegram. The relay cannot read bot credentials.
        class VerifiedRelay(http.client.HTTPSConnection):
            def connect(self):
                raw = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                raw.settimeout(timeout)
                try:
                    raw.connect(relay)
                    self.sock = ssl.create_default_context().wrap_socket(raw, server_hostname="api.telegram.org")
                except Exception:
                    raw.close(); raise
        connection = VerifiedRelay("api.telegram.org", timeout=timeout)
        try:
            connection.request("POST", parsed.path, body=json.dumps(payload).encode(),
                               headers={"Content-Type": "application/json", **(headers or {})})
            response = connection.getresponse()
            if response.status != 200:
                raise RuntimeError("Telegram request failed")
            return json.loads(response.read(1048576))
        finally:
            connection.close()
    request = Request(url, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json", **(headers or {})})
    with urlopen(request, timeout=timeout) as response:
        result = json.load(response)
    return result


class CleanerBot:
    def __init__(self, token, worker_token, stars_enabled=False, transport=post,
                 authority_origin="http://127.0.0.1:4352"):
        origin = urlsplit(authority_origin)
        if (origin.scheme not in ("http", "https") or not origin.hostname or origin.username
                or origin.password or origin.query or origin.fragment or origin.path not in ("", "/")):
            raise ValueError("Invalid licensing origin")
        self.token = token
        self.worker = worker_token
        self.stars_enabled = stars_enabled
        self.transport = transport
        self.authority_origin = authority_origin.rstrip("/")

    def telegram(self, method, **payload):
        result = self.transport(f"https://api.telegram.org/bot{self.token}/{method}", payload)
        if result.get("ok") is not True:
            raise RuntimeError("Telegram rejected request")
        return result.get("result")

    def authority(self, user, action, **fields):
        return self.transport(self.authority_origin + "/api/network/v1/internal/telegram/ads",
                              {"telegram_user_id": user, "action": action, **fields},
                              {"x-network-bot-token": self.worker})

    def say(self, chat, text, markup=None):
        fields = {"chat_id": chat, "text": text}
        if markup:
            fields["reply_markup"] = markup
        self.telegram("sendMessage", **fields)

    @staticmethod
    def payment_fields(value):
        match = ORDER.fullmatch(value.get("invoice_payload", ""))
        amount = value.get("total_amount")
        if not match or value.get("currency") != "XTR" or type(amount) is not int or amount <= 0:
            raise ValueError("Invalid payment")
        return {"order_id": match[1], "currency": "XTR", "total_amount": amount}

    def invoice(self, user, months):
        if not self.stars_enabled:
            self.say(user, "Оплата пока не включена. Бесплатная очистка доступна; /paysupport — помощь.")
            return
        result = self.authority(user, "invoice", months=months)
        if result.get("currency") != "XTR" or type(result.get("total_amount")) is not int or result["total_amount"] <= 0:
            raise ValueError("Invalid server tariff")
        payload = result.get("payload", "")
        if not ORDER.fullmatch(payload):
            raise ValueError("Invalid server order")
        self.telegram("sendInvoice", chat_id=user, title=f"YETI³ без рекламы · {months} мес.",
                      description="Доступ для привязанного аккаунта сети YETI³. Без автоматического продления.",
                      payload=payload, provider_token="", currency="XTR",
                      prices=[{"label": "Без рекламы", "amount": result["total_amount"]}],
                      start_parameter="cleaner-ads")

    def terms_for_purchase(self, user, months):
        self.say(user, f"Выбран срок: {months} мес. Прочитайте условия и политику перед покупкой. Оплата Telegram Stars, не рублями. Без автопродления. В счёте будет актуальная цена сервера.",
                 {"inline_keyboard": [[{"text": "Условия", "url": "https://license.gochain.space/legal/terms"},
                                        {"text": "Конфиденциальность", "url": "https://license.gochain.space/legal/privacy"}],
                                       [{"text": "Согласен, показать счёт", "callback_data": f"agree:{months}"}]]})

    def handle(self, update):
        if not isinstance(update, dict):
            raise ValueError("Invalid update")
        query = update.get("pre_checkout_query")
        if query:
            ok = False
            try:
                if not self.stars_enabled:
                    raise ValueError("Checkout disabled")
                fields = self.payment_fields(query)
                ok = self.authority(query["from"]["id"], "precheckout", **fields).get("ok") is True
            except Exception:
                pass
            fields = {"pre_checkout_query_id": query["id"], "ok": ok}
            if not ok:
                fields["error_message"] = "Оплата недоступна: проверьте привязку аккаунта или создайте новый счёт."
            self.telegram("answerPreCheckoutQuery", **fields)
            return
        callback = update.get("callback_query")
        if callback:
            # Bound to a private chat and the user approving the terms.
            message = callback.get("message", {})
            user = callback["from"]["id"]
            if message.get("chat", {}).get("type") != "private" or message["chat"]["id"] != user:
                return
            self.telegram("answerCallbackQuery", callback_query_id=callback["id"])
            choose = re.fullmatch(r"choose:(1|2|3|6|12|24|36)", callback.get("data", ""))
            if choose:
                self.terms_for_purchase(user, int(choose[1]))
                return
            match = re.fullmatch(r"agree:(1|2|3|6|12|24|36)", callback.get("data", ""))
            if match:
                try:
                    self.invoice(user, int(match[1]))
                except Exception:
                    self.say(user, "Счёт не создан. Сначала привяжите Telegram к аккаунту сети в https://license.gochain.space/account. Затем повторите /plans.")
            return
        message = update.get("message", {})
        chat = message.get("chat", {})
        user = message.get("from", {}).get("id")
        if chat.get("type") != "private" or chat.get("id") != user or not user:
            return
        payment = message.get("successful_payment")
        refund = message.get("refunded_payment")
        if payment or refund:
            value = payment or refund
            fields = self.payment_fields(value)
            charge = value.get("telegram_payment_charge_id")
            if not isinstance(charge, str) or not charge or len(charge) > 160:
                raise ValueError("Missing charge")
            # Backend records idempotency, amounts, ownership, stacking and refund revocation.
            # Never grant access for a pre-checkout, screenshot or client-generated receipt.
            result = self.authority(user, "paid" if payment else "refund", charge_id=charge, **fields)
            if payment and not (result.get("ads_enabled") is False or result.get("paid") is True):
                raise RuntimeError("Access not acknowledged")
            self.say(user, "Платёж подтверждён. Войдите в тот же аккаунт сети в Cleaner — реклама отключится." if payment else "Возврат зарегистрирован. Срок доступа пересчитан сервером.")
            return
        command = message.get("text", "").split()
        if not command:
            return
        name = command[0].split("@")[0]
        if name in ("/support", "/paysupport"):
            self.say(user, "Помощь с покупками и возвратами: ursolov@gmail.com. Укажите номер платежа, без паролей и фото документов. Telegram Support не обрабатывает покупки у разработчика.")
        elif name == "/terms":
            self.say(user, "Условия: https://license.gochain.space/legal/terms\nКонфиденциальность: https://license.gochain.space/legal/privacy\nРазовая покупка срока, без автопродления. Возвраты — /paysupport.")
        elif name == "/status":
            try:
                result = self.authority(user, "status")
                self.say(user, "Реклама отключена для аккаунта сети." if result.get("ads_enabled") is False else "Бесплатный режим с рекламой. /plans — сроки отключения.")
            except Exception:
                self.say(user, "Привяжите Telegram к аккаунту сети: https://license.gochain.space/account")
        elif name == "/buy" and len(command) == 2 and command[1].isdigit() and int(command[1]) in DURATIONS:
            self.terms_for_purchase(user, int(command[1]))
        else:
            buttons = [{"text": f"{months} мес.", "callback_data": f"choose:{months}"} for months in DURATIONS]
            self.say(user, "YETI³ Cleaner: очистка бесплатна.\nВыберите срок отключения рекламы для аккаунта сети.\nСначала привяжите Telegram к аккаунту сети: https://license.gochain.space/account\n/status · /terms · /paysupport",
                     {"inline_keyboard": [buttons[i:i+2] for i in range(0, len(buttons), 2)]})


def make_handler(bot, secret):
    if len(secret) < 32:
        raise ValueError("Webhook secret must have at least 32 characters")

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(10)

        def log_message(self, *args):
            pass  # No user payloads, chat IDs, tokens or payment details in HTTP logs.

        def do_GET(self):
            if self.path != "/health":
                self.send_error(404); return
            value = json.dumps({"ready": True, "checkout_enabled": bot.stars_enabled}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(value)))
            self.end_headers(); self.wfile.write(value)

        def do_POST(self):
            if self.path != "/webhook" or not hmac.compare_digest(self.headers.get("X-Telegram-Bot-Api-Secret-Token", ""), secret):
                self.send_error(403); return
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= 262144:
                    self.send_error(413); return
                update = json.loads(self.rfile.read(size))
            except (ValueError, json.JSONDecodeError):
                self.send_error(400); return
            try:
                bot.handle(update)
            except Exception:
                # Telegram retries. Payment events must not be acknowledged until persisted.
                self.send_error(503); return
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok")

    return Handler


if __name__ == "__main__":
    bot = CleanerBot(os.environ["CLEANER_TELEGRAM_BOT_TOKEN"], os.environ["CLEANER_NETWORK_WORKER_TOKEN"],
                     stars_enabled=os.environ.get("CLEANER_STARS_ENABLED") == "true",
                     authority_origin=os.environ.get("CLEANER_AUTHORITY_ORIGIN", "http://127.0.0.1:4352"))
    server = ThreadingHTTPServer(("127.0.0.1", int(os.environ.get("CLEANER_BOT_PORT", "8097"))),
                                 make_handler(bot, os.environ["CLEANER_WEBHOOK_SECRET"]))
    server.serve_forever()
