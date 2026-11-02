"""Telegram transport shared by release backends; never print token-bearing URLs."""
import json
import os
import urllib.request

def send_message(chat, text):
    data = json.dumps({'chat_id': chat, 'text': text,
                       'link_preview_options': {'is_disabled': True}}).encode()
    request = urllib.request.Request(
        'https://api.telegram.org/bot' + os.environ['UPDATE_BOT_TOKEN'] + '/sendMessage',
        data=data, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=30) as response:
        result = json.load(response)
        if not result.get('ok'):
            raise ValueError('Telegram rejected notification')
        return result['result']['message_id']
