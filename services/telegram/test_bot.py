import unittest
from bot import CleanerBot, make_handler

class BotTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        def transport(url, data, headers=None):
            self.calls.append((url, data, headers))
            if '/internal/' in url:
                if data['action'] == 'invoice':
                    return {'currency':'XTR','total_amount':50,'payload':'yeti3_ads_'+'a'*32}
                return {'ok':True,'ads_enabled':False}
            return {'ok':True,'result':{}}
        self.bot = CleanerBot('fixture-token', 'fixture-worker', True, transport)
    def message(self, **extra):
        return {'message':{'chat':{'id':42,'type':'private'},'from':{'id':42},**extra}}
    def payment(self):
        return {'invoice_payload':'yeti3_ads_'+'a'*32,'currency':'XTR','total_amount':50,'telegram_payment_charge_id':'charge-fixture'}
    def test_precheckout_never_grants_access(self):
        self.bot.handle({'pre_checkout_query':{'id':'query','from':{'id':42},**self.payment()}})
        self.assertEqual(self.calls[0][1]['action'],'precheckout')
        self.assertTrue(self.calls[-1][1]['ok'])
        self.assertFalse(any(call[1].get('action') == 'paid' for call in self.calls))
    def test_payment_and_refund_go_to_authority(self):
        for field, action in [('successful_payment','paid'),('refunded_payment','refund')]:
            self.bot.handle(self.message(**{field:self.payment()}))
            self.assertEqual(self.calls[-2][1]['action'],action)
            self.assertEqual(self.calls[-2][1]['charge_id'],'charge-fixture')
    def test_wrong_currency_is_rejected(self):
        value = self.payment(); value['currency'] = 'RUB'
        with self.assertRaises(ValueError):
            self.bot.handle(self.message(successful_payment=value))
        self.assertEqual(self.calls,[])
    def test_ordinary_message_cannot_grant(self):
        self.bot.handle(self.message(text='Я оплатил, вот чек'))
        self.assertFalse(any('/internal/' in call[0] for call in self.calls))
    def test_invoice_requires_terms_acceptance(self):
        self.bot.handle(self.message(text='/buy 12'))
        self.assertFalse(any('sendInvoice' in call[0] for call in self.calls))
        self.bot.handle({'callback_query':{'id':'cb','from':{'id':42},'data':'agree:12','message':{'chat':{'id':42,'type':'private'}}}})
        self.assertEqual(self.calls[-1][1]['currency'],'XTR')
        self.assertEqual(self.calls[-1][1]['prices'][0]['amount'],50)
    def test_disabled_checkout_fails_closed(self):
        self.bot.stars_enabled=False
        self.bot.handle({'pre_checkout_query':{'id':'query','from':{'id':42},**self.payment()}})
        self.assertFalse(self.calls[-1][1]['ok'])
        self.assertFalse(any('/internal/' in call[0] for call in self.calls))
    def test_no_payment_success_if_authority_fails(self):
        def failing(*args, **kwargs): raise RuntimeError('fixture failure')
        self.bot.transport=failing
        with self.assertRaises(RuntimeError): self.bot.handle(self.message(successful_payment=self.payment()))
    def test_webhook_requires_long_secret_and_ignores_group(self):
        with self.assertRaises(ValueError): make_handler(self.bot,'short')
        event=self.message(text='/buy 1');event['message']['chat']['type']='group'
        self.bot.handle(event)
        self.assertEqual(self.calls,[])

    def test_menu_offers_all_seven_terms_without_issuing_invoice(self):
        self.bot.handle(self.message(text='/plans'))
        buttons = self.calls[-1][1]['reply_markup']['inline_keyboard']
        self.assertEqual([b['callback_data'] for row in buttons for b in row],
                         ['choose:'+str(n) for n in (1,2,3,6,12,24,36)])
        self.assertFalse(any('/internal/' in c[0] for c in self.calls))
    def test_choose_shows_terms_and_does_not_create_order(self):
        self.bot.handle({'callback_query':{'id':'fixture','from':{'id':42},'data':'choose:36',
                         'message':{'chat':{'id':42,'type':'private'}}}})
        buttons = self.calls[-1][1]['reply_markup']['inline_keyboard']
        self.assertEqual(buttons[-1][0]['callback_data'], 'agree:36')
        self.assertFalse(any('/internal/' in c[0] for c in self.calls))

if __name__ == '__main__': unittest.main()
